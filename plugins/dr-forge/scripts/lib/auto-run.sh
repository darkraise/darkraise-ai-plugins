# Sourced. An auto run's state (reference/auto-run.md): one JSON file in the
# primary checkout's self-ignoring sdd/ directory, bound to one session.
# Defines functions only; scripts/auto-run is the command line.
#
# AR_SESSION names the caller. A caller whose session the run is not bound to
# sees no run, so another session in the same repository never acts on it.

. "$(dirname "${BASH_SOURCE[0]}")/forge-dir.sh"

AR_STALE_MINUTES=60
AR_RESUME_CAP=3
AR_FAILURE_CAP=2

ar_jq() { "${DR_FORGE_JQ:-jq}" "$@"; }

ar_primary_root() {
  local common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null || return 1
}

# ar_path — the state file's path, whether or not it exists.
ar_path() {
  local primary
  primary=$(ar_primary_root) || return 1
  printf '%s/sdd/auto-run.json\n' "$(forge_dir state "$primary")"
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
ar_update() {
  local path tmp filter=$1
  shift
  path=$(ar_path) || return 1
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
  rec="$HOME/.claude/dr-forge/sessions/by-id/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-').json"
  if [ -f "$rec" ]; then
    tp=$(ar_jq -r '.transcript_path // empty' < "$rec" 2>/dev/null | tr -d '\r')
    if [ -n "$tp" ] && command -v cygpath >/dev/null 2>&1; then tp=$(cygpath -u "$tp"); fi
    if [ -n "$tp" ] && [ -f "$tp" ]; then printf '%s\n' "$tp"; return 0; fi
  fi
  tp=$(ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$1".jsonl 2>/dev/null | head -n 1)
  [ -n "$tp" ] || return 1
  printf '%s\n' "$tp"
}

# ar_is_stale — true when the run's session has not written its transcript
# within AR_STALE_MINUTES, or has none: whoever owned the run is gone.
ar_is_stale() {
  local sid tp
  sid=$(ar_get session)
  [ -n "$sid" ] || return 0
  tp=$(ar_transcript "$sid") || return 0
  [ -n "$(find "$tp" -mmin +"$AR_STALE_MINUTES" 2>/dev/null)" ]
}

# ar_start SPEC REGISTER FORCE — prints the register path. A register it
# creates goes in the checkout the run starts from, where its path resolves.
ar_start() {
  local spec=$1 register=$2 force=$3 path top slug base
  path=$(ar_path) || { echo "auto-run: not inside a git repository" >&2; return 2; }
  if [ "$force" != 1 ] && ar_state | ar_jq -e '.active == true' >/dev/null 2>&1 && ! ar_is_stale; then
    echo "auto-run: an auto run is already active ($(ar_state | ar_jq -r '.spec')); stop it with auto-run stop, or pass --force" >&2
    return 4
  fi
  top=$(git rev-parse --show-toplevel)
  if [ -z "$register" ]; then
    slug=$(basename "$spec" .md)
    slug=${slug%-design}
    slug=$(sed -E 's/^[0-9]{4}-[0-9]{2}-[0-9]{2}-//' <<<"$slug")
    register="$(forge_dir_rel docs "$top")/registers/$(date +%Y-%m-%d)-$slug-auto.md"
    if [ ! -f "$top/$register" ]; then
      mkdir -p "$(dirname "$top/$register")" || return 1
      printf '# Auto run: %s\n\n**Source:** items the auto run for `%s` deferred\n**Covers:** %s\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n' \
        "$slug" "$spec" "$spec" > "$top/$register" || return 1
    fi
  fi
  base=$(git symbolic-ref --short -q HEAD 2>/dev/null || true)
  mkdir -p "$(dirname "$path")" || return 1
  [ -f "$(dirname "$path")/.gitignore" ] || printf '*\n' > "$(dirname "$path")/.gitignore"
  ar_jq -n --arg s "$AR_SESSION" --arg spec "$spec" --arg reg "$register" --arg base "$base" \
    --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    active: true, session: $s, rebind: false, stopped: null, startedAt: $now,
    spec: $spec, plan: null, register: $reg, base: (if $base == "" then null else $base end),
    phase: "spec", regime: "normal", pending: null, resumePrompt: null, launch: null,
    failures: 0, compactions: 0, resumes: 0, decisions: [], rulings: []
  }' > "$path" || return 1
  printf '%s\n' "$register"
}

ar_status() {
  ar_state | ar_jq -r '"auto run: \(.phase) — regime \(.regime) — pending \(.pending // "none") — \(.compactions) compactions — \(.resumes) resumes — \(.decisions | length) pending decisions — spec \(.spec) — plan \(.plan // "none") — base \(.base // "none") — register \(.register)"'
}

ar_pending() { ar_state | ar_jq -r '.pending // "none"'; }

ar_stop() { # ar_stop [REASON]
  ar_update '.active = false | .stopped = (if $r == "" then null else $r end) | .pending = null' --arg r "${1:-}"
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

# ar_clear PHASE — the cleared session's first prompt and launch, from the
# handoff scripts/next-step just wrote. PHASE 1 for a phase clear; otherwise
# the clear is a self-resume, and the AR_RESUME_CAP-th in a row stops the run
# (return 5).
ar_clear() {
  local is_phase=$1 primary latest prompt="" launch model="" effort="" resumes
  primary=$(ar_primary_root) || return 1
  latest="$(forge_dir state "$primary")/handoff/latest.md"
  [ -f "$latest" ] && prompt=$(ar_fenced "$latest" 'Paste as the first prompt:')
  [ -n "$prompt" ] || { echo "auto-run: no first prompt in $latest; run scripts/next-step first" >&2; return 1; }
  launch=$(ar_fenced "$latest" 'Launch in ' | head -n 1)
  if [[ $launch =~ claude\ --model\ ([^ ]+)\ --effort\ ([^ ]+) ]]; then
    model=${BASH_REMATCH[1]} effort=${BASH_REMATCH[2]}
  fi
  resumes=$(ar_get resumes)
  resumes=${resumes:-0}
  if [ "$is_phase" != 1 ]; then
    resumes=$((resumes + 1))
    if [ "$resumes" -ge "$AR_RESUME_CAP" ]; then
      ar_stop "three self-resumes without a completed task"
      echo "auto-run: stopped — $AR_RESUME_CAP self-resumes in a row without a completed task" >&2
      return 5
    fi
  fi
  ar_update '.pending = "clear" | .rebind = true | .resumes = ($r | tonumber) | .resumePrompt = $p
    | .launch = (if $m == "" then null else {model: $m, effort: $e} end)' \
    --arg r "$resumes" --arg p "$prompt" --arg m "$model" --arg e "$effort"
}

ar_rebind() { # ar_rebind ID
  ar_state | ar_jq -e '.active == true and .rebind == true' >/dev/null 2>&1 \
    || { echo "auto-run: no clear is waiting for its session" >&2; return 4; }
  ar_update '.session = $id | .rebind = false | .pending = "resume" | .failures = 0 | .regime = "normal"' --arg id "$1"
}

ar_resumed() { ar_update 'if .pending == "resume" then .pending = null else . end'; }

ar_compacted() { ar_update '.compactions += 1 | .failures = 0 | .pending = "after-compact"'; }

ar_failure() { # ar_failure [REASON] — return 5 when this failure stops the run
  local n
  n=$(ar_get failures)
  n=$(( ${n:-0} + 1 ))
  if [ "$n" -ge "$AR_FAILURE_CAP" ]; then
    ar_stop "${1:-the cockpit could not compact or clear}"
    return 5
  fi
  ar_update '.failures = ($n | tonumber)' --arg n "$n"
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

AR_TASK_MARGIN=140000
AR_HIGH_PCT=90
AR_AFTER_HANDOFF_PCT=85
AR_AFTER_HIGH_PCT=85

# ar_limit BUDGET WINDOW N REGIME — where a checkpoint covering N tasks
# compacts: the task budget, or AR_HIGH_PCT of the window in the high regime,
# less one task's worst growth for each task beside the first.
ar_limit() {
  local limit
  if [ "$4" = high ]; then limit=$(( $2 * AR_HIGH_PCT / 100 )); else limit=$1; fi
  limit=$(( limit - ($3 - 1) * AR_TASK_MARGIN ))
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

# ar_settle P BUDGET WINDOW — apply the after-compaction rule to the run: set
# the regime, clear pending, print continue or handoff.
ar_settle() {
  local result regime
  result=$(ar_after "$1" "$2" "$3")
  if [ "$result" = handoff ]; then regime=$(ar_get regime); else regime=$result; fi
  ar_update '.regime = $r | .pending = null' --arg r "${regime:-normal}" || return 1
  if [ "$result" = handoff ]; then echo handoff; else echo continue; fi
}

# ar_verdict TOKENS BUDGET WINDOW [N] — prints "<ok|compact|handoff> <limit>
# <regime>". A compaction not yet measured is settled first with TOKENS as its
# size; a pending clear is a handoff in progress. An ok clears a compaction a
# wider wave probe requested.
ar_verdict() {
  local tokens=$1 budget=$2 window=$3 n=${4:-1} pending regime limit
  pending=$(ar_get pending)
  if [ "$pending" = after-compact ] && [ "$(ar_settle "$tokens" "$budget" "$window")" = handoff ]; then
    pending=handoff
  fi
  regime=$(ar_get regime)
  regime=${regime:-normal}
  limit=$(ar_limit "$budget" "$window" "$n" "$regime")
  if [ "$pending" = handoff ] || [ "$pending" = clear ]; then
    echo "handoff $limit $regime"
  elif [ "$tokens" -ge "$limit" ]; then
    ar_update '.pending = "compact"' || return 1
    echo "compact $limit $regime"
  else
    if [ "$pending" = compact ]; then ar_update '.pending = null' || return 1; fi
    echo "ok $limit $regime"
  fi
}
