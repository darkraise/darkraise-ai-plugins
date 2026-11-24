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
# native PATH — PATH as native programs read it: jq.exe, node.exe and git.exe
# cannot open a Git Bash path such as /d/a/... with MSYS_NO_PATHCONV set.
native() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
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
o_ok=$(cd "$RO" && CLAUDE_CODE_SESSION_ID=sess-a4 bash "$BRIEF" --open docs/plans/p.md 1 2>/dev/null | sed -e "s#$(git -C "$RO" rev-parse --show-toplevel | tr -d '\r')#R#g" -e "s#$RO#R#g"); s_ok=$?
RO2="$TMP/ro2"; newrepo "$RO2"; mkdir -p "$RO2/.dforge/sdd"
ln -s "$TMP/no/such/dir/m.tsv" "$RO2/.dforge/sdd/usage-markers.tsv"
o_bad=$(cd "$RO2" && CLAUDE_CODE_SESSION_ID=sess-a4 bash "$BRIEF" --open docs/plans/p.md 1 2>/dev/null | sed -e "s#$(git -C "$RO2" rev-parse --show-toplevel | tr -d '\r')#R#g" -e "s#$RO2#R#g"); s_bad=$?
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

# --- transcript and marker fixture builders (the report's inputs are plain files) ---
tsx() { printf '2026-01-01T%02d:%02d:%02dZ' "$(( $1 / 3600 ))" "$(( ($1 / 60) % 60 ))" "$(( $1 % 60 ))"; }
rec_user() { # rec_user FILE SECONDS [TEXT] — a user record
  jq -nc --arg t "$(tsx "$2")" --arg x "${3:-go}" '{type:"user",isSidechain:false,timestamp:$t,message:{role:"user",content:$x}}' >> "$1"
}
rec_asst() { # rec_asst FILE SECONDS ID MODEL IN CR C5 C1 OUT [CONTENT_JSON [SIDECHAIN]]
  jq -nc --arg t "$(tsx "$2")" --arg id "$3" --arg m "$4" --argjson i "$5" --argjson cr "$6" --argjson c5 "$7" --argjson c1 "$8" \
    --argjson o "$9" --argjson content "${10:-[]}" --argjson side "${11:-false}" \
    '{type:"assistant",isSidechain:$side,timestamp:$t,message:{id:$id,model:$m,role:"assistant",content:$content,
      usage:{input_tokens:$i,cache_read_input_tokens:$cr,cache_creation_input_tokens:($c5+$c1),cache_creation:{ephemeral_5m_input_tokens:$c5,ephemeral_1h_input_tokens:$c1},output_tokens:$o}}}' >> "$1"
}
rec_compact() { # rec_compact FILE SECONDS PRE POST DURATION_MS
  jq -nc --arg t "$(tsx "$2")" --argjson pre "$3" --argjson post "$4" --argjson d "$5" \
    '{type:"system",subtype:"compact_boundary",isSidechain:false,content:"Conversation compacted",timestamp:$t,compactMetadata:{trigger:"auto",preTokens:$pre,postTokens:$post,durationMs:$d}}' >> "$1"
}
tool_bash() { jq -nc --arg id "$1" --arg c "$2" '{type:"tool_use",id:$id,name:"Bash",input:{command:$c}}'; }
tool_agent() { jq -nc --arg id "$1" --arg t "$2" '{type:"tool_use",id:$id,name:"Agent",input:{subagent_type:$t,description:"d",prompt:"p"}}'; }
tool_read() { jq -nc --arg id "$1" --arg f "$2" '{type:"tool_use",id:$id,name:"Read",input:{file_path:$f}}'; }
rec_result() { # rec_result FILE SECONDS TOOL_USE_ID CHARS — a tool result of CHARS characters
  jq -nc --arg t "$(tsx "$2")" --arg id "$3" --arg x "$(head -c "$4" < /dev/zero | tr '\0' 'x')" \
    '{type:"user",isSidechain:false,timestamp:$t,message:{role:"user",content:[{type:"tool_result",tool_use_id:$id,content:$x}]}}' >> "$1"
}
sz() { wc -c < "$1" | tr -d ' '; }
mrow() { # mrow FILE SECONDS EVENT PLAN N SID TRANSCRIPT SIZE CTX CALLER [RANGE [DEFERRED]]
  printf '%s\t%s\tdforge\t%s\t/plugin\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$(tsx "$2")" "$3" "$VERSION" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11:-}" "${12:-}" >> "$1"
}

# --- A5, A22, A25, A29: one transcript, one marked task, every field a literal ---
RP="$TMP/rp"; newrepo "$RP"
cat > "$RP/docs/plans/rp.md" <<'EOF'
# Report fixture

**Goal:** Report.

## Global Constraints

- None.

### Task 1: one

**Files:** `src/a.sh`, `src/b.sh`

Body.

### Task 2: two

Body.
EOF
git -C "$RP" add docs; git -C "$RP" commit -q -m rp
PROJ="$HOME/.claude/projects/-rp"; mkdir -p "$PROJ"
TR="$PROJ/sr.jsonl"; : > "$TR"
MK="$RP/.dforge/sdd/usage-markers.tsv"; mkdir -p "$(dirname "$MK")"; : > "$MK"
rec_user "$TR" 0 "before the task"
rec_asst "$TR" 5 pre claude-opus-5-5 1 1111 0 0 1 '[]'
mrow "$MK" 10 open docs/plans/rp.md 1 sr "$TR" "$(sz "$TR")" 40000 task-brief:1
rec_user "$TR" 11
rec_asst "$TR" 20 m1 claude-opus-5-5 11 20001 1301 0 7 "[$(tool_bash b1 'grep -n foo src/a.sh'), $(tool_read r1 "$RP/src/a.sh")]"
rec_asst "$TR" 21 m1 claude-opus-5-5 11 20001 1301 0 41 "[$(tool_bash b1 'grep -n foo src/a.sh'), $(tool_read r1 "$RP/src/a.sh")]"
rec_result "$TR" 22 r1 4000
rec_asst "$TR" 30 m2 claude-opus-5-5 13 30003 0 1707 29 "[$(tool_read r2 "$RP/src/a.sh"), $(tool_bash b2 'sed -n 1,20p src/b.sh'), $(tool_bash b3 'rg -n bar src/zzz.sh'), $(tool_bash b4 'git status')]"
rec_result "$TR" 31 r2 4000
rec_compact "$TR" 35 61000 5200 123000
rec_asst "$TR" 40 m3 claude-opus-5-5 17 9011 0 2309 31 "[$(tool_bash b5 'bash scripts/run-codex-task.sh p.md 1'), $(tool_bash b5b 'bash scripts/run-codex-task.sh p.md 1 --retry'), $(tool_bash b5c 'bash scripts/run-agy-task.sh p.md 1'), $(tool_bash b5d 'bash scripts/run-codex-review.sh r.md'), $(tool_bash b5e 'bash scripts/run-agy-review.sh r.md'), $(tool_bash b5f 'bash scripts/run-review-panel r.md'), $(tool_bash b7 'bash scripts/run-api-judge x'), $(tool_agent a1 dforge:impl-sonnet-high), $(tool_bash b6 'bash scripts/task-step rereview p.md 1')]"
mrow "$MK" 50 close docs/plans/rp.md 1 sr "$TR" "$(sz "$TR")" 61234 task-close:1 abc1234..def5678
rec_asst "$TR" 55 post claude-opus-5-5 2 2222 0 0 3 '[]'
SUB="$PROJ/sr/subagents"; mkdir -p "$SUB"
rec_asst "$SUB/agent-a1.jsonl" 25 sa1 claude-sonnet-5-5 100 0 0 0 50 '[]' true
printf '{"agentType":"dforge:judge-opus"}' > "$SUB/agent-a1.meta.json"
rec_asst "$SUB/agent-a1.jsonl" 26 sa1 claude-sonnet-5-5 100 0 0 0 50 '[]' true


J=$(cd "$RP" && bash "$REPORT" --format json 2>"$TMP/a5.err")
T='.plans[0].tasks[0]'
# vals EXPR — every scalar under EXPR, one JSON array; key REGEX — the first value whose key matches
vals() { jq -c "[$2 | .. | scalars]" <<<"$1" 2>/dev/null; }
has_val() { jq -e --argjson v "$3" "[$2 | .. | scalars] | any(. == \$v)" <<<"$1" >/dev/null 2>&1 && echo yes || echo no; }
key() { jq -c --arg r "$3" "[$2 | to_entries[] | select(.key | test(\$r; \"i\")) | .value][0]" <<<"$1" 2>/dev/null; }
near() { jq -e --argjson v "$3" "[$2 | .. | numbers] | any((. - \$v) | fabs < 0.0000015)" <<<"$1" >/dev/null 2>&1 && echo yes || echo no; }

# --- A5 ---
check "A5: one closed task is reported" "$(jq -c '.plans[0].tasks | length' <<<"$J")" "1"
check "A5: turns (a repeated message id counts once)" "$(key "$J" "$T" '^turns$')" "3"
check "A5: input tokens" "$(has_val "$J" "$T" 41)" "yes"
check "A5: cache read" "$(has_val "$J" "$T" 59015)" "yes"
check "A5: cache write, 5 minute" "$(has_val "$J" "$T" 1301)" "yes"
check "A5: cache write, 1 hour" "$(has_val "$J" "$T" 4016)" "yes"
check "A5: output tokens (the repeated id keeps its maximum, 41, not 7 or 48)" "$(has_val "$J" "$T" 101)" "yes"
check "A5: output is never the double-counted 108" "$(has_val "$J" "$T" 108)" "no"
check "A5: model" "$(vals "$J" "$T" | jq -c 'index("claude-opus-5-5") != null')" "true"
check "A5: lookups (grep, two Reads, sed -n, rg; git status is not one)" "$(key "$J" "$T" '^lookups$')" "5"
READ_TOK=$(key "$J" "$T" 'read.?tokens')
check "A5: Read tokens, for two 4000-character results, between 1000 and 4000"   "$([ "${READ_TOK:-0}" -ge 1000 ] 2>/dev/null && [ "${READ_TOK:-0}" -le 4000 ] && echo yes || echo "no: $READ_TOK")" "yes"
check "A5: repeat whole-file reads" "$(key "$J" "$T" 'repeat')" "1"
check "A5: a compaction with its seconds (123000 ms or 123 s)"   "$(jq -e "[$T | .compactions[]? | .. | scalars] | (any(. == 123000) or any(. == 123))" <<<"$J" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "A5: context at open and at close" "$(has_val "$J" "$T" 40000)/$(has_val "$J" "$T" 61234)" "yes/yes"
SUBJ=$(jq -c "$T | [.. | objects | select(has(\"dforge:judge-opus\"))][0][\"dforge:judge-opus\"]" <<<"$J" 2>/dev/null)
check "A5: subagent usage by agent type, a repeated id once (100 in, 50 out)"   "$(jq -c '[.. | scalars] | [any(. == 100), any(. == 50), any(. == 200), any(. == 100) and (map(select(. == 100)) | length == 1)]' <<<"$SUBJ" 2>/dev/null)" "[true,true,false,true]"
check "A5: subagent cost at the Sonnet 5.5 rate (700 micro-dollars)" "$(near "$SUBJ" '.' 0.0007)" "yes"
# Task cost: the main-chain tokens at Opus 5.5 rates from the prices file, plus the subagent's.
EXPECT=$(jq -n --slurpfile p "$(native "$P/reference/api-prices.json")" '$p[0].models["claude-opus-5-5"] as $m | (41*$m.input + 59015*$m.cacheRead + 1301*$m.cacheWrite5m + 4016*$m.cacheWrite1h + 101*$m.output) / 1000000 + 0.0007')
check "A5: task cost" "$(near "$J" "$T | .cost" "$EXPECT")" "yes"
check "A5: a task is not charged for a subagent outside its window (one subagent file)" "$(jq -c "[$T | .. | objects | select(has(\"dforge:judge-opus\"))] | length" <<<"$J")" "1"

# --- A25: dispatch counts and fix rounds come from the transcript alone ---
check "A25: no ledger or review record exists for the fixture" "$(find "$RP/.dforge" -name progress.md | wc -l | tr -d ' '):$(ls "$RP/docs/dforge/reviews" 2>/dev/null | wc -l | tr -d ' ')" "0:0"
DSP=$(key "$J" "$T" '^dispatch')
dfam() { jq -c --arg r "$1" '[to_entries[] | select(.key | test($r; "i")) | .value] | add' <<<"$DSP" 2>/dev/null; }
check "A25: codex executor dispatches (two)" "$(dfam 'codex.*task')" "2"
check "A25: agy executor dispatches" "$(dfam 'agy.*task')" "1"
check "A25: codex review dispatches" "$(dfam 'codex.*review')" "1"
check "A25: agy review dispatches" "$(dfam 'agy.*review')" "1"
check "A25: review panel dispatches" "$(dfam 'panel')" "1"
check "A25: run-api-judge dispatches" "$(dfam 'api.?judge')" "1"
check "A25: Agent calls by agent type" "$(dfam 'impl-sonnet-high')" "1"
check "A25: fix rounds from task-step rereview calls" "$(key "$J" "$T" 'fix.?rounds')" "1"

# --- A22: lookups that hit a file the task's **Files:** line names ---
JP=$(cd "$RP" && bash "$REPORT" --plan docs/plans/rp.md --format json 2>/dev/null)
check "A22: share of lookups on named files (4 of 5)" "$([ "$(has_val "$JP" "$T" 0.8)" = yes ] || [ "$(has_val "$JP" "$T" 80)" = yes ] && echo yes || echo "no: $(key "$JP" "$T" 'share')")" "yes"

# --- A29: outside bucket, cost per completed task, growth, postTokens ---
check "A29: growth is the sum of positive context changes (10410; the drop is not netted)" "$(key "$J" "$T" 'growth')" "10410"
check "A29: postTokens and the first request's context after the compaction" "$(has_val "$J" "$T" 5200)/$(has_val "$J" "$T" 11337)" "yes/yes"
OUT=$(key "$J" '.plans[0]' '^outside')
OUT_COST=$(jq -n --slurpfile p "$(native "$P/reference/api-prices.json")" '$p[0].models["claude-opus-5-5"] as $m | (2*$m.input + 2222*$m.cacheRead + 3*$m.output) / 1000000')
check "A29: an outside-tasks bucket holds the usage after the close" "$(near "$OUT" '.' "$OUT_COST")" "yes"
SEG=$(jq -c "$T | .cost" <<<"$J")
check "A29: segment-only cost per completed task, beside the other figure" "$(near "$J" '.plans[0] | del(.tasks, .outside, .byModel, .byRepo)' "$SEG")" "yes"
WITH=$(jq -n --argjson a "$SEG" --argjson b "$OUT_COST" '$a + $b')
check "A29: cost per completed task is (segments + outside) / completed" "$(near "$J" '.plans[0] | del(.tasks, .outside, .byModel, .byRepo)' "$WITH")" "yes"

# --- A23: a task across two transcripts; two overlapping tasks in one transcript ---
mkrep() { # mkrep NAME — a repository, its project directory and an empty marker file
  RN="$TMP/$1"; newrepo "$RN"
  # Named as usage-report names it, after the checkout git reports: on
  # Windows the long form, not TMP's 8.3 spelling.
  PJ="$HOME/.claude/projects/$(git -C "$RN" rev-parse --show-toplevel | tr -d '\r' | tr -d '\n' | tr -c 'A-Za-z0-9' '-')"; mkdir -p "$PJ"
  MKN="$RN/.dforge/sdd/usage-markers.tsv"; mkdir -p "$(dirname "$MKN")"; : > "$MKN"
}
runrep() { (cd "$RN" && bash "$REPORT" "$@" --format json 2>/dev/null); }

mkrep xs
TA="$PJ/sa.jsonl"; TB="$PJ/sb.jsonl"; : > "$TA"; : > "$TB"
rec_asst "$TA" 1 a0 claude-opus-5-5 99 9999 0 0 99 '[]'
mrow "$MKN" 10 open docs/plans/p.md 1 sa "$TA" "$(sz "$TA")" 1000 task-brief:1
rec_asst "$TA" 20 a1 claude-opus-5-5 21 1001 0 0 31 '[]'
rec_asst "$TA" 30 a2 claude-opus-5-5 22 1002 0 0 32 '[]'
rec_asst "$TB" 40 b1 claude-opus-5-5 23 1003 0 0 33 '[]'
rec_asst "$TB" 50 b2 claude-opus-5-5 24 1004 0 0 34 '[]'
mrow "$MKN" 60 close docs/plans/p.md 1 sb "$TB" "$(sz "$TB")" 2000 task-close:1 aa11..bb22
rec_asst "$TB" 70 b3 claude-opus-5-5 88 8888 0 0 88 '[]'
J=$(runrep)
T='.plans[0].tasks[0]'
check "A23: one row for the task across two transcripts" "$(jq -c '.plans[0].tasks | length' <<<"$J")" "1"
check "A23: its turns are the four in the two segments" "$(key "$J" "$T" '^turns$')" "4"
check "A23: input is the two segments summed once (21+22+23+24)" "$(has_val "$J" "$T" 90)" "yes"
check "A23: cache read is the two segments summed once" "$(has_val "$J" "$T" 4010)" "yes"
check "A23: output is the two segments summed once" "$(has_val "$J" "$T" 130)" "yes"
check "A23: nothing before the open or after the close is in the task" "$(has_val "$J" "$T" 99)/$(has_val "$J" "$T" 88)" "no/no"

mkrep xg
TG="$PJ/sg.jsonl"; : > "$TG"
rec_asst "$TG" 5 g0 claude-opus-5-5 77 7777 0 0 77 '[]'
mrow "$MKN" 10 open docs/plans/p.md 2 sg "$TG" "$(sz "$TG")" 1000 task-brief:2
rec_asst "$TG" 20 g1 claude-opus-5-5 31 3001 0 0 41 '[]'
mrow "$MKN" 25 open docs/plans/p.md 3 sg "$TG" "$(sz "$TG")" 1100 task-brief:3
rec_asst "$TG" 30 g2 claude-opus-5-5 32 3002 0 0 42 '[]'
mrow "$MKN" 35 close docs/plans/p.md 2 sg "$TG" "$(sz "$TG")" 2000 task-close:2 aa11..bb22
rec_asst "$TG" 40 g3 claude-opus-5-5 33 3003 0 0 43 '[]'
mrow "$MKN" 45 close docs/plans/p.md 3 sg "$TG" "$(sz "$TG")" 2100 task-close:3 bb22..cc33
J=$(runrep)
check "A23: tasks 2 and 3 form one group row" "$(jq -c '.plans[0].tasks | length' <<<"$J")" "1"
check "A23: the row names both tasks" "$(jq -c '[.plans[0].tasks[0] | .tasks[]?]' <<<"$J")" "[2,3]"
check "A23: the union is measured once (turns 3)" "$(key "$J" "$T" '^turns$')" "3"
check "A23: input is the union once (31+32+33 = 96), not task 2's plus task 3's" "$(has_val "$J" "$T" 96)/$(has_val "$J" "$T" 63)" "yes/no"
check "A23: both tasks count as completed" "$(jq -c '.plans[0].completed' <<<"$J")" "2"
check "A23: the report names the row a group" "$(jq -c "$T | [.. | scalars] | any(. == true)" <<<"$J")" "true"

# --- A24, A6: the ledger gone; a ledger line the markers miss; a deferred ledger line ---
mkrep xu
TU="$PJ/su.jsonl"; : > "$TU"
rec_asst "$TU" 2 u0 claude-opus-5-5 5 500 0 0 5 '[]'
mrow "$MKN" 10 open docs/plans/p.md 1 su "$TU" "$(sz "$TU")" 1000 task-brief:1
rec_asst "$TU" 20 u1 claude-opus-5-5 6 600 0 0 6 '[]'
mrow "$MKN" 30 close docs/plans/p.md 1 su "$TU" "$(sz "$TU")" 1500 task-close:1 aa11..bb22
mrow "$MKN" 31 close docs/plans/p.md 4 su "$TU" "$(sz "$TU")" 1600 auto-run:task-complete "" 1
rec_asst "$TU" 40 u2 claude-opus-5-5 7 700 0 0 7 "[$(tool_bash c1 'bash /x/scripts/task-brief --open docs/plans/p.md 3')]"
rec_asst "$TU" 50 u3 claude-opus-5-5 8 800 0 0 8 '[]'
rec_asst "$TU" 60 u4 claude-opus-5-5 9 900 0 0 9 "[$(tool_bash c2 'bash /x/scripts/task-close docs/plans/p.md 3 "done: x; verified: y; remaining: none; discovered: none; assumptions: none"')]"
rec_asst "$TU" 70 u5 claude-opus-5-5 4 400 0 0 4 '[]'
JN=$(runrep --plan docs/plans/p.md)
check "A24: with no ledger, the marked task 1 is reported" "$(jq -c '[.plans[0].tasks[] | select(.tasks == [1])] | length' <<<"$JN")" "1"
check "A24: with no ledger, its commit range comes from the close row" "$(has_val "$JN" '.plans[0].tasks[] | select(.tasks == [1])' '"aa11..bb22"')" "yes"
check "A24: with no ledger, the deferred close row is not a completed task" "$(jq -c '.plans[0].completed' <<<"$JN")" "1"
check "A24: with no ledger, the deferred flag is reported for task 4" \
  "$(jq -e '[.plans[0] | .. | scalars | select(type == "string") | select(test("deferred"; "i"))] | length > 0' <<<"$JN" >/dev/null 2>&1 && echo yes || echo no)" "yes"
LD="$RN/.dforge/sdd/p"; mkdir -p "$LD"
printf '# SDD ledger — plan: docs/plans/p.md\nTask 1: complete (commits aa11..bb22, unreviewed) — x\nTask 2: complete (deferred by the auto run) — reason\nTask 3: complete (commits bb22..cc33, unreviewed) — y\n' > "$LD/progress.md"
JL=$(runrep --plan docs/plans/p.md)
check "A24: a ledger complete line with no marker is listed unmarked (task 3 only)" "$(key "$JL" '.plans[0]' '^unmarked$')" "1"
check "A24: the unmarked task is listed as unmarked" \
  "$(jq -c '[.plans[0].tasks[] | select(.tasks == [3]) | [.. | scalars] | any(. == "unmarked")] | any' <<<"$JL")" "true"
check "A24: the unmarked task's inferred turns come from its boundaries (at least 2)" \
  "$(jq -e '[.plans[0].tasks[] | select(.tasks == [3]) | .turns] | .[0] >= 2' <<<"$JL" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "A6: the deferred ledger line is no task row" "$(jq -c '[.plans[0].tasks[] | .tasks[]] | index(2)' <<<"$JL")" "null"
check "A6: the deferred ledger line is not listed unmarked (unmarked counts task 3 alone)" "$(key "$JL" '.plans[0]' '^unmarked$')" "1"
check "A6: the deferred ledger line is not a completed task (1 marked + 1 inferred)" "$(jq -c '.plans[0].completed' <<<"$JL")" "2"

# --- A8: an unpriced model adds nothing to cost ---
mkrep xp
TP="$PJ/sp.jsonl"; : > "$TP"
mrow "$MKN" 10 open docs/plans/p.md 1 sp "$TP" 0 1000 task-brief:1
rec_asst "$TP" 20 p1 claude-opus-5-5 1000 0 0 0 0 '[]'
rec_asst "$TP" 21 p2 claude-mystery-9 5000000 0 0 0 5000000 '[]'
mrow "$MKN" 30 close docs/plans/p.md 1 sp "$TP" "$(sz "$TP")" 1500 task-close:1 aa11..bb22
J=$(runrep)
check "A8: the unknown model is named as unpriced" \
  "$(jq -c '[.plans[0].tasks[0] | .. | scalars | select(. == "claude-mystery-9")] | length > 0' <<<"$J")" "true"
check "A8: only the priced model's tokens are costed (1000 Opus input tokens)" \
  "$(near "$J" '.plans[0].tasks[0] | .cost' "$(jq -n --slurpfile p "$(native "$P/reference/api-prices.json")" '1000 * $p[0].models["claude-opus-5-5"].input / 1000000')")" "yes"
check "A8: the unknown model adds no cost (nothing near what 5M tokens would cost)" \
  "$(jq -c '.plans[0].tasks[0].cost < 0.01' <<<"$J")" "true"
check "A8: dagents ships the same prices file" "$(cmp -s "$P/reference/api-prices.json" "$REPO_ROOT/plugins/dagents/reference/api-prices.json" && echo same || echo differ)" "same"
# validate-repository over a copy of the committed tree
VR="$TMP/vr"; mkdir -p "$VR"
git -C "$(native "$REPO_ROOT")" archive HEAD | tar -x -C "$VR"
check "A8: validate-repository passes on an untouched copy" "$(node "$(native "$REPO_ROOT/scripts/validate-repository.mjs")" "$VR" >/dev/null 2>&1; echo $?)" "0"
for f in plugins/dagents/scripts/lib/usage-report.mjs plugins/dagents/reference/api-prices.json plugins/dagents/scripts/usage-report plugins/dagents/scripts/lib/usage-marker.sh; do
  cp "$VR/$f" "$TMP/vr-keep"
  printf '\n# drift\n' >> "$VR/$f"
  [ "${f##*.}" != json ] || { cp "$TMP/vr-keep" "$VR/$f"; jq '.models["claude-opus-5-5"].input = 5' "$VR/$f" > "$TMP/vr-edit" && cp "$TMP/vr-edit" "$VR/$f"; }
  out=$(node "$(native "$REPO_ROOT/scripts/validate-repository.mjs")" "$VR" 2>&1); st=$?
  check "A8: validate-repository fails when $f drifts" "$([ "$st" -ne 0 ] && echo fails || echo "passes: $out")" "fails"
  cp "$TMP/vr-keep" "$VR/$f"
done

# --- A27: context-size --observations pairs Claude rows, plain and auto path ---
RB="$TMP/rb"; newrepo "$RB"
tscript sess-p 50000 >/dev/null
(cd "$RB" && CLAUDE_CODE_SESSION_ID=sess-p bash "$BRIEF" --open docs/plans/p.md 1 >/dev/null 2>&1)
tscript sess-p 90000 >/dev/null
(cd "$RB" && CLAUDE_CODE_SESSION_ID=sess-p bash "$BRIEF" --open docs/plans/p.md 2 >/dev/null 2>&1)
OBS=$(cd "$RB" && bash "$P/scripts/context-size" --observations 2>&1)
check "A27: plain path: the growth between two task briefs of a Claude session" "$(grep -c '^sess-p  Task 1 -> Task 2  +40k$' <<<"$OBS")" "1"
check "A27: plain path: the span line" "$(grep -c '^sess-p  span  50k -> 90k$' <<<"$OBS")" "1"
check "A27: plain path: the budget log rows name the session" "$(cut -f4 "$RB/.dforge/sdd/budget-log.tsv" 2>/dev/null | sort -u | tr '\n' ' ')" "sess-p "

RQ="$TMP/rq"; newrepo "$RQ"
tscript sess-q 30000 >/dev/null; beat sess-q
(cd "$RQ" && bash "$AR" --session sess-q start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
  bash "$AR" --session sess-q attach --plan docs/plans/p.md >/dev/null 2>&1
  CLAUDE_CODE_SESSION_ID=sess-q bash "$BRIEF" --open docs/plans/p.md 1 >"$TMP/q1.out" 2>&1)
tscript sess-q 75000 >/dev/null
(cd "$RQ" && CLAUDE_CODE_SESSION_ID=sess-q bash "$BRIEF" --open docs/plans/p.md 2 >"$TMP/q2.out" 2>&1)
check "A27: auto path: the briefs printed the auto budget line" "$(grep -hc '^budget (auto' "$TMP/q1.out" "$TMP/q2.out" | tr '\n' ' ')" "1 1 "
OBSQ=$(cd "$RQ" && bash "$P/scripts/context-size" --observations 2>&1)
check "A27: auto path: the growth between two task briefs of a Claude session" "$(grep -c '^sess-q  Task 1 -> Task 2  +45k$' <<<"$OBSQ")" "1"

RN2="$TMP/rn2"; newrepo "$RN2"
PN2="$HOME/.claude/projects/$(printf '%s' "$RN2" | tr -c 'A-Za-z0-9' '-')"; mkdir -p "$PN2"
printf '{"type":"assistant","isSidechain":false,"message":{"id":"m1","model":"claude-opus-5-5","usage":{"input_tokens":0,"cache_creation_input_tokens":0,"cache_read_input_tokens":20000,"output_tokens":1}}}\n' > "$PN2/named-by-file.jsonl"
(cd "$RN2" && bash "$BRIEF" --open docs/plans/p.md 1 >/dev/null 2>&1)
check "A27: with no session id in the environment, the row's session is the transcript's name" "$(cut -f4 "$RN2/.dforge/sdd/budget-log.tsv" 2>/dev/null)" "named-by-file"

# --- A26: --from-archive over a small fixture archive ---
ARC="$TMP/archive"; mkdir -p "$ARC/-root-repositories-x" "$ARC/-root-repositories-y"
printf 'session\tproject\tdforge\tstart\tend\tplans\ttasks\tcost_usd_list_1h\nar1\t/root/repositories/x\t4.17.1\t2026-11-01T10:00:00Z\t2026-11-01T10:09:00Z\t2026-11-01-alpha\t3\t0.01\nar2\t/root/repositories/y\t5.0.1\t2026-11-02T10:00:00Z\t2026-11-02T10:09:00Z\t2026-11-02-beta\t2\t0.01\n' > "$ARC/manifest.tsv"
APL=docs/dforge/plans/2026-11-01-alpha.md; BPL=docs/dforge/plans/2026-11-02-beta.md
A1F="$ARC/-root-repositories-x/ar1.jsonl"; A2F="$ARC/-root-repositories-y/ar2.jsonl"; : > "$A1F"; : > "$A2F"
rec_asst "$A1F" 5 x0 claude-opus-5-5 1 100 0 0 1 "[$(tool_bash k1 "bash /p/scripts/task-brief --open $APL 1")]"
rec_asst "$A1F" 10 x1 claude-opus-5-5 2 200 0 0 2 '[]'
rec_asst "$A1F" 15 x2 claude-opus-5-5 3 300 0 0 3 "[$(tool_bash k2 "bash /p/scripts/task-close $APL 1 \"done: x\"")]"
rec_asst "$A1F" 20 x3 claude-opus-5-5 4 400 0 0 4 "[$(tool_bash k3 "bash /p/scripts/task-step start $APL 2 3")]"
rec_asst "$A1F" 25 x4 claude-opus-5-5 5 500 0 0 5 '[]'
rec_asst "$A1F" 30 x5 claude-opus-5-5 6 600 0 0 6 "[$(tool_bash k4 "bash /p/scripts/task-close $APL 2 \"done: x\"")]"
rec_asst "$A1F" 35 x6 claude-opus-5-5 7 700 0 0 7 "[$(tool_bash k5 "bash /p/scripts/task-close $APL 3 \"done: x\"")]"
rec_asst "$A2F" 5 y0 claude-opus-5-5 1 100 0 0 1 "[$(tool_bash j1 "PLAN=$BPL; bash /p/scripts/task-brief --open \"\$PLAN\" 1")]"
rec_asst "$A2F" 10 y1 claude-opus-5-5 2 200 0 0 2 '[]'
rec_asst "$A2F" 15 y2 claude-opus-5-5 3 300 0 0 3 "[$(tool_bash j2 "PLAN=$BPL; bash /p/scripts/task-close \"\$PLAN\" 1 \"done: x\"")]"
rec_asst "$A2F" 20 y3 claude-opus-5-5 4 400 0 0 4 "[$(tool_bash j3 "PLAN=$BPL && bash /p/scripts/task-brief --open \$PLAN 2")]"
rec_asst "$A2F" 25 y4 claude-opus-5-5 5 500 0 0 5 '[]'
rec_asst "$A2F" 30 y5 claude-opus-5-5 6 600 0 0 6 "[$(tool_bash j4 "PLAN=$BPL && bash /p/scripts/task-close \$PLAN 2 \"done: x\"")]"
JA=$(cd "$TMP" && bash "$REPORT" --from-archive "$ARC" --format json 2>/dev/null)
tasks_of() { jq -c --arg n "$1" '[.plans[] | select([.. | strings] | any(test($n))) | .tasks[] | .tasks[]] | unique' <<<"$JA" 2>/dev/null; }
check "A26: both plans of the manifest are reported" "$(jq -c '[.plans[] | .plan] | length' <<<"$JA")" "2"
check "A26: alpha's tasks, batch start included (1, 2 and 3)" "$(tasks_of alpha)" "[1,2,3]"
check "A26: beta's tasks, with the plan in a variable (1 and 2)" "$(tasks_of beta)" "[1,2]"
check "A26: every task is labelled inferred" "$(jq -c '[.plans[] | .tasks[] | [.. | scalars] | any(. == "inferred")] | all' <<<"$JA")" "true"

# --- A28: the report saved at finishing, reused with the ledger gone ---
RF="$TMP/rf"; newrepo "$RF"
printf '\n**Spec:** docs/specs/s.md\n' >> "$RF/docs/plans/p.md"
mkdir -p "$RF/docs/dforge/reviews" "$RF/docs/dforge/registers" "$RF/docs/specs"
printf '# Review record: p

Plan: docs/plans/p.md

final review lens security — 1 Critical, 2 Important, 3 Minor; fixed 1, rejected 0
final review lens ui-ux — 0 Critical, 1 Important, 0 Minor; fixed 1, rejected 0
Final review: clean (commits aa11..bb22, 0 parked)
' > "$RF/docs/dforge/reviews/p.md"
git -C "$RF" worktree add -q "$TMP/wf" -b wf
PF="$HOME/.claude/projects/$(printf '%s' "$RF" | tr -c 'A-Za-z0-9' '-')"; mkdir -p "$PF"
TF="$PF/sf.jsonl"; : > "$TF"
MKF="$RF/.dforge/sdd/usage-markers.tsv"; mkdir -p "$(dirname "$MKF")"; : > "$MKF"
FB=$(git -C "$RF" rev-parse HEAD); printf 'x\n' > "$RF/x.txt"; git -C "$RF" add x.txt; git -C "$RF" commit -q -m x; FH=$(git -C "$RF" rev-parse HEAD)
mrow "$MKF" 10 open docs/plans/p.md 1 sf "$TF" 0 1000 task-brief:1
rec_asst "$TF" 20 f1 claude-opus-5-5 6 600 0 0 6 '[]'
mrow "$MKF" 30 close docs/plans/p.md 1 sf "$TF" "$(sz "$TF")" 1500 task-close:1 "$FB..$FH"
mkdir -p "$RF/.dforge/sdd/p"
printf '# SDD ledger — plan: docs/plans/p.md\nTask 1: fix round 3/3 (lint; commits %s..%s; still failing)\nTask 1: complete (commits %s..%s, unreviewed) — x\n' "$FB" "$FH" "$FB" "$FH" > "$RF/.dforge/sdd/p/progress.md"
out=$(cd "$TMP/wf" && bash "$REPORT" --plan docs/plans/p.md --save 2>&1); st=$?
SAVED="$RF/.dforge/sdd/usage-report-p.json"
check "A28: saving from a worktree exits 0 and prints nothing" "$st:$out" "0:"
check "A28: the report is saved in the primary checkout's state directory" "$([ -f "$SAVED" ] && echo yes || echo no)" "yes"
check "A28: the saved file is the JSON report" "$(jq -c '.plans[0].plan' "$SAVED" 2>/dev/null)" '"docs/plans/p.md"'
git -C "$RF" worktree remove --force "$TMP/wf"
rm -rf "$RF/.dforge/sdd/p" "$RF/docs/dforge/reviews/p.md"
JS=$(cd "$RF" && bash "$REPORT" --plan docs/plans/p.md --format json 2>/dev/null)
check "A28: the saved report carries the final-review findings by severity (1 Critical, 3 Important, 3 Minor)" \
  "$(jq -c '.plans[0].quality.findings | [(.Critical // .critical), (.Important // .important), (.Minor // .minor)]' "$SAVED" 2>/dev/null)" "[1,3,3]"
check "A28: with the ledger, workspace and review record gone, the same findings come from the saved report" \
  "$(jq -c '.plans[0].quality.findings | [(.Critical // .critical), (.Important // .important), (.Minor // .minor)]' <<<"$JS" 2>/dev/null)" "[1,3,3]"
check "A28: the ledger's breaker item is in the saved report" "$(jq -c '.plans[0].quality.breakerItems' "$SAVED" 2>/dev/null)" "1"
check "A28: with the ledger gone, the breaker item still comes from the saved report" "$(jq -c '.plans[0].quality.breakerItems' <<<"$JS" 2>/dev/null)" "1"
check "A28: the plan is still reported" "$(jq -c '.plans | length' <<<"$JS")" "1"
check "A28: the quality fields are labelled as of finishing" \
  "$(jq -c '[.plans[0] | .. | strings | select(test("finishing"; "i"))] | length > 0' <<<"$JS" 2>/dev/null)" "true"

# --- the auto-run polish: A11 resume, A12 version, A13 budget at close, A17 api-error, A18 counters ---
arrun() { # arrun REPO SESSION ARGS… — one auto-run call with a live cockpit in SESSION
  local d=$1 s=$2; shift 2
  beat "$s"
  (cd "$d" && bash "$AR" --session "$s" "$@")
}
state() { cat "$1/.dforge/sdd/auto-run.json"; }
RR="$TMP/rr"; newrepo "$RR"
git -C "$RR" commit -q --allow-empty -m base
arrun "$RR" r1 start --spec docs/s.md --register docs/r.md --isolation in-place >/dev/null 2>&1
arrun "$RR" r1 attach --plan docs/plans/p.md >/dev/null 2>&1
arrun "$RR" r1 total holds >/dev/null 2>&1; arrun "$RR" r1 total holds >/dev/null 2>&1
arrun "$RR" r1 compacted --seconds 40 >/dev/null 2>&1
arrun "$RR" r1 stalled >/dev/null 2>&1
arrun "$RR" r1 api-error >/dev/null 2>&1
jq '.failures = 2 | .resumes = 3 | .compactionsSinceTask = 4 | .pending = "compact" | .resumePrompt = "x" | .rebind = true' "$RR/.dforge/sdd/auto-run.json" > "$TMP/st.json" && cp "$TMP/st.json" "$RR/.dforge/sdd/auto-run.json"
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
jq '.stoppedKind = "guard"' "$RR/.dforge/sdd/auto-run.json" > "$TMP/st.json" && cp "$TMP/st.json" "$RR/.dforge/sdd/auto-run.json"
arrun "$RR" r4 resume >"$TMP/g.out" 2>"$TMP/g.err"; st=$?
check "A11: a guard stop is refused with exit 4, naming the reason" "$st:$([ -s "$TMP/g.err" ] && echo says || echo silent)" "4:says"
jq '.stoppedKind = "carried"' "$RR/.dforge/sdd/auto-run.json" > "$TMP/st.json" && cp "$TMP/st.json" "$RR/.dforge/sdd/auto-run.json"
arrun "$RR" r4 resume >/dev/null 2>&1; st=$?
check "A11: a carried-path stop is refused with exit 4" "$st" "4"
jq '.stoppedKind = null' "$RR/.dforge/sdd/auto-run.json" > "$TMP/st.json" && cp "$TMP/st.json" "$RR/.dforge/sdd/auto-run.json"
(cd "$RR" && bash "$AR" --session r5 resume >/dev/null 2>&1); st=$?
check "A11: resume from a session with no live cockpit exits 2 and leaves the run stopped" "$st:$(jq -c '.active' "$RR/.dforge/sdd/auto-run.json")" "2:false"
arrun "$RR" r4 resume >/dev/null 2>&1; st=$?
check "A11: with the stop kind cleared the same run resumes" "$st" "0"
arrun "$RR" r4 phase plan >/dev/null 2>&1
arrun "$RR" r4 stop --reason planstop >/dev/null 2>&1
arrun "$RR" r6 resume >/dev/null 2>&1; st=$?
check "A11: a run stopped in the plan phase resumes" "$st:$(jq -c '[.phase, .active, .session]' "$RR/.dforge/sdd/auto-run.json")" '0:["plan",true,"r6"]'
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
check "A11: setup — the run is in the execute phase on its branch" "$(jq -c '[.phase, .branch]' "$RX/.dforge/sdd/auto-run.json")" '["execute","auto/qa-run"]'
arrun "$RX" x1 stop --reason "manual" >/dev/null 2>&1
arrun "$RX" x2 resume >/dev/null 2>&1; st=$?
check "A11: an execute-phase run whose branch exists resumes" "$st:$(jq -c '.active' "$RX/.dforge/sdd/auto-run.json")" "0:true"
arrun "$RX" x2 stop --reason "manual 2" >/dev/null 2>&1
git -C "$RX" checkout -q main; git -C "$RX" branch -q -D auto/qa-run
arrun "$RX" x3 resume >"$TMP/x.out" 2>"$TMP/x.err"; st=$?
check "A11: an execute-phase run whose branch is gone is refused with exit 4" "$st:$(jq -c '.active' "$RX/.dforge/sdd/auto-run.json")" "4:false"
check "A11: the refusal names the reason" "$([ -s "$TMP/x.err" ] && echo says || echo silent)" "says"

# --- A17: the api-error command line ---
RE="$TMP/re"; newrepo "$RE"
arrun "$RE" e1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
arrun "$RE" e1 api-error >/dev/null 2>&1; arrun "$RE" e1 api-error >/dev/null 2>&1; arrun "$RE" e1 api-error >/dev/null 2>&1
check "A17: three api-error calls count three" "$(jq -c '[.apiErrors, .stalls, .active]' "$RE/.dforge/sdd/auto-run.json")" "[3,0,true]"
arrun "$RE" e1 api-error --clear >/dev/null 2>&1
check "A17: --clear resets the count" "$(jq -c '.apiErrors' "$RE/.dforge/sdd/auto-run.json")" "0"
arrun "$RE" e1 api-error >/dev/null 2>&1
arrun "$RE" e1 task-complete >/dev/null 2>&1
check "A17: task-complete resets the count" "$(jq -c '.apiErrors' "$RE/.dforge/sdd/auto-run.json")" "0"
sts=""
for i in 1 2 3 4 5 6 7 8 9 10; do arrun "$RE" e1 api-error >/dev/null 2>&1; sts="$sts$? "; done
check "A17: nine api-errors exit 0 and the tenth exits 5" "$sts" "0 0 0 0 0 0 0 0 0 5 "
check "A17: the tenth stops the run with an API-error reason" "$(jq -c '[.active, (.stopped | test("api"; "i"))]' "$RE/.dforge/sdd/auto-run.json")" "[false,true]"
check "A17: api errors never count as stalls" "$(jq -c '[.stalls, .totals.stalls]' "$RE/.dforge/sdd/auto-run.json")" "[0,0]"

# --- A12: the version warning ---
RV="$TMP/rv"; newrepo "$RV"; tscript v1 10000 >/dev/null
arrun "$RV" v1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
arrun "$RV" v1 attach --plan docs/plans/p.md >/dev/null 2>&1
check "A12: the run records the plugin version and root" "$(jq -c '[.version, .root]' "$RV/.dforge/sdd/auto-run.json")" "[\"$VERSION\",\"$P\"]"
mkroot() { # mkroot DIR VERSION — a copy of the plugin at another root and version
  mkdir -p "$1"; cp -R "$P/scripts" "$P/.claude-plugin" "$1/"
  jq --arg v "$2" '.version = $v' "$(native "$P/.claude-plugin/plugin.json")" > "$1/.claude-plugin/plugin.json"
}
mkroot "$TMP/other-9" 9.9.9
mkroot "$TMP/other-same" "$VERSION"
WARN="auto run: plugin version mismatch — run $VERSION at $P, this call 9.9.9 at $(cd "$TMP/other-9" && pwd)"
beat v1
(cd "$RV" && bash "$TMP/other-9/scripts/auto-run" --session v1 status >"$TMP/v.out" 2>"$TMP/v.err")
check "A12: an auto-run call from another version warns on stderr, naming both versions and roots" "$(grep -cxF "$WARN" "$TMP/v.err")" "1"
check "A12: the warning is not on stdout" "$(grep -c 'version mismatch' "$TMP/v.out")" "0"
check "A12: the mismatch is recorded in auto-run.json" "$(state "$RV" | jq -c '[.. | strings | select(test("9\\.9\\.9"))] | length > 0')" "true"
(cd "$RV" && bash "$TMP/other-same/scripts/auto-run" --session v1 status >/dev/null 2>"$TMP/v2.err")
check "A12: a call from another root with the same version prints no warning" "$(grep -c 'version mismatch' "$TMP/v2.err")" "0"
(cd "$RV" && CLAUDE_CODE_SESSION_ID=v1 bash "$TMP/other-9/scripts/task-brief" --open docs/plans/p.md 1 >/dev/null 2>"$TMP/v3.err")
check "A12: task-brief --open from another version warns exactly once" "$(grep -cxF "$WARN" "$TMP/v3.err")" "1"
printf 'x\n' > "$RV/x.txt"; git -C "$RV" add x.txt; git -C "$RV" commit -q -m x
(cd "$RV" && CLAUDE_CODE_SESSION_ID=v1 bash "$TMP/other-9/scripts/task-close" docs/plans/p.md 1 "$CP" >"$TMP/v4.out" 2>"$TMP/v4.err")
check "A12: task-close from another version warns exactly once" "$(grep -cxF "$WARN" "$TMP/v4.err")" "1"
check "A12: the warning never appears on task-close's stdout as a pending decision" "$(grep -c 'version mismatch' "$TMP/v4.out")" "0"
RV0="$TMP/rv0"; newrepo "$RV0"
arrun "$RV0" w1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
beat w1
(cd "$RV0" && bash "$P/scripts/auto-run" --session w1 status >/dev/null 2>"$TMP/v5.err")
check "A12: a call from the run's own version warns nothing" "$(grep -c 'version mismatch' "$TMP/v5.err")" "0"

# --- A13: the budget line after every task-close of an auto run ---
RW="$TMP/rw"; newrepo "$RW"
tscript w1 50000 >/dev/null
arrun "$RW" w1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
arrun "$RW" w1 attach --plan docs/plans/p.md >/dev/null 2>&1
rw() { (cd "$RW" && CLAUDE_CODE_SESSION_ID=w1 bash "$KIT/scripts/$1" "${@:2}"); }
rw task-brief --open docs/plans/p.md 1 >/dev/null 2>&1
printf 'x\n' > "$RW/x.txt"; git -C "$RW" add x.txt; git -C "$RW" commit -q -m x
out=$(rw task-close docs/plans/p.md 1 "$CP" 2>/dev/null); st=$?
check "A13: task 1 of 3 closes with exit 0" "$st" "0"
check "A13: the last line is the auto budget line, ok" "$(tail -n 1 <<<"$out" | grep -Ec '^budget \(auto[^)]*\): 50k of [0-9]+k \([0-9]+%\) — ok — ')" "1"
rw task-brief --open docs/plans/p.md 2 >/dev/null 2>&1
printf 'y\n' > "$RW/y.txt"; git -C "$RW" add y.txt; git -C "$RW" commit -q -m y
tscript w1 3000000 >/dev/null
out=$(rw task-close docs/plans/p.md 2 "$CP" 2>/dev/null); st=$?
check "A13: over budget, the line says compact and the exit code is still 0" "$st:$(tail -n 1 <<<"$out" | grep -Ec '^budget \(auto[^)]*\): .* — compact — ')" "0:1"
tscript w1 50000 >/dev/null
rw task-brief --open docs/plans/p.md 3 >/dev/null 2>&1
printf 'z\n' > "$RW/z.txt"; git -C "$RW" add z.txt; git -C "$RW" commit -q -m z
KST="$TMP/kitstop"; mkdir -p "$KST"; cp -R "$P/scripts" "$P/.claude-plugin" "$KST/"
mv "$KST/scripts/auto-run" "$KST/scripts/auto-run.real"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = task-complete ] && exit 5; done\nexec bash "$(dirname "$0")/auto-run.real" "$@"\n' > "$KST/scripts/auto-run"
out=$(cd "$RW" && CLAUDE_CODE_SESSION_ID=w1 bash "$KST/scripts/task-close" docs/plans/p.md 3 "$CP" 2>/dev/null); st=$?
check "A13: a task-complete that stopped the run exits 5 and no budget line follows" "$st:$(grep -c '^budget' <<<"$out")" "5:0"

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
check "A18: nothing is saved when the report is missing" "$(ls "$RC3/.dforge/sdd"/usage-report-*.json 2>/dev/null | wc -l | tr -d ' ')" "0"
FIN=$(tr -d '\r' < "$P/reference/auto-run.md" | flat)
check "A18: the finishing text prints the counters, the per-task summary and the missing line" \
  "$(has "$FIN" 'auto-run counters')/$(has "$FIN" 'usage summary missing')/$(has "$FIN" 'segment-only')" "yes/yes/yes"
check "A18: the finishing text names the CLAUDE.md follow-up" "$(has "$FIN" "update each repository's claude.md compact instructions")" "yes"

# --- A14: the review panel's availability memory in an auto run ---
PANEL="$P/scripts/run-review-panel"
PN="$TMP/panel"; mkdir -p "$PN"
printf '# review prompt\n' > "$PN/prompt.md"
cat > "$PN/codex-gate" <<'EOF'
#!/usr/bin/env bash
echo 'codex-gate usable=true reason=ok review=true resets_at=- source=cache'
EOF
cat > "$PN/agy-gate" <<'EOF'
#!/usr/bin/env bash
echo 'agy-gate usable=false reason=setting review=false resets_at=- claude=on claude_resets_at=- source=setting'
EOF
cat > "$PN/codex-runner" <<EOF
#!/usr/bin/env bash
out=""; while [ \$# -gt 0 ]; do case "\$1" in --out) out="\$2"; shift 2 ;; *) shift ;; esac; done
echo x >> "$PN/launches"
line=\$(cat "$PN/next-line" 2>/dev/null)
case "\$line" in *"status=OK"*) printf '{}' > "\$out" ;; esac
printf '%s\n' "\${line//@OUT@/\$out}"
EOF
chmod +x "$PN/codex-gate" "$PN/agy-gate" "$PN/codex-runner"
export PANEL_CODEX_GATE="$PN/codex-gate" PANEL_AGY_GATE="$PN/agy-gate" PANEL_CODEX_RUNNER="$PN/codex-runner"
launches() { wc -l < "$PN/launches" 2>/dev/null | tr -d ' ' | sed 's/^$/0/'; }
panel() { # panel REPO — one task panel from REPO as session pr1
  rm -rf "$PN/out"
  (cd "$1" && CLAUDE_CODE_SESSION_ID=pr1 bash "$PANEL" --kind task --tier heavy --cwd "$1" --out-dir "$PN/out" --prompt "$PN/prompt.md" 2>/dev/null)
}
quota_line() { printf 'codex-judge gpt-6-astra/xhigh status=FAILED exit=1 out=- evidence=none reason=quota%s\n' "${1:+ until=$1}" > "$PN/next-line"; }
skips() { jq -c '.reviewSkips // []' "$1/.dforge/sdd/auto-run.json" 2>/dev/null; }

RPA="$TMP/rpa"; newrepo "$RPA"
arrun "$RPA" pr1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
rm -f "$PN/launches"
UNTIL=$(( $(date +%s) + 3600 ))
quota_line "$UNTIL"
out=$(panel "$RPA")
check "A14: the quota failure's line is printed" "$(grep -c 'codex-judge .* status=FAILED .* reason=quota' <<<"$out")" "1"
check "A14: the failure is recorded under reviewSkips with its family and until" \
  "$(skips "$RPA" | jq -c --argjson u "$UNTIL" '[.[0].family, .[0].until, (.[0].failedAt | type)] | . == ["codex", $u, "number"]')" "true"
check "A14: the runner ran once" "$(launches)" "1"
out=$(panel "$RPA")
check "A14: inside the window the family is skipped as quota-skip" "$(grep -c 'codex-judge none/none status=SKIPPED .* reason=quota-skip' <<<"$out")" "1"
check "A14: inside the window nothing was launched" "$(launches)" "1"
# Past the until epoch without waiting for it: a slow runner made a short
# real window expire before the second panel ran.
jq '.reviewSkips[0].until = 1' "$RPA/.dforge/sdd/auto-run.json" > "$TMP/ar.json" && mv "$TMP/ar.json" "$RPA/.dforge/sdd/auto-run.json"
printf 'codex-judge gpt-6-astra/xhigh status=OK exit=0 out=@OUT@ evidence=none\n' > "$PN/next-line"
out=$(panel "$RPA")
check "A14: after the until epoch the family launches again" "$(launches):$(grep -c 'status=OK' <<<"$out")" "2:1"
# a second quota failure skips the family for the rest of the run
quota_line "$(( $(date +%s) + 2 ))"
out=$(panel "$RPA")
quota_line "$(( $(date +%s) + 2 ))"
sleep 3
out=$(panel "$RPA")
LAUNCHES=$(launches)
sleep 3
out=$(panel "$RPA")
check "A14: after a second quota failure the family stays skipped past its named reset" "$(launches):$(grep -c 'reason=quota-skip' <<<"$out")" "$LAUNCHES:1"
# no reset named: 5 hours
RPB="$TMP/rpb"; newrepo "$RPB"
arrun "$RPB" pr1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
quota_line ""
panel "$RPB" >/dev/null
check "A14: with no reset named the skip lasts 5 hours" "$(skips "$RPB" | jq -c '(.[0].until - .[0].failedAt) | . >= 17990 and . <= 18010')" "true"
# outside an auto run
RPC="$TMP/rpc"; newrepo "$RPC"
before=$(launches)
panel "$RPC" >/dev/null
check "A14: outside an auto run no skip is recorded" "$([ -f "$RPC/.dforge/sdd/auto-run.json" ] && echo file || echo none)" "none"
panel "$RPC" >/dev/null
check "A14: outside an auto run the family launches every time" "$(( $(launches) - before ))" "2"
# a denied-command review: a panel failure, never a run-long skip
RPD="$TMP/rpd"; newrepo "$RPD"
arrun "$RPD" pr1 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1
printf 'codex-judge gpt-6-astra/xhigh status=FAILED exit=1 out=- evidence=none reason=denied\n' > "$PN/next-line"
before=$(launches)
panel "$RPD" >/dev/null
panel "$RPD" >/dev/null
check "A14: a reason=denied review is counted as a panel failure each time" "$(jq -c '.totals.panelFailures' "$RPD/.dforge/sdd/auto-run.json")" "2"
check "A14: a reason=denied review sets no skip, so the family launches again" "$(skips "$RPD"):$(( $(launches) - before ))" "[]:2"
unset PANEL_CODEX_GATE PANEL_AGY_GATE PANEL_CODEX_RUNNER

# --- A15: task-step verdict reads 71-76(diff) as lines 71-76 ---
RT="$TMP/rt"; git init -q -b main "$RT"; git -C "$RT" config user.name Darkraise; git -C "$RT" config user.email dark@example.invalid
mkdir -p "$RT/docs"
printf '# P\n\n**Goal:** G.\n\n## Global Constraints\n\n- None.\n\n### Task 1: a\n\n**Files:** `x.sh`\n\n**Risk:** 3\n\n**Implementer:** `dforge:impl-sonnet-high`\n\nBody.\n' > "$RT/docs/plan.md"
git -C "$RT" add docs; git -C "$RT" commit -q -m init
(cd "$RT" && bash "$BRIEF" --open docs/plan.md 1 >/dev/null 2>&1)
printf 'x\n' > "$RT/x.sh"; git -C "$RT" add x.sh; git -C "$RT" commit -q -m x
(cd "$RT" && bash "$P/scripts/task-step" review docs/plan.md 1 >/dev/null 2>&1)
WS="$RT/.dforge/sdd/plan"
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
ROUND0=$(jq -c .round "$WS/task-1-step.json")
FILES0=$(ls "$WS" | wc -l | tr -d ' ')
VOUT=$(cd "$RT" && bash "$P/scripts/task-step" verdict docs/plan.md 1 2>&1); st=$?
check "A15: the verdict is accepted (exit 0)" "$st" "0"
check "A15: the finding is recorded as lines 71-76" "$(grep -c 'plugins/x.sh:71-76 — off by one' <<<"$VOUT")" "1"
check "A15: the parenthetical is not kept in the recorded line" "$(grep -c '71-76(diff)' <<<"$VOUT")" "0"
check "A15: the fix list names lines 71-76" "$(grep -c '^- plugins/x.sh:71-76: off by one' "$WS/task-1-fix-1.md" 2>/dev/null)" "1"
check "A15: no new dispatch: the round count is unchanged and only the fix file is added" \
  "$(jq -c .round "$WS/task-1-step.json"):$(( $(ls "$WS" | wc -l | tr -d ' ') - FILES0 ))" "$ROUND0:1"

# --- A16: a UI proof report passes the implementer stop gate; others without ## Verdict do not ---
GATE_IN() { # GATE_IN AGENT_ID REPORT — the SubagentStop input naming a report
  jq -nc --arg id "$1" --arg cwd "$TMP/gate-cwd" --arg m "$(printf '**Status:** DONE\nReport: %s' "$2")" \
    '{session_id:"11111111-2222-4333-8444-555555555555",cwd:$cwd,agent_id:$id,agent_type:"dforge:impl-sonnet-high",hook_event_name:"SubagentStop",stop_hook_active:false,last_assistant_message:$m}'
}
mkdir -p "$TMP/gate-cwd"; git -C "$TMP/gate-cwd" init -q 2>/dev/null
export XDG_STATE_HOME="$TMP/xdg"
gate() { GATE_IN "$1" "$2" | bash "$P/scripts/impl-stop-gate" 2>"$TMP/gate.err"; GST=$?; }
printf '# UI proof: dashboard\n\nScreenshots taken.\n' > "$TMP/proof.md"
gate g-proof "$TMP/proof.md"
check "A16: a proof report with no ## Verdict passes" "$GST:$(wc -c < "$TMP/gate.err" | tr -d ' ')" "0:0"
printf '\n  \n# UI proof: dashboard\n\nbody\n' > "$TMP/proof-blank.md"
gate g-proof2 "$TMP/proof-blank.md"
check "A16: blank lines before the proof heading still pass" "$GST" "0"
printf '# Notes\n\nNo verdict here.\n' > "$TMP/other.md"
gate g-other "$TMP/other.md"
check "A16: any other report without the heading is refused (exit 2)" "$GST" "2"
printf '# UI proofs\n\nbody\n' > "$TMP/near.md"
gate g-near "$TMP/near.md"
check "A16: a heading that only resembles the proof heading is refused" "$GST" "2"
printf '## Notes\n\n# UI proof: late\n' > "$TMP/late.md"
gate g-late "$TMP/late.md"
check "A16: a proof heading that is not the first non-empty line is refused" "$GST" "2"
printf '## Verdict\npass: 1\n' > "$TMP/qa.md"
gate g-qa "$TMP/qa.md"
check "A16: a QA report that opens with ## Verdict still passes" "$GST" "0"
unset XDG_STATE_HOME

# --- the replay harness (evals/workflow-ab): A21, A30, A31 ---
case ${OSTYPE:-} in
  msys*|cygwin*) echo 'skip - replay harness: Linux only'; HARNESS=0 ;;
  *) HARNESS=1 ;;
esac
if [ "$HARNESS" = 1 ]; then
WAB="$REPO_ROOT/evals/workflow-ab"
FXP=docs/dforge/plans/2026-01-01-fixture.md
WT="$(mktemp -d "${WAB_TEST_TMP:-/var/tmp}/efficiency-acceptance.XXXXXX")"
trap 'rm -rf "$TMP" "$WT"' EXIT
export WAB_ROOT="$WT/root" WAB_PLAN="$FXP"
mkdir -p "$WT/owner-config"
printf '{\n  "model": "opus",\n  "theme": "dark"\n}\n' > "$WT/owner-config/settings.json"
printf '{"handoffTokens": 275000}\n' > "$WT/owner-dforge.json"
export WAB_CLAUDE_CONFIG="$WT/owner-config" WAB_DFORGE_CONFIG="$WT/owner-dforge.json"
printf '#!/bin/sh\necho "9.9.9 (Claude Code)"\n' > "$WT/claude-version"; chmod +x "$WT/claude-version"
# A pass-through stand-in for the mount-namespace sandbox, which CI runners
# refuse; workflow-ab.test.sh tests the real one where the host allows it.
cat > "$WT/sandbox-pass" <<'EOF'
#!/usr/bin/env bash
[ "$1" = --check ] && exit 0
while [ $# -gt 0 ] && [ "$1" != -- ]; do shift; done
shift
exec "$@"
EOF
export WAB_SANDBOX="$WT/sandbox-pass"

# make_src DIR [SED] — a source repository holding the fixture, with a later commit past the base and an origin
make_src() {
  mkdir -p "$1"; cp -R "$WAB/fixture/." "$1/"
  mkdir -p "$1/.claude"
  printf '{"enabledPlugins": {"extra@market": true}}\n' > "$1/.claude/settings.json"
  mv "$1/$FXP" "$WT/plan.md"
  git -C "$1" init -q -b main; git -C "$1" config user.name Tester; git -C "$1" config user.email tester@localhost
  git -C "$1" add -A; git -C "$1" commit -q -m base
  mv "$WT/plan.md" "$1/$FXP"
  [ -z "${2:-}" ] || sed -i -E "$2" "$1/$FXP"
  git -C "$1" add -A; git -C "$1" commit -q -m "docs: add the plan"
  printf 'later\n' > "$1/later.txt"; git -C "$1" add -A; git -C "$1" commit -q -m later
  git init -q --bare "$1.origin.git"; git -C "$1" remote add origin "$1.origin.git"; git -C "$1" push -q origin main
}
base_of() { git -C "$1" rev-list --max-parents=0 HEAD; }
wprep() { WAB_CLAUDE="$WT/claude-version" bash "$WAB/prepare" "$@" >"$WT/prep.out" 2>&1; WST=$?; }

# stubs: tmux runs the session command in its own process group; claude records its argv and environment
cat > "$WT/tmux" <<EOF
#!/usr/bin/env bash
T=$WT
printf '%s\n' "\$*" >> "\$T/tmux.log"
cmd=\$1; shift
name=""
for ((i = 1; i <= \$#; i++)); do
  case \${!i} in -t|-s) j=\$((i + 1)); name=\${!j#=}; name=\${name%:}; break ;; esac
done
case \$cmd in
  new-session) setsid bash -c "\${!#}" >/dev/null 2>&1 & echo \$! > "\$T/tmux-\$name.pid" ;;
  has-session) p=\$(cat "\$T/tmux-\$name.pid" 2>/dev/null) && kill -0 "\$p" 2>/dev/null; exit \$? ;;
  list-panes) cat "\$T/tmux-\$name.pid" ;;
  kill-session) p=\$(cat "\$T/tmux-\$name.pid" 2>/dev/null) && kill -TERM -- "-\$p" 2>/dev/null; rm -f "\$T/tmux-\$name.pid" ;;
  capture-pane) cat "\$T/pane.txt" 2>/dev/null ;;
esac
exit 0
EOF
cat > "$WT/claude-stub" <<EOF
#!/usr/bin/env bash
T=$WT
if [ "\${1:-}" = --version ]; then echo "9.9.9 (Claude Code)"; exit 0; fi
printf '%s\n' "\$@" > "\$T/claude.argv"
env > "\$T/claude.env"
echo \$\$ > "\$T/claude.pid"
[ -e "\$T/hang" ] && exec sleep 300
exit 0
EOF
STUBP="$WT/stub-plugins"; mkdir -p "$STUBP/plugins/dforge/scripts" "$STUBP/plugins/dagents/scripts"
for a in dforge dagents; do
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n' "$WT/auto-run.log" > "$STUBP/plugins/$a/scripts/auto-run"
done
chmod +x "$WT/tmux" "$WT/claude-stub"
export WAB_TMUX="$WT/tmux"
wlaunch() { # wlaunch ARGS… — with the stubs and a 3-second limit unless MAXS is set
  WAB_PLUGINS="$STUBP" WAB_CLAUDE="$WT/claude-stub" WAB_MAX_SECONDS="${MAXS:-3}" bash "$WAB/launch" "$@" >"$WT/launch.out" 2>&1; LST=$?
}
snap() { git -C "$1" status --porcelain; git -C "$1" remote -v; git -C "$1" for-each-ref; git -C "$1" worktree list --porcelain; git -C "$1" stash list; git -C "$1" rev-parse HEAD; }

make_src "$WT/src"
export WAB_SOURCE="$WT/src" WAB_BASE; WAB_BASE=$(base_of "$WT/src")
LATER=$(git -C "$WT/src" rev-parse HEAD)
printf 'dirty\n' >> "$WT/src/greet.sh"; git -C "$WT/src" stash -q; printf 'untracked\n' > "$WT/src/scratch.txt"
SRC_SNAP=$(snap "$WT/src")
SET_SUM=$(sha256sum "$WT/owner-config/settings.json" | cut -d' ' -f1)

# --- A30: the pins and the arm record ---
wprep dforge 1; D1=$WST
wprep dagents 1; D2=$WST
check "A30: prepare exits 0 for both arms" "$D1$D2" "00"
DC="$WAB_ROOT/dforge-1/home/.dforge/config.json"; AC="$WAB_ROOT/dagents-1/home/.dagents/config.json"
check "A30: dforge pins: handoffTokens at the owner's pin, finishAction keep, API judge off, external reviews off" \
  "$(jq -c '[.handoffTokens, .finishAction, .decisionApi, .codexReview, .agyReview]' "$DC" 2>/dev/null)" '[275000,"keep","off",false,false]'
check "A30: dforge's three apiBudget caps are 0" "$(jq -c '[to_entries[] | select(.key | startswith("apiBudget")) | .value]' "$DC" 2>/dev/null)" "[0,0,0]"
check "A30: dagents pins: handoffTokens, finishAction keep, Codex and agy surfaces off" \
  "$(jq -c '[.handoffTokens, .finishAction, .codexReview, .codexLane, .agyLane]' "$AC" 2>/dev/null)" '[275000,"keep",false,false,false]'
for arm in dforge dagents; do
  AJ="$WAB_ROOT/$arm-1/arm.json"
  check "A30: $arm's arm record exists and names the arm" "$(jq -r .arm "$AJ" 2>/dev/null)" "$arm"
  check "A30: $arm's arm record holds the pins" "$(jq -c '.pins.handoffTokens, .pins.finishAction' "$AJ" 2>/dev/null | tr '\n' ' ')" '275000 "keep" '
  check "A30: $arm's arm record holds the launch model and effort" "$(jq -c '[to_entries[] | select(.key | test("^model$|^effort$")) | .value]' "$AJ" 2>/dev/null)" '["sonnet","high"]'
  check "A30: $arm's arm record holds parallelism, the Claude Code version and the autoCompactWindow" \
    "$(jq -c '[(keys | map(test("parallelism")) | any), (keys | map(test("claude.?version"; "i")) | any), (keys | map(test("autoCompactWindow")) | any)] | all' "$AJ" 2>/dev/null)" "true"
  check "A30: $arm's arm record holds the plugin commit and whether darkmem is available" \
    "$(jq -c '[(keys | map(test("plugin.?commit"; "i")) | any), (keys | map(test("darkmem")) | any)] | all' "$AJ" 2>/dev/null)" "true"
done
make_src "$WT/src-bad" 's/^\*\*Integration check:\*\* .*/**Integration check:** `false`/'
WAB_SOURCE="$WT/src-bad" WAB_BASE=$(base_of "$WT/src-bad") wprep dforge 2 --check
check "A30: prepare --check fails when the Integration check fails" "$WST" "1"
rm -f "$WT/claude.argv"; : > "$WT/tmux.log"
wlaunch dforge 2
check "A30: launch is blocked after a failed check" "$([ "$LST" -ne 0 ] && echo blocked || echo "ran: $(cat "$WT/launch.out")")" "blocked"
check "A30: the nested session never started" "$([ -e "$WT/claude.argv" ] && echo started || echo no):$(grep -c '^new-session' "$WT/tmux.log")" "no:0"
make_src "$WT/src-ok" 's/^\*\*Integration check:\*\* .*/**Integration check:** `true`/'
WAB_SOURCE="$WT/src-ok" WAB_BASE=$(base_of "$WT/src-ok") wprep dforge 3 --check
check "A30: prepare --check passes when the checks pass" "$WST" "0"

# --- A31: converted plans, the arm record's model and effort, and one plugin per launch ---
DP="$WAB_ROOT/dforge-1/clone/$FXP"; AP="$WAB_ROOT/dagents-1/clone/docs/dagents/plans/2026-01-01-fixture.md"
RL_D=$(grep -F 'replay in a clone with no remote' "$DP"); RL_A=$(grep -F 'replay in a clone with no remote' "$AP")
check "A31: the dforge copy carries exactly one replay-constraint line" "$(grep -cF 'replay in a clone with no remote' "$DP")" "1"
check "A31: the dagents copy carries exactly one replay-constraint line" "$(grep -cF 'replay in a clone with no remote' "$AP")" "1"
check "A31: the two lines are identical" "$([ -n "$RL_D" ] && [ "$RL_D" = "$RL_A" ] && echo same || echo differ)" "same"
check "A31: the line forbids push, tag and workflow dispatch and says a gate that needs one is not run" \
  "$(has "$(printf '%s' "$RL_D" | tr 'A-Z' 'a-z')" 'no push, tag or workflow dispatch')/$(has "$RL_D" 'recorded as not run')" "yes/yes"
check "A31: the dforge copy's Execution line is inline on sonnet at high effort" "$(has "$(grep '^\*\*Execution:\*\*' "$DP")" '**Execution:** inline — `claude --model sonnet --effort high`')" "yes"
check "A31: the dagents copy keeps its subagent Execution line" "$(grep '^\*\*Execution:\*\*' "$AP")" "$(grep '^\*\*Execution:\*\*' "$WAB/fixture/$FXP")"
make_src "$WT/src-opus" '/^### Task 2/,$ { s/impl-sonnet-high/impl-opus-medium/; s/risk 1 = 5/risk 3 = 7/ }'
WAB_SOURCE="$WT/src-opus" WAB_BASE=$(base_of "$WT/src-opus") wprep dforge 4
check "A31: with an opus implementer and a risk-3 task, the Execution line names opus at high effort" \
  "$(has "$(grep '^\*\*Execution:\*\*' "$WAB_ROOT/dforge-4/clone/$FXP")" '**Execution:** inline — `claude --model opus --effort high`')" "yes"
check "A31: that arm record holds opus and high" "$(jq -c '[to_entries[] | select(.key | test("^model$|^effort$")) | .value]' "$WAB_ROOT/dforge-4/arm.json" 2>/dev/null)" '["opus","high"]'
check "A31: the dforge copy qualifies the unqualified Items citation" "$(grep '^\*\*Items:\*\*' "$DP")" '**Items:** 2026-01-01-fixture#1'
check "A31: both converted plans pass their arm's plan-lint" "$(grep -c 'plan-lint: 0 errors' "$WAB_ROOT/dforge-1/out/plan-lint.txt" "$WAB_ROOT/dagents-1/out/plan-lint.txt" | sed 's#.*:##' | tr '\n' ' ')" "1 1 "
rm -f "$WT/claude.argv"; : > "$WT/tmux.log"
rm -f "$WAB_ROOT/dforge-1/clone/.claude/settings.local.json"
wlaunch dforge 1
check "A31: launch refuses while the clone's project settings enable a second plugin" "$([ "$LST" -ne 0 ] && echo refused || echo "ran")" "refused"
check "A31: the refusal names the other plugin" "$(grep -c 'extra@market' "$WT/launch.out")" "1"
check "A31: no nested session started" "$([ -e "$WT/claude.argv" ] && echo started || echo no):$(grep -c '^new-session' "$WT/tmux.log")" "no:0"

# --- A21: a run under stubs leaves the source and the owner's settings alone ---
check "A21: the clone has no remote" "$(git -C "$WAB_ROOT/dforge-1/clone" remote)" ""
check "A21: the clone's pre-push hook refuses" "$("$WAB_ROOT/dforge-1/clone/.git/hooks/pre-push" >/dev/null 2>&1; echo $?)" "1"
CL="$WAB_ROOT/dforge-1/clone"
check "A21: no object outside the base's ancestry (the later commit is not in the clone)" "$(git -C "$CL" cat-file -e "$LATER" 2>/dev/null && echo present || echo absent)" "absent"
check "A21: every ref is the base's ancestry plus the one replay-plan commit" \
  "$(git -C "$CL" rev-list --all | grep -vxF -f <(git -C "$WT/src" rev-list "$WAB_BASE") | wc -l | tr -d ' ')" "1"
check "A21: no unreachable object is left in the clone" "$(git -C "$CL" fsck --unreachable --no-reflogs 2>/dev/null | grep -c unreachable)" "0"
check "A21: after prepare the source's status, remotes, refs, worktrees, stashes and HEAD are unchanged" "$(snap "$WT/src")" "$SRC_SNAP"
rm -f "$WT/claude.argv" "$WT/claude.env"; : > "$WT/tmux.log"
wprep dforge 8
wlaunch dforge 8
check "A21: launch under stubs exits 0" "$LST" "0"
check "A21: after launch the source is unchanged" "$(snap "$WT/src")" "$SRC_SNAP"
check "A21: after launch the owner's settings.json is byte-identical" "$(sha256sum "$WT/owner-config/settings.json" | cut -d' ' -f1)" "$SET_SUM"
ENVARR=(); while IFS= read -r l; do ENVARR+=("$l"); done < <(grep -E '^[A-Za-z_][A-Za-z0-9_]*=[^ ]*$' "$WT/claude.env")
check "A21: a push to an ssh URL fails under the launch environment" \
  "$(cd "$CL" && env -i "${ENVARR[@]}" git push ssh://example.invalid/x.git HEAD >/dev/null 2>&1; [ $? -ne 0 ] && echo fails || echo pushed)" "fails"
check "A21: the clone still has no remote after the launch" "$(git -C "$CL" remote)" ""
# a run past its limit is stopped and marked timed-out
: > "$WT/auto-run.log"; touch "$WT/hang"
wprep dforge 5
MAXS=2 wlaunch dforge 5
check "A21: a run past its limit exits 0 and is marked timed-out" "$LST:$(cat "$WAB_ROOT/dforge-5/state" 2>/dev/null)" "0:timed-out"
check "A21: the bound run was told to stop" "$(grep -c -- ' stop --reason workflow-ab: timed-out$' "$WT/auto-run.log")" "1"
check "A21: the harness killed its own tmux session" "$(grep -c '^kill-session -t =wab-dforge-5' "$WT/tmux.log")" "1"
sleep 1
check "A21: the nested session's process is gone" "$(kill -0 "$(cat "$WT/claude.pid")" 2>/dev/null && echo alive || echo gone)" "gone"
check "A21: the timed-out run left the source unchanged too" "$(snap "$WT/src")" "$SRC_SNAP"
# a harness killed mid-run: the nested session had the run's own config
# directory, so the owner's settings.json is left byte for byte
CFG="$WT/repair-config"; mkdir -p "$CFG"; printf '{\n  "model": "opus",\n  "theme": "dark"\n}\n' > "$CFG/settings.json"
cp "$CFG/settings.json" "$WT/settings.orig"
wprep dforge 6
( WAB_CLAUDE_CONFIG="$CFG" MAXS=60 wlaunch dforge 6 ) &
LP=$!
for _ in $(seq 60); do [ -f "$WAB_ROOT/dforge-6/launcher.sh" ] && [ -f "$WT/tmux-wab-dforge-6.pid" ] && break; sleep 0.2; done
killtree() { local c; for c in $(pgrep -P "$1"); do killtree "$c"; done; kill -KILL "$1" 2>/dev/null; }
killtree "$LP"; wait "$LP" 2>/dev/null
p=$(cat "$WT/tmux-wab-dforge-6.pid" 2>/dev/null) && kill -KILL -- "-$p" 2>/dev/null
rm -f "$WT/tmux-wab-dforge-6.pid"
check "A21: the killed run's session was given the run's config directory, not the owner's" \
  "$(grep -c -F -- "CLAUDE_CONFIG_DIR=$WAB_ROOT/dforge-6/claude-config" "$WAB_ROOT/dforge-6/launcher.sh") $(grep -c -F -- "CLAUDE_CONFIG_DIR=$CFG" "$WAB_ROOT/dforge-6/launcher.sh")" "1 0"
check "A21: a harness killed mid-run leaves the owner's settings.json byte for byte" "$(cmp -s "$CFG/settings.json" "$WT/settings.orig" && echo same || echo differ)" "same"
fi

# --- A9, A10: the skill and instruction text, read independently of the cases above ---
SK=$(tr -d '\r' < "$P/skills/executing-plans/SKILL.md")
check "A9: a Lookups heading of any level lies within the first 15,000 characters" "$(head -c 15000 <<<"$SK" | grep -Ec '^#{1,6}[[:space:]]+Lookups[[:space:]]*$')" "1"
check "A9: the skill never claims the session already read the code" \
  "$(has "$(flat <<<"$SK")" 'has read the code')/$(has "$(flat <<<"$SK")" 'already read the code')" "no/no"
check "A9: the skill says an auto run starts in a cleared session" "$(has "$(flat <<<"$SK")" 'auto run starts in a cleared session')" "yes"
for src in "cockpit:$(tr -d '\r' < "$P/hooks/cockpit/register.tsx" | grep -A1 '^const AUTO_COMPACT_INSTRUCTIONS' | flat)" \
           "session-budget:$(tr -d '\r' < "$P/reference/session-budget.md" | awk '/^# Compact instructions$/ { f = 1; next } f && /^```/ { exit } f' | flat)"; do
  n=${src%%:*}; t=${src#*:}
  check "A10: the $n instructions cap the summary at 1,500 words" "$(has "$t" '1,500 words')" "yes"
  check "A10: the $n instructions keep rulings only for the task in flight and plan-wide ones" "$(has "$t" 'task in flight')/$(has "$t" 'plan-wide')" "yes/yes"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
