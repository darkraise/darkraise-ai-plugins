# Sourced. An auto run's state (reference/auto-run.md): one JSON file in the
# primary checkout's self-ignoring sdd/ directory, bound to one session.
# Defines functions only; scripts/auto-run is the command line. The limits use
# CTX_TASK_MARGIN, so scripts/lib/context.sh is sourced first.
#
# AR_SESSION names the caller. A caller whose session the run is not bound to
# sees no run, so another session in the same repository never acts on it.

. "$(dirname "${BASH_SOURCE[0]}")/roots.sh"

AR_STALE_MINUTES=60
AR_LOCK_TENTHS=100
AR_RESUME_CAP=3
AR_FAILURE_CAP=2
AR_BEAT_SECONDS=180

ar_jq() { "${DFORGE_JQ:-jq}" "$@"; }

ar_primary_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null || return 1
}

# ar_in_primary — true in the primary checkout. An auto run's tasks run in a
# linked worktree (dforge:using-git-worktrees), so a task step here would land
# on the run's base.
ar_in_primary() {
  local dir common
  dir=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  [ "$dir" = "$common" ]
}

# ar_path — the state file's path, whether or not it exists.
ar_path() {
  local primary
  primary=$(ar_primary_root) || return 1
  printf '%s/sdd/auto-run.json\n' "$(dforge_dir state "$primary")"
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
# each reading the file the other is about to replace.
ar_update() {
  local path status
  path=$(ar_path) || return 1
  if command -v "${DFORGE_FLOCK:-flock}" >/dev/null 2>&1; then
    (
      "${DFORGE_FLOCK:-flock}" -w 10 9 || exit 1
      ar_write "$path" "$@"
    ) 9>>"$path.lock"
    return
  fi
  ar_lock_dir "$path.lockd" || return 1
  ar_write "$path" "$@"
  status=$?
  rmdir "$path.lockd" 2>/dev/null
  return $status
}

# ar_lock_dir DIR — mkdir as the lock where flock is missing (macOS, some Git
# Bash builds). A write holds it for milliseconds, so a lock still held after
# AR_LOCK_TENTHS tenths of a second belongs to a process that died: take it.
ar_lock_dir() {
  local i
  for ((i = 0; i < AR_LOCK_TENTHS; i++)); do
    mkdir "$1" 2>/dev/null && return 0
    sleep 0.1
  done
  rmdir "$1" 2>/dev/null
  mkdir "$1" 2>/dev/null
}

ar_write() { # ar_write PATH FILTER [jq options…]
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

# ar_get FIELD — one field, raw; empty for null or false.
ar_get() {
  ar_state | ar_jq -r --arg f "$1" '.[$f] // empty | if type == "array" or type == "object" then tojson else tostring end'
}

# ar_transcript SESSION — the session's transcript: its by-id record's path,
# else the projects tree's <SESSION>.jsonl. Records hold native paths, so a
# Windows path is converted as scripts/lib/context.sh does.
ar_transcript() {
  local rec tp
  rec="$HOME/.claude/dforge/sessions/by-id/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-').json"
  if [ -f "$rec" ]; then
    tp=$(ar_jq -r '.transcript_path // empty' < "$rec" 2>/dev/null | tr -d '\r')
    if [ -n "$tp" ] && command -v cygpath >/dev/null 2>&1; then tp=$(cygpath -u "$tp"); fi
    if [ -n "$tp" ] && [ -f "$tp" ]; then printf '%s\n' "$tp"; return 0; fi
  fi
  tp=$(ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$1".jsonl 2>/dev/null | head -n 1)
  [ -n "$tp" ] || return 1
  printf '%s\n' "$tp"
}

# ar_beat_file SESSION — where the session's cockpit writes its heartbeat: the
# epoch seconds of its last beat.
ar_beat_file() {
  printf '%s/.claude/dforge/sessions/cockpit/%s\n' "${HOME:-}" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
}

# ar_beat_age SESSION — seconds since the session's cockpit last beat; fails
# when the file is missing or holds no number.
ar_beat_age() {
  local file beat
  file=$(ar_beat_file "$1")
  [ -f "$file" ] || return 1
  beat=$(head -n 1 "$file" | tr -dc '0-9')
  [ -n "$beat" ] || return 1
  echo $(( $(date +%s) - beat ))
}

# ar_is_stale — true when whoever owned the run is gone: its session's cockpit
# heartbeat is older than AR_BEAT_SECONDS, or, for a session with no heartbeat
# file, its transcript was not written within AR_STALE_MINUTES or it has none.
ar_is_stale() {
  local sid tp age
  sid=$(ar_get session)
  [ -n "$sid" ] || return 0
  if [ -f "$(ar_beat_file "$sid")" ]; then
    age=$(ar_beat_age "$sid") || return 0
    [ "$age" -gt "$AR_BEAT_SECONDS" ]
    return
  fi
  tp=$(ar_transcript "$sid") || return 0
  [ -n "$(find "$tp" -mmin +"$AR_STALE_MINUTES" 2>/dev/null)" ]
}

# ar_start SPEC REGISTER FORCE — prints the register path. A register it
# creates goes in the checkout the run starts from, where its path resolves.
ar_start() {
  local spec=$1 register=$2 force=$3 path top slug base tmp regfile age
  path=$(ar_path) || { echo "auto-run: not inside a git repository" >&2; return 2; }
  # Nothing would compact, switch or wake the run without the cockpit.
  age=$(ar_beat_age "$AR_SESSION") && [ "$age" -le "$AR_BEAT_SECONDS" ] \
    || { echo "auto-run: no live cockpit in this session" >&2; return 2; }
  if [ "$force" != 1 ] && ar_state | ar_jq -e '.active == true' >/dev/null 2>&1 && ! ar_is_stale; then
    echo "auto-run: an auto run is already active ($(ar_state | ar_jq -r '.spec')); stop it with auto-run stop, or pass --force" >&2
    return 4
  fi
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
    fi
  fi
  base=$(git symbolic-ref --short -q HEAD 2>/dev/null || true)
  mkdir -p "$(dirname "$path")" || return 1
  [ -f "$(dirname "$path")/.gitignore" ] || printf '*\n' > "$(dirname "$path")/.gitignore"
  tmp=$(mktemp "$path.XXXXXX") || return 1
  if ! ar_jq -n --arg s "$AR_SESSION" --arg spec "$spec" --arg reg "$register" --arg base "$base" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    active: true, session: $s, rebind: false, stopped: null, startedAt: $now,
    spec: $spec, plan: null, register: $reg, base: (if $base == "" then null else $base end),
    phase: "spec", regime: "normal", pending: null, resumePrompt: null, launch: null,
    failures: 0, compactions: 0, resumes: 0, decisions: [], rulings: [],
    setupDue: false, stalls: 0, stalledAt: null, compactionsSinceTask: 0
  }' > "$tmp"; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$path" || return 1
  printf '%s\n' "$register"
}

ar_status() {
  ar_state | ar_jq -r '"auto run: \(.phase) — regime \(.regime) — pending \(.pending // "none") — \(.compactions) compactions — \(.resumes) resumes — \(.decisions | length) pending decisions — spec \(.spec) — plan \(.plan // "none") — base \(.base // "none") — register \(.register)\(if .setupDue == true then " — setup due" else "" end)"'
}

ar_pending() { ar_state | ar_jq -r '.pending // "none"'; }

ar_stop() { # ar_stop [REASON]
  ar_update '.active = false | .stopped = (if $r == "" then null else $r end) | .pending = null' --arg r "${1:-}"
}

# ar_set_phase PHASE — refuses execute in the primary checkout (return 4): the
# execution worktree Setup makes is missing. execute and final settle Setup.
ar_set_phase() {
  if [ "$1" = execute ] && ar_in_primary; then
    echo "auto-run: this is the primary checkout; create the execution worktree first (dforge:using-git-worktrees), then run auto-run phase execute from it" >&2
    return 4
  fi
  ar_update '.phase = $p | if $p == "execute" or $p == "final" then .setupDue = false else . end' --arg p "$1"
}

# ar_task_complete — a task's complete line is written, so the progress counts
# start again. In the primary checkout that task ran on the run's base: the run
# stops (return 5) rather than finish there.
ar_task_complete() {
  if ar_in_primary; then
    ar_stop "a task was completed in the primary checkout" || return 1
    echo "auto-run: a task was completed in the primary checkout; the run has stopped. End as reference/auto-run.md §Stopping says." >&2
    return 5
  fi
  ar_update '.resumes = 0 | .stalls = 0 | .stalledAt = null | .compactionsSinceTask = 0 | .setupDue = false'
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

# ar_handoff — the first prompt and launch from the handoff scripts/next-step
# just wrote, into AR_PROMPT, AR_MODEL and AR_EFFORT.
ar_handoff() {
  local primary latest launch
  AR_PROMPT="" AR_MODEL="" AR_EFFORT=""
  primary=$(ar_primary_root) || return 1
  dforge_stores_init "$primary"
  latest=$(dforge_latest_file "$primary")
  [ -f "$latest" ] && AR_PROMPT=$(ar_fenced "$latest" 'Paste as the first prompt:')
  [ -n "$AR_PROMPT" ] || { echo "auto-run: no first prompt in $latest; run scripts/next-step first" >&2; return 1; }
  launch=$(ar_fenced "$latest" 'Launch in ' | head -n 1)
  if [[ $launch =~ claude\ --model\ ([^ ]+)\ --effort\ ([^ ]+) ]]; then
    AR_MODEL=${BASH_REMATCH[1]} AR_EFFORT=${BASH_REMATCH[2]}
  fi
}

# ar_switch — at plan saved, the in-place move to execution: the first prompt
# and launch as ar_clear reads them. Refuses (return 4) without an attached
# plan, or when the first prompt names another plan. Never a self-resume. The
# phase moves to execute, so the switch's compaction is measured under
# execution's rules and an oversized one still hands off. Setup is due until
# a phase execute from the execution worktree, a task-complete or phase final.
ar_switch() {
  local plan
  plan=$(ar_get plan)
  [ -n "$plan" ] || { echo "auto-run: no plan is attached; run auto-run attach --plan first" >&2; return 4; }
  ar_handoff || return 1
  [[ $AR_PROMPT == *"$(basename "$plan")"* ]] \
    || { echo "auto-run: the handoff's first prompt names another plan than $plan; run scripts/next-step $plan again" >&2; return 4; }
  ar_update '.pending = "switch" | .phase = "execute" | .setupDue = true | .compactionsSinceTask = 0 | .resumePrompt = $p
    | .launch = (if $m == "" then null else {model: $m, effort: $e} end)' \
    --arg p "$AR_PROMPT" --arg m "$AR_MODEL" --arg e "$AR_EFFORT"
}

# ar_clear PHASE — the cleared session's first prompt and launch, from the
# handoff scripts/next-step just wrote. PHASE 1 for a phase clear; otherwise
# the clear is a self-resume, and the AR_RESUME_CAP-th in a row stops the run
# (return 5).
ar_clear() {
  local is_phase=$1 resumes
  ar_handoff || return 1
  if [ "$is_phase" != 1 ]; then
    ar_update '.resumes = ((.resumes // 0) + 1)' || return 1
    resumes=$(ar_get resumes)
    if [ "${resumes:-0}" -ge "$AR_RESUME_CAP" ]; then
      ar_stop "three self-resumes without a completed task" || return 1
      echo "auto-run: stopped — $AR_RESUME_CAP self-resumes in a row without a completed task" >&2
      return 5
    fi
  fi
  ar_update '.pending = "clear" | .rebind = true | .resumePrompt = $p
    | .launch = (if $m == "" then null else {model: $m, effort: $e} end)' \
    --arg p "$AR_PROMPT" --arg m "$AR_MODEL" --arg e "$AR_EFFORT"
}

ar_rebind() { # ar_rebind ID
  ar_state | ar_jq -e '.active == true and .rebind == true' >/dev/null 2>&1 \
    || { echo "auto-run: no clear is waiting for its session" >&2; return 4; }
  ar_update '.session = $id | .rebind = false | .pending = "resume" | .failures = 0 | .regime = "normal"' --arg id "$1"
}

# ar_resumed — the cockpit submitted its stage's prompt. After a switch the
# compaction is still to be measured, so after-compact becomes due.
ar_resumed() {
  ar_update '.failures = 0
    | if .pending == "resume" then .pending = null
      elif .pending == "switch-resume" then .pending = "after-compact"
      else . end'
}

# ar_compacted [--switch] — book a compaction; the switch's own leaves its
# resume stage due. One in the final or finish phase sets finalCompacted, after
# which every budget line of the run says ok.
ar_compacted() {
  local next=after-compact
  [ "${1:-}" = --switch ] && next=switch-resume
  ar_update '.compactions += 1 | .failures = 0 | .pending = $n
    | .finalCompacted = ((.finalCompacted // false) or .phase == "final" or .phase == "finish")' --arg n "$next"
}

ar_failure() { # ar_failure [REASON] — return 5 when this failure stops the run
  local n
  ar_update '.failures = ((.failures // 0) + 1)' || return 1
  n=$(ar_get failures)
  if [ "${n:-0}" -ge "$AR_FAILURE_CAP" ]; then
    ar_stop "${1:-the cockpit could not compact or clear}" || return 1
    return 5
  fi
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

# ar_limit BUDGET WINDOW N REGIME — where a checkpoint covering N tasks
# compacts: the task budget, or AR_HIGH_PCT of the window in the high regime,
# less one task's worst growth for each task beside the first.
ar_limit() {
  local limit
  if [ "$4" = high ]; then limit=$(( $2 * AR_HIGH_PCT / 100 )); else limit=$1; fi
  limit=$(( limit - ($3 - 1) * CTX_TASK_MARGIN ))
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
# is written, and the final review and finishing run, in this session.
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
    ar_update '.pending = "handoff"' || return 1
    echo handoff
    return
  fi
  ar_update '.regime = $r | .pending = null' --arg r "$result" || return 1
  echo continue
}

# ar_verdict TOKENS BUDGET WINDOW [N] — prints "<ok|compact|handoff> <limit>
# <regime>". A compaction not yet measured is settled first with TOKENS as its
# size; a pending clear is a handoff in progress. An ok clears a compaction a
# wider wave probe requested. Once a compaction ran in the final phases
# (finalCompacted) it never asks for another: Claude Code's own is the backstop.
ar_verdict() {
  local tokens=$1 budget=$2 window=$3 n=${4:-1} pending regime limit settled
  pending=$(ar_get pending)
  if [ "$pending" = after-compact ]; then
    settled=$(ar_settle "$tokens" "$budget" "$window") || return 1
    [ "$settled" != handoff ] || pending=handoff
  fi
  regime=$(ar_get regime)
  regime=${regime:-normal}
  limit=$(ar_limit "$budget" "$window" "$n" "$regime")
  if [ "$pending" = handoff ] || [ "$pending" = clear ]; then
    echo "handoff $limit $regime"
  elif [ "$tokens" -ge "$limit" ] && ! ar_state | ar_jq -e '.finalCompacted == true' >/dev/null 2>&1; then
    ar_update '.pending = "compact"' || return 1
    echo "compact $limit $regime"
  else
    if [ "$pending" = compact ]; then ar_update '.pending = null' || return 1; fi
    echo "ok $limit $regime"
  fi
}
