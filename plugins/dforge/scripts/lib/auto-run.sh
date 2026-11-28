# Sourced. An auto run's state (reference/auto-run.md): one JSON file in the
# primary checkout's self-ignoring sdd/ directory, bound to one session.
# Defines functions only; scripts/auto-run is the command line.
#
# AR_SESSION names the caller. A caller whose session the run is not bound to
# sees no run, so another session in the same repository never acts on it.

# plan.sh brings roots.sh, and the plan and ledger readers ar_enter_final uses.
. "$(dirname "${BASH_SOURCE[0]}")/plan.sh"
. "$(dirname "${BASH_SOURCE[0]}")/lock.sh"
. "$(dirname "${BASH_SOURCE[0]}")/register.sh"
. "$(dirname "${BASH_SOURCE[0]}")/session-live.sh"
AR_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

AR_RESUME_CAP=3
AR_FAILURE_CAP=2
AR_STALL_CAP=3
AR_COMPACTION_CAP=3
AR_API_ERROR_CAP=10

# A native jq.exe ends its lines CRLF; every script sourcing this sets
# pipefail, so jq's own status, which -e relies on, still decides.
ar_jq() { "${DFORGE_JQ:-jq}" "$@" | tr -d '\r'; }

ar_primary_root() { plan_primary_root; }

# ar_in_primary — true in the primary checkout. A worktree run's tasks run in
# a linked worktree (dforge:using-git-worktrees), so a task step here would
# land on the run's base; ar_guard applies it to worktree runs only.
ar_in_primary() {
  local dir common
  dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "$dir" = "$common" ]
}

# ar_path — the state file's path, whether or not it exists: the working
# directory's when its run is the caller's, else the one the caller's binding
# names when that run is the caller's, else the working directory's. An
# active run the binding names goes before a run of the caller's that ended
# in the working directory, which would otherwise hide it.
# AR_RESOLVE=local takes the working directory's at once.
ar_path() {
  local primary="" here="" sid=${AR_SESSION:-${CLAUDE_CODE_SESSION_ID:-}} bfile bound_primary there
  if primary=$(ar_primary_root); then
    here="$(dforge_dir state "$primary")/sdd/auto-run.json"
  else
    primary=""
  fi
  if [ "${AR_RESOLVE:-}" = local ]; then
    [ -n "$here" ] || return 1
    printf '%s\n' "$here"
    return 0
  fi
  # With no binding elsewhere every step lands on the working directory's
  # file, so the common case reads no state.
  if [ -n "$sid" ]; then
    bfile=$(ar_binding_file "$sid")
    if [ -f "$bfile" ]; then
      bound_primary=$(ar_binding_get "$sid" primary)
      if [ -n "$bound_primary" ]; then
        there="$(dforge_dir state "$bound_primary")/sdd/auto-run.json"
        if [ "$there" != "$here" ] && _ar_session_is "$there" "$sid" \
           && { ! { [ -n "$here" ] && _ar_session_is "$here" "$sid"; } \
                || { ! _ar_active_for "$here" "$sid" && _ar_active_for "$there" "$sid"; }; }; then
          printf '%s\n' "$there"
          return 0
        fi
      fi
    fi
  fi
  [ -n "$here" ] || return 1
  printf '%s\n' "$here"
}

_ar_session_is() { # _ar_session_is PATH SID
  [ -f "$1" ] && ar_jq -e --arg s "$2" '.session == $s' < "$1" >/dev/null 2>&1
}

_ar_active_for() { # _ar_active_for PATH SID
  [ -f "$1" ] && ar_jq -e --arg s "$2" '.session == $s and .active == true' < "$1" >/dev/null 2>&1
}

# ar_run_primary — the primary checkout holding the resolved state file
# (<primary>/<state>/sdd/auto-run.json).
ar_run_primary() {
  local path
  path=$(ar_path) || return 1
  dirname "$(dirname "$(dirname "$path")")"
}

# ar_foreign — true when the working directory is not in the run's primary
# checkout's repository, or in no repository at all.
ar_foreign() {
  local mine run
  mine=$(ar_primary_root) || return 0
  run=$(ar_run_primary) || return 0
  [ "$(dr_native_path "$mine")" != "$(dr_native_path "$run")" ]
}

# ar_checkout — where the run's steps run: the worktree of the attached
# plan's ledger, else the run's primary.
ar_checkout() {
  local primary plan found
  primary=$(ar_run_primary) || return 1
  plan=$(ar_get plan)
  if [ -n "$plan" ] && found=$(plan_ledger_any "$primary" "$plan" 2>/dev/null) && [ -n "${found#*$'\t'}" ]; then
    printf '%s\n' "${found#*$'\t'}"
  else
    printf '%s\n' "$primary"
  fi
}

_ar_quote() { local q="'\\''"; printf "'%s'" "${1//\'/$q}"; }

# ar_cd_prefix [DIR] — "cd '<DIR>' && " when DIR (default: the run's checkout)
# is outside the directory the caller's session started in; nothing when inside
# it or when that directory is unknown.
ar_cd_prefix() {
  local sid=${AR_SESSION:-${CLAUDE_CODE_SESSION_ID:-}} rec cwd checkout=${1:-}
  rec="${HOME:-}/.claude/dforge/sessions/by-id/$(_session_safe "$sid").json"
  [ -f "$rec" ] || return 0
  cwd=$(ar_jq -r '.cwd // empty | strings' < "$rec" 2>/dev/null) || return 0
  [ -n "$cwd" ] || return 0
  [ -n "$checkout" ] || checkout=$(ar_checkout) || return 0
  cwd=$(dr_native_path "$cwd")
  case $(dr_native_path "$checkout") in
    "$cwd" | "$cwd"/*) return 0 ;;
  esac
  printf 'cd %s && ' "$(_ar_quote "$checkout")"
}

# ar_require_checkout — return 7, naming the command's checkout, when the
# caller is outside the run's repository.
ar_require_checkout() {
  ar_foreign || return 0
  printf "auto-run: run this from the run's checkout: cd %s && …\n" "$(_ar_quote "$(ar_checkout)")" >&2
  return 7
}

# A session's binding names the primary checkout whose state holds the run
# bound to it; the cockpit echoes what it read to the .seen file beside it.
ar_binding_file() { # ar_binding_file SID
  printf '%s/.claude/dforge/sessions/run/%s.json\n' "${HOME:-}" "$(_session_safe "$1")"
}

ar_binding_get() { # ar_binding_get SID primary|nonce — empty when unreadable
  local f
  f=$(ar_binding_file "$1")
  [ -f "$f" ] || return 0
  ar_jq -r --arg k "$2" '.[$k] // empty | strings' < "$f" 2>/dev/null || true
}

ar_binding_write() { # ar_binding_write SID PRIMARY — prints the nonce
  local f tmp nonce
  f=$(ar_binding_file "$1")
  mkdir -p "$(dirname "$f")" || return 1
  nonce="$(date +%s)-$$-$RANDOM"
  tmp=$(mktemp "$f.XXXXXX") || return 1
  if ar_jq -n --arg p "$2" --arg n "$nonce" --argjson at "$(date +%s)" '{primary: $p, nonce: $n, at: $at}' > "$tmp" \
     && [ -s "$tmp" ] && mv -f "$tmp" "$f"; then
    printf '%s\n' "$nonce"
  else
    rm -f "$tmp"
    return 1
  fi
}

ar_seen_ok() { # ar_seen_ok SID — the cockpit has read this binding
  local f
  f=$(ar_binding_file "$1")
  [ -f "$f" ] && [ -f "${f%.json}.seen" ] || return 1
  cat "$f" "${f%.json}.seen" 2>/dev/null | ar_jq -s -e \
    'length == 2 and (.[0].nonce | type == "string") and .[0].primary == .[1].primary and .[0].nonce == .[1].nonce' >/dev/null 2>&1
}

# ar_ack_wait SID — wait DFORGE_BIND_WAIT seconds (10 by default) for the
# cockpit to echo SID's binding. The wait is measured on the clock, not in
# passes: a pass costs two process starts, which are slow on Windows. SECONDS
# counts whole seconds, so the wait ends within a second after its length.
ar_ack_wait() {
  local wait=${DFORGE_BIND_WAIT:-10} end
  case $wait in '' | *[!0-9]*) wait=10 ;; esac
  end=$SECONDS
  [ "$wait" -eq 0 ] || end=$(( SECONDS + wait + 1 ))
  while :; do
    ar_seen_ok "$1" && return 0
    [ "$SECONDS" -lt "$end" ] || return 1
    sleep 0.05
  done
}

# ar_binding_around SID PRIMARY CMD [ARGS…] — write SID's binding, wait for
# the cockpit to echo it (return 2 without the echo), run CMD, and when either
# fails put the binding's earlier bytes back (or remove it when there was
# none), so a refused start or resume leaves no binding (the lock file
# beside it stays). The rollback runs under
# the binding's lock and only while the file still holds the nonce written
# here: a newer binding written meanwhile stays.
ar_binding_around() {
  local sid=$1 primary=$2 f keep="" rc nonce
  shift 2
  f=$(ar_binding_file "$sid")
  if [ -f "$f" ]; then
    keep=$(mktemp "$f.keep.XXXXXX") || return 1
    cp -p "$f" "$keep" || { rm -f "$keep"; return 1; }
  fi
  if ! nonce=$(ar_binding_write "$sid" "$primary"); then
    [ -z "$keep" ] || rm -f "$keep"
    return 1
  fi
  if ar_ack_wait "$sid"; then
    "$@"
    rc=$?
  else
    echo "auto-run: the cockpit in this session does not see this run" >&2
    rc=2
  fi
  if [ "$rc" -ne 0 ]; then
    dr_locked "$f" _ar_binding_rollback "$f" "$nonce" "$keep" || [ -z "$keep" ] || rm -f "$keep"
  else
    [ -z "$keep" ] || rm -f "$keep"
  fi
  return "$rc"
}

_ar_binding_rollback() { # _ar_binding_rollback FILE NONCE KEEP
  if [ "$(ar_jq -r '.nonce // empty' < "$1" 2>/dev/null)" = "$2" ]; then
    if [ -n "$3" ]; then mv -f "$3" "$1"; else rm -f "$1"; fi
  fi
  [ -z "$3" ] || rm -f "$3"
}

# ar_state — the state file's JSON; fails when there is none.
ar_state() {
  local path
  path=$(ar_path) || return 1
  [ -f "$path" ] || return 1
  ar_jq -e 'objects' < "$path" 2>/dev/null
}

# ar_bound — true when an active run is bound to AR_SESSION.
ar_bound() {
  [ -n "${AR_SESSION:-}" ] || return 1
  ar_state | ar_jq -e --arg s "$AR_SESSION" '.active == true and .session == $s' >/dev/null 2>&1
}

# ar_update FILTER [jq options…] — apply a jq filter to the state atomically.
# Concurrent updates (a Stop auto press beside a ruling add) queue instead of
# each reading the file the other is about to replace. The binding is checked
# again under the lock: a caller that saw the run bound before it waited may
# find it stopped, replaced or rebound to another session.
# The run's id is read before the wait, so a run replaced meanwhile (a
# --force start of the same session) is refused too.
ar_update() {
  local path seen
  path=$(ar_path) || return 1
  seen=$(ar_jq -r '.runId // empty' < "$path" 2>/dev/null)
  AR_RUN_SEEN=$seen dr_locked "$path" ar_write "$path" "$@"
}

# ar_write PATH FILTER [jq options…] — with AR_RUN_SEEN set, the run must
# still be the one of that id; a state written before run ids skips that.
ar_write() {
  ar_write_ok "$1" || return
  ar_put "$@"
}

# ar_write_ok PATH — ar_write's binding check, for a locked write that reads
# the state before it writes.
ar_write_ok() {
  ar_jq -e --arg s "${AR_SESSION:-}" --arg r "${AR_RUN_SEEN:-}" \
    '.active == true and .session == $s and ($r == "" or .runId == null or .runId == $r)' < "$1" >/dev/null 2>&1 \
    || { echo "auto-run: no auto run is bound to this session" >&2; return 3; }
}

ar_put() { # ar_put PATH FILTER [jq options…] — ar_write without the binding check
  local path=$1 filter=$2 tmp
  shift 2
  tmp=$(mktemp "$path.XXXXXX") || return 1
  if ar_jq "$@" "$filter" < "$path" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv -f "$tmp" "$path"
  else
    rm -f "$tmp"
    return 1
  fi
}

ar_create() { # ar_create PATH [jq options…] FILTER — the state from jq -n
  local path=$1 tmp
  shift
  tmp=$(mktemp "$path.XXXXXX") || return 1
  if ar_jq -n "$@" > "$tmp" && [ -s "$tmp" ]; then
    mv -f "$tmp" "$path"
  else
    rm -f "$tmp"
    return 1
  fi
}

# ar_get FIELD — one field, raw; empty for null or false.
ar_get() {
  ar_state | ar_jq -r --arg f "$1" '.[$f] // empty | if type == "array" or type == "object" then tojson else tostring end'
}

# The session helpers live in session-live.sh, beside AR_STALE_MINUTES and
# AR_BEAT_SECONDS.
ar_transcript() { session_transcript "$@"; }
ar_beat_file() { session_beat_file "$@"; }
ar_beat_age() { session_beat_age "$@"; }

# ar_is_stale — true when whoever owned the run is gone (session_gone); a run
# with no session counts as gone.
ar_is_stale() { session_gone "$(ar_get session)"; }

# ar_busy — true when the recorded run is active and its owner is not gone.
ar_busy() {
  ar_state | ar_jq -e '.active == true' >/dev/null 2>&1 && ! ar_is_stale
}

ar_busy_refusal() {
  echo "auto-run: an auto run is already active ($(ar_state | ar_jq -r '.spec')); stop it with auto-run stop, or pass --force" >&2
  return 4
}

# ar_stale_holds — true, with the refusal on stderr, when the recorded run is
# active, its owner gone, and its state still holds a decision or a ruling: a
# start over it would lose them, so stop --stale reads them first.
ar_stale_holds() {
  local counts
  ar_state | ar_jq -e '.active == true' >/dev/null 2>&1 && ar_is_stale || return 1
  counts=$(ar_state | ar_jq -r '"\((.decisions // []) | length) \((.rulings // []) | length)"')
  [ -n "$counts" ] && [ "$counts" != "0 0" ] || return 1
  echo "auto-run: the run of gone session $(ar_get session) ($(ar_get spec)) still holds ${counts% *} pending decisions and ${counts#* } rulings; run auto-run stop --stale to read them, then start again" >&2
}

# ar_create_unless_busy FORCE PATH [jq options…] FILTER — ar_create, run under
# the state's lock: a start that waited for the lock looks again, because the
# run it found absent may have been started meanwhile.
ar_create_unless_busy() {
  local force=$1
  shift
  if [ "$force" != 1 ] && ar_busy; then ar_busy_refusal; return; fi
  if [ "$force" != 1 ] && ar_stale_holds; then return 4; fi
  ar_create "$@"
}

# ar_log EVENT [DETAIL] — append one row to the run log beside the state file.
# Never fails its caller.
ar_log() {
  local path phase="" detail=${2:-}
  path=$(ar_path 2>/dev/null) || return 0
  [ -f "$path" ] && phase=$(ar_jq -r '.phase // empty' < "$path" 2>/dev/null | tr -d '\r')
  detail=${detail//[$'\t\n\r']/ }
  { printf '%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "${AR_SESSION:-}" "$phase" "$detail" \
      >> "$(dirname "$path")/auto-run-log.tsv"; } 2>/dev/null
  return 0
}

# ar_start SPEC REGISTER FORCE [ISOLATION] — prints the register path. A
# register it creates goes in the checkout the run starts from, where its path
# resolves. ISOLATION is worktree (the default) or in-place.
ar_start() {
  local spec=$1 register=$2 force=$3 iso=${4:-worktree} path age
  path=$(ar_path) || { echo "auto-run: not inside a git repository" >&2; return 2; }
  # Nothing would compact, switch or wake the run without the cockpit.
  age=$(ar_beat_age "$AR_SESSION") && [ "$age" -le "$AR_BEAT_SECONDS" ] \
    || { echo "auto-run: no live cockpit in this session" >&2; return 2; }
  if [ "$force" != 1 ] && ar_busy; then ar_busy_refusal; return; fi
  if [ "$force" != 1 ] && ar_stale_holds; then return 4; fi
  ar_binding_around "$AR_SESSION" "$(ar_primary_root)" _ar_start_bound "$spec" "$register" "$force" "$iso" "$path"
}

# _ar_start_bound SPEC REGISTER FORCE ISOLATION PATH — ar_start once the
# cockpit sees the binding.
_ar_start_bound() {
  local spec=$1 register=$2 force=$3 iso=$4 path=$5 top slug base regfile="" made="" rc
  top=$(git rev-parse --show-toplevel)
  dforge_stores_init "$top"
  if [ -z "$register" ]; then
    slug=$(basename "$spec" .md)
    slug=${slug%-design}
    slug=$(sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//' <<<"$slug")
    register="$(dforge_name "$(dforge_docs_root "$top")" "$top")/registers/$(date +%Y-%m-%d)-$slug-auto.md"
    regfile=$(dforge_resolve "$register" "$top")
    if [ ! -f "$regfile" ]; then
      mkdir -p "$(dirname "$regfile")" || return 1
      printf '# Auto run: %s\n\n**Source:** items the auto run for `%s` deferred\n**Covers:** %s\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n' \
        "$slug" "$spec" "$spec" > "$regfile" || return 1
      made=1
    fi
  fi
  base=$(git symbolic-ref --short -q HEAD 2>/dev/null || true)
  mkdir -p "$(dirname "$path")" || return 1
  dforge_self_ignore "$(dirname "$path")"
  # Under the update lock, so a --force start never lands between another
  # session's read and write of the state and is lost.
  dr_locked "$path" ar_create_unless_busy "$force" "$path" --arg s "$AR_SESSION" --arg spec "$spec" --arg reg "$register" --arg base "$base" \
    --arg iso "$iso" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    active: true, session: $s, runId: $runId, rebind: false, stopped: null, startedAt: $now,
    spec: $spec, plan: null, register: $reg, base: (if $base == "" then null else $base end),
    phase: "spec", regime: "normal", pending: null, resumePrompt: null, launch: null,
    failures: 0, compactions: 0, resumes: 0, decisions: [], rulings: [],
    setupDue: false, stalls: 0, stalledAt: null, compactionsSinceTask: 0,
    progressMark: null, compactionsSinceProgress: 0,
    totals: {compactionSeconds: 0, holds: 0, stalls: 0, apiErrors: 0, reconcilePrompts: 0, panelFailures: 0},
    isolation: $iso, branch: null, branchBase: null, carried: null,
    version: $version, root: $root
  }' --arg version "$(ar_plugin_version)" --arg root "$AR_PLUGIN_ROOT" --arg runId "$(date +%s)-$$-$RANDOM"
  rc=$?
  # A register this start made goes with the refused start.
  if [ "$rc" -ne 0 ]; then
    [ -z "$made" ] || rm -f "$regfile"
    return "$rc"
  fi
  ar_log start "$spec"
  ar_log bind "$(ar_primary_root)"
  # A register opened at the spec review before the spec existed may still
  # cover nothing, and next-step finds a register only through its Covers.
  [ -z "$regfile" ] && [ -n "$register" ] && regfile=$(dforge_resolve "$register" "$top")
  if [ -f "$regfile" ] && [ "$(register_field "$regfile" Covers)" = - ]; then
    local lockbase
    { lockbase=$(dr_lock_base "$regfile") && dr_locked "$lockbase" _ar_set_covers "$regfile" "$spec"; } \
      || echo "auto-run: could not set **Covers:** in $regfile to $spec; set it by hand, or next-step finds no register" >&2
  fi
  printf '%s\n' "$register"
}

# _ar_set_covers REGISTER SPEC — under the register's lock, an empty Covers
# becomes SPEC. It is read again here: another writer may have set it since.
_ar_set_covers() {
  local tmp rc
  [ "$(register_field "$1" Covers)" = - ] || return 0
  tmp=$(mktemp) || return 1
  COVERS="**Covers:** $2" awk '
    !done && /^\*\*Covers:\*\*[ \t]*-[ \t\r]*$/ { print ENVIRON["COVERS"]; done = 1; next }
    { print }' "$1" > "$tmp" && dr_replace "$1" "$tmp"
  rc=$?
  rm -f "$tmp"
  return "$rc"
}

# The plugin this library belongs to, as a run records the plugin it ran on.
AR_PLUGIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
ar_plugin_version() { ar_jq -r '.version // empty' < "$AR_PLUGIN_ROOT/.claude-plugin/plugin.json"; }

# ar_version_check — warn once on stderr when this plugin's version differs
# from the one the run bound to AR_SESSION recorded, and record the first
# mismatch. The guard variable keeps the caller's child auto-run calls silent.
# A run recorded before versions were kept skips the check, and a different
# root with the same version is no mismatch.
ar_version_check() {
  [ "${AR_VERSION_CHECKED:-}" != 1 ] || return 0
  export AR_VERSION_CHECKED=1
  local path run mine
  ar_bound || return 0
  path=$(ar_path) || return 0
  run=$(ar_jq -r '.version // empty' < "$path" 2>/dev/null)
  [ -n "$run" ] || return 0
  mine=$(ar_plugin_version 2>/dev/null)
  [ -n "$mine" ] && [ "$mine" != "$run" ] || return 0
  printf 'auto run: plugin version mismatch — run %s at %s, this call %s at %s\n' \
    "$run" "$(ar_jq -r '.root // "unknown"' < "$path" 2>/dev/null)" "$mine" "$AR_PLUGIN_ROOT" >&2
  dr_locked "$path" ar_put "$path" 'if .mismatch then . else .mismatch = {run: .version, root: .root, call: $v, callRoot: $r, at: $now} end' \
    --arg v "$mine" --arg r "$AR_PLUGIN_ROOT" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >/dev/null 2>&1 || true
}

# ar_resume — reactivate the stopped run for AR_SESSION (reference/auto-run.md
# §Resuming). Return 2 without a live cockpit, 4 with the reason on stderr
# when the run cannot resume.
ar_resume() {
  local path age
  path=$(ar_path) || { echo "auto-run: not inside a git repository" >&2; return 2; }
  age=$(ar_beat_age "$AR_SESSION") && [ "$age" -le "$AR_BEAT_SECONDS" ] \
    || { echo "auto-run: no live cockpit in this session" >&2; return 2; }
  [ -f "$path" ] || { echo "auto-run: there is no auto run to resume" >&2; return 4; }
  ar_binding_around "$AR_SESSION" "$(ar_primary_root)" dr_locked "$path" _ar_resume_locked "$path" || return $?
  ar_log resume
  ar_log bind "$(ar_primary_root)"
  ar_status
}

_ar_resume_locked() {
  local path=$1 stopped kind phase setup hit rc branch plan found top
  ar_jq -e '.active == true' < "$path" >/dev/null 2>&1 \
    && { echo "auto-run: the run is active, not stopped" >&2; return 4; }
  stopped=$(ar_get stopped)
  [ -n "$stopped" ] || { echo "auto-run: the run finished; there is nothing to resume" >&2; return 4; }
  kind=$(ar_get stoppedKind)
  # A run stopped before stoppedKind existed is known by the reasons
  # ar_task_complete writes.
  if [ -z "$kind" ]; then
    case $stopped in
      "a task was completed "*) kind=guard ;;
      "carried path "*" was committed" | "git could not check the carried paths") kind=carried ;;
    esac
  fi
  case $kind in
    guard) echo "auto-run: the run stopped on a workspace guard ($stopped) and cannot resume" >&2; return 4 ;;
    carried) echo "auto-run: the run stopped on a carried path ($stopped) and cannot resume" >&2; return 4 ;;
  esac
  hit=$(ar_carried_hit)
  rc=$?
  case $rc in
    0) echo "auto-run: carried path $hit was committed; the run cannot resume" >&2; return 4 ;;
    2) echo "auto-run: git could not check the carried paths; the run cannot resume" >&2; return 4 ;;
  esac
  phase=$(ar_get phase)
  setup=$(ar_get setupDue)
  if { [ "$phase" = execute ] && [ "$setup" != true ]; } || [ "$phase" = final ]; then
    if ar_guard; then
      case $AR_GUARD_RULE in
        1) echo "auto-run: HEAD is the run's base branch; resume from the run's workspace" >&2 ;;
        2) echo "auto-run: HEAD is off the run's branch $(ar_get branch); resume on it" >&2 ;;
        *) echo "auto-run: this is the primary checkout of a worktree run; resume from its worktree" >&2 ;;
      esac
      return 4
    fi
    if [ "$(ar_get isolation)" = in-place ]; then
      branch=$(ar_get branch)
      git show-ref --verify --quiet "refs/heads/$branch" \
        || { echo "auto-run: the run's branch $branch is gone" >&2; return 4; }
    else
      plan=$(ar_get plan)
      found=""
      top=$(git rev-parse --show-toplevel)
      [ -z "$plan" ] || found=$(plan_ledger_any "$top" "$plan")
      # Until Setup writes the ledger the worktree's path is not recorded, so
      # any checkout holding the plan is taken for it: a heuristic, since
      # another worktree with the plan resumes too. ar_guard has already
      # refused the primary and the base.
      if [ -n "$found" ]; then [ -d "${found#*$'\t'}" ]
      else [ -n "$plan" ] && [ -f "$(dforge_resolve "$plan" "$top")" ]
      fi || { echo "auto-run: the plan's worktree is gone (plan ${plan:-none})" >&2; return 4; }
    fi
  fi
  ar_put "$path" '.active = true | .session = $s | .rebind = false
    | .stopHistory = ((.stopHistory // []) + [{reason: .stopped, at: (.stoppedAt // null), resumedAt: $now}])
    | .stopped = null | .stoppedAt = null | .stoppedKind = null
    | .stalls = 0 | .resumes = 0 | .failures = 0 | .apiErrors = 0 | .compactionsSinceTask = 0
    | .progressMark = null | .compactionsSinceProgress = 0
    | .stalledAt = null | .pending = null | .resumePrompt = null | .launch = null
    | .version = $version | .root = $root' \
    --arg s "$AR_SESSION" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg version "$(ar_plugin_version)" --arg root "$AR_PLUGIN_ROOT"
}

# ar_review_skip FAMILY [UNTIL] — record a review family's quota failure in
# the run: skipped until UNTIL (epoch), or for 5 hours when none is known. A
# second quota failure of the family skips it for the rest of the run (until
# null).
ar_review_skip() {
  ar_update '.reviewSkips = ((.reviewSkips // []) as $s
    | if any($s[]; .family == $f)
      then $s | map(if .family == $f then .failedAt = $now | .until = null else . end)
      else $s + [{family: $f, failedAt: $now, until: ($until // ($now + 18000)), kind: "quota"}] end)' \
    --arg f "$1" --argjson now "$(date +%s)" --argjson until "${2:-null}"
}

# ar_review_skipped FAMILY — true while the family's recorded skip lasts.
ar_review_skipped() {
  ar_state | ar_jq -e --arg f "$1" --argjson now "$(date +%s)" \
    'any((.reviewSkips // [])[]; .family == $f and (.until == null or .until > $now))' >/dev/null 2>&1
}

# ar_total NAME [N] — add N (default 1) to the run's totals.NAME. No binding
# check, so a hook of the owning session books even while the binding moves;
# a stopped or finished run is left as it is.
ar_total() {
  local path
  path=$(ar_path) || return 1
  [ -f "$path" ] || return 1
  dr_locked "$path" ar_put "$path" 'if .active == true then .totals[$n] = ((.totals[$n] // 0) + $k) else . end' \
    --arg n "$1" --argjson k "${2:-1}" || return
  [ "$1" != holds ] || ! ar_jq -e '.active == true' < "$path" >/dev/null 2>&1 || ar_log hold
}

# ar_counters — the run's totals, one per line (reference/auto-run.md); the
# version line only when a mismatch was recorded.
ar_counters() {
  ar_state | ar_jq -r '(.totals // {}) as $t
    | "compactions: \(.compactions // 0) (\($t.compactionSeconds // 0) s)",
      "holds: \($t.holds // 0)",
      "stalls: \($t.stalls // 0)",
      "API errors: \($t.apiErrors // 0)",
      "reconcile prompts: \($t.reconcilePrompts // 0)",
      "panel failures: \($t.panelFailures // 0)",
      (.mismatch | select(. != null) | "version mismatch: \(.run) at \(.root) vs \(.call) at \(.callRoot)")'
}

ar_status() {
  local line
  line=$(ar_state | ar_jq -r '"auto run: \(.phase) — regime \(.regime) — pending \(.pending // "none") — \(.compactions) compactions — \(.resumes) resumes — \(.decisions | length) pending decisions — spec \(.spec) — plan \(.plan // "none") — base \(.base // "none") — register \(.register) — isolation \(.isolation // "worktree")\(if .branch then " — branch \(.branch)" else "" end)\(if .setupDue == true then " — setup due" else "" end)"') || return
  printf '%s\n' "$line"
  if ar_seen_ok "$AR_SESSION"; then echo "cockpit: sees this run"; else echo "cockpit: does not see this run"; fi
}

ar_pending() { ar_state | ar_jq -r '.pending // "none"'; }

# ar_setup_branch NAME — an in-place run's branch, checked out here: records
# it, the commit it starts from, and every path git status lists as carried,
# the user's uncommitted changes the run must never commit (the run's own
# register excepted). Refuses (return 4, recording nothing) a second call,
# which would move the carried check's start past commits already made, the
# run's base, a HEAD on another branch, and staged changes, which a task's
# commit would take along.
ar_setup_branch() {
  local name=$1 entry xy path staged=() paths=() carried recorded register head tmp top
  recorded=$(ar_get branch)
  if [ -n "$recorded" ]; then
    echo "auto-run: the run's branch is already recorded: $recorded" >&2
    return 4
  fi
  if [ "$name" = "$(ar_get base)" ]; then
    echo "auto-run: $name is the run's base branch" >&2
    return 4
  fi
  if [ "$(git symbolic-ref --short -q HEAD 2>/dev/null)" != "$name" ]; then
    echo "auto-run: HEAD is not on $name" >&2
    return 4
  fi
  head=$(git rev-parse HEAD) && [ -n "$head" ] || return 1
  top=$(git rev-parse --show-toplevel) || return 1
  register=$(dforge_resolve "$(ar_get register)" "$top")
  register=${register#"$top"/}
  tmp=$(mktemp) || return 1
  if ! git status --porcelain=v1 -z --untracked-files=all >"$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  while IFS= read -r -d '' entry; do
    xy=${entry:0:2} path=${entry:3}
    case ${xy:0:1} in ' ' | '?') ;; *) staged+=("$path") ;; esac
    [ "$path" = "$register" ] || paths+=("$path")
    case $xy in
      *R* | *C*) IFS= read -r -d '' path && { [ "$path" = "$register" ] || paths+=("$path"); } ;;
    esac
  done <"$tmp"
  rm -f "$tmp"
  if [ ${#staged[@]} -gt 0 ]; then
    echo "auto-run: staged changes in this checkout: ${staged[*]}" >&2
    return 4
  fi
  carried=$( { [ ${#paths[@]} -eq 0 ] || printf '%s\0' "${paths[@]}"; } | ar_jq -Rsc 'split("\u0000") | map(select(. != ""))') || return 1
  local state seen
  state=$(ar_path) || return 1
  seen=$(ar_jq -r '.runId // empty' < "$state" 2>/dev/null)
  AR_RUN_SEEN=$seen dr_locked "$state" _ar_setup_branch_write "$state" "$name" "$head" "$carried"
}

# _ar_setup_branch_write PATH NAME HEAD CARRIED — ar_setup_branch's write,
# under the state's lock: a second call that passed the first look while this
# one waited finds the branch recorded.
_ar_setup_branch_write() {
  local recorded
  ar_write_ok "$1" || return
  recorded=$(ar_jq -r '.branch // empty' < "$1" 2>/dev/null)
  if [ -n "$recorded" ]; then
    echo "auto-run: the run's branch is already recorded: $recorded" >&2
    return 4
  fi
  ar_put "$1" '.branch = $b | .branchBase = $h | .carried = $c' --arg b "$2" --arg h "$3" --argjson c "$4"
}

ar_carried() { ar_state | ar_jq -r '(.carried // [])[]'; }

# ar_guard — true (0) when a task step here would land where the run must not
# commit, with AR_GUARD_RULE naming the rule: 1, HEAD is the run's base (or
# detached with no base); 2, an in-place run's HEAD is off its recorded
# branch, or no branch is recorded, so Setup's Step 0 never ran and the
# carried paths are unknown; 3, a worktree run is in the primary checkout. A worktree run checks
# 3 before 1, so its primary-checkout case keeps rule 3's message.
ar_guard() {
  local iso head base branch
  AR_GUARD_RULE=""
  iso=$(ar_get isolation)
  head=$(git symbolic-ref --short -q HEAD 2>/dev/null || true)
  base=$(ar_get base)
  if [ "$iso" != in-place ] && ar_in_primary; then AR_GUARD_RULE=3; return 0; fi
  if { [ -n "$base" ] && [ "$head" = "$base" ]; } || { [ -z "$base" ] && [ -z "$head" ]; }; then
    AR_GUARD_RULE=1
    return 0
  fi
  if [ "$iso" = in-place ]; then
    branch=$(ar_get branch)
    if [ -z "$branch" ] || [ "$head" != "$branch" ]; then AR_GUARD_RULE=2; return 0; fi
  fi
  return 1
}

# ar_carried_hit — prints the first path committed since branchBase that the
# run carried, the user's own uncommitted change; returns 1 when there is
# none, and 2 when git cannot tell, which callers treat as a hit rather than
# as clean. Each commit's paths count, so a change committed and then
# reverted is still a hit. --no-renames lists a renamed carried path under
# its old name too.
ar_carried_hit() {
  local bb carried path tmp
  bb=$(ar_get branchBase)
  [ -n "$bb" ] || return 1
  carried=$(ar_carried) || return 2
  [ -n "$carried" ] || return 1
  tmp=$(mktemp) || return 2
  # -m diffs a merge against each parent: a resolution can change a path alone.
  if ! git log -m --no-renames --name-only -z --format= "$bb..HEAD" >"$tmp"; then
    rm -f "$tmp"
    return 2
  fi
  while IFS= read -r -d '' path; do
    [ -n "$path" ] || continue
    if grep -Fxq -- "$path" <<<"$carried"; then
      rm -f "$tmp"
      printf '%s\n' "$path"
      return 0
    fi
  done <"$tmp"
  rm -f "$tmp"
  return 1
}

ar_stop() { # ar_stop [REASON [KIND]] — KIND guard or carried marks a stop resume refuses
  ar_update '.active = false | .stopped = (if $r == "" then null else $r end) | .pending = null
    | .stoppedAt = $now | .stoppedKind = (if $k == "" then null else $k end)' \
    --arg r "${1:-}" --arg k "${2:-}" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return
  ar_log stop "${1:-}"
}

# ar_stop_stale — stop, from any session, an active run whose owner is gone
# (ar_is_stale), with reason `owner session <id> is gone`, then print what it
# leaves undecided. A replaced or crashed session can never bind again, so the
# binding check is skipped. Return 3 when no run is active or its owner lives.
ar_stop_stale() {
  local path sid
  ar_state | ar_jq -e '.active == true' >/dev/null 2>&1 \
    || { echo "auto-run: no auto run is active" >&2; return 3; }
  sid=$(ar_get session)
  ar_is_stale || { echo "auto-run: the run's owner session $sid is still live; stop it from that session" >&2; return 3; }
  path=$(ar_path) || return 1
  local status=0
  dr_locked "$path" _ar_stop_if_stale "$path" "$sid" || status=$?
  case $status in
    0) ;;
    3) echo "auto-run: the run changed while it was being stopped (a new run, or its owner came back); nothing was stopped" >&2; return 3 ;;
    *) return 1 ;;
  esac
  echo "auto-run: stopped — owner session $sid is gone"
  ar_decision_list | sed 's/^/pending decision: /'
  ar_ruling_list | sed 's/^/ruling: /'
}

# _ar_stop_if_stale PATH SID — under the state's lock, so a run started with
# --force since the check outside it is never stopped: stop the run only while
# SID still owns it, it is active, and SID is gone. Return 3 otherwise.
_ar_stop_if_stale() {
  ar_jq -e --arg s "$2" '.active == true and .session == $s' < "$1" >/dev/null 2>&1 && ar_is_stale || return 3
  ar_put "$1" '.active = false | .stopped = $r | .pending = null | .stoppedAt = $now | .stoppedKind = null' \
    --arg r "owner session $2 is gone" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" || return
  ar_log stop "owner session $2 is gone"
}

# ar_set_phase PHASE — refuses (return 4) execute where ar_guard does, since
# the workspace Setup prepares is missing, and final or finish once a carried
# path was committed. execute and final settle Setup.
ar_set_phase() {
  local hit rc
  if [ "$1" = execute ] && ar_guard; then
    if [ "$AR_GUARD_RULE" = 3 ]; then
      echo "auto-run: this is the primary checkout; create the execution worktree first (dforge:using-git-worktrees), then run auto-run phase execute from it" >&2
    else
      echo "auto-run: HEAD is not on the run's branch; follow dforge:using-git-worktrees Step 0 for the run, then run auto-run phase execute again" >&2
    fi
    return 4
  fi
  if [ "$1" = final ] || [ "$1" = finish ]; then
    hit=$(ar_carried_hit)
    rc=$?
    if [ "$rc" = 0 ]; then
      echo "auto-run: carried path $hit was committed; stop the run" >&2
      return 4
    elif [ "$rc" = 2 ]; then
      echo "auto-run: git could not list the commits since the run's branch base; stop the run" >&2
      return 4
    fi
  fi
  ar_update '.phase = $p | if $p == "execute" or $p == "final" then .setupDue = false else . end' --arg p "$1" || return
  ar_log phase "$1"
}

# ar_enter_final — in the execute phase, once the attached plan's ledger has a
# complete line for every task, move the run to the final phase, so the check
# after the last task is measured where no compaction hands off.
ar_enter_final() {
  local plan ledger tasks
  [ "$(ar_get phase)" = execute ] || return 0
  plan=$(ar_get plan)
  [ -n "$plan" ] || return 0
  plan=$(plan_locate "$plan")
  [ -f "$plan" ] || return 0
  ledger=$(plan_ledger "$plan")
  [ -n "$ledger" ] || return 0
  tasks=$(plan_tasks "$plan" | cut -f1 | sort -u)
  [ -n "$tasks" ] || return 0
  [ -z "$(comm -23 <(printf '%s\n' "$tasks") <(ledger_done "$ledger" | sort -u))" ] || return 0
  ar_update '.phase = "final" | .setupDue = false' || return
  ar_log phase final
}

# ar_task_complete — a task's complete line is written, so the progress counts
# start again. During the execute or final phase a task where ar_guard refuses
# ran where the run must not commit, and in any phase a committed carried path
# is the user's change: the run stops (return 5) rather than finish there. The
# spec and plan phases belong in the primary checkout.
ar_task_complete() {
  local phase reason="" kind hit rc
  phase=$(ar_get phase)
  if { [ "$phase" = execute ] || [ "$phase" = final ]; } && ar_guard; then
    kind=guard
    case $AR_GUARD_RULE in
      1) reason="a task was completed on the run's base branch" ;;
      2) reason="a task was completed off the run's branch" ;;
      *) reason="a task was completed in the primary checkout" ;;
    esac
  else
    kind=carried
    hit=$(ar_carried_hit)
    rc=$?
    if [ "$rc" = 0 ]; then
      reason="carried path $hit was committed"
    elif [ "$rc" = 2 ]; then
      reason="git could not check the carried paths"
    fi
  fi
  if [ -n "$reason" ]; then
    ar_stop "$reason" "$kind" || return $?
    echo "auto-run: $reason; the run has stopped. End as reference/auto-run.md §Stopping says." >&2
    return 5
  fi
  ar_update '.resumes = 0 | .stalls = 0 | .stalledAt = null | .compactionsSinceTask = 0 | .apiErrors = 0 | .setupDue = false' || return $?
  ar_sweep_closes
}

# ar_sweep_closes — a close marker for every complete task the marker file
# lacks one for (a task closed by hand, or deferred by the run), so a usage
# report never runs a task's slice to the next open. Needs usage-marker.sh;
# never fails.
ar_sweep_closes() {
  declare -F um_mark >/dev/null || return 0
  local plan ledger markers rel closed line n range deferred
  plan=$(ar_get plan)
  [ -n "$plan" ] || return 0
  plan=$(plan_locate "$plan")
  [ -f "$plan" ] || return 0
  ledger=$(plan_ledger "$plan")
  [ -n "$ledger" ] && [ -f "$ledger" ] || return 0
  markers="$(dforge_dir state "$(ctx_primary_root 2>/dev/null)")/sdd/usage-markers.tsv"
  rel=$(_um_plan_rel "$plan")
  closed=""
  [ ! -f "$markers" ] || closed=$(UM_PLAN=$rel awk -F'\t' '{ sub(/\r$/, "") } $2 == "close" && $6 == ENVIRON["UM_PLAN"] { print $7 }' "$markers" 2>/dev/null)
  while IFS= read -r line; do
    [[ $line =~ ^Task\ ([0-9]+):\ complete\ \((.*) ]] || continue
    n=${BASH_REMATCH[1]} range="" deferred=""
    ! grep -qx "$n" <<<"$closed" || continue
    case ${BASH_REMATCH[2]} in
      'commits '*) range=${BASH_REMATCH[2]#commits }; range=${range%%[,)]*} ;;
      'deferred by the auto run)'*) deferred=1 ;;
    esac
    um_mark close "$plan" "$n" "" auto-run:task-complete "$range" "$deferred"
  done < <(tr -d '\r' < "$ledger")
  return 0
}

# ar_fenced FILE PREFIX — the first fenced block after the first line that
# starts with PREFIX.
ar_fenced() {
  awk -v h="$2" '
    !seen && index($0, h) == 1 { seen = 1; next }
    seen && !open && /^```/ { open = 1; next }
    open && /^```/ { exit }
    open { print }
  ' "$1"
}

# ar_owner_handoff DIR SID — the newest handoff of any checkout or the mirror
# (dforge_handoff_files) whose next-step marker carries session=SID.
ar_owner_handoff() {
  local f m word words mt best="" best_mt=-1 found
  [ -n "$2" ] || return 0
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    m=$(tr -d '\r' < "$f" | grep -E '^<!-- next-step: .* -->$' | tail -n 1)
    m=${m#<!-- next-step: }
    read -ra words <<<"${m%% subject=*}"
    found=0
    for word in ${words[@]+"${words[@]}"}; do [ "$word" = "session=$2" ] && found=1; done
    [ "$found" -eq 1 ] || continue
    mt=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null) || mt=0
    if [ "${mt:-0}" -gt "$best_mt" ]; then best=$f best_mt=${mt:-0}; fi
  done < <(dforge_handoff_files "$1")
  [ -z "$best" ] || printf '%s\n' "$best"
}

# ar_handoff — the first prompt and launch from the handoff scripts/next-step
# just wrote, into AR_PROMPT, AR_MODEL and AR_EFFORT. Returns 5 when another
# live session holds the plan's handoff.
ar_handoff() {
  local primary here plan latest="" launch
  AR_PROMPT="" AR_MODEL="" AR_EFFORT=""
  primary=$(ar_primary_root) || return 1
  dforge_stores_init "$primary"
  here=$(git rev-parse --show-toplevel 2>/dev/null) || here=$primary
  # The attached plan's handoff is the one next-step wrote for it, from this
  # checkout: where T falls can depend on where next-step runs.
  plan=$(ar_get plan)
  if [ -n "$plan" ]; then
    local err rc=0
    err=$(mktemp) || return 1
    latest=$(cd "$here" && bash "$AR_LIB_DIR/../next-step" --target "$plan" 2>"$err") || rc=$?
    # 7: another live session holds the plan's handoff, and next-step has
    # stopped this session's run; its line names the holder.
    if [ "$rc" -eq 7 ]; then
      grep '^next-step: ' "$err" >&2
      rm -f "$err"
      return 5
    fi
    rm -f "$err"
    [ "$rc" -eq 0 ] || latest=""
  else
    # A design-phase clear: the newest handoff whose marker names the run's
    # owner session, read by name; another session's handoff is never resumed.
    latest=$(ar_owner_handoff "$here" "$(ar_get session)")
  fi
  [ -n "$latest" ] && [ -f "$latest" ] && AR_PROMPT=$(ar_fenced "$latest" 'Paste as the first prompt:')
  [ -n "$AR_PROMPT" ] || { echo "auto-run: no first prompt in ${latest:-any handoff of this run}; run scripts/next-step first" >&2; return 1; }
  launch=$(ar_fenced "$latest" 'Launch in ' | head -n 1)
  if [[ $launch =~ claude\ --model\ ([^ ]+)\ --effort\ ([^ ]+) ]]; then
    AR_MODEL=${BASH_REMATCH[1]} AR_EFFORT=${BASH_REMATCH[2]}
  fi
}

# ar_prompt_names_plan PLAN — AR_PROMPT names PLAN's file as a whole word:
# `myplan.md` is not `plan.md`.
ar_prompt_names_plan() {
  local name
  name=$(basename "$1")
  [[ $AR_PROMPT =~ (^|[^A-Za-z0-9._-])"$name"($|[^A-Za-z0-9_-]) ]]
}

# ar_switch — at plan saved, the move to execution: the first prompt
# and launch as ar_clear reads them. Refuses (return 4) without an attached
# plan, or when the first prompt names another plan. Never a self-resume.
# The phase moves to execute before the cockpit clears the session. Setup is
# due until a phase execute from the execution workspace, a task-complete or
# phase final.
ar_switch() {
  local plan
  plan=$(ar_get plan)
  [ -n "$plan" ] || { echo "auto-run: no plan is attached; run auto-run attach --plan first" >&2; return 4; }
  ar_handoff || return
  ar_prompt_names_plan "$plan" \
    || { echo "auto-run: the handoff's first prompt names another plan than $plan; run scripts/next-step $plan again" >&2; return 4; }
  ar_update '.pending = "switch" | .phase = "execute" | .setupDue = true | .compactionsSinceTask = 0 | .resumePrompt = $p
    | .launch = (if $m == "" then null else {model: $m, effort: $e} end)' \
    --arg p "$AR_PROMPT" --arg m "$AR_MODEL" --arg e "$AR_EFFORT" || return
  ar_log switch
}

# ar_clear PHASE — the cleared session's first prompt and launch, from the
# handoff scripts/next-step just wrote. PHASE 1 for a phase clear; otherwise
# the clear is a self-resume, and the AR_RESUME_CAP-th in a row stops the run
# (return 5).
ar_clear() {
  local is_phase=$1 plan rc=0
  ar_handoff || return
  # The plan's checkout may hold a block another session left there for
  # another plan; storing its prompt would resume the wrong plan.
  plan=$(ar_get plan)
  if [ -n "$plan" ] && ! ar_prompt_names_plan "$plan"; then
    echo "auto-run: the handoff's first prompt names another plan than $plan; run scripts/next-step $plan again" >&2
    return 4
  fi
  if [ "$is_phase" != 1 ]; then
    ar_capped '' '.resumes = ((.resumes // 0) + 1) | cap_stop(.resumes; $cap; "\($cap) self-resumes without a completed task")' \
      --argjson cap "$AR_RESUME_CAP" || rc=$?
    [ "$rc" -ne 5 ] || echo "auto-run: stopped — $AR_RESUME_CAP self-resumes in a row without a completed task" >&2
    [ "$rc" -eq 0 ] || return "$rc"
  fi
  ar_update '.pending = "clear" | .rebind = true | .resumePrompt = $p
    | .launch = (if $m == "" then null else {model: $m, effort: $e} end)' \
    --arg p "$AR_PROMPT" --arg m "$AR_MODEL" --arg e "$AR_EFFORT" || return
  if [ "$is_phase" = 1 ]; then ar_log clear phase; else ar_log clear resume; fi
}

# The cockpit rebinds from the session that replaced the cleared one, so no
# session check applies: the waiting clear is what authorises the rebind.
ar_rebind() { # ar_rebind ID
  local path
  ar_state | ar_jq -e '.active == true and .rebind == true' >/dev/null 2>&1 \
    || { echo "auto-run: no clear is waiting for its session" >&2; return 4; }
  path=$(ar_path) || return 1
  dr_locked "$path" ar_rebind_locked "$path" "$1"
}

ar_rebind_locked() { # ar_rebind_locked PATH ID
  ar_jq -e '.active == true and .rebind == true' < "$1" >/dev/null 2>&1 \
    || { echo "auto-run: no clear is waiting for its session" >&2; return 4; }
  # The binding first: a failed write must leave the state with the session
  # that can still stop the run. It names the run's primary, which is not the
  # working directory's when the call comes from another repository.
  ar_binding_write "$2" "$(dirname "$(dirname "$(dirname "$1")")")" >/dev/null || return
  ar_put "$1" '.session = $id | .rebind = false | .pending = "resume" | .failures = 0 | .regime = "normal"' --arg id "$2" \
    || { local rc=$?; rm -f "$(ar_binding_file "$2")"; return "$rc"; }
  ar_log rebind "$2"
}

# ar_resumed — the cockpit submitted its stage's prompt.
ar_resumed() {
  ar_update '.failures = 0
    | if .pending == "resume" then .pending = null else . end'
}

# ar_progress_mark — "<ledger lines>|<HEAD>|<newest mtime>": the attached
# plan's ledger line count (0 without one), HEAD of the run's checkout, and the
# newest modification time of the spec and of the plans whose Spec line names
# it. A part that cannot be read is empty.
ar_progress_mark() {
  local primary plan file lines=0 head spec newest="" mt
  primary=$(ar_run_primary) || primary=""
  plan=$(ar_get plan)
  spec=$(ar_get spec)
  head=$(git -C "$(ar_checkout 2>/dev/null)" rev-parse HEAD 2>/dev/null | tr -d '\r')
  [ -n "$primary" ] || { printf '%s|%s|' "$lines" "$head"; return 0; }
  if [ -n "$plan" ]; then
    # A worktree run keeps its ledger in the plan's worktree.
    file=$(plan_ledger_any "$primary" "$plan" 2>/dev/null | cut -f1)
    [ -z "$file" ] || [ ! -f "$file" ] || lines=$(wc -l < "$file" | tr -d ' ')
  fi
  if [ -n "$spec" ]; then
    declare -F _spec_plan_files >/dev/null || . "$(dirname "${BASH_SOURCE[0]}")/route.sh"
    while IFS= read -r file; do
      [ -n "$file" ] && [ -f "$file" ] || continue
      mt=$(stat -c %Y "$file" 2>/dev/null || stat -f %m "$file" 2>/dev/null) || continue
      [ -n "$newest" ] && [ "$newest" -ge "$mt" ] || newest=$mt
    done < <(cd "$primary" && { dforge_resolve "$spec" "$primary"; dforge_stores_init "$primary"; _spec_plan_files "$primary" "$spec" | cut -f2; } 2>/dev/null)
  fi
  printf '%s|%s|%s' "$lines" "$head" "$newest"
}

# ar_capped EVENT FILTER [jq options…] — ar_update with FILTER, in which
# cap_stop(COUNT; CAP; REASON) stops the run once COUNT reaches CAP: the count
# and the stop are one locked write, so no update lands between them. Logs
# EVENT (when not empty), then the stop; returns 5 when this update stopped the
# run.
ar_capped() {
  local event=$1 filter=$2 at stopped
  shift 2
  at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  ar_update 'def cap_stop($n; $cap; $r): if $n >= $cap
      then .active = false | .stopped = $r | .stoppedAt = $at | .stoppedKind = null | .pending = null
      else . end; '"$filter" --arg at "$at" "$@" || return
  [ -z "$event" ] || ar_log "$event"
  stopped=$(ar_state | ar_jq -r --arg at "$at" 'select(.active == false and .stoppedAt == $at) | .stopped // empty')
  [ -n "$stopped" ] || return 0
  ar_log stop "$stopped"
  return 5
}

# ar_compacted — book a compaction. In execute it counts toward
# AR_COMPACTION_CAP, reached without a completed task; in the other phases
# toward the same cap, reached while ar_progress_mark stays unchanged. Either
# stops the run (return 5): a step that cannot fit in a window would otherwise
# loop. --seconds N adds the compaction's duration to totals.compactionSeconds.
ar_compacted() {
  local secs=0 mark=""
  [ "${1:-}" = --seconds ] && secs=$2
  [ "$(ar_get phase)" = execute ] || mark=$(ar_progress_mark)
  ar_capped compacted '.compactions += 1 | .failures = 0 | .pending = "after-compact"
    | .totals.compactionSeconds = ((.totals.compactionSeconds // 0) + $secs)
    | if .phase == "execute"
      then .compactionsSinceTask = ((.compactionsSinceTask // 0) + 1)
        | cap_stop(.compactionsSinceTask; $cap; "\($cap) compactions without a completed task")
      elif .progressMark == $mark
      then .compactionsSinceProgress = ((.compactionsSinceProgress // 0) + 1)
        | cap_stop(.compactionsSinceProgress; $cap; "\($cap) compactions in \(.phase) without progress")
      else .progressMark = $mark | .compactionsSinceProgress = 1 end' \
    --argjson secs "$secs" --arg mark "$mark" --argjson cap "$AR_COMPACTION_CAP"
}

ar_failure() { # ar_failure [REASON] — return 5 when this failure stops the run
  ar_capped '' '.failures = ((.failures // 0) + 1) | cap_stop(.failures; $cap; $r)' \
    --argjson cap "$AR_FAILURE_CAP" --arg r "${1:-the cockpit could not compact or clear}"
}

# ar_stalled — the cockpit found the run idle with no sentinel answered, and
# nudged it. The AR_STALL_CAP-th since the last completed task stops the run
# (return 5).
ar_stalled() {
  ar_capped stalled '.stalls = ((.stalls // 0) + 1) | .stalledAt = $now | .totals.stalls = ((.totals.stalls // 0) + 1)
    | cap_stop(.stalls; $cap; "\($cap) stalls without a completed task")' \
    --argjson now "$(date +%s)" --argjson cap "$AR_STALL_CAP"
}

# ar_api_error [--clear] — count a turn that ended on an API error, apart from
# stalls; the tenth in a row stops the run (return 5). --clear resets the count.
ar_api_error() {
  if [ "${1:-}" = --clear ]; then
    ar_update '.apiErrors = 0'
    return
  fi
  ar_capped '' '.apiErrors = ((.apiErrors // 0) + 1) | .totals.apiErrors = ((.totals.apiErrors // 0) + 1)
    | cap_stop(.apiErrors; $cap; "\($cap) API errors in a row")' --argjson cap "$AR_API_ERROR_CAP"
}

ar_decision_add() { # ar_decision_add ID QUESTION OPTIONS REASON TASK
  ar_update '.decisions = (((.decisions // []) | map(select(.id != $id))) + [{id: $id, question: $q, options: $o, opusReason: $r, task: (if $t == "" then null else $t end)}])' \
    --arg id "$1" --arg q "$2" --arg o "$3" --arg r "$4" --arg t "$5"
}

ar_decision_list() { ar_state | ar_jq -c '(.decisions // [])[]'; }

ar_decision_clear() { # ar_decision_clear [ID]
  if [ -n "${1:-}" ]; then
    ar_update '.decisions = ((.decisions // []) | map(select(.id != $id)))' --arg id "$1"
  else
    ar_update '.decisions = []'
  fi
}

ar_ruling_add() { ar_update '.rulings = ((.rulings // []) + [$t])' --arg t "$1"; }

ar_ruling_list() { ar_state | ar_jq -r '(.rulings // [])[]'; }

AR_HIGH_PCT=90
AR_AFTER_HANDOFF_PCT=85
AR_AFTER_HIGH_PCT=85

# ar_hard BUDGET WINDOW — the most a session may hold outside execute:
# BUDGET plus a quarter, below Claude Code's compaction point (93% of the
# window) by 40000, and never below BUDGET.
ar_hard() {
  local hard point
  hard=$(( $1 * 125 / 100 )) point=$(( $2 * 93 / 100 - 40000 ))
  [ "$hard" -le "$point" ] || hard=$point
  [ "$hard" -ge "$1" ] || hard=$1
  echo "$hard"
}

# ar_limit BUDGET WINDOW REGIME [PHASE] — where a checkpoint compacts: the
# task budget, or AR_HIGH_PCT of the window in the high regime, capped at
# ar_hard in the phases no compaction hands off from or before (spec, plan,
# final, finish). PHASE defaults to the run's.
ar_limit() {
  local limit phase hard
  if [ $# -ge 4 ]; then phase=$4; else phase=$(ar_get phase 2>/dev/null); fi
  if [ "$3" = high ]; then
    limit=$(( $2 * AR_HIGH_PCT / 100 ))
    case $phase in
      spec | plan | final | finish)
        hard=$(ar_hard "$1" "$2")
        [ "$limit" -le "$hard" ] || limit=$hard
        ;;
    esac
  else
    limit=$1
  fi
  [ "$limit" -gt 0 ] || limit=1
  echo "$limit"
}

# ar_after P BUDGET WINDOW — the after-compaction rule: handoff, high or normal.
ar_after() {
  if [ $(( $1 * 100 )) -ge $(( $3 * AR_AFTER_HANDOFF_PCT )) ]; then echo handoff
  elif [ $(( $1 * 100 )) -ge $(( $2 * AR_AFTER_HIGH_PCT )) ]; then echo high
  else echo normal
  fi
}

# ar_holds_session — true in the phases no compaction hands off from: the plan
# is written, the final review runs, and finishing runs in its own session.
ar_holds_session() {
  ar_state | ar_jq -e '.phase == "plan" or .phase == "final" or .phase == "finish"' >/dev/null 2>&1
}

# ar_settle P BUDGET WINDOW — apply the after-compaction rule to the run: set
# the regime, clear pending, print continue; a handoff keeps the regime and
# stays pending until clear. A phase that holds the session takes the high
# regime instead of a handoff.
ar_settle() {
  local result
  result=$(ar_after "$1" "$2" "$3")
  if [ "$result" = handoff ] && ar_holds_session; then result=high; fi
  if [ "$result" = handoff ]; then
    ar_update '.pending = "handoff"' || return $?
    echo handoff
    return
  fi
  ar_update '.regime = $r | .pending = null' --arg r "$result" || return $?
  echo continue
}

# ar_verdict TOKENS BUDGET WINDOW [EARLY] — prints "<ok|compact|handoff>
# <limit> <regime>". A compaction not yet measured is settled first with TOKENS
# as its size; a pending clear is a handoff in progress. In execute the
# boundary is limit - BUDGET/5: with EARLY 1 (a task boundary) a compaction is
# due from there. An ok clears a pending compaction only below the boundary
# (the limit outside execute), so one booked at a task boundary survives other
# callers' lines; it also clears a resume the cockpit never confirmed: the
# session measuring itself is the resumed one.
# WINDOW 0 is an unknown window: "unknown 0 <regime>", status 3, and no
# size-based compaction or handoff; a pending compaction settles to continue,
# so a Stop hold that waits on it cannot repeat forever.
ar_verdict() {
  local tokens=$1 budget=$2 window=$3 early=${4:-0} pending regime limit settled boundary threshold
  pending=$(ar_get pending)
  if [ "$window" = 0 ]; then
    if [ "$pending" = after-compact ]; then ar_update '.pending = null' || return $?; fi
    regime=$(ar_get regime)
    echo "unknown 0 ${regime:-normal}"
    return 3
  fi
  if [ "$pending" = after-compact ]; then
    settled=$(ar_settle "$tokens" "$budget" "$window") || return $?
    [ "$settled" != handoff ] || pending=handoff
  fi
  regime=$(ar_get regime)
  regime=${regime:-normal}
  limit=$(ar_limit "$budget" "$window" "$regime")
  boundary=$limit
  if [ "$(ar_get phase)" = execute ]; then
    boundary=$(( limit - budget / 5 ))
    [ "$boundary" -ge 1 ] || boundary=1
  fi
  threshold=$limit
  [ "$early" != 1 ] || threshold=$boundary
  if [ "$pending" = handoff ] || [ "$pending" = clear ]; then
    echo "handoff $limit $regime"
  elif [ "$tokens" -ge "$threshold" ]; then
    ar_update '.pending = "compact"' || return $?
    echo "compact $limit $regime"
  else
    if { [ "$pending" = compact ] && [ "$tokens" -lt "$boundary" ]; } || [ "$pending" = resume ]; then
      ar_update '.pending = null' || return $?
    fi
    echo "ok $limit $regime"
  fi
}
