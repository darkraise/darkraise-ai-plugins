#!/usr/bin/env bash
# The dagents usage-report wrapper reads dagents' own stores only: the
# primary checkout's .dagents markers, never a .dforge marker file beside them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAP="$HERE/../../plugins/dagents/scripts/usage-report"
TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 HOME="$TMP/home"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# rows PLUGIN TASK — an open and a close row for TASK of the plan.
rows() {
  printf '2026-01-01T00:00:00Z\topen\t%s\t1.0.0\t/plugin\tdocs/dagents/plans/p.md\t%s\ts1\t\t0\t\ttask-brief:%s\t\t\n' "$1" "$2" "$2"
  printf '2026-01-01T00:01:00Z\tclose\t%s\t1.0.0\t/plugin\tdocs/dagents/plans/p.md\t%s\ts1\t\t3\t\ttask-close:%s\ta..b\t\n' "$1" "$2" "$2"
}

# --- wrapper_reads_own_stores ---
R="$TMP/repo"
git init -q "$R"
git -C "$R" config user.name Darkraise
git -C "$R" config user.email dark@example.invalid
mkdir -p "$R/docs/dagents/plans" "$R/.dagents/sdd" "$R/.dforge/sdd"
printf '# P\n\n### Task 1: one\n\nBody.\n\n### Task 2: two\n\nBody.\n' > "$R/docs/dagents/plans/p.md"
git -C "$R" add docs
git -C "$R" commit -q -m init
rows dagents 1 > "$R/.dagents/sdd/usage-markers.tsv"
rows dforge 2 > "$R/.dforge/sdd/usage-markers.tsv"
J=$(cd "$R" && bash "$WRAP" --format json 2>/dev/null)
check "wrapper_reads_own_stores: one plan" "$(jq -c '.plans | length' <<<"$J" 2>/dev/null | tr -d '\r')" "1"
check "wrapper_reads_own_stores: only the .dagents task" \
  "$(jq -c '[.plans[0].tasks[].tasks[]]' <<<"$J" 2>/dev/null | tr -d '\r')" "[1]"
# The rows' session s1 resolves to a transcript in the checkout's project directory.
# Named after the checkout as git reports it, as the wrapper names it: on
# Windows the long path, not TMP's 8.3 form.
PROJ="$HOME/.claude/projects/$(git -C "$R" rev-parse --show-toplevel | tr -d '\r\n' | tr -c 'A-Za-z0-9' '-')"
mkdir -p "$PROJ"
printf '{}\n' > "$PROJ/s1.jsonl"
J=$(cd "$R" && bash "$WRAP" --plan docs/dagents/plans/p.md --format json 2>/dev/null)
check "wrapper_reads_own_stores: --plan names the plan" "$(jq -c '[.plans[].completed]' <<<"$J" 2>/dev/null | tr -d '\r')" "[1]"

# --- summary_missing_reasons ---
nonode_path() { # PATH with no node: a directory holding it stood in for by links to its other programs
  local d f m out='' IFS=:
  for d in $PATH; do
    if [ -x "$d/node" ]; then
      m="$TMP/nonode/$(printf '%s' "$d" | tr -c 'A-Za-z0-9' '_')"
      mkdir -p "$m"
      for f in "$d"/*; do [ "${f##*/}" = node ] || ln -s "$f" "$m/" 2>/dev/null; done
      d=$m
    fi
    out=${out:+$out:}$d
  done
  printf '%s\n' "$out"
}
WM="$TMP/wm"
git init -q "$WM"
mkdir -p "$WM/docs/dagents/plans" "$WM/.dagents/sdd"
printf '# P\n\n### Task 1: one\n\nBody.\n' > "$WM/docs/dagents/plans/p.md"
SAVEDM="$WM/.dagents/sdd/usage-report-p.json"
wm() { (cd "$WM" && bash "$WRAP" "$@"); }
missing_case() { # missing_case NAME REASON [PATH] — --plan and --save each print only the reason, exit 0 and save nothing
  local out rc path=${3:-$PATH}
  out=$(PATH="$path" wm --plan docs/dagents/plans/p.md 2>"$TMP/merr"); rc=$?
  check "summary_missing_reasons: $1: exit 0 and nothing on stdout" "$rc:$out" "0:"
  check "summary_missing_reasons: $1: one stderr line" "$(cat "$TMP/merr")" "usage summary missing: $2"
  out=$(PATH="$path" wm --plan docs/dagents/plans/p.md --save 2>"$TMP/merr"); rc=$?
  check "summary_missing_reasons: $1: --save exits 0 with the same line" "$rc:$out:$(cat "$TMP/merr")" "0::usage summary missing: $2"
  check "summary_missing_reasons: $1: --save leaves no saved report" "$([ -e "$SAVEDM" ] && echo saved || echo none)" "none"
}
: > "$WM/.dagents/sdd/usage-markers.tsv"
missing_case "an empty marker file" "no markers"
printf '2026-01-01T00:00:00Z\topen\tdagents\t1.0.0\t/plugin\tdocs/dagents/plans/p.md\t1\ts9\t%s\t10\t\ttask-brief:1\t\t\n' "$TMP/gone/s9.jsonl" \
  > "$WM/.dagents/sdd/usage-markers.tsv"
missing_case "markers naming a transcript that does not exist" "no transcript"
missing_case "no node on PATH" "node not found" "$(nonode_path)"

# --- inferred_bounds: a quoted script path ---
B=$(cd "$HERE/../../plugins/dagents/scripts/lib" && node --input-type=module -e '
  import { inferBounds } from "./usage-report.mjs";
  const call = (c) => ({ type: "assistant", message: { content: [{ type: "tool_use", id: "t", name: "Bash", input: { command: c } }] } });
  const at = (list) => list.map((c, i) => ({ offset: i, entry: c ? call(c) : { type: "assistant", message: { content: [] } } }));
  console.log(JSON.stringify(inferBounds(at(["bash \"/p/scripts/task-brief\" --open docs/p.md 1", null,
    "bash \"/p/scripts/task-close\" docs/p.md 1 x", "bash \x27/p/scripts/task-step\x27 start docs/p.md 2"])).map((b) => [b.task, b.start, b.end])));' 2>&1)
check "inferred_bounds: a quoted script path" "$B" '[[1,0,3],[2,3,4]]'

# --- plan_files: the paths a task names ---
B=$(cd "$HERE/../../plugins/dagents/scripts/lib" && node --input-type=module -e '
  import { planFiles } from "./usage-report.mjs";
  const t = ["### Task 1: one", "", "**Files:**", "- Modify: `src/a.sh:10-20`", "- Test: `tests/a.test.sh`", "",
    "**Interfaces:** none", "", "**Files:**", "- Create: `src/b.sh`", "",
    "### Task 2: two", "", "**Files:**", "- Modify: `src/My View.tsx`", ""].join("\n");
  console.log(JSON.stringify(planFiles(t, 1)));
  console.log(JSON.stringify(planFiles(t, 2)));' 2>&1)
check "plan_files: every part's paths, without line ranges" "$(sed -n 1p <<<"$B")" '["src/a.sh","tests/a.test.sh","src/b.sh"]'
check "plan_files: a backticked path with a space is kept whole" "$(sed -n 2p <<<"$B")" '["src/My View.tsx"]'

# --- the report core, on fixtures built here: one assistant record per line ---
REPORT="$HERE/../../plugins/dagents/scripts/lib/usage-report.mjs"
if command -v cygpath >/dev/null 2>&1; then REPORT=$(cygpath -m "$REPORT"); fi
q() { jq -c "$2" <<<"$1" 2>/dev/null | tr -d '\r'; }
# say FILE ID TIME INPUT [MODEL] [BASH] — append a main-chain record, with a Bash call when BASH is given
say() {
  local content='[]'
  [ -z "${6:-}" ] || content=$(jq -nc --arg c "$6" '[{type: "tool_use", id: ("t-" + $c | gsub("[^A-Za-z0-9]"; "")), name: "Bash", input: {command: $c}}]')
  jq -nc --arg id "$2" --arg t "$3" --argjson n "$4" --arg m "${5:-claude-opus-5-5}" --argjson c "$content" \
    '{type: "assistant", isSidechain: false, timestamp: $t, message: {id: $id, model: $m, content: $c,
      usage: {input_tokens: $n, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, output_tokens: 0}}}' >> "$1"
}
at() { wc -c < "$1" | tr -d ' '; } # at FILE — the byte offset the next record starts at
mark() { # mark EVENT TIME PLAN TASK SESSION BYTES [RANGE]
  printf '%s\t%s\tdagents\t5.1.1\t/plugin\t%s\t%s\t%s\t\t%s\t1\ttask-%s:%s\t%s\t\n' "$2" "$1" "$3" "$4" "$5" "$6" "$1" "$4" "${7:-}"
}

# --- unmarked_ledger_line: a complete task no transcript bounds ---
UB="$TMP/ub"; mkdir -p "$UB/proj"
say "$UB/proj/u1.jsonl" u1 2026-01-01T00:00:01Z 5
{ mark open 2026-01-01T00:00:00Z docs/plans/p.md 1 u1 0; mark close 2026-01-01T00:00:02Z docs/plans/p.md 1 u1 "$(at "$UB/proj/u1.jsonl")" a..b; } > "$UB/markers.tsv"
printf '# SDD ledger — plan: docs/plans/p.md\nTask 1: complete (commits a..b, unreviewed) — x\nTask 2: complete (commits b..c, unreviewed) — y\n' > "$UB/progress.md"
J=$(node "$REPORT" --markers "$UB/markers.tsv" --transcripts "$UB/proj" --ledger "$UB/progress.md" --format json 2>/dev/null)
check "unmarked_ledger_line: a complete task no transcript bounds is unresolved" \
  "$(q "$J" '.plans[0] | [.completed, ([.tasks[] | [.tasks[0], .label]] | sort), (.excluded | map(select(test("no transcript bounds"))))]')" \
  '[1,[[1,"marked"],[2,"unresolved"]],["Task 2: no transcript bounds its slice"]]'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
