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

# --- A11, A17, A12 in this plugin ---
G1=$fail
RR="$TMP/rr"; newrepo "$RR"
git -C "$RR" commit -q --allow-empty -m base
arrun "$RR" r1 start --spec docs/s.md --register docs/r.md --isolation in-place >/dev/null 2>&1
arrun "$RR" r1 attach --plan docs/plans/p.md >/dev/null 2>&1
arrun "$RR" r1 total holds >/dev/null 2>&1; arrun "$RR" r1 total holds >/dev/null 2>&1
arrun "$RR" r1 compacted --seconds 40 >/dev/null 2>&1
arrun "$RR" r1 stalled >/dev/null 2>&1
arrun "$RR" r1 api-error >/dev/null 2>&1
jq '.failures = 2 | .resumes = 3 | .compactionsSinceTask = 4 | .pending = "compact" | .resumePrompt = "x" | .rebind = true' "$RR/.dagents/sdd/auto-run.json" > "$TMP/st.json" && cp "$TMP/st.json" "$RR/.dagents/sdd/auto-run.json"
BEFORE=$(state "$RR")
check "A11: setup — the run's caps are non-zero before the stop" \
  "$(jq -c '[.stalls, .resumes, .failures, .apiErrors, .compactionsSinceTask] | map(. > 0) | all' <<<"$BEFORE")" "true"
arrun "$RR" r1 stop --reason "operator stop" >/dev/null 2>&1
out=$(arrun "$RR" r2 resume 2>"$TMP/resume.err"); st=$?
AFTER=$(state "$RR")
check "A11: resume of a stopped spec-phase run exits 0" "$st" "0"
check "A11: resume prints the status line" "$(head -n 1 <<<"$out" | grep -c '^auto run: spec ')" "1"
check "A11: the run is active and bound to the calling session" "$(jq -c '[.active, .session]' <<<"$AFTER")" '[true,"r2"]'
check "A11: phase, base, plan and totals are unchanged" \
  "$(jq -c '[.phase, .base, .plan, .totals]' <<<"$AFTER")" "$(jq -c '[.phase, .base, .plan, .totals]' <<<"$BEFORE")"
check "A11: cap counters are 0" "$(jq -c '[.stalls, .resumes, .failures, .apiErrors, .compactionsSinceTask]' <<<"$AFTER")" "[0,0,0,0,0]"
check "A11: stalledAt, pending, resumePrompt and launch are null and rebind is false" \
  "$(jq -c '[.stalledAt, .pending, .resumePrompt, .launch, .rebind]' <<<"$AFTER")" "[null,null,null,null,false]"
check "A11: the stop is in stopHistory with its reason" "$(jq -c '[.stopHistory[0].reason, (.stopHistory[0].at | type), (.stopHistory[0].resumedAt | type)]' <<<"$AFTER")" '["operator stop","string","string"]'
check "A11: the stopped marker is cleared" "$(jq -c '.stopped' <<<"$AFTER")" "null"
arrun "$RR" r3 resume >/dev/null 2>&1; st=$?
check "A11: resume of an active run exits 4" "$st" "4"
arrun "$RR" r2 stop --reason again >/dev/null 2>&1
jq '.stoppedKind = "guard"' "$RR/.dagents/sdd/auto-run.json" > "$TMP/st.json" && cp "$TMP/st.json" "$RR/.dagents/sdd/auto-run.json"
arrun "$RR" r4 resume >"$TMP/g.out" 2>"$TMP/g.err"; st=$?
check "A11: a guard stop is refused with exit 4, naming the reason" "$st:$([ -s "$TMP/g.err" ] && echo says || echo silent)" "4:says"
jq '.stoppedKind = "carried"' "$RR/.dagents/sdd/auto-run.json" > "$TMP/st.json" && cp "$TMP/st.json" "$RR/.dagents/sdd/auto-run.json"
arrun "$RR" r4 resume >/dev/null 2>&1; st=$?
check "A11: a carried-path stop is refused with exit 4" "$st" "4"
jq '.stoppedKind = null' "$RR/.dagents/sdd/auto-run.json" > "$TMP/st.json" && cp "$TMP/st.json" "$RR/.dagents/sdd/auto-run.json"
(cd "$RR" && bash "$AR" --session r5 resume >/dev/null 2>&1); st=$?
check "A11: resume from a session with no live cockpit exits 2 and leaves the run stopped" "$st:$(jq -c '.active' "$RR/.dagents/sdd/auto-run.json")" "2:false"
arrun "$RR" r4 resume >/dev/null 2>&1; st=$?
check "A11: with the stop kind cleared the same run resumes" "$st" "0"
arrun "$RR" r4 phase plan >/dev/null 2>&1
arrun "$RR" r4 stop --reason planstop >/dev/null 2>&1
arrun "$RR" r6 resume >/dev/null 2>&1; st=$?
check "A11: a run stopped in the plan phase resumes" "$st:$(jq -c '[.phase, .active, .session]' "$RR/.dagents/sdd/auto-run.json")" '0:["plan",true,"r6"]'
# finished: the finish phase, then stopped
arrun "$RR" r6 phase execute >/dev/null 2>&1; arrun "$RR" r6 phase final >/dev/null 2>&1; arrun "$RR" r6 phase finish >/dev/null 2>&1
arrun "$RR" r6 stop >/dev/null 2>&1
arrun "$RR" r7 resume >/dev/null 2>&1; st=$?
check "A11: a finished run is refused with exit 4" "$st" "4"

# execute phase, in place: the recorded branch must exist
RX="$TMP/rx"; newrepo "$RX"
arrun "$RX" x1 start --spec docs/s.md --register docs/r.md --isolation in-place >/dev/null 2>&1
arrun "$RX" x1 attach --plan docs/plans/p.md >/dev/null 2>&1
git -C "$RX" checkout -q -b auto/qa-run
arrun "$RX" x1 setup-branch auto/qa-run >/dev/null 2>&1
arrun "$RX" x1 phase execute >/dev/null 2>&1
check "A11: setup — the run is in the execute phase on its branch" "$(jq -c '[.phase, .branch]' "$RX/.dagents/sdd/auto-run.json")" '["execute","auto/qa-run"]'
arrun "$RX" x1 stop --reason "manual" >/dev/null 2>&1
arrun "$RX" x2 resume >/dev/null 2>&1; st=$?
check "A11: an execute-phase run whose branch exists resumes" "$st:$(jq -c '.active' "$RX/.dagents/sdd/auto-run.json")" "0:true"
arrun "$RX" x2 stop --reason "manual 2" >/dev/null 2>&1
git -C "$RX" checkout -q main; git -C "$RX" branch -q -D auto/qa-run
arrun "$RX" x3 resume >"$TMP/x.out" 2>"$TMP/x.err"; st=$?
check "A11: an execute-phase run whose branch is gone is refused with exit 4" "$st:$(jq -c '.active' "$RX/.dagents/sdd/auto-run.json")" "4:false"
check "A11: the refusal names the reason" "$([ -s "$TMP/x.err" ] && echo says || echo silent)" "says"

# --- A17: the api-error command line ---
RE="$TMP/re"; newrepo "$RE"
arrun "$RE" e1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
arrun "$RE" e1 api-error >/dev/null 2>&1; arrun "$RE" e1 api-error >/dev/null 2>&1; arrun "$RE" e1 api-error >/dev/null 2>&1
check "A17: three api-error calls count three" "$(jq -c '[.apiErrors, .stalls, .active]' "$RE/.dagents/sdd/auto-run.json")" "[3,0,true]"
arrun "$RE" e1 api-error --clear >/dev/null 2>&1
check "A17: --clear resets the count" "$(jq -c '.apiErrors' "$RE/.dagents/sdd/auto-run.json")" "0"
arrun "$RE" e1 api-error >/dev/null 2>&1
arrun "$RE" e1 task-complete >/dev/null 2>&1
check "A17: task-complete resets the count" "$(jq -c '.apiErrors' "$RE/.dagents/sdd/auto-run.json")" "0"
sts=""
for i in 1 2 3 4 5 6 7 8 9 10; do arrun "$RE" e1 api-error >/dev/null 2>&1; sts="$sts$? "; done
check "A17: nine api-errors exit 0 and the tenth exits 5" "$sts" "0 0 0 0 0 0 0 0 0 5 "
check "A17: the tenth stops the run with an API-error reason" "$(jq -c '[.active, (.stopped | test("api"; "i"))]' "$RE/.dagents/sdd/auto-run.json")" "[false,true]"
check "A17: api errors never count as stalls" "$(jq -c '[.stalls, .totals.stalls]' "$RE/.dagents/sdd/auto-run.json")" "[0,0]"

# --- A12: the version warning ---
RV="$TMP/rv"; newrepo "$RV"; tscript v1 10000 >/dev/null
arrun "$RV" v1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
arrun "$RV" v1 attach --plan docs/plans/p.md >/dev/null 2>&1
check "A12: the run records the plugin version and root" "$(jq -c '[.version, .root]' "$RV/.dagents/sdd/auto-run.json")" "[\"$VERSION\",\"$P\"]"
mkroot() { # mkroot DIR VERSION — a copy of the plugin at another root and version
  mkdir -p "$1"; cp -R "$P/scripts" "$P/skills" "$P/reference" "$P/criteria" "$P/agents" "$P/.claude-plugin" "$1/" 2>/dev/null
  jq --arg v "$2" '.version = $v' "$P/.claude-plugin/plugin.json" > "$1/.claude-plugin/plugin.json"
}
mkroot "$TMP/other-9" 9.9.9
mkroot "$TMP/other-same" "$VERSION"
WARN="auto run: plugin version mismatch — run $VERSION at $P, this call 9.9.9 at $TMP/other-9"
beat v1
(cd "$RV" && bash "$TMP/other-9/scripts/auto-run" --session v1 status >"$TMP/v.out" 2>"$TMP/v.err")
check "A12: an auto-run call from another version warns on stderr, naming both versions and roots" "$(grep -cxF "$WARN" "$TMP/v.err")" "1"
check "A12: the warning is not on stdout" "$(grep -c 'version mismatch' "$TMP/v.out")" "0"
check "A12: the mismatch is recorded in auto-run.json" "$(state "$RV" | jq -c '[.. | strings | select(test("9\\.9\\.9"))] | length > 0')" "true"
(cd "$RV" && bash "$TMP/other-same/scripts/auto-run" --session v1 status >/dev/null 2>"$TMP/v2.err")
check "A12: a call from another root with the same version prints no warning" "$(grep -c 'version mismatch' "$TMP/v2.err")" "0"
(cd "$RV" && CLAUDE_CODE_SESSION_ID=v1 bash "$TMP/other-9/scripts/task-step" start docs/plans/p.md 1 --wave 1 >/dev/null 2>"$TMP/v3.err")
check "A12: task-step start from another version warns exactly once" "$(grep -cxF "$WARN" "$TMP/v3.err")" "1"
printf 'Task 1: complete (commits aaa1111..bbb2222, unreviewed) — x\n' >> "$(find "$RV/.dagents/sdd" -name progress.md | head -1)"
(cd "$RV" && CLAUDE_CODE_SESSION_ID=v1 bash "$TMP/other-9/scripts/auto-run" task-complete >"$TMP/v4.out" 2>"$TMP/v4.err")
check "A12: task-complete from another version warns exactly once" "$(grep -cxF "$WARN" "$TMP/v4.err")" "1"
check "A12: the warning never appears on task-complete's stdout" "$(grep -c 'version mismatch' "$TMP/v4.out")" "0"
RV0="$TMP/rv0"; newrepo "$RV0"
arrun "$RV0" w1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
beat w1
(cd "$RV0" && bash "$P/scripts/auto-run" --session w1 status >/dev/null 2>"$TMP/v5.err")
check "A12: a call from the run's own version warns nothing" "$(grep -c 'version mismatch' "$TMP/v5.err")" "0"


# --- A18: the run counters ---
RC3="$TMP/rc3"; newrepo "$RC3"
arrun "$RC3" c1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
arrun "$RC3" c1 attach --plan docs/plans/p.md >/dev/null 2>&1
arrun "$RC3" c1 compacted --seconds 70 >/dev/null 2>&1
arrun "$RC3" c1 total holds >/dev/null 2>&1
arrun "$RC3" c1 stalled >/dev/null 2>&1
arrun "$RC3" c1 api-error >/dev/null 2>&1
arrun "$RC3" c1 total reconcilePrompts >/dev/null 2>&1
arrun "$RC3" c1 total panelFailures >/dev/null 2>&1
beat c1
(cd "$RC3" && bash "$TMP/other-9/scripts/auto-run" --session c1 status >/dev/null 2>&1)
CNT=$(arrun "$RC3" c1 counters 2>&1); st=$?
check "A18: counters exits 0" "$st" "0"
check "A18: compactions with their total seconds" "$(grep -Eic 'compactions?.*1.*70' <<<"$CNT")" "1"
check "A18: holds" "$(grep -Eic '^holds.*1' <<<"$CNT")" "1"
check "A18: stalls" "$(grep -Eic '^stalls.*1' <<<"$CNT")" "1"
check "A18: API errors" "$(grep -Eic 'api errors.*1' <<<"$CNT")" "1"
check "A18: reconcile prompts" "$(grep -Eic 'reconcile prompts.*1' <<<"$CNT")" "1"
check "A18: panel failures" "$(grep -Eic 'panel failures.*1' <<<"$CNT")" "1"
check "A18: the first version mismatch, naming both versions" "$(grep -E 'mismatch' <<<"$CNT" | grep -c "9\.9\.9.*$VERSION\|$VERSION.*9\.9\.9")" "1"
TOT0=$(state "$RC3" | jq -c .totals)
arrun "$RC3" c1 task-complete >/dev/null 2>&1
check "A18: task-complete leaves the totals unchanged" "$(state "$RC3" | jq -c .totals)" "$TOT0"
arrun "$RC3" c1 stop --reason s >/dev/null 2>&1
arrun "$RC3" c2 resume >/dev/null 2>&1
check "A18: resume leaves the totals unchanged" "$(state "$RC3" | jq -c .totals)" "$TOT0"
# the finishing message: the saved report's summary, or one line naming why it is missing
MISS=$(cd "$RC3" && bash "$REPORT" --plan docs/plans/p.md --save 2>&1 >/dev/null); st=$?
check "A18: a report that cannot be made exits 0 and names why in one line" "$st:$(grep -c '^usage summary missing: .' <<<"$MISS")" "0:1"
check "A18: nothing is saved when the report is missing" "$(ls "$RC3/.dagents/sdd"/usage-report-*.json 2>/dev/null | wc -l | tr -d ' ')" "0"

# --- A13: task-complete prints the auto budget line after every task of an auto run ---
G2=$fail
RW="$TMP/rw"; newrepo "$RW"
tscript w1 50000 >/dev/null
arrun "$RW" w1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
arrun "$RW" w1 attach --plan docs/plans/p.md >/dev/null 2>&1
(cd "$RW" && CLAUDE_CODE_SESSION_ID=w1 bash "$P/scripts/task-step" start docs/plans/p.md 1 --wave 1 >/dev/null 2>&1)
LW=$(find "$RW/.dagents/sdd" -name progress.md | head -1)
printf 'Task 1: complete (commits aaa1111..bbb2222, unreviewed) — x\n' >> "$LW"
out=$(CLAUDE_CODE_SESSION_ID=w1 arrun "$RW" w1 task-complete 2>/dev/null); st=$?
check "A13: task 1 of 4 completes with exit 0" "$st" "0"
check "A13: the last line is the auto budget line, ok" "$(tail -n 1 <<<"$out" | grep -Ec '^budget \(auto[^)]*\): 50k of [0-9]+k \([0-9]+%\) — ok — ')" "1"
tscript w1 3000000 >/dev/null
printf 'Task 2: complete (commits bbb2222..ccc3333, unreviewed) — x\n' >> "$LW"
out=$(CLAUDE_CODE_SESSION_ID=w1 arrun "$RW" w1 task-complete 2>/dev/null); st=$?
check "A13: over budget the line says compact and the exit code is still 0" "$st:$(tail -n 1 <<<"$out" | grep -Ec '^budget \(auto[^)]*\): .* — compact — ')" "0:1"
# a stop: the task is completed off the run's branch
RS="$TMP/rs"; newrepo "$RS"; tscript s1 50000 >/dev/null
arrun "$RS" s1 start --spec docs/s.md --register docs/r.md --isolation in-place >/dev/null 2>&1
arrun "$RS" s1 attach --plan docs/plans/p.md >/dev/null 2>&1
git -C "$RS" checkout -q -b auto/qa-run
arrun "$RS" s1 setup-branch auto/qa-run >/dev/null 2>&1
arrun "$RS" s1 phase execute >/dev/null 2>&1
git -C "$RS" checkout -q main
out=$(CLAUDE_CODE_SESSION_ID=s1 arrun "$RS" s1 task-complete 2>/dev/null); st=$?
check "A13: a task-complete that stops the run exits 5 and no budget line follows" "$st:$(grep -c '^budget' <<<"$out")" "5:0"
check "A13 (A11): the guard stop is recorded with a guard kind" "$(state "$RS" | jq -c '[.active, .stoppedKind]')" '[false,"guard"]'
arrun "$RS" s2 resume >/dev/null 2>&1; st=$?
check "A11: a guard stop is refused by resume with exit 4" "$st" "4"
GATE_BAD=$((fail - G2))

# --- A27: context-size --observations pairs Claude rows on the plain and the auto path ---
G3=$fail
RB="$TMP/rb"; newrepo "$RB"
tscript sess-p 50000 >/dev/null
(cd "$RB" && CLAUDE_CODE_SESSION_ID=sess-p bash "$P/scripts/task-brief" docs/plans/p.md 1 >/dev/null 2>&1)
tscript sess-p 90000 >/dev/null
(cd "$RB" && CLAUDE_CODE_SESSION_ID=sess-p bash "$P/scripts/task-brief" docs/plans/p.md 2 >/dev/null 2>&1)
OBS=$(cd "$RB" && bash "$P/scripts/context-size" --observations 2>&1)
check "A27: plain path: the growth between two task briefs of a Claude session" "$(grep -c '^sess-p  Task 1 -> Task 2  +40k$' <<<"$OBS")" "1"
check "A27: plain path: the session's span" "$(grep -c '^sess-p  span  50k -> 90k$' <<<"$OBS")" "1"
RQ="$TMP/rq"; newrepo "$RQ"
tscript sess-q 30000 >/dev/null
arrun "$RQ" sess-q start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
arrun "$RQ" sess-q attach --plan docs/plans/p.md >/dev/null 2>&1
(cd "$RQ" && CLAUDE_CODE_SESSION_ID=sess-q bash "$P/scripts/task-brief" docs/plans/p.md 1 >"$TMP/q1.out" 2>&1)
tscript sess-q 75000 >/dev/null
(cd "$RQ" && CLAUDE_CODE_SESSION_ID=sess-q bash "$P/scripts/task-brief" docs/plans/p.md 2 >"$TMP/q2.out" 2>&1)
check "A27: auto path: the briefs printed the auto budget line" "$(grep -c '^budget (auto' "$TMP/q1.out" "$TMP/q2.out" | sed 's#[^:]*:##' | tr '\n' ' ')" "1 1 "
OBSQ=$(cd "$RQ" && bash "$P/scripts/context-size" --observations 2>&1)
check "A27: auto path: the growth between two task briefs of a Claude session" "$(grep -c '^sess-q  Task 1 -> Task 2  +45k$' <<<"$OBSQ")" "1"
OBS_BAD=$((fail - G3))

# --- A14: a quota failure in an auto run skips the Codex review family for a while ---
G4=$fail
CR="$TMP/cr"; mkdir -p "$CR/bin" "$CR/config/plugins" "$CR/work"
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$CR/config/settings.json"
jq -nc --arg p "$HERE/fixtures/stub-codex-plugin" '{version:2, plugins:{"codex@openai-codex":[{scope:"user", installPath:$p, version:"1.0.3"}]}}' > "$CR/config/plugins/installed_plugins.json"
jq -nc '{plugin:"codex@openai-codex", min_version:"1.0.3", max_major:1, trust:{calibration:"pending", smoke:"pending"}}' > "$CR/policy.json"
printf '```codex-judge\ngpt-6-astra high 2\ngpt-6.1-sol high 2\n```\n' > "$CR/ladder.md"
BASH_BIN=$(command -v bash)
for dep in jq timeout head tr sed awk grep cat mktemp rm; do printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v "$dep")" > "$CR/bin/$dep"; chmod +x "$CR/bin/$dep"; done
printf '#!%s\necho "codex-gate usable=true reason=ok review=true lane=true resets_at=- source=cache"\n' "$BASH_BIN" > "$CR/gate"
git -C "$CR/work" init -q -b main; git -C "$CR/work" commit -q --allow-empty -m base
printf 'prompt\n' > "$CR/p.txt"
RUNSTATE="$CR/work/.dagents/sdd/auto-run.json"
seat() { # seat MODE — one task review from the work tree as session cr1
  printf '0' > "$CR/calls"
  mkdir -p "$DAGENTS_CODEX_SESSION_DIR"
  printf '{"session_id":"cr1","usable":true,"review":true,"lane":true,"reason":"ok","plugin_version":"1.0.3"}\n' > "$DAGENTS_CODEX_SESSION_DIR/cr1.json"
  PATH="$CR/bin:$PATH" CODEX_REVIEW_GATE="$CR/gate" CODEX_REVIEW_LADDER="$CR/ladder.md" CLAUDE_CONFIG_DIR="$CR/config" CLAUDE_PROJECT_DIR= \
    DAGENTS_CODEX_POLICY="$CR/policy.json" CLAUDE_CODE_SESSION_ID=cr1 STUB_MODE="$1" STUB_CALL_FILE="$CR/calls" \
    bash "$P/scripts/run-codex-review.sh" --kind task --cwd "$CR/work" --out "$CR/o.json" --prompt "$CR/p.txt" 2>/dev/null
}
ncalls() { cat "$CR/calls" 2>/dev/null || echo 0; }
mkdir -p "$(dirname "$RUNSTATE")"
jq -n '{active: true, session: "cr1", phase: "execute", decisions: [], rulings: []}' > "$RUNSTATE"
seat quota >/dev/null
check "A14: a quota failure in an auto run is recorded under reviewSkips for the codex family, for 5 hours" \
  "$(jq -c '[.reviewSkips[0].family, (.reviewSkips[0].until - .reviewSkips[0].failedAt)]' "$RUNSTATE")" '["codex",18000]'
out=$(seat ok)
check "A14: inside the window the family is skipped as quota-skip and nothing launches" "$(grep -c 'status=SKIPPED .* reason=quota-skip' <<<"$out"):$(ncalls)" "1:0"
jq '.reviewSkips[0].until = 1' "$RUNSTATE" > "$RUNSTATE.tmp" && mv "$RUNSTATE.tmp" "$RUNSTATE"
out=$(seat ok)
check "A14: after the window it launches again" "$(grep -c SKIPPED <<<"$out"):$(ncalls)" "0:1"
rm -rf "$CR/work/.dagents"
seat quota >/dev/null
check "A14: outside an auto run nothing is recorded" "$([ -e "$CR/work/.dagents/sdd/auto-run.json" ] && echo recorded || echo none)" "none"
CODEX_BAD=$((fail - G4))

# --- A15: task-step verdict reads 71-76(diff) as lines 71-76 ---
G5=$fail
RT="$TMP/rt"; newrepo "$RT"
sed -i 's/^\*\*Evaluation:\*\* .*risk 0 = 0$/**Evaluation:** files 1 - spec 2 - coupling 1 - risk 3 = 7/' "$RT/docs/plans/p.md"
git -C "$RT" commit -q -am risk
(cd "$RT" && CLAUDE_CODE_SESSION_ID=rt1 bash "$P/scripts/task-step" start docs/plans/p.md 1 --wave 1 >/dev/null 2>&1)
printf 'x\n' > "$RT/x.sh"; git -C "$RT" add x.sh; git -C "$RT" commit -q -m x
(cd "$RT" && CLAUDE_CODE_SESSION_ID=rt1 bash "$P/scripts/task-step" review docs/plans/p.md 1 >"$TMP/rev.out" 2>&1); RVST=$?
WS=$(dirname "$(find "$RT/.dagents/sdd" -name task-1-step.json | head -1)")
check "A15: setup — task-step review ran" "$RVST" "0"
cat > "$WS/task-1-review-report.md" <<'EOF'
## Verdict
spec: pass
quality: changes
scores: spec 15 / scope 15 / verification 12 / quality 9

## Findings
- [Important] plugins/x.sh:71-76(diff) — off by one
- [Minor] plugins/y.sh:3(diff) — naming

## Cannot verify
- none
EOF
FILES0=$(ls "$WS" | wc -l | tr -d ' ')
ROUND0=$(jq -c .round "$WS/task-1-step.json")
VOUT=$(cd "$RT" && bash "$P/scripts/task-step" verdict docs/plans/p.md 1 2>&1); st=$?
check "A15: the verdict is accepted (exit 0)" "$st" "0"
check "A15: the finding is recorded as lines 71-76" "$(grep -c 'plugins/x.sh:71-76 — off by one' <<<"$VOUT")" "1"
check "A15: the parenthetical is not kept" "$(grep -c '71-76(diff)' <<<"$VOUT")" "0"
check "A15: the fix list names lines 71-76" "$(grep -c '^- plugins/x.sh:71-76: off by one' "$WS/task-1-fix-1.md" 2>/dev/null)" "1"
check "A15: no new dispatch: the round count is unchanged and only the fix file is added" "$(jq -c .round "$WS/task-1-step.json"):$(( $(ls "$WS" | wc -l | tr -d ' ') - FILES0 ))" "$ROUND0:1"
VERDICT_BAD=$((fail - G5))

# --- A16: a UI proof report passes the implementer stop gate ---
G6=$fail
gate_in() { # gate_in AGENT_ID MESSAGE
  jq -nc --arg id "$1" --arg cwd "$TMP/gate-cwd" --arg m "$2" \
    '{session_id:"11111111-2222-4333-8444-555555555555",cwd:$cwd,agent_id:$id,agent_type:"dagents:impl-sonnet-high",hook_event_name:"SubagentStop",stop_hook_active:false,last_assistant_message:$m}'
}
mkdir -p "$TMP/gate-cwd"; git -C "$TMP/gate-cwd" init -q 2>/dev/null
export XDG_STATE_HOME="$TMP/xdg"
gate() { gate_in "$1" "$(printf '**Status:** DONE\nReport: %s' "$2")" | bash "$P/scripts/impl-stop-gate" 2>"$TMP/gate.err"; GST=$?; }
printf '# UI proof: dashboard\n\nScreenshots taken.\n' > "$TMP/proof.md"
gate g-proof "$TMP/proof.md"
check "A16: a proof report without the implementer report sections passes" "$GST:$(wc -c < "$TMP/gate.err" | tr -d ' ')" "0:0"
printf '\n  \n# UI proof: dashboard\n\nbody\n' > "$TMP/proof-blank.md"
gate g-proof2 "$TMP/proof-blank.md"
check "A16: blank lines before the proof heading still pass" "$GST" "0"
printf '# Notes\n\nNothing the gate asks for.\n' > "$TMP/other.md"
gate g-other "$TMP/other.md"
check "A16: any other report without its required sections is refused (exit 2)" "$GST" "2"
printf '# UI proofs\n\nbody\n' > "$TMP/near.md"
gate g-near "$TMP/near.md"
check "A16: a heading that only resembles the proof heading is refused" "$GST" "2"
printf '## Notes\n\n# UI proof: late\n' > "$TMP/late.md"
gate g-late "$TMP/late.md"
check "A16: a proof heading that is not the first non-empty line is refused" "$GST" "2"
unset XDG_STATE_HOME
UIGATE_BAD=$((fail - G6))

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
