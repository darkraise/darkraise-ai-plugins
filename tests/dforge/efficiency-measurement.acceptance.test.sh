#!/usr/bin/env bash
# Efficiency measurement and auto-run polish: the skill and instruction text
# the spec pins (A9, A10).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/../../plugins/dforge" && pwd)"

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

# ---------------------------------------------------------------------------
# Acceptance statements A1-A6, A8, A11-A18, A21-A31: the markers, the report,
# the auto-run polish and the replay harness, through the public CLI only.
# ---------------------------------------------------------------------------
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/projects/fx"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR \
  USAGE_MARK USAGE_MARK_PLAN USAGE_MARK_TASKS USAGE_MARK_CALLER USAGE_MARK_RANGE USAGE_MARK_DEFERRED
VERSION=$(jq -r .version < "$P/.claude-plugin/plugin.json")
BRIEF="$P/scripts/task-brief"
CLOSE="$P/scripts/task-close"
AR="$P/scripts/auto-run"
REPORT="$P/scripts/usage-report"
CP='done: x; verified: y; remaining: none; discovered: none; assumptions: none'

# newrepo DIR — a repository with a two-task plan, one commit.
newrepo() {
  [ -n "${1:-}" ] || { echo "newrepo: no path" >&2; exit 2; }
  git init -q -b main "$1"
  git -C "$1" config user.name Darkraise
  git -C "$1" config user.email dark@example.invalid
  mkdir -p "$1/docs/plans"
  printf '# Fixture\n\n**Goal:** Fixture.\n\n## Global Constraints\n\n- None.\n\n### Task 1: one\n\n**Files:** `a.sh`\n\nBody.\n\n### Task 2: two\n\nBody.\n\n### Task 3: three\n\nBody.\n' \
    > "$1/docs/plans/p.md"
  git -C "$1" add docs
  git -C "$1" commit -q -m init
}
# tscript SID CTX — a one-record transcript whose context is CTX tokens.
tscript() {
  mkdir -p "$HOME/.claude/projects/fx"
  printf '{"type":"assistant","isSidechain":false,"message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":%s,"output_tokens":1}}}\n' \
    "$2" > "$HOME/.claude/projects/fx/$1.jsonl"
  printf '%s' "$HOME/.claude/projects/fx/$1.jsonl"
}
beat() { mkdir -p "$HOME/.claude/dforge/sessions/cockpit"; date +%s > "$HOME/.claude/dforge/sessions/cockpit/$1"; }
mcol() { awk -F'\t' -v ev="$2" -v t="$3" '$2 == ev && $7 == t' "$1" 2>/dev/null; }

# --- A1: task-brief --open writes one 14-column open row, also from a worktree ---
R1="$TMP/r1"; newrepo "$R1"
git -C "$R1" worktree add -q "$TMP/w1" -b w1
T1=$(tscript sess-a1 77000)
(cd "$TMP/w1" && CLAUDE_CODE_SESSION_ID=sess-a1 bash "$BRIEF" --open docs/plans/p.md 1 >"$TMP/a1.out" 2>&1)
M1="$R1/.dforge/sdd/usage-markers.tsv"
check "A1: one row in the primary checkout's state directory" "$(wc -l < "$M1" 2>/dev/null | tr -d ' ')" "1"
check "A1: 14 tab-separated columns" "$(awk -F'\t' '{print NF}' "$M1" 2>/dev/null)" "14"
check "A1: UTC time is column 1" "$(cut -f1 "$M1" 2>/dev/null | grep -Ec '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$')" "1"
check "A1: event, plugin and version" "$(cut -f2-4 "$M1" 2>/dev/null)" "$(printf 'open\tdforge\t%s' "$VERSION")"
check "A1: plan document name, task, session id, transcript path" "$(cut -f6-9 "$M1" 2>/dev/null)" \
  "$(printf 'docs/plans/p.md\t1\tsess-a1\t%s' "$T1")"
check "A1: transcript byte size" "$(cut -f10 "$M1" 2>/dev/null)" "$(wc -c < "$T1" | tr -d ' ')"
check "A1: the context figure is the one the budget line measured (77000)" "$(cut -f11 "$M1" 2>/dev/null)" "77000"
check "A1: the budget line printed 77k" "$(grep -c '^budget[^:]*: 77k of ' "$TMP/a1.out")" "1"
check "A1: close-only columns are empty" "$(cut -f13-14 "$M1" 2>/dev/null)" "$(printf '\t')"
check "A1: nothing written in the worktree's own state" "$([ -e "$TMP/w1/.dforge/sdd/usage-markers.tsv" ] && echo yes || echo no)" "no"

# --- A3: close rows, in order; a sweep closes every completed task; no extra open ---
RA="$TMP/ra"; newrepo "$RA"
printf 'x\n' > "$RA/x.txt"
KIT="$TMP/kit"; mkdir -p "$KIT"; cp -R "$P/scripts" "$P/.claude-plugin" "$KIT/"
mv "$KIT/scripts/auto-run" "$KIT/scripts/auto-run.real"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = task-complete ] && cp "$UM_FILE" "$UM_COPY" 2>/dev/null; done\nexec bash "$(dirname "$0")/auto-run.real" "$@"\n' > "$KIT/scripts/auto-run"
export UM_FILE="$RA/.dforge/sdd/usage-markers.tsv" UM_COPY="$TMP/at-task-complete.tsv"
tscript sess-a3 90000 >/dev/null
beat sess-a3
ra() { (cd "$RA" && CLAUDE_CODE_SESSION_ID=sess-a3 bash "$KIT/scripts/$1" "${@:2}"); }
ra auto-run --session sess-a3 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
ra auto-run --session sess-a3 attach --plan docs/plans/p.md >/dev/null 2>&1
ra task-brief --open docs/plans/p.md 1 >/dev/null 2>&1
BASE=$(git -C "$RA" rev-parse HEAD)
git -C "$RA" add x.txt; git -C "$RA" commit -q -m x
HEADC=$(git -C "$RA" rev-parse HEAD)
ra task-close docs/plans/p.md 1 "$CP" >"$TMP/close1.out" 2>&1; CLOSE_ST=$?
check "A3: task-close exits 0 in an auto run" "$CLOSE_ST" "0"
check "A3: exactly one close row for task 1" "$(mcol "$UM_FILE" close 1 | wc -l | tr -d ' ')" "1"
RNG=$(mcol "$UM_FILE" close 1 | cut -f13)
check "A3: the close row's range runs from the open's HEAD to the new HEAD" \
  "$([[ $RNG == *..* && $BASE == "${RNG%%..*}"* && $HEADC == "${RNG##*..}"* ]] && echo yes || echo "no: $RNG")" "yes"
check "A3: a completed task has an empty deferred flag" "$(mcol "$UM_FILE" close 1 | cut -f14)" ""
check "A3: the close row was written before auto-run task-complete ran" "$(mcol "$UM_COPY" close 1 | wc -l | tr -d ' ')" "1"
ra task-brief --open docs/plans/p.md 1 >/dev/null 2>&1
ra task-brief docs/plans/p.md 1 >/dev/null 2>&1
check "A3: a look at the finished task's brief writes no open row" "$(mcol "$UM_FILE" open 1 | wc -l | tr -d ' ')" "1"
ra task-close docs/plans/p.md 1 "$CP" >/dev/null 2>&1
check "A3: a second task-close adds no second close row" "$(mcol "$UM_FILE" close 1 | wc -l | tr -d ' ')" "1"
ra task-brief --open docs/plans/p.md 2 >/dev/null 2>&1
ra task-brief --open docs/plans/p.md 2 >/dev/null 2>&1
check "A3: a repeated task-brief --open in one session writes one open row" "$(mcol "$UM_FILE" open 2 | wc -l | tr -d ' ')" "1"
LEDGER=$(find "$RA/.dforge/sdd" -name progress.md | head -1)
printf 'Task 2: complete (commits aaa1111..bbb2222, unreviewed) — x\nTask 3: complete (commits bbb2222..ccc3333, unreviewed) — y\n' >> "$LEDGER"
ra auto-run --session sess-a3 task-complete >/dev/null 2>&1
check "A3: task-complete after two complete lines closes task 2" "$(mcol "$UM_FILE" close 2 | cut -f13)" "aaa1111..bbb2222"
check "A3: task-complete after two complete lines closes task 3" "$(mcol "$UM_FILE" close 3 | cut -f13)" "bbb2222..ccc3333"
ra auto-run --session sess-a3 task-complete >/dev/null 2>&1
check "A3: a second sweep adds no close row" "$(awk -F'\t' '$2 == "close"' "$UM_FILE" | wc -l | tr -d ' ')" "3"

# --- A6 (marker half): a deferred ledger line closes with the deferred flag and no range ---
printf 'Task 4: complete (deferred by the auto run) — reason\n' >> "$LEDGER"
printf '\n### Task 4: four\n\nBody.\n' >> "$RA/docs/plans/p.md"
git -C "$RA" add docs; git -C "$RA" commit -q -m p4
ra auto-run --session sess-a3 task-complete >/dev/null 2>&1
check "A6: the deferred task's close row has the flag 1 and no range" "$(mcol "$UM_FILE" close 4 | cut -f13-14 | tr '\t' '|')" "|1"

# --- A4: a marker that cannot be written, or no transcript, changes nothing the caller prints ---
pair() { # pair LABEL SID MODE — the same call with and without the fault
  local d="$TMP/pair" o1 o2 s1 s2
  rm -rf "$d"; newrepo "$d"
  o1=$(cd "$d" && CLAUDE_CODE_SESSION_ID=$2 bash "$BRIEF" --open docs/plans/p.md 1 2>/dev/null); s1=$?
  rm -rf "$d"; newrepo "$d"
  [ "$3" != dir ] || mkdir -p "$d/.dforge/sdd/usage-markers.tsv"
  o2=$(cd "$d" && CLAUDE_CODE_SESSION_ID=$2 bash "$BRIEF" --open docs/plans/p.md 1 2>/dev/null); s2=$?
  check "A4 ($1): same exit code" "$s2" "$s1"
  check "A4 ($1): same stdout" "$o2" "$o1"
}
tscript sess-a4 50000 >/dev/null
pair "marker path is a directory" sess-a4 dir
pair "no transcript for the session" sess-nothing none
RO="$TMP/ro"; newrepo "$RO"
o_ok=$(cd "$RO" && CLAUDE_CODE_SESSION_ID=sess-a4 bash "$BRIEF" --open docs/plans/p.md 1 2>/dev/null | sed "s#$RO#R#g"); s_ok=$?
RO2="$TMP/ro2"; newrepo "$RO2"; mkdir -p "$RO2/.dforge/sdd"
ln -s "$TMP/no/such/dir/m.tsv" "$RO2/.dforge/sdd/usage-markers.tsv"
o_bad=$(cd "$RO2" && CLAUDE_CODE_SESSION_ID=sess-a4 bash "$BRIEF" --open docs/plans/p.md 1 2>/dev/null | sed "s#$RO2#R#g"); s_bad=$?
check "A4 (dangling marker path): same exit code" "$s_bad" "$s_ok"
check "A4 (dangling marker path): same stdout" "$o_bad" "$o_ok"
RC="$TMP/rc"; newrepo "$RC"; tscript sess-a4c 40000 >/dev/null
mkdir -p "$RC/.dforge/sdd/usage-markers.tsv"
cd "$RC" && CLAUDE_CODE_SESSION_ID=sess-a4c bash "$BRIEF" --open docs/plans/p.md 1 >/dev/null 2>&1
git -C "$RC" add -A >/dev/null 2>&1; printf 'y\n' > "$RC/y.txt"; git -C "$RC" add y.txt; git -C "$RC" commit -q -m y
o_c=$(CLAUDE_CODE_SESSION_ID=sess-a4c bash "$CLOSE" docs/plans/p.md 1 "$CP" 2>/dev/null); s_c=$?
cd "$HERE"
RC2="$TMP/rc2"; newrepo "$RC2"; cd "$RC2" && CLAUDE_CODE_SESSION_ID=sess-a4c bash "$BRIEF" --open docs/plans/p.md 1 >/dev/null 2>&1
printf 'y\n' > "$RC2/y.txt"; git -C "$RC2" add y.txt; git -C "$RC2" commit -q -m y
o_c2=$(CLAUDE_CODE_SESSION_ID=sess-a4c bash "$CLOSE" docs/plans/p.md 1 "$CP" 2>/dev/null); s_c2=$?
cd "$HERE"
check "A4 (task-close, marker path a directory): same exit code" "$s_c" "$s_c2"
check "A4 (task-close, marker path a directory): same stdout apart from the paths" "${o_c//$RC/R}" "${o_c2//$RC2/R}"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
