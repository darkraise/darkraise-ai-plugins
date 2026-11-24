#!/usr/bin/env bash
# Efficiency measurement and auto-run polish: the skill and instruction text
# the spec pins (A9, A10).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/../../plugins/dagents" && pwd)"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
# flat — stdin as one line: newlines to spaces, runs of spaces squeezed, case folded.
flat() { tr -d '\r' | tr '\n' ' ' | tr -s ' ' | tr '[:upper:]' '[:lower:]'; }
has() { case $1 in *"$2"*) echo yes ;; *) echo no ;; esac; }

# --- lookups_block_early ---
SKILL="$P/skills/executing-plans/SKILL.md"
check "lookups_block_early: ## Lookups within the first 15,000 characters" \
  "$(head -c 15000 "$SKILL" | tr -d '\r' | grep -c '^## Lookups$')" "1"
check "lookups_block_early: no claim that the session has read the code" \
  "$(has "$(flat < "$SKILL")" 'session has read the code')" "no"

# --- compact_instructions_bounded ---
COCKPIT=$(tr -d '\r' < "$P/hooks/cockpit/register.tsx" | awk '/^const AUTO_COMPACT_INSTRUCTIONS =/ { f = 1; next } f { print; exit }' | flat)
BUDGET=$(tr -d '\r' < "$P/reference/session-budget.md" | awk '/^# Compact instructions$/ { f = 1; next } f && /^```/ { exit } f' | flat)
for phrase in 'at most 1,500 words' 'rulings only for the task in flight and plan-wide rulings' 'one line per finished task'; do
  check "compact_instructions_bounded: the cockpit says '$phrase'" "$(has "$COCKPIT" "$phrase")" "yes"
  check "compact_instructions_bounded: session-budget.md says '$phrase'" "$(has "$BUDGET" "$phrase")" "yes"
done

# --- mirror_audit ---
# Each polish item and the markers and report: the dagents cases that mirror
# it (every one must exist), or a row of fixtures/mirror-na.tsv with a reason.
ROOT="$(cd "$HERE/../.." && pwd)"
NA="$HERE/fixtures/mirror-na.tsv"
MIRROR='1	tests/dagents/efficiency-measurement.acceptance.test.sh::compact_instructions_bounded
2	tests/dagents/auto-run.test.sh::resume_reactivates
2	tests/dagents/auto-run.test.sh::resume_refusals
3	tests/dagents/auto-run.test.sh::version_mismatch_warns_once
3	plugins/dagents/tests/cockpit.test.ts::run row shows mismatch
4	tests/dagents/budget-line.test.sh::task_complete_prints_auto_line
5	tests/dagents/codex-review.test.sh::quota_skip_in_run
5	tests/dagents/codex-review.test.sh::prompt_says_headless
7	tests/dagents/task-step.test.sh::verdict_line_ref_parenthetical
8	tests/dagents/impl-stop-gate.test.sh::ui_proof_exempt
9	tests/dagents/auto-run.test.sh::api_error_counts_apart
9	plugins/dagents/tests/cockpit.test.ts::api-error ending re-prompts
10	tests/dagents/auto-run.test.sh::counters_after_events
10	plugins/dagents/tests/cockpit.test.ts::compaction books seconds
markers	tests/dagents/usage-marker.test.sh::task_step_start_opens_each
markers	tests/dagents/usage-marker.test.sh::marker_failure_silent
report	tests/dagents/usage-report.test.sh::wrapper_reads_own_stores'
check "mirror_audit: fixtures/mirror-na.tsv exists" "$([ -f "$NA" ] && echo yes || echo no)" "yes"
bad=$(tr -d '\r' 2>/dev/null < "$NA" | awk -F'\t' 'NF && ($1 == "" || $2 == "")' | wc -l | tr -d ' ')
check "mirror_audit: every n/a row names an item and a reason" "$bad" "0"
for item in 1 2 3 4 5 7 8 9 10 markers report; do
  cases=$(printf '%s\n' "$MIRROR" | awk -F'\t' -v i="$item" '$1 == i { print $2 }')
  missing=""
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    grep -qF -- "${c#*::}" "$ROOT/${c%%::*}" 2>/dev/null || missing="$missing ${c}"
  done <<<"$cases"
  if [ -n "$cases" ] && [ -z "$missing" ]; then got=mirrored
  elif tr -d '\r' 2>/dev/null < "$NA" | awk -F'\t' -v i="$item" '$1 == i && $2 != "" { f = 1 } END { exit !f }'; then got="n/a"
  else got="neither:${missing:- no case}"; fi
  check "mirror_audit: polish $item is mirrored or n/a" "$( [ "${got#neither}" = "$got" ] && echo ok || echo "$got")" "ok"
done
# Polish 5 is mirrored for the Codex family only: the rest must be recorded n/a.
check "mirror_audit: polish 5's panel and agy runner are recorded n/a" \
  "$(tr -d '\r' 2>/dev/null < "$NA" | awk -F'\t' '$1 == "5" && $2 != "" { n++ } END { print n + 0 }')" "1"

# ---------------------------------------------------------------------------
# The same statements against this plugin's own stores (A2-A4, A6, A11-A18,
# A22-A25, A27-A29), through its public scripts.
# ---------------------------------------------------------------------------
TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/projects/fx"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DAGENTS_NO_SETTINGS=1
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DAGENTS_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR \
  USAGE_MARK USAGE_MARK_PLAN USAGE_MARK_TASKS USAGE_MARK_CALLER USAGE_MARK_RANGE USAGE_MARK_DEFERRED
export DAGENTS_CODEX_SESSION_DIR="$TMP/sessions"
printf '%s\n' '#!/usr/bin/env bash' 'echo "codex-gate usable=false reason=off review=false lane=false resets_at=- source=cache"' > "$TMP/gate-stub"
export TASK_STEP_CODEX_GATE="$TMP/gate-stub"
VERSION=$(jq -r .version < "$P/.claude-plugin/plugin.json")
AR="$P/scripts/auto-run"
REPORT="$P/scripts/usage-report"
CP='done: x; verified: y; remaining: none; discovered: none; assumptions: none'
BASEFAIL=$fail

newrepo() {
  [ -n "${1:-}" ] || { echo "newrepo: no path" >&2; exit 2; }
  git init -q -b main "$1"
  git -C "$1" config user.name Darkraise
  git -C "$1" config user.email dark@example.invalid
  mkdir -p "$1/docs/plans"
  {
    printf '# Fixture\n\n**Goal:** Fixture.\n\n**Execution:** subagent — `claude --model sonnet --effort high` — x\n\n'
    printf '## Global Constraints\n\n- None.\n\n## Contracts\n\n- None.\n'
    for t in 1 2 3 4; do
      printf '\n### Task %s: t%s\n\n**Files:** `a.sh`\n\n**Implementer:** dagents:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n\nBody.\n' "$t" "$t"
    done
  } > "$1/docs/plans/p.md"
  git -C "$1" add docs
  git -C "$1" commit -q -m init
}
tscript() { # tscript SID CTX
  mkdir -p "$HOME/.claude/projects/fx"
  printf '{"type":"assistant","isSidechain":false,"message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s,"output_tokens":1}}}\n' \
    "$2" > "$HOME/.claude/projects/fx/$1.jsonl"
  printf '%s' "$HOME/.claude/projects/fx/$1.jsonl"
}
beat() { mkdir -p "$HOME/.claude/dagents/sessions/cockpit"; date +%s > "$HOME/.claude/dagents/sessions/cockpit/$1"; }
arrun() { local d=$1 s=$2; shift 2; beat "$s"; (cd "$d" && bash "$AR" --session "$s" "$@"); }
state() { cat "$1/.dagents/sdd/auto-run.json"; }
mcol() { awk -F'\t' -v ev="$2" -v t="$3" '$2 == ev && $7 == t' "$1" 2>/dev/null; }

# --- A2: task-step start writes one open row for each task number ---
G0=$fail
R2="$TMP/r2"; newrepo "$R2"
T2=$(tscript sess-a2 64000)
(cd "$R2" && CLAUDE_CODE_SESSION_ID=sess-a2 bash "$P/scripts/task-step" start docs/plans/p.md 2 3 --wave 1 >/dev/null 2>&1)
M2="$R2/.dagents/sdd/usage-markers.tsv"
check "A2: two open rows, one per task" "$(awk -F'\t' '$2 == "open" { print $7 }' "$M2" 2>/dev/null | sort | tr '\n' ' ')" "2 3 "
check "A2: each row has 14 columns" "$(awk -F'\t' '{print NF}' "$M2" | sort -u | tr '\n' ' ')" "14 "
check "A2: plugin, version, plan, session id, transcript and the measured context" \
  "$(awk -F'\t' '$7 == "2" { print $3 "|" $4 "|" $6 "|" $8 "|" $9 "|" $11 }' "$M2")" "dagents|$VERSION|docs/plans/p.md|sess-a2|$T2|64000"
check "A2: the byte size is the transcript's" "$(awk -F'\t' '$7 == "2" { print $10 }' "$M2")" "$(wc -c < "$T2" | tr -d ' ')"
(cd "$R2" && CLAUDE_CODE_SESSION_ID=sess-a2 bash "$P/scripts/task-step" start docs/plans/p.md 2 3 --wave 1 >/dev/null 2>&1)
(cd "$R2" && CLAUDE_CODE_SESSION_ID=sess-a2 bash "$P/scripts/task-brief" docs/plans/p.md 2 >/dev/null 2>&1)
check "A3: a repeated task-step start or a task-brief in one session writes no further open row" "$(awk -F'\t' '$2 == "open"' "$M2" | wc -l | tr -d ' ')" "2"
(cd "$R2" && CLAUDE_CODE_SESSION_ID=sess-a2 bash "$P/scripts/task-brief" docs/plans/p.md 4 >/dev/null 2>&1)
check "A2: a task-brief alone opens its task" "$(mcol "$M2" open 4 | cut -f12)" "task-brief:4"

# --- A3: task-complete closes every complete task, once ---
RA="$TMP/ra"; newrepo "$RA"
tscript sess-a3 90000 >/dev/null
arrun "$RA" sess-a3 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
arrun "$RA" sess-a3 attach --plan docs/plans/p.md >/dev/null 2>&1
(cd "$RA" && CLAUDE_CODE_SESSION_ID=sess-a3 bash "$P/scripts/task-step" start docs/plans/p.md 1 2 --wave 1 >/dev/null 2>&1)
MA="$RA/.dagents/sdd/usage-markers.tsv"
LEDGER=$(find "$RA/.dagents/sdd" -name progress.md | head -1)
printf 'Task 1: complete (commits aaa1111..bbb2222, unreviewed) — x\nTask 2: complete (commits bbb2222..ccc3333, 1 parked) — y\n' >> "$LEDGER"
arrun "$RA" sess-a3 task-complete >/dev/null 2>&1
check "A3: task-complete after two complete lines closes task 1 with its range" "$(mcol "$MA" close 1 | cut -f13-14 | tr '\t' '|')" "aaa1111..bbb2222|"
check "A3: and task 2 with its range" "$(mcol "$MA" close 2 | cut -f13-14 | tr '\t' '|')" "bbb2222..ccc3333|"
check "A3: the close rows' caller is auto-run" "$(awk -F'\t' '$2 == "close" { print $12 }' "$MA" | sed 's/:.*//' | sort -u)" "auto-run"
arrun "$RA" sess-a3 task-complete >/dev/null 2>&1
check "A3: a second sweep adds nothing: exactly one close row per task" "$(awk -F'\t' '$2 == "close"' "$MA" | wc -l | tr -d ' ')" "2"
(cd "$RA" && CLAUDE_CODE_SESSION_ID=sess-a3 bash "$P/scripts/task-step" start docs/plans/p.md 1 --wave 1 >/dev/null 2>&1)
(cd "$RA" && CLAUDE_CODE_SESSION_ID=sess-a3 bash "$P/scripts/task-brief" docs/plans/p.md 2 >/dev/null 2>&1)
check "A3: a start or a brief after the close writes no open row" "$(awk -F'\t' '$2 == "open"' "$MA" | wc -l | tr -d ' ')" "2"
printf 'Task 3: complete (deferred by the auto run) — reason\n' >> "$LEDGER"
arrun "$RA" sess-a3 task-complete >/dev/null 2>&1
check "A6: the deferred line closes with the flag 1 and no range" "$(mcol "$MA" close 3 | cut -f13-14 | tr '\t' '|')" "|1"

# --- A4: a marker that cannot be written changes nothing its caller prints or returns ---
pair() { # pair LABEL SID MODE
  local d="$TMP/pair" o1 o2 s1 s2
  rm -rf "$d"; newrepo "$d"
  o1=$(cd "$d" && CLAUDE_CODE_SESSION_ID=$2 bash "$P/scripts/task-step" start docs/plans/p.md 1 --wave 1 2>/dev/null | sed "s#$d#R#g"); s1=$?
  rm -rf "$d"; newrepo "$d"
  [ "$3" != dir ] || mkdir -p "$d/.dagents/sdd/usage-markers.tsv"
  o2=$(cd "$d" && CLAUDE_CODE_SESSION_ID=$2 bash "$P/scripts/task-step" start docs/plans/p.md 1 --wave 1 2>/dev/null | sed "s#$d#R#g"); s2=$?
  check "A4 ($1): same exit code" "$s2" "$s1"
  check "A4 ($1): same stdout" "$(sed 's/base [0-9a-f]*/base X/' <<<"$o2")" "$(sed 's/base [0-9a-f]*/base X/' <<<"$o1")"
}
tscript sess-a4 50000 >/dev/null
pair "marker path is a directory" sess-a4 dir
pair "no transcript for the session" sess-nothing none
MARK_BAD=$((fail - G0))

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
