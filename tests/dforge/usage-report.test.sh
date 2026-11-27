#!/usr/bin/env bash
# usage-report.mjs slices transcripts at the task markers' byte offsets and
# prices each slice. Fixtures: tests/dforge/fixtures/usage/<case>/ (markers.tsv
# and a Claude project directory, proj/). Costs below are worked by hand from
# reference/api-prices.json: per Mtok, Opus 5.5 input 4, cache read 0.2,
# write 5m 5, write 1h 8, output 20; Sonnet 5.5 input 2, cache read 0.1,
# output 10.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# node.exe reads a Git Bash path such as /d/a/... as D:\d\a\..., and
# MSYS_NO_PATHCONV below stops Git Bash from converting it.
if command -v cygpath >/dev/null 2>&1; then HERE=$(cygpath -m "$HERE"); fi
REPORT="$HERE/../../plugins/dforge/scripts/lib/usage-report.mjs"
FX="$HERE/fixtures/usage"
export MSYS_NO_PATHCONV=1
TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export GIT_CONFIG_NOSYSTEM=1
# Its inferBounds inputs name the run-control scripts; none is run.
unset CLAUDE_CODE_SESSION_ID AR_SESSION

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
rep() { # rep CASE — the JSON report of one fixture
  node "$REPORT" --markers "$FX/$1/markers.tsv" --transcripts "$FX/$1/proj" --format json 2>/dev/null
}
q() { jq -c "$2" <<<"$1" 2>/dev/null | tr -d '\r'; }

# --- per_task_fields ---
J=$(rep basic)
T1='.plans[0].tasks[] | select(.tasks == [1])'
check "per_task_fields: task 1 usage" \
  "$(q "$J" "$T1 | [.turns, .input, .cacheRead, .cacheWrite5m, .cacheWrite1h, .output]")" "[2,15,5000,100,300,60]"
check "per_task_fields: task 1 models" "$(q "$J" "$T1 | .models")" '["claude-opus-5-5"]'
check "per_task_fields: task 1 context" "$(q "$J" "$T1 | [.contextOpen, .contextClose]")" "[1000,3305]"
check "per_task_fields: task 1 subagent" "$(q "$J" "$T1 | .subagents")" \
  '{"dforge:judge-opus":{"turns":1,"input":100,"cacheRead":0,"cacheWrite5m":0,"cacheWrite1h":0,"output":50,"cost":0.0007}}'
# 15*4 + 5000*0.2 + 100*5 + 300*8 + 60*20 = 5160, plus the subagent's 700.
check "per_task_fields: task 1 cost" "$(q "$J" "$T1 | .cost")" "0.00586"
check "per_task_fields: task 1 label, group and range" "$(q "$J" "$T1 | [.label, .group, .range]")" '["marked",false,"aaa..bbb"]'
check "per_task_fields: task 2 usage and cost" \
  "$(q "$J" '.plans[0].tasks[] | select(.tasks == [2]) | [.turns, .input, .cacheRead, .output, .cost]')" "[1,7,500,8,0.000144]"
# m0 comes before the first open (excluded); m4 after task 2 is outside: 2*4 + 3*20.
check "per_task_fields: outside the tasks" "$(q "$J" '.plans[0].outside | [.turns, .cost]')" "[1,0.000068]"
check "per_task_fields: cost per task, with and without outside" "$(q "$J" '.plans[0] | [.completed, .costPerTask, .costPerTaskSegments]')" "[2,0.003036,0.003002]"
check "per_task_fields: by model" "$(q "$J" '.plans[0].byModel | keys')" '["claude-opus-5-5","claude-sonnet-5-5"]'
check "per_task_fields: md has a row per task" \
  "$(node "$REPORT" --markers "$FX/basic/markers.tsv" --transcripts "$FX/basic/proj" | grep -c '^| [12] |')" "2"

# --- deferred_excluded, unpriced_model, open_after_close_ignored ---
J=$(rep misc)
check "deferred_excluded: not completed" "$(q "$J" '.plans[0] | [.completed, (.tasks | map(.tasks[]))]')" "[1,[7]]"
check "deferred_excluded: listed as excluded" "$(q "$J" '.plans[0].excluded')" '["Task 6: deferred by the auto run","before first open","finishing session"]'
check "deferred_excluded: not in the cost per task" "$(q "$J" '.plans[0] | .costPerTaskSegments == .tasks[0].cost')" "true"
# k4 and k5 after task 7 are outside (577*4); task 6's slice is neither.
check "deferred_excluded: its slice is not outside" "$(q "$J" '.plans[0].outside | [.turns, .cost]')" "[2,0.002308]"
check "unpriced_model: listed and priced at 0" "$(q "$J" '.plans[0].tasks[0] | [.unpriced, .cost, .turns]')" '[["claude-unknown-9"],0.00004,2]'
check "open_after_close_ignored: the task keeps its slice" "$(q "$J" '.plans[0].tasks[0] | [.input, .contextOpen]')" "[1010,3]"
check "open_after_close_ignored: an open with no close is unclosed" "$(q "$J" '.plans[0].unclosed')" "1"

# --- task_across_sessions ---
J=$(rep sessions)
check "task_across_sessions: the tail of A plus B's segment" \
  "$(q "$J" '.plans[0].tasks[0] | [.tasks, .turns, .input]')" "[[3],3,7]"

# --- overlapping_group ---
J=$(rep group)
check "overlapping_group: one row for both tasks" "$(q "$J" '.plans[0].tasks | length')" "1"
check "overlapping_group: tasks, group and the union once" \
  "$(q "$J" '.plans[0].tasks[0] | [.tasks, .group, .turns, .input]')" "[[4,5],true,3,7]"
check "overlapping_group: both tasks completed" "$(q "$J" '.plans[0].completed')" "2"

# --- lookups_and_files_share ---
J=$(node "$REPORT" --markers "$FX/lookups/markers.tsv" --transcripts "$FX/lookups/proj" --plan "$FX/lookups/p.md" --format json 2>/dev/null)
# Two whole reads of a.sh, rg on b.sh, sed -n on c.sh; git status is no lookup.
# Read results of 400 and 200 characters are 100 + 50 tokens at 4 per token.
check "lookups_and_files_share: lookups, repeats, share and read tokens" \
  "$(q "$J" '.plans[0].tasks[0] | [.lookups, .repeatReads, .filesLookupShare, .readTokens]')" "[4,1,0.75,150]"

# --- compaction_fields ---
J=$(rep compaction)
check "compaction_fields: task 2's compaction" "$(q "$J" '.plans[0].tasks[] | select(.tasks == [2]) | .compactions')" \
  '[{"durationMs":117000,"postTokens":32000,"nextContext":40000}]'
check "compaction_fields: the first task after it counts its lookups" \
  "$(q "$J" '.plans[0].tasks | map(.lookupsAfterCompaction)')" "[null,2]"

# --- growth_and_outside ---
J=$(rep growth)
check "growth_and_outside: growth sums the rises" "$(q "$J" '.plans[0].tasks[] | select(.tasks == [1]) | .growth')" "40000"
# Task 1: 420000 cache read * 0.2; task 2: 10 * 4; outside (between tasks): 1000 * 4.
check "growth_and_outside: the usage between tasks is outside" "$(q "$J" '.plans[0].outside | [.turns, .input]')" "[1,1000]"
check "growth_and_outside: both cost figures" "$(q "$J" '.plans[0] | [.costPerTask, .costPerTaskSegments]')" "[0.04402,0.04202]"
check "growth_and_outside: the usage before the first open is excluded" "$(q "$J" '.plans[0].excluded')" '["before first open","finishing session"]'

# --- splits_and_all_plans ---
J=$(node "$REPORT" --markers "$FX/splits/repo/state/sdd/usage-markers.tsv" --transcripts "$FX/splits/proj" --format json 2>/dev/null)
check "splits_and_all_plans: both plans" "$(q "$J" '[.plans[].plan]')" '["docs/plans/p.md","docs/plans/q.md"]'
check "splits_and_all_plans: by model" "$(q "$J" '.plans[0].byModel | map_values([.input, .cost])')" \
  '{"claude-opus-5-5":[10,0.00004],"claude-sonnet-5-5":[20,0.00004]}'
check "splits_and_all_plans: by repository" "$(q "$J" '.plans[0].byRepo | to_entries | map([(.key | gsub("\\\\"; "/") | sub(".*/fixtures/"; "")), .value.input, .value.cost])')" \
  '[["usage/splits/repo",30,0.00008]]'

# --- wait_seconds ---
J=$(rep wait)
check "wait_seconds: from the background call to its notification" "$(q "$J" '.plans[0].tasks[0].waitSeconds')" "90"

# --- dispatches_from_transcript ---
J=$(rep dispatch)
check "dispatches_from_transcript: families and agent types" "$(q "$J" '.plans[0].tasks[0].dispatches')" \
  '{"codex-task":1,"review-panel":1,"api-judge":1,"dforge:judge-sonnet-high":2}'
check "dispatches_from_transcript: fix rounds from rereview calls" "$(q "$J" '.plans[0].tasks[0].fixRounds')" "2"

# --- ledger_gone: the close rows alone carry each task's range ---
J=$(rep misc)
check "ledger_gone: closed tasks with their ranges, the deferred one excluded" \
  "$(q "$J" '[[.plans[0].tasks[] | [.tasks[0], .range]], (.plans[0].excluded | map(select(test("deferred"))))]')" \
  '[[[7,"h..i"]],["Task 6: deferred by the auto run"]]'

# --- unmarked_ledger_line ---
J=$(node "$REPORT" --markers "$FX/unmarked/markers.tsv" --transcripts "$FX/unmarked/proj" --ledger "$FX/unmarked/progress.md" --format json 2>/dev/null)
check "unmarked_ledger_line: a row from the inferred bounds" \
  "$(q "$J" '.plans[0].tasks[] | select(.tasks == [6]) | [.label, .range, .input]')" '["unmarked","c..d",30]'
check "unmarked_ledger_line: counted" "$(q "$J" '.plans[0].unmarked')" "1"
B=$(cd "$HERE/../../plugins/dforge/scripts/lib" && node --input-type=module -e '
  import { inferBounds } from "./usage-report.mjs";
  const e = { type: "assistant", message: { content: [{ type: "tool_use", id: "t", name: "Bash",
    input: { command: "P=docs/p.md; bash task-step start \"$P\" 2 3" } }] } };
  console.log(JSON.stringify(inferBounds([{ offset: 0, entry: e }]).map((b) => [b.plan, b.task])));' 2>&1)
check "unmarked_ledger_line: a batch start with a variable" "$B" '[["docs/p.md",2],["docs/p.md",3]]'

# --- quality_pairing ---
QR="$TMP/qrepo"
git init -q "$QR"
qc() { # qc DATE SUBJECT FILE
  printf '%s\n' "$2" >> "$QR/$3"
  git -C "$QR" add -A
  GIT_AUTHOR_DATE=$1 GIT_COMMITTER_DATE=$1 git -C "$QR" -c user.name=t -c user.email=t@example.invalid commit -q -m "$2"
}
qc 2025-12-31T00:00:00Z "feat: base" a.sh
QA=$(git -C "$QR" rev-parse --short HEAD)
qc 2026-01-02T00:00:00Z "fix(x): inside the task range" a.sh
QB=$(git -C "$QR" rev-parse --short HEAD)
qc 2026-01-02T12:00:00Z "feat: not a fix" a.sh
qc 2026-01-03T00:00:00Z "fix(y): after the finish" a.sh
qc 2026-01-03T01:00:00Z "fix: another file" z.sh
qc 2026-01-20T00:00:00Z "fix: too late" a.sh
printf '2026-01-01T00:00:00Z\topen\tdforge\t5.1.1\t/plugin\tdocs/plans/p.md\t1\tq1\t\t0\t1\ttask-brief:1\t\t\n2026-01-01T00:10:00Z\tclose\tdforge\t5.1.1\t/plugin\tdocs/plans/p.md\t1\tq1\t\t\t2\ttask-close:1\t%s..%s\t\n' "$QA" "$QB" > "$TMP/q-markers.tsv"
J=$(node "$REPORT" --markers "$TMP/q-markers.tsv" --transcripts "$FX/quality/proj" --plan "$FX/quality/plans/p.md" \
  --review-record "$FX/quality/record.md" --register "$FX/quality/reg.md" --repo "$QR" --format json 2>/dev/null)
check "quality_pairing: the plan's quality" "$(q "$J" '.plans[0].quality')" \
  '{"findings":{"Critical":1,"Important":2},"fixRounds":0,"breakerItems":0,"deferredRows":2,"followUpTasks":3,"fixCommits":1}'

# --- archive_inferred ---
# Two sessions with no markers: alpha opens with task-brief and closes with
# task-close; beta starts tasks 1 and 2 in one task-step call through $P.
J=$(node "$REPORT" --from-archive "$FX/archive" --format json 2>/dev/null)
check "archive_inferred: both manifest plans" "$(q "$J" '[.plans[].plan] | sort')" '["2026-11-01-alpha.md","2026-11-02-beta.md"]'
check "archive_inferred: every task inferred" "$(q "$J" '[.plans[].tasks[].label] | unique')" '["inferred"]'
A='.plans[] | select(.plan == "2026-11-01-alpha.md")'
check "archive_inferred: alpha's tasks and turns" "$(q "$J" "[$A | .tasks[] | [.tasks, .turns]]")" '[[[1],3],[[2],3]]'
check "archive_inferred: alpha's repository from the manifest" "$(q "$J" "$A | [.completed, (.byRepo | keys)]")" '[2,["/root/repositories/x"]]'
check "archive_inferred: beta's batch start is one group" \
  "$(q "$J" '[.plans[] | select(.plan == "2026-11-02-beta.md") | .tasks[] | [.tasks, .group, .turns]]')" '[[[1,2],true,4]]'

# --- wrapper_resolves_stores ---
# A checkout whose plan names a spec a register covers, with the basic
# fixture's markers and transcript in dforge's own stores.
WRAP="$HERE/../../plugins/dforge/scripts/usage-report"
WT=$TMP
if command -v cygpath >/dev/null 2>&1; then WT=$(cygpath -m "$TMP"); fi
wrap() { # wrap DIR ARGS… — the wrapper run in DIR with an isolated home
  local dir=$1; shift
  (cd "$dir" && env -u CLAUDE_CONFIG_DIR -u CLAUDE_CODE_SESSION_ID -u AR_SESSION HOME="$WT/home" \
    bash "$WRAP" "$@")
}
WR="$WT/wr"
git init -q "$WR"
git -C "$WR" config user.name Darkraise
git -C "$WR" config user.email dark@example.invalid
mkdir -p "$WR/docs/dforge/plans" "$WR/docs/dforge/specs" "$WR/docs/dforge/registers" "$WR/docs/dforge/reviews"
printf '# P\n\n**Spec:** `docs/dforge/specs/s.md`\n\n### Task 1: one\n\nBody.\n\n### Task 2: two\n\nBody.\n' > "$WR/docs/dforge/plans/p.md"
printf '# S\n' > "$WR/docs/dforge/specs/s.md"
printf '# Register\n\n**Covers:** `docs/dforge/specs/s.md`\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | a | - | - | done | |\n| 2 | b | - | - | deferred | later |\n' \
  > "$WR/docs/dforge/registers/r.md"
printf '# Review record: p\n\n- [Important] one\n' > "$WR/docs/dforge/reviews/p.md"
git -C "$WR" add docs
git -C "$WR" commit -q -m init
mkdir -p "$WR/.dforge/sdd/p"
awk -F'\t' 'BEGIN { OFS = "\t" } { $6 = "docs/dforge/plans/p.md"; print }' "$FX/basic/markers.tsv" > "$WR/.dforge/sdd/usage-markers.tsv"
printf '# SDD ledger — plan: docs/dforge/plans/p.md\nTask 2: fix round 3/3 (x; commits a..b; still failing)\n' > "$WR/.dforge/sdd/p/progress.md"
# Named after the checkout as git reports it, as the wrapper names it: on
# Windows the long path, not TMP's 8.3 form.
PROJ="$WT/home/.claude/projects/$(git -C "$WR" rev-parse --show-toplevel | tr -d '\r\n' | tr -c 'A-Za-z0-9' '-')"
mkdir -p "$PROJ"
cp -R "$FX/basic/proj/." "$PROJ/"
J=$(wrap "$WR" --plan docs/dforge/plans/p.md --format json 2>/dev/null)
check "wrapper_resolves_stores: markers and transcripts" "$(q "$J" '.plans[0] | [.completed, .tasks[0].turns]')" "[2,2]"
check "wrapper_resolves_stores: register, review record and workspace" "$(q "$J" '.plans[0].quality')" \
  '{"findings":{"Important":1},"fixRounds":0,"breakerItems":1,"deferredRows":1,"followUpTasks":0,"fixCommits":0}'

# --- saved_report_reused ---
git -C "$WR" worktree add -q "$WT/wrw" -b wrw
OUT=$(wrap "$WT/wrw" --plan docs/dforge/plans/p.md --save 2>/dev/null)
check "saved_report_reused: --save exits 0" "$?" "0"
check "saved_report_reused: --save prints nothing" "$OUT" ""
SAVED="$WR/.dforge/sdd/usage-report-p.json"
check "saved_report_reused: the saved report is the json report" \
  "$(cat "$SAVED" 2>/dev/null)" "$(wrap "$WT/wrw" --plan docs/dforge/plans/p.md --format json 2>/dev/null)"
rm -rf "$WR/.dforge/sdd/p"
J=$(wrap "$WT/wrw" --plan docs/dforge/plans/p.md --format json 2>/dev/null)
check "saved_report_reused: quality as of finishing" "$(q "$J" '.plans[0] | [.quality, .asOf]')" \
  "$(jq -c '.plans[0] | [.quality, "finishing"]' "$SAVED" 2>/dev/null | tr -d '\r')"
check "saved_report_reused: the saved quality kept the breaker item" "$(q "$J" '.plans[0].quality.breakerItems')" "1"
wrap "$WR" --save >/dev/null 2>&1
check "saved_report_reused: --save without --plan exits 2" "$?" "2"

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
mkdir -p "$WM/docs/dforge/plans" "$WM/.dforge/sdd"
printf '# P\n\n### Task 1: one\n\nBody.\n' > "$WM/docs/dforge/plans/p.md"
SAVEDM="$WM/.dforge/sdd/usage-report-p.json"
missing_case() { # missing_case NAME REASON [PATH] — --plan and --save each print only the reason, exit 0 and save nothing
  local out rc path=${3:-$PATH}
  out=$(PATH="$path" wrap "$WM" --plan docs/dforge/plans/p.md 2>"$TMP/merr"); rc=$?
  check "summary_missing_reasons: $1: exit 0 and nothing on stdout" "$rc:$out" "0:"
  check "summary_missing_reasons: $1: one stderr line" "$(cat "$TMP/merr")" "usage summary missing: $2"
  out=$(PATH="$path" wrap "$WM" --plan docs/dforge/plans/p.md --save 2>"$TMP/merr"); rc=$?
  check "summary_missing_reasons: $1: --save exits 0 with the same line" "$rc:$out:$(cat "$TMP/merr")" "0::usage summary missing: $2"
  check "summary_missing_reasons: $1: --save leaves no saved report" "$([ -e "$SAVEDM" ] && echo saved || echo none)" "none"
}
: > "$WM/.dforge/sdd/usage-markers.tsv"
missing_case "an empty marker file" "no markers"
printf '2026-01-01T00:00:00Z\topen\tdforge\t1.0.0\t/plugin\tdocs/dforge/plans/p.md\t1\ts9\t%s\t10\t\ttask-brief:1\t\t\n' "$TMP/gone/s9.jsonl" \
  > "$WM/.dforge/sdd/usage-markers.tsv"
missing_case "markers naming a transcript that does not exist" "no transcript"
missing_case "no node on PATH" "node not found" "$(nonode_path)"

# --- fixtures built here: one assistant record per line ---
# say FILE ID TIME INPUT [MODEL] [BASH] — append a main-chain record, with a Bash call when BASH is given
say() {
  local content='[]'
  [ -z "${6:-}" ] || content=$(jq -nc --arg c "$6" '[{type: "tool_use", id: ("t-" + $c | gsub("[^A-Za-z0-9]"; "")), name: "Bash", input: {command: $c}}]')
  jq -nc --arg id "$2" --arg t "$3" --argjson n "$4" --arg m "${5:-claude-opus-5-5}" --argjson c "$content" \
    '{type: "assistant", isSidechain: false, timestamp: $t, message: {id: $id, model: $m, content: $c,
      usage: {input_tokens: $n, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, output_tokens: 0}}}' >> "$1"
}
at() { wc -c < "$1" | tr -d ' '; } # at FILE — the byte offset the next record starts at
mark() { # mark EVENT TIME PLAN TASK SESSION BYTES [RANGE] [DEFERRED]
  printf '%s\t%s\tdforge\t5.1.1\t/plugin\t%s\t%s\t%s\t\t%s\t1\ttask-%s:%s\t%s\t%s\n' "$2" "$1" "$3" "$4" "$5" "$6" "$1" "$4" "${7:-}" "${8:-}"
}

# --- inferred_open_only: open rows, no close, a ledger complete line ---
IO="$TMP/io"; mkdir -p "$IO/proj"
say "$IO/proj/i1.jsonl" i1 2026-01-01T00:00:01Z 0 "" 'bash task-brief --open docs/plans/p.md 1'
say "$IO/proj/i1.jsonl" i2 2026-01-01T00:00:02Z 30
mark open 2026-01-01T00:00:01Z docs/plans/p.md 1 i1 0 > "$IO/markers.tsv"
printf '# SDD ledger — plan: docs/plans/p.md\nTask 1: complete (commits a..b, unreviewed) — x\n' > "$IO/progress.md"
J=$(node "$REPORT" --markers "$IO/markers.tsv" --transcripts "$IO/proj" --ledger "$IO/progress.md" --format json 2>/dev/null)
check "inferred_open_only: measured by inference" "$(q "$J" '.plans[0].tasks | map([.tasks, .label, .range, .input])')" '[[[1],"inferred","a..b",30]]'
check "inferred_open_only: completed, not unclosed or unmarked" "$(q "$J" '.plans[0] | [.completed, .unclosed, .unmarked]')" "[1,0,0]"

# --- plain_brief_after_open: a plain task-brief re-reads; alone it opens ---
B=$(cd "$HERE/../../plugins/dforge/scripts/lib" && node --input-type=module -e '
  import { inferBounds } from "./usage-report.mjs";
  const call = (c) => ({ type: "assistant", message: { content: [{ type: "tool_use", id: c, name: "Bash", input: { command: c } }] } });
  const at = (list) => list.map((c, i) => ({ offset: i, entry: c ? call(c) : { type: "assistant", message: { content: [] } } }));
  const one = inferBounds(at(["bash task-brief --open docs/p.md 1", null, "bash task-brief docs/p.md 1", null, "bash task-close docs/p.md 1 x"]));
  const two = inferBounds(at(["bash task-brief docs/p.md 2", null, "bash task-close docs/p.md 2 x"]));
  console.log(JSON.stringify([...one, ...two].map((b) => [b.task, b.start, b.end])));' 2>&1)
check "plain_brief_after_open: one slice per task" "$B" '[[1,0,5],[2,0,3]]'

# --- inferred_bounds: a quoted script path ---
B=$(cd "$HERE/../../plugins/dforge/scripts/lib" && node --input-type=module -e '
  import { inferBounds } from "./usage-report.mjs";
  const call = (c) => ({ type: "assistant", message: { content: [{ type: "tool_use", id: "t", name: "Bash", input: { command: c } }] } });
  const at = (list) => list.map((c, i) => ({ offset: i, entry: c ? call(c) : { type: "assistant", message: { content: [] } } }));
  console.log(JSON.stringify(inferBounds(at(["bash \"/p/scripts/task-brief\" --open docs/p.md 1", null,
    "bash \"/p/scripts/task-close\" docs/p.md 1 x", "bash \x27/p/scripts/task-step\x27 start docs/p.md 2"])).map((b) => [b.task, b.start, b.end])));' 2>&1)
check "inferred_bounds: a quoted script path" "$B" '[[1,0,3],[2,3,4]]'

# --- plan_files: the paths a task names ---
B=$(cd "$HERE/../../plugins/dforge/scripts/lib" && node --input-type=module -e '
  import { planFiles } from "./usage-report.mjs";
  const t = ["### Task 1: one", "", "**Files:**", "- Modify: `src/a.sh:10-20`", "- Test: `tests/a.test.sh`", "",
    "**Interfaces:** none", "", "**Files:**", "- Create: `src/b.sh`", "",
    "### Task 2: two", "", "**Files:**", "- Modify: `src/My View.tsx`", ""].join("\n");
  console.log(JSON.stringify(planFiles(t, 1)));
  console.log(JSON.stringify(planFiles(t, 2)));' 2>&1)
check "plan_files: every part's paths, without line ranges" "$(sed -n 1p <<<"$B")" '["src/a.sh","tests/a.test.sh","src/b.sh"]'
check "plan_files: a backticked path with a space is kept whole" "$(sed -n 2p <<<"$B")" '["src/My View.tsx"]'

# --- unmarked_ledger_line: a complete task no transcript bounds ---
UB="$TMP/ub"; mkdir -p "$UB/proj"
say "$UB/proj/u1.jsonl" u1 2026-01-01T00:00:01Z 5
{ mark open 2026-01-01T00:00:00Z docs/plans/p.md 1 u1 0; mark close 2026-01-01T00:00:02Z docs/plans/p.md 1 u1 "$(at "$UB/proj/u1.jsonl")" a..b; } > "$UB/markers.tsv"
printf '# SDD ledger — plan: docs/plans/p.md\nTask 1: complete (commits a..b, unreviewed) — x\nTask 2: complete (commits b..c, unreviewed) — y\n' > "$UB/progress.md"
J=$(node "$REPORT" --markers "$UB/markers.tsv" --transcripts "$UB/proj" --ledger "$UB/progress.md" --format json 2>/dev/null)
check "unmarked_ledger_line: a complete task no transcript bounds is unresolved" \
  "$(q "$J" '.plans[0] | [.completed, ([.tasks[] | [.tasks[0], .label]] | sort), (.excluded | map(select(test("no transcript bounds"))))]')" \
  '[1,[[1,"marked"],[2,"unresolved"]],["Task 2: no transcript bounds its slice"]]'

# --- quality_pairing: breaker items from the ledger, not the workspace ---
mkdir -p "$UB/ledger" "$UB/ws"
printf 'Task 1: fix round 3/3 (x; commits a..b; still failing)\n' > "$UB/ledger/progress.md"
J=$(node "$REPORT" --markers "$UB/markers.tsv" --transcripts "$UB/proj" --ledger "$UB/ledger/progress.md" --workspace "$UB/ws" --format json 2>/dev/null)
check "quality_pairing: breaker items from the ledger" "$(q "$J" '.plans[0].quality.breakerItems')" "1"

# --- wait_matches_job: a launch with no job id is not credited with another job's end ---
WJ="$TMP/wj"; mkdir -p "$WJ/proj"
jq -nc '{type: "assistant", isSidechain: false, timestamp: "2026-01-01T00:00:10Z", message: {id: "j1", model: "claude-opus-5-5",
  content: [{type: "tool_use", id: "b1", name: "Bash", input: {command: "sleep 1", run_in_background: true}}], usage: {input_tokens: 1, output_tokens: 0}}}' >> "$WJ/proj/j1.jsonl"
jq -nc '{type: "user", isSidechain: false, timestamp: "2026-01-01T00:00:11Z", message: {role: "user", content: [{type: "tool_result", tool_use_id: "b1", content: "Started."}]}}' >> "$WJ/proj/j1.jsonl"
jq -nc '{type: "assistant", isSidechain: false, timestamp: "2026-01-01T00:00:40Z", message: {id: "j2", model: "claude-opus-5-5",
  content: [{type: "tool_use", id: "b2", name: "Bash", input: {command: "sleep 60", run_in_background: true}}], usage: {input_tokens: 1, output_tokens: 0}}}' >> "$WJ/proj/j1.jsonl"
jq -nc '{type: "user", isSidechain: false, timestamp: "2026-01-01T00:00:41Z", message: {role: "user", content: [{type: "tool_result", tool_use_id: "b2", content: "Command running in background with ID: bg2."}]}}' >> "$WJ/proj/j1.jsonl"
jq -nc '{type: "user", isSidechain: false, timestamp: "2026-01-01T00:01:40Z", message: {role: "user", content: "<task-notification><task-id>bg2</task-id><status>completed</status></task-notification>"}}' >> "$WJ/proj/j1.jsonl"
{ mark open 2026-01-01T00:00:00Z docs/plans/p.md 1 j1 0; mark close 2026-01-01T00:02:00Z docs/plans/p.md 1 j1 "$(at "$WJ/proj/j1.jsonl")" a..b; } > "$WJ/markers.tsv"
J=$(node "$REPORT" --markers "$WJ/markers.tsv" --transcripts "$WJ/proj" --format json 2>/dev/null)
check "wait_matches_job: bg2's wait from its own launch" "$(q "$J" '.plans[0].tasks[0].waitSeconds')" "60"

# --- outside_subagents: before the first open, inside another plan's slice, after both ---
OS="$TMP/os"; f="$OS/proj/o1.jsonl"; mkdir -p "$OS/proj/o1/subagents"
say "$f" o1 2026-01-01T00:00:01Z 1
p0=$(at "$f"); say "$f" o2 2026-01-01T00:00:10Z 10; p1=$(at "$f")
say "$f" o3 2026-01-01T00:00:20Z 100; q1=$(at "$f")
say "$f" o4 2026-01-01T00:00:30Z 1000
sub() { # sub NAME TIME INPUT MODEL
  printf '{"agentType": "x:%s"}\n' "$1" > "$OS/proj/o1/subagents/agent-$1.meta.json"
  jq -nc --arg t "$2" --argjson n "$3" --arg m "$4" --arg id "s-$1" '{type: "assistant", isSidechain: true, timestamp: $t,
    message: {id: $id, model: $m, usage: {input_tokens: $n, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, output_tokens: 0}}}' \
    > "$OS/proj/o1/subagents/agent-$1.jsonl"
}
sub early 2026-01-01T00:00:02Z 7 claude-opus-5-5
sub other 2026-01-01T00:00:21Z 70 claude-opus-5-5
sub late 2026-01-01T00:00:31Z 700 claude-sonnet-5-5
{
  mark open 2026-01-01T00:00:05Z docs/plans/p.md 1 o1 "$p0"
  mark close 2026-01-01T00:00:15Z docs/plans/p.md 1 o1 "$p1" a..b
  mark open 2026-01-01T00:00:18Z docs/plans/q.md 1 o1 "$p1"
  mark close 2026-01-01T00:00:25Z docs/plans/q.md 1 o1 "$q1" c..d
} > "$OS/markers.tsv"
J=$(node "$REPORT" --markers "$OS/markers.tsv" --transcripts "$OS/proj" --plan docs/plans/p.md --format json 2>/dev/null)
check "outside_subagents: only the late subagent and the main record after both plans" "$(q "$J" '.plans[0].outside | [.turns, .input]')" "[2,1700]"
check "outside_subagents: the early one is before the first open" "$(q "$J" '.plans[0].excluded | index("before first open") != null')" "true"
check "outside_subagents: the late one counts in by model" "$(q "$J" '.plans[0].byModel["claude-sonnet-5-5"].input')" "700"

# --- unresolved_tasks: no transcript, or a mark with no byte offset ---
UR="$TMP/ur"; mkdir -p "$UR/proj"
say "$UR/proj/r1.jsonl" r1 2026-01-01T00:00:01Z 5
{
  mark open 2026-01-01T00:00:00Z docs/plans/p.md 1 gone 0; mark close 2026-01-01T00:00:01Z docs/plans/p.md 1 gone 10 a..b
  mark open 2026-01-01T00:00:00Z docs/plans/p.md 2 r1 ""; mark close 2026-01-01T00:00:02Z docs/plans/p.md 2 r1 "$(at "$UR/proj/r1.jsonl")" b..c
  mark open 2026-01-01T00:00:00Z docs/plans/p.md 3 r1 0; mark close 2026-01-01T00:00:03Z docs/plans/p.md 3 r1 "$(at "$UR/proj/r1.jsonl")" c..d
} > "$UR/markers.tsv"
J=$(node "$REPORT" --markers "$UR/markers.tsv" --transcripts "$UR/proj" --format json 2>/dev/null)
check "unresolved_tasks: labelled unresolved, the bounded one marked" "$(q "$J" '[.plans[0].tasks[] | [.tasks[0], .label]] | sort')" '[[1,"unresolved"],[2,"unresolved"],[3,"marked"]]'
check "unresolved_tasks: only the bounded task is completed" "$(q "$J" '.plans[0].completed')" "1"
check "unresolved_tasks: each listed as excluded" "$(q "$J" '[.plans[0].excluded[] | select(test("no transcript bounds"))]')" \
  '["Task 1: no transcript bounds its slice","Task 2: no transcript bounds its slice"]'

# --- quality_unknowns: a gone range, no repository, no record ---
qrun() { # qrun RANGE REPO RECORD — the plan's quality
  printf '2026-01-01T00:00:00Z\topen\tdforge\t5.1.1\t/plugin\tdocs/plans/p.md\t1\tq1\t\t0\t1\ttask-brief:1\t\t\n2026-01-01T00:10:00Z\tclose\tdforge\t5.1.1\t/plugin\tdocs/plans/p.md\t1\tq1\t\t\t2\ttask-close:1\t%s\t\n' "$1" > "$TMP/q2-markers.tsv"
  node "$REPORT" --markers "$TMP/q2-markers.tsv" --transcripts "$FX/quality/proj" --plan "$FX/quality/plans/p.md" \
    --review-record "$3" --register "$FX/quality/reg.md" --repo "$2" --format json 2>/dev/null | jq -c '.plans[0].quality | [.findings, .fixCommits]'
}
check "quality_unknowns: a range whose commits are gone still counts later fixes" "$(qrun deadbee..cafebab "$QR" "$FX/quality/record.md")" '[{"Critical":1,"Important":2},2]'
mkdir -p "$TMP/notrepo"
check "quality_unknowns: no repository is unknown, not zero" "$(qrun "$QA..$QB" "$TMP/notrepo" "$FX/quality/record.md")" '[{"Critical":1,"Important":2},null]'
check "quality_unknowns: an unreadable record is unknown, not zero" "$(qrun "$QA..$QB" "$QR" "$TMP/absent.md")" '[null,1]'
check "quality_unknowns: one unreadable repository of several leaves the count unknown" \
  "$(node "$REPORT" --markers "$TMP/q2-markers.tsv" --transcripts "$FX/quality/proj" --plan "$FX/quality/plans/p.md" \
    --review-record "$FX/quality/record.md" --register "$FX/quality/reg.md" --repo "$TMP/notrepo" --repo "$QR" --format json 2>/dev/null \
    | jq -c '.plans[0].quality | [.findings, .fixCommits]')" '[{"Critical":1,"Important":2},null]'

# --- quality_pairing: a register name inside a longer one ---
FD="$TMP/fu"; mkdir -p "$FD/plans" "$FD/reg" "$FD/proj"
say "$FD/proj/f1.jsonl" f1 2026-01-01T00:00:01Z 5
{ mark open 2026-01-01T00:00:00Z docs/plans/p.md 1 f1 0; mark close 2026-01-01T00:00:02Z docs/plans/p.md 1 f1 "$(at "$FD/proj/f1.jsonl")" a..b; } > "$FD/markers.tsv"
printf '# P\n\n### Task 1: one\n' > "$FD/plans/p.md"
printf '# Next\n\n**Items:** milestone-10 2, 3\n\n### Task 1: a\n\n### Task 2: b\n\n### Task 3: c\n' > "$FD/plans/next.md"
printf '# Register\n' > "$FD/reg/milestone-1.md"
J=$(node "$REPORT" --markers "$FD/markers.tsv" --transcripts "$FD/proj" --plan "$FD/plans/p.md" --register "$FD/reg/milestone-1.md" --format json 2>/dev/null)
check "quality_pairing: a register name inside a longer one is not its follow-up" "$(q "$J" '.plans[0].quality.followUpTasks')" "0"

# --- quality_pairing: a fix commit to a non-ASCII path ---
NR="$TMP/nrepo"; git init -q "$NR"; mkdir -p "$TMP/nplan"
nc() { # nc DATE SUBJECT
  printf '%s\n' "$2" >> "$NR/é.sh"
  git -C "$NR" add -A
  GIT_AUTHOR_DATE=$1 GIT_COMMITTER_DATE=$1 git -C "$NR" -c user.name=t -c user.email=t@example.invalid commit -q -m "$2"
}
nc 2025-12-31T00:00:00Z "feat: base"
nc 2026-01-02T00:00:00Z "fix: é"
printf '# P\n\n### Task 1: one\n\n**Files:**\n- Modify: `é.sh`\n' > "$TMP/nplan/p.md"
J=$(node "$REPORT" --markers "$FD/markers.tsv" --transcripts "$FD/proj" --plan "$TMP/nplan/p.md" --repo "$NR" --format json 2>/dev/null)
check "quality_pairing: a fix commit to a non-ASCII path counts" "$(q "$J" '.plans[0].quality.fixCommits')" "1"

# --- streamed_once: a message whose records a close splits ---
SO="$TMP/so"; mkdir -p "$SO/proj"; f="$SO/proj/s1.jsonl"
rec() { # rec FILE TIME OUTPUT — one record of message m1
  jq -nc --arg t "$2" --argjson o "$3" '{type: "assistant", isSidechain: false, timestamp: $t, message: {id: "m1",
    model: "claude-opus-5-5", content: [], usage: {input_tokens: 0, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, output_tokens: $o}}}' >> "$1"
}
rec "$f" 2026-01-01T00:00:01Z 5; c=$(at "$f"); rec "$f" 2026-01-01T00:00:03Z 50
{ mark open 2026-01-01T00:00:00Z docs/plans/p.md 1 s1 0; mark close 2026-01-01T00:00:02Z docs/plans/p.md 1 s1 "$c" a..b; } > "$SO/markers.tsv"
J=$(node "$REPORT" --markers "$SO/markers.tsv" --transcripts "$SO/proj" --format json 2>/dev/null)
check "streamed_once: a message split by a close is counted once" "$(q "$J" '[(.plans[0].tasks[0] | .turns, .output), .plans[0].outside.turns]')" "[1,50,0]"

# --- outside_unpriced: an unpriced model after the last close ---
OU="$TMP/ou"; mkdir -p "$OU/proj"; f="$OU/proj/u1.jsonl"
say "$f" u1 2026-01-01T00:00:01Z 5; c=$(at "$f"); say "$f" u2 2026-01-01T00:00:03Z 7 claude-unknown-9
{ mark open 2026-01-01T00:00:00Z docs/plans/p.md 1 u1 0; mark close 2026-01-01T00:00:02Z docs/plans/p.md 1 u1 "$c" a..b; } > "$OU/markers.tsv"
J=$(node "$REPORT" --markers "$OU/markers.tsv" --transcripts "$OU/proj" --format json 2>/dev/null)
MD=$(node "$REPORT" --markers "$OU/markers.tsv" --transcripts "$OU/proj" 2>/dev/null | tr -d '\r')
check "outside_unpriced: listed in the json and the markdown" \
  "$(q "$J" '.plans[0].outside.unpriced')|$(grep -cF 'outside tasks: $0.00 (unpriced: claude-unknown-9)' <<<"$MD")" '["claude-unknown-9"]|1'

# --- outside_subagents: one inside a deferred task's slice ---
DS="$TMP/ds"; f="$DS/proj/d1.jsonl"; mkdir -p "$DS/proj/d1/subagents"
say "$f" d1 2026-01-01T00:00:05Z 1; c=$(at "$f"); say "$f" d2 2026-01-01T00:00:20Z 10; e=$(at "$f")
printf '{"agentType": "x:deferred"}\n' > "$DS/proj/d1/subagents/agent-a.meta.json"
jq -nc '{type: "assistant", isSidechain: true, timestamp: "2026-01-01T00:00:12Z", message: {id: "s-a", model: "claude-opus-5-5",
  usage: {input_tokens: 70, cache_read_input_tokens: 0, cache_creation_input_tokens: 0, output_tokens: 0}}}' > "$DS/proj/d1/subagents/agent-a.jsonl"
{
  mark open 2026-01-01T00:00:00Z docs/plans/p.md 6 d1 0; mark close 2026-01-01T00:00:15Z docs/plans/p.md 6 d1 "$c" a..b 1
  mark open 2026-01-01T00:00:15Z docs/plans/p.md 7 d1 "$c"; mark close 2026-01-01T00:00:25Z docs/plans/p.md 7 d1 "$e" b..c
} > "$DS/markers.tsv"
J=$(node "$REPORT" --markers "$DS/markers.tsv" --transcripts "$DS/proj" --format json 2>/dev/null)
check "outside_subagents: one inside a deferred task's slice is not outside" "$(q "$J" '.plans[0].outside | [.turns, .input]')" "[0,0]"

# --- archive_inferred: a task the markers record ---
AR="$TMP/arch"; mkdir -p "$AR/-r-x"; f="$AR/-r-x/a1.jsonl"
printf 'session\tproject\na1\t/r/x\n' > "$AR/manifest.tsv"
for t in 1 2; do
  say "$f" "o$t" "2026-11-01T10:0${t}:00Z" 1 "" "bash /p/scripts/task-brief --open docs/dforge/plans/2026-11-01-alpha.md $t"
  say "$f" "c$t" "2026-11-01T10:0${t}:30Z" 1 "" "bash /p/scripts/task-close docs/dforge/plans/2026-11-01-alpha.md $t x"
done
{ mark open 2026-11-01T10:01:00Z docs/dforge/plans/2026-11-01-alpha.md 1 a1 0
  mark close 2026-11-01T10:02:40Z docs/dforge/plans/2026-11-01-alpha.md 1 a1 "$(at "$f")"; } > "$AR/markers.tsv"
J=$(node "$REPORT" --markers "$AR/markers.tsv" --transcripts "$AR" --from-archive "$AR" --format json 2>/dev/null)
check "archive_inferred: a task the markers record is not inferred again" \
  "$(q "$J" '[.plans[] | select(.plan == "2026-11-01-alpha.md") | .tasks[].tasks[]]')" "[2]"

# --- splits_and_all_plans: one plan path in two repositories ---
TR="$TMP/tr"
for r in ra rb; do
  mkdir -p "$TR/$r/.dforge/sdd" "$TR/proj-$r"
  say "$TR/proj-$r/$r-s.jsonl" "$r-m" 2026-01-01T00:00:01Z 5
  { mark open 2026-01-01T00:00:00Z docs/plans/p.md 1 "$r-s" 0
    mark close 2026-01-01T00:00:02Z docs/plans/p.md 1 "$r-s" "$(at "$TR/proj-$r/$r-s.jsonl")" a..b; } > "$TR/$r/.dforge/sdd/usage-markers.tsv"
done
J=$(node "$REPORT" --markers "$TR/ra/.dforge/sdd/usage-markers.tsv" "$TR/rb/.dforge/sdd/usage-markers.tsv" \
  --transcripts "$TR/proj-ra" "$TR/proj-rb" --format json 2>/dev/null)
check "splits_and_all_plans: one plan path in two repositories stays two plans" \
  "$(q "$J" '[.plans[] | [.plan, (.repo | gsub("\\\\"; "/") | sub(".*/"; ""))]] | sort')" '[["docs/plans/p.md","ra"],["docs/plans/p.md","rb"]]'

# --- main_module: the core run through a symbolic link ---
ln -s "$HERE/../../plugins/dforge" "$TMP/link" 2>/dev/null
if [ -L "$TMP/link" ]; then
  check "main_module: runs through a symbolic link" \
    "$(node "$TMP/link/scripts/lib/usage-report.mjs" --format json 2>/dev/null | jq -c . 2>/dev/null | tr -d '\r')" '{"plans":[]}'
else
  printf 'skip - main_module\n'
fi

# --- prices_unreadable ---
mkdir -p "$TMP/noprices/lib"
cp "$REPORT" "$TMP/noprices/lib/"
J=$(node "$TMP/noprices/lib/usage-report.mjs" --markers "$FX/basic/markers.tsv" --transcripts "$FX/basic/proj" --format json 2>/dev/null)
check "prices_unreadable: the report says why" "$(q "$J" '.pricesError | test("api-prices.json")')" "true"
check "prices_unreadable: and the markdown says so first" \
  "$(node "$TMP/noprices/lib/usage-report.mjs" --markers "$FX/basic/markers.tsv" --transcripts "$FX/basic/proj" 2>/dev/null | head -n 1 | grep -c '^Prices unreadable, every cost is unpriced: .*api-prices.json')" "1"
check "prices_unreadable: a readable prices file adds no field" "$(q "$(rep basic)" 'has("pricesError")')" "false"

# --- usage errors ---
node "$REPORT" --format csv >/dev/null 2>&1
check "usage: a bad format exits 2" "$?" "2"
node "$REPORT" --no-such >/dev/null 2>&1
check "usage: an unknown argument exits 2" "$?" "2"
check "usage: no input is an empty report" "$(node "$REPORT" --format json | jq -c .)" '{"plans":[]}'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
