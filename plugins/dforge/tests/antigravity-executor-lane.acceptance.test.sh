#!/usr/bin/env bash
# Acceptance tests for the Antigravity executor lane spec
# (docs/dforge/specs/2026-11-02-antigravity-executor-lane-design.md), the
# statements A1-A11, A14-A19 (A12 and A13 are demos). Each test is written from
# the statement's text and reaches the behaviour through the scripts the spec
# names (executors, agy-gate, detect-executors.sh, run-agy-task.sh, plan-lint,
# plan-revise, lane-breaker), the files the plugin ships, or, where a statement
# is about what a skill tells a session to do, the text of the shipped
# references. The agy CLI is a stub written by this file on a sealed PATH: the
# real agy, ~/.claude and ~/.gemini are never reached.
# Usage:
#   bash antigravity-executor-lane.acceptance.test.sh            run every test
#   bash antigravity-executor-lane.acceptance.test.sh A5 A9     run the named tests
# A17 runs the maintained suites only when QA_RUN_SUITES=1 (test-all runs each
# of them already) and the claude CLI checks only when a claude binary is on the
# original PATH or CLAUDE_BIN names one.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
S="$PLUGIN/scripts"
BASE=${AGY_LANE_BASE:-7349308be4ff220f663a47e8d916fed1bddbe565}
CLAUDE_BIN=${CLAUDE_BIN:-$(command -v claude 2>/dev/null || true)}
ONLY=" $* "

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
matches() { # matches <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
skip() { printf 'skip - %s\n' "$1"; }
selected() { [ "$ONLY" = "  " ] || [[ "$ONLY" == *" $1 "* ]]; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A PATH holding every tool the scripts use and no agy: the host has a real one.
SEAL="$TMP/seal"
STUBBIN="$TMP/stubbin"
mkdir -p "$SEAL" "$STUBBIN"
while IFS= read -r dir; do
  for tool in "$dir"/*; do
    name=${tool##*/}
    case "$name" in agy|agy.exe|claude|claude.exe) continue ;; esac
    [ -e "$SEAL/$name" ] || ln -s "$tool" "$SEAL/$name" 2>/dev/null
  done
done < <(for tool in bash node jq git cat date awk sed grep timeout ps tr; do dirname "$(type -P "$tool")"; done | sort -u)

cat > "$STUBBIN/agy" <<'STUB'
#!/usr/bin/env bash
# Stand-in for the Antigravity CLI. STUB_MODE picks the result of a print call.
set -u
if [ -n "${STUB_LOG:-}" ]; then
  { printf 'CALL\n'; for arg in "$@"; do printf 'ARG:%s\n' "$arg"; done; } >> "$STUB_LOG"
fi
case "${1:-}" in
  --version) printf '%s\n' "${STUB_VERSION:-1.4.12}"; exit 0 ;;
  models)
    case "${STUB_AUTH:-ok}" in
      logged-out) printf 'You are not logged in. Please sign in with agy login.\n' >&2; exit 1 ;;
      broken) printf 'unexpected internal failure\n' >&2; exit 3 ;;
    esac
    printf 'Fetching available models...\n'
    printf 'gemini-3.8-flash-medium\tGemini 3.8 Flash (Medium)\n'
    printf 'claude-sonnet-5-5-medium\tClaude Sonnet 5.5 (Medium)\n'
    exit 0 ;;
esac
printing=no
for arg in "$@"; do [ "$arg" = -p ] && printing=yes; done
[ "$printing" = yes ] || { printf 'stub agy: unsupported call\n' >&2; exit 64; }

conv="${STUB_CONV:-conv-1}"
work() { printf 'stub\n' > out.txt; printf 'more\n' >> base.txt; }
verdict() { # verdict <status>
  jq -nc --arg s "$1" --arg subject "${STUB_SUBJECT:-feat(stub): add out}" \
    '{status: $s, summary: "stub summary", commit_subject: $subject, questions: [], discovered_issues: [], assumptions: []}'
}
emit() { # emit <status> [finished_reason]
  jq -nc --arg c "$conv" --argjson v "$(verdict "$1")" --arg f "${2:-}" \
    '{conversation_id: $c, status: "SUCCESS", response: "ok", structured_output: $v, usage: {total_tokens: 10}}
     + (if $f == "" then {} else {finished_reason: $f} end)'
}
case "${STUB_MODE:-done}" in
  done) work; emit DONE ;;
  blocked) emit BLOCKED ;;
  error)
    jq -nc --arg e "${STUB_ERROR:-something failed}" \
      '{conversation_id: "", status: "ERROR", response: "", error: $e, finished_reason: "error"}'
    exit 1 ;;
  print-timeout)
    jq -nc --arg c "$conv" '{conversation_id: $c, status: "SUCCESS", response: "", finished_reason: "print_timeout"}'
    printf 'print timeout after 5s with turn in progress\n' >&2 ;;
  print-timeout-done)
    work; emit DONE print_timeout
    printf 'print timeout after 5s with turn in progress\n' >&2 ;;
  git-commit) work; git add -A >/dev/null 2>&1; git commit -qm 'stub commit' >/dev/null 2>&1; emit DONE ;;
  git-stash) work; git stash push -u -q >/dev/null 2>&1; emit DONE ;;
  git-branch) work; git branch stub-branch >/dev/null 2>&1; emit DONE ;;
  index) work; git add out.txt >/dev/null 2>&1; emit DONE ;;
  *) printf 'stub agy: unknown STUB_MODE\n' >&2; exit 64 ;;
esac
STUB
chmod +x "$STUBBIN/agy"
printf '#!/bin/sh\nexit 0\n' > "$STUBBIN/antigravity"; chmod +x "$STUBBIN/antigravity"

# Node cannot run a bash-script stub on Windows; the probe needs it to.
SPAWNABLE=$(PATH="$STUBBIN:$SEAL" node -e 'const r = require("child_process").spawnSync(process.argv[1], ["--version"], { encoding: "utf8" }); console.log(r.status === 0 ? "yes" : "no")' "$STUBBIN/agy" 2>/dev/null | tr -d '\r')

export PATH="$STUBBIN:$SEAL"
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions"
export STUB_LOG="$TMP/agy.log"
POLICY_PASS="$TMP/policy-pass.json"
POLICY_FAIL="$TMP/policy-fail.json"
jq '.trust.smoke = "pass"' "$PLUGIN/reference/agy-policy.json" > "$POLICY_PASS"
jq '.trust.smoke = "fail"' "$PLUGIN/reference/agy-policy.json" > "$POLICY_FAIL"
export DR_AGY_POLICY="$POLICY_PASS"

check "the sealed PATH resolves agy to the stub" "$([ "$(command -v agy)" -ef "$STUBBIN/agy" ] && echo yes || echo no)" "yes"

fresh_session() { # fresh_session <name>: a gate cache nothing has touched
  export CLAUDE_CODE_SESSION_ID="qa-$1" DR_AGY_SESSION_DIR="$TMP/sessions-$1"
}
gate() { bash "$S/agy-gate" "$@" 2>&1 | tr -d '\r'; }
conf() { bash "$S/dforge-config" "$@" >/dev/null 2>&1; }
doc() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; } # a file as one line, whitespace collapsed
block() { # block <ladder block name>: its non-empty lines
  tr -d '\r' < "$PLUGIN/reference/ladder.md" | awk -v want="$1" '$0 == "```" want { f = 1; next } f && $0 == "```" { exit } f && NF { print }'
}
base_known() { git -C "$REPO_ROOT" cat-file -e "$BASE^{commit}" 2>/dev/null; }
base_tree() { # base_tree: the plugin as of BASE, extracted once; prints its plugin root
  if [ ! -d "$TMP/base-tree/plugins/dforge" ]; then
    mkdir -p "$TMP/base-tree"
    git -C "$REPO_ROOT" archive "$BASE" plugins/dforge | tar -x -C "$TMP/base-tree"
  fi
  printf '%s\n' "$TMP/base-tree/plugins/dforge"
}

# --- the primary repository and worktree helpers for the wrapper tests ---------
PRIMARY="$TMP/primary"
git init -q "$PRIMARY"
git -C "$PRIMARY" config user.email qa@example.com
git -C "$PRIMARY" config user.name QA
git -C "$PRIMARY" config core.autocrlf false
printf 'base\n' > "$PRIMARY/base.txt"
printf 'claude conventions\n' > "$PRIMARY/CLAUDE.md"
printf 'agents conventions\n' > "$PRIMARY/AGENTS.md"
git -C "$PRIMARY" add base.txt CLAUDE.md AGENTS.md
git -C "$PRIMARY" commit -qm 'test: seed'
printf 'Implement only the approved files.\n' > "$TMP/brief.md"
printf '["base.txt","out.txt","unused.txt"]\n' > "$TMP/scope.json"
W="" R="" TID=task-one
newwork() { # newwork <name>: sets W (worktree), R (report) and TID
  W="$TMP/wt-$1"; R="$TMP/$1.report.md"; TID="task-$1"
  git -C "$PRIMARY" worktree add -q -b "wt-$1" "$W"
}
runw() { bash "$S/run-agy-task.sh" --cwd "$W" --task-id "$TID" --write-set "$TMP/scope.json" \
  --brief "$TMP/brief.md" --report "$R" --model claude-sonnet-5-5 --effort medium "$@" > "$TMP/out" 2> "$TMP/err"; }
status_line() { tail -1 "$TMP/out" | tr -d '\r'; }
state_file() { # state_file <worktree> <task id>
  printf '%s/dforge/tasks/%s/state.json' "$(git -C "$1" rev-parse --absolute-git-dir)" "$(printf '%s' "$2" | git -C "$1" hash-object --stdin)"
}
pcalls() { local n; n=$(grep -c '^ARG:-p$' "$STUB_LOG" 2>/dev/null); echo "${n:-0}"; } # print calls so far
lastprint() { awk 'function flush() { if (index("\n" cur, "\nARG:-p\n")) last = cur; cur = "" }
  /^CALL$/ { flush(); next } { cur = cur $0 "\n" } END { flush(); printf "%s", last }' "$STUB_LOG" | tr -d '\r'; }
arg_after() { lastprint | awk -v f="ARG:$1" 'p { sub(/^ARG:/, ""); print; exit } $0 == f { p = 1 }'; }
args_after() { lastprint | awk -v f="ARG:$1" 'p { sub(/^ARG:/, ""); print; p = 0 } $0 == f { p = 1 }'; }

# Both a lane-gate session for the wrapper tests and a closed-quota check use
# the real agy-gate, so the wrapper is exercised against what ships.
fresh_session wrapper

# ---------------------------------------------------------------- A1
if selected A1; then
  if [ "$SPAWNABLE" = yes ]; then
    fresh_session a1
    roster=$(bash "$S/detect-executors.sh" 2>/dev/null | tr -d '\r')
    row=$(jq -c '.[] | select(.id == "agy")' <<<"$roster")
    check "A1: agy is reported usable" "$(jq -r '.usable' <<<"$row")" "true"
    check "A1: agy is reported with its version" "$(jq -r '.version' <<<"$row")" "1.4.12"
    check "A1: no antigravity row (an antigravity binary on PATH included)" \
      "$(jq -r '[.[] | select(.id == "antigravity")] | length' <<<"$roster")" "0"
    check "A1: exactly one agy row" "$(jq -r '[.[] | select(.id == "agy")] | length' <<<"$roster")" "1"
    check "A1: the version follows the binary" \
      "$(STUB_VERSION=1.9.3 bash "$S/detect-executors.sh" 2>/dev/null | jq -r '.[] | select(.id == "agy") | .version')" "1.9.3"
  else
    skip "A1: node cannot spawn a bash stub on this host"
  fi
fi

# ---------------------------------------------------------------- A2
if selected A2; then
  check "A2: ranked prints agy before codex" "$(bash "$S/executors" ranked 2>/dev/null | tr -d '\r' | tr '\n' ' ')" "agy codex "
  check "A2: list prints the registered ids, agy included" "$(bash "$S/executors" list 2>/dev/null | tr -d '\r' | tr '\n' ' ')" "agy codex "
  if base_known; then
    baseplugin=$(base_tree)
    check "A2: list is the BASE list plus agy" \
      "$(bash "$S/executors" list 2>/dev/null | tr -d '\r' | grep -vx agy | tr '\n' ' ')" \
      "$(bash "$baseplugin/scripts/executors" list 2>/dev/null | tr -d '\r' | tr '\n' ' ')"
  else
    skip "A2: BASE $BASE is not in this clone"
  fi
  REG="$TMP/reg"
  prio() { # prio <agy priority json | none> <codex priority json | none>: a registry in $REG
    rm -rf "$REG"; mkdir -p "$REG"
    local id val
    for id in agy codex; do
      if [ "$id" = agy ]; then val=$1; else val=$2; fi
      if [ "$val" = none ]; then jq 'del(.priority)' "$PLUGIN/reference/executors/$id.json" > "$REG/$id.json"
      else jq --argjson p "$val" '.priority = $p' "$PLUGIN/reference/executors/$id.json" > "$REG/$id.json"; fi
    done
  }
  ranked() { DR_EXECUTORS_DIR="$REG" bash "$S/executors" ranked 2>"$TMP/ranked.err" | tr -d '\r' | tr '\n' ' '; }
  prio 30 20;     check "A2: a lower number ranks first (codex 20 before agy 30)" "$(ranked)" "codex agy "
  prio 0 20;      check "A2: priority 0 is a valid priority" "$(ranked)" "agy codex "
  prio 20 0;      check "A2: priority 0 ranks first for codex" "$(ranked)" "codex agy "
  prio 5 5;       check "A2: equal priorities rank by id" "$(ranked)" "agy codex "
  prio none none; check "A2: entries without priority rank by id" "$(ranked)" "agy codex "
  prio none 20;   check "A2: an entry without priority ranks after every entry with one" "$(ranked)" "codex agy "
  prio 10 none;   check "A2: agy ahead of a codex without priority" "$(ranked)" "agy codex "
  for bad in '"high"' '-1' '1.5' 'true' '[]'; do
    prio "$bad" 20
    check "A2: priority $bad ranks last" "$(ranked)" "codex agy "
    check "A2: priority $bad writes one stderr line" "$(wc -l < "$TMP/ranked.err" | tr -d ' ')" "1"
    check "A2: list still prints both ids with priority $bad" \
      "$(DR_EXECUTORS_DIR="$REG" bash "$S/executors" list 2>/dev/null | tr -d '\r' | tr '\n' ' ')" "agy codex "
  done
  prio 10 '"later"'
  check "A2: a non-integer codex priority leaves codex last" "$(ranked)" "agy codex "
  check "A2: and still writes one stderr line" "$(wc -l < "$TMP/ranked.err" | tr -d ' ')" "1"
  prio 10 20; ranked >/dev/null
  check "A2: valid priorities write nothing to stderr" "$(wc -c < "$TMP/ranked.err" | tr -d ' ')" "0"
fi

# Plan fixtures for A3, A4 and A5.
agent_for() { case $1 in 0|1|2) echo impl-sonnet-low ;; 3|4) echo impl-sonnet-medium ;; 5) echo impl-sonnet-high ;; *) echo impl-opus-high ;; esac; }
mkplan() { # mkplan <file> <ticked ids or empty> <"a b c d[|line^line]">...: a plan, one task per spec
  local file=$1 ticked=$2 n=0 idx="" body="" spec axes extra a b c d t tick=""
  shift 2
  [ -z "$ticked" ] || tick="> **External executors:** $ticked"
  for spec in "$@"; do
    n=$((n + 1)); axes=${spec%%|*}; extra=""
    [[ "$spec" != *"|"* ]] || extra=${spec#*|}
    read -r a b c d <<<"$axes"; t=$((a + b + c + d))
    idx+="$n. Thing $n"$'\n'
    body+="### Task $n: Thing $n"$'\n\n'"**Files:**"$'\n'"- Create: \`f$n.txt\`"$'\n\n'
    body+="**Implementer:** dforge:$(agent_for "$t")"$'\n'
    body+="**Evaluation:** files $a - spec $b - coupling $c - risk $d = $t"$'\n'
    body+="**Approach:** inline - skip 1: follows the pattern"$'\n'
    [ -z "$extra" ] || body+="$(tr '^' '\n' <<<"$extra")"$'\n'
    body+=$'\n'"- [ ] **Step 1: Do it**"$'\n\n'
  done
  cat > "$file" <<PLAN
# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** \`docs/spec.md\`

**Execution:** subagent — \`claude --model sonnet --effort high\` — Task 2 scores 4

**Program:** \`docs/program.md\` — sub-project 1 of 2 — next: Second part

$tick

**Task check:** \`bash quick.sh\` — gate 1 has Tier: task

**Integration check:** \`bash test.sh\`

**CI:** none

**Plan review:** 2026-09-12 — dforge:judge-fable — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

$idx
$body
PLAN
}
LREPO="$TMP/lrepo"
mkdir -p "$LREPO/docs"
git init -q "$LREPO"
git -C "$LREPO" config user.email qa@example.com
git -C "$LREPO" config user.name QA
printf '# Spec\n' > "$LREPO/docs/spec.md"
printf '# Program\n' > "$LREPO/docs/program.md"
lint() { (cd "$LREPO" && bash "${2:-$S}/plan-lint" "docs/$1" --no-probe 2>&1 | tr -d '\r'; echo "rc=${PIPESTATUS[0]}"); }
revise() { (cd "$LREPO" && bash "${2:-$S}/plan-revise" "docs/$1" 2>&1 | tr -d '\r'); }
revise_stdout() { (cd "$LREPO" && bash "${2:-$S}/plan-revise" "docs/$1" 2>/dev/null | tr -d '\r'); }
revise_stderr() { (cd "$LREPO" && bash "${2:-$S}/plan-revise" "docs/$1" 2>&1 >/dev/null | tr -d '\r'); }
rung_of() { # rung_of <block> <total>: "<model> / <effort>" from an assignment block
  block "$1" | awk -v t="$2" '$1 == t { print $2 " / " $3; exit }'
}

# ---------------------------------------------------------------- A3
if selected A3; then
  # Axes giving each total from 0 to 7 at risk 2 or less with Rule S clean; a
  # total of 8 cannot clear Rule S (files + spec + coupling < 6) at risk <= 2.
  axes_for=("0 0 0 0" "0 0 1 0" "0 1 1 0" "1 1 1 0" "0 1 1 2" "1 1 1 2" "2 1 2 1" "2 1 2 2")
  mkplan "$LREPO/docs/a3.md" "agy, codex" "${axes_for[@]}"
  rev=$(revise a3.md)
  for t in 0 1 2 3 4 5 6 7; do
    unit=$(grep -E "^unit $((t + 1)) " <<<"$rev")
    want=$(block agy-assignment | awk -v t="$t" '$1 == t { print $2 "/" $3; exit }')
    matches "A3: total $t at risk <= 2 lists agy first with the agy-assignment rung ($want)" "$unit" "rungs=agy:$want(,|$)"
    has "A3: total $t clears the gate" "$unit" "gate=pass"
  done
  # Totals 3 to 8 mirror the native table: Sonnet medium, Sonnet medium, Sonnet high, Opus high.
  for pair in "3 claude-sonnet-5-5 medium" "4 claude-sonnet-5-5 medium" "5 claude-sonnet-5-5 high" "6 claude-opus-5-5 high" "7 claude-opus-5-5 high" "8 claude-opus-5-5 high"; do
    set -- $pair
    check "A3: agy-assignment row $1 is $2 $3" "$(block agy-assignment | awk -v t="$1" '$1 == t { print $2 " " $3 }')" "$2 $3"
  done
  for t in 0 1 2; do
    matches "A3: agy-assignment row $t is a gemini-3.8-flash, gemini-4-argon or claude-sonnet-5-5 rung" \
      "$(block agy-assignment | awk -v t="$t" '$1 == t { print $2 "/" $3 }')" \
      '^(gemini-3\.8-flash/(low|medium)|gemini-4-argon/low|claude-sonnet-5-5/low)$'
  done
  # plan-lint accepts the agy line from the block for each total, with both ticked.
  specs=()
  for i in 0 1 2 3 4 5 6 7; do
    specs+=("${axes_for[$i]}|**Executor:** agy $(rung_of agy-assignment "$i")")
  done
  mkplan "$LREPO/docs/a3-ok.md" "agy, codex" "${specs[@]}"
  out=$(lint a3-ok.md)
  lacks "A3: plan-lint accepts an agy line from agy-assignment for totals 0-7" "$out" "ERROR Task"
  # A wrong rung is an error.
  mkplan "$LREPO/docs/a3-wrong.md" "agy, codex" "0 1 1 0|**Executor:** agy claude-opus-5-5 / high"
  has "A3: plan-lint rejects an agy line off the agy-assignment rung" "$(lint a3-wrong.md)" "ERROR Task 1"
  # Naming codex for a task agy admits is an ERROR, in either header order, for each total codex's own gate also admits.
  cmin=$(block gate | awk '$1 == "min_score" { print $2 }'); cmax=$(block gate | awk '$1 == "max_score" { print $2 }')
  for pair in "2:0 1 1 0" "3:1 1 1 0" "4:1 1 1 1"; do
    t=${pair%%:*}; ax=${pair#*:}
    [ "$t" -ge "$cmin" ] && [ "$t" -le "$cmax" ] || continue
    crung=$(rung_of codex-assignment "$t")
    for ticks in "agy, codex" "codex, agy"; do
      mkplan "$LREPO/docs/a3-codex.md" "$ticks" "$ax|**Executor:** codex $crung"
      out=$(lint a3-codex.md)
      matches "A3: total $t naming codex while agy is ticked ($ticks) is an ERROR that names agy" "$out" "^ERROR Task 1:.*agy"
      has "A3: that run exits 1" "$out" "rc=1"
    done
    mkplan "$LREPO/docs/a3-codex.md" "codex" "$ax|**Executor:** codex $crung"
    lacks "A3: total $t naming codex with agy unticked is not an error" "$(lint a3-codex.md)" "ERROR Task 1"
  done
fi

# ---------------------------------------------------------------- A4
if selected A4; then
  # Risk 3: files 0 spec 1 coupling 1 risk 3 = 5.
  mkplan "$LREPO/docs/a4-risk.md" "agy, codex" "0 1 1 3"
  unit=$(revise a4-risk.md | grep -E '^unit 1 ')
  lacks "A4: a risk-3 unit lists no agy rung" "$unit" "agy:"
  has "A4: a risk-3 unit fails the gate on risk" "$unit" "gate=fail:risk"
  mkplan "$LREPO/docs/a4-risk-hand.md" "agy, codex" "0 1 1 3|**Executor:** agy $(rung_of agy-assignment 5)"
  out=$(lint a4-risk-hand.md)
  matches "A4: plan-lint rejects an agy line written by hand on a risk-3 task" "$out" "^ERROR Task 1:"
  has "A4: that run exits 1" "$out" "rc=1"
  # A human override.
  mkplan "$LREPO/docs/a4-ovr.md" "agy, codex" "0 1 1 2|**Override:** kept"
  unit=$(revise a4-ovr.md | grep -E '^unit 1 ')
  lacks "A4: an overridden unit lists no agy rung" "$unit" "agy:"
  mkplan "$LREPO/docs/a4-ovr-hand.md" "agy, codex" "0 1 1 2|**Override:** kept^**Executor:** agy $(rung_of agy-assignment 4)"
  out=$(lint a4-ovr-hand.md)
  matches "A4: plan-lint rejects an agy line written by hand on an overridden task" "$out" "^ERROR Task 1:"
  has "A4: that run exits 1" "$out" "rc=1"
  # Control: the same task without the override takes the line.
  mkplan "$LREPO/docs/a4-ctl.md" "agy, codex" "0 1 1 2|**Executor:** agy $(rung_of agy-assignment 4)"
  lacks "A4: control: the same task without an override takes the agy line" "$(lint a4-ctl.md)" "ERROR Task"
  # A batch is one dispatch over several tasks, which has no plan-file form: the rule is the shipped text.
  lane=$(doc "$PLUGIN/reference/executor-lane.md")
  has "A4: the lane reference keeps batched tasks off the lane" "$lane" "Batched tasks stay on the Claude lane"
  has "A4: and forbids an Executor line on a batched task" "$lane" 'Do not write an `**Executor:**` line on a batched task'
fi

# ---------------------------------------------------------------- A5
if selected A5; then
  if base_known; then
    baseplugin=$(base_tree)
    # Plans: ours (codex ticked or nothing ticked, codex lines on codex-band tasks) and the repository's own.
    mkplan "$LREPO/docs/a5-codex.md" "codex" "0 1 1 0|**Executor:** codex $(rung_of codex-assignment 2)" \
      "0 1 1 1|**Executor:** codex $(rung_of codex-assignment 3)" "0 1 1 2" "0 0 1 0"
    mkplan "$LREPO/docs/a5-none.md" "" "0 1 1 0" "0 1 1 1" "0 1 1 2" "2 1 2 2" "0 1 1 3"
    mkplan "$LREPO/docs/a5-bad.md" "codex" "0 1 1 2|**Executor:** codex gpt-6.1-sol / low" "0 1 1 3|**Executor:** codex gpt-6.1-sol / low"
    plans="a5-codex.md a5-none.md a5-bad.md"
    mkdir -p "$LREPO/docs/real"
    for rel in docs/superpowers/plans/2026-09-11-dr-superpowers-fold-companions.md \
               docs/superpowers/plans/2026-10-21-cockpit-live-state.md \
               docs/superpowers/plans/2026-10-13-darkmem-store-moves.md \
               docs/superpowers/plans/2026-08-31-companions-external-executors.md \
               docs/dforge/plans/2026-10-26-faster-plans.md; do
      [ -f "$REPO_ROOT/$rel" ] || continue
      cp "$REPO_ROOT/$rel" "$LREPO/docs/real/${rel##*/}"
      plans="$plans real/${rel##*/}"
    done
    conf set agyLane true
    for scenario in unticked agyLane-off; do
      plans_run=$plans
      if [ "$scenario" = agyLane-off ]; then conf set agyLane false; plans_run="a5-codex.md a5-none.md a5-bad.md"; fi
      for p in $plans_run; do
        head_out=$(lint "$p"); base_out=$(lint "$p" "$baseplugin/scripts")
        check "A5 ($scenario): plan-lint on $p is unchanged from BASE" "$head_out" "$base_out"
        head_rev=$(revise_stdout "$p"); base_rev=$(revise_stdout "$p" "$baseplugin/scripts")
        check "A5 ($scenario): plan-revise stdout on $p is unchanged from BASE" "$head_rev" "$base_rev"
        head_err=$(revise_stderr "$p"); base_err=$(revise_stderr "$p" "$baseplugin/scripts")
        check "A5 ($scenario): plan-revise stderr on $p is unchanged from BASE" "$head_err" "$base_err"
      done
    done
    conf set agyLane true
    # The lane probe: agy off for the session leaves the Codex warning exactly as at BASE.
    mkdir -p "$TMP/p5"
    printf '#!/bin/sh\necho %s\n' "'[{\"id\":\"codex\",\"usable\":true,\"reason\":null}]'" > "$TMP/p5/codex-roster.sh"
    printf '#!/bin/sh\necho %s\n' "'[{\"id\":\"agy\",\"usable\":true,\"reason\":null},{\"id\":\"codex\",\"usable\":true,\"reason\":null}]'" > "$TMP/p5/both-roster.sh"
    mkdir -p "$DR_CODEX_SESSION_DIR"
    printf '{"session_id":"qa-a5","usable":true,"review":false,"lane":true}\n' > "$DR_CODEX_SESSION_DIR/qa-a5.json"
    fresh_session a5
    conf set agyLane false
    gate >/dev/null
    mkplan "$LREPO/docs/a5-probe.md" "codex" "0 1 1 0" "0 1 1 1" "0 1 1 2"
    probe_head=$(cd "$LREPO" && PLAN_LINT_ROSTER="$TMP/p5/both-roster.sh" timeout 120 bash "$S/plan-lint" docs/a5-probe.md 2>&1 | tr -d '\r')
    probe_base=$(cd "$LREPO" && PLAN_LINT_ROSTER="$TMP/p5/codex-roster.sh" timeout 120 bash "$baseplugin/scripts/plan-lint" docs/a5-probe.md 2>&1 | tr -d '\r')
    check "A5: with agyLane=false the lane-eligible warnings equal BASE's" "$probe_head" "$probe_base"
    has "A5: and Codex is still named" "$probe_head" "lane-eligible with no **Executor:** line (codex"
    conf set agyLane true
    # Survey mode pinned to the fixture registry.
    mkdir -p "$TMP/survey/docs"
    git init -q "$TMP/survey"
    cp "$LREPO/docs/a5-codex.md" "$LREPO/docs/a5-none.md" "$TMP/survey/docs/"
    survey_head=$(cd "$TMP/survey" && DR_EXECUTORS_DIR="$PLUGIN/tests/fixtures/executors" bash "$S/plan-revise" --survey docs 2>&1 | tr -d '\r')
    survey_base=$(cd "$TMP/survey" && DR_EXECUTORS_DIR="$PLUGIN/tests/fixtures/executors" bash "$baseplugin/scripts/plan-revise" --survey docs 2>&1 | tr -d '\r')
    check "A5: survey mode pinned to the fixture registry equals BASE" "$survey_head" "$survey_base"
  else
    skip "A5: BASE $BASE is not in this clone"
  fi
fi

# ---------------------------------------------------------------- A6
if selected A6; then
  if [ "$SPAWNABLE" = yes ]; then
    newwork a6
    base=$(git -C "$W" rev-parse HEAD)
    STUB_CONV=conv-a6 runw
    check "A6: a DONE run exits 0" "$?" "0"
    head=$(git -C "$W" rev-parse HEAD)
    line=$(status_line)
    check "A6: the status line is rung, status, exit, commits, thread" \
      "${line%% report=*}" "agy claude-sonnet-5-5/medium status=DONE exit=0 commits=${base:0:7}..${head:0:7} thread=conv-a6"
    rpt=${line##* report=}
    check "A6: the status line names a report that exists" "$([ -f "$rpt" ] && echo yes || echo no)" "yes"
    check "A6: exactly one commit was added" "$(git -C "$W" rev-list --count "$base..HEAD" | tr -d ' ')" "1"
    check "A6: the commit carries the reported subject" "$(git -C "$W" log -1 --format=%s)" "feat(stub): add out"
    check "A6: the commit holds only the approved files the stub changed" \
      "$(git -C "$W" show --name-only --format= HEAD | tr -d '\r' | sort | tr '\n' ' ')" "base.txt out.txt "
    check "A6: the commit holds the produced file" "$(git -C "$W" show HEAD:out.txt | tr -d '\r')" "stub"
    check "A6: the worktree is clean afterwards" "$(git -C "$W" status --porcelain | wc -l | tr -d ' ')" "0"
    check "A6: the task record is complete" "$(jq -r .phase "$(state_file "$W" "$TID")")" "complete"
  else
    skip "A6: node cannot spawn a bash stub on this host"
  fi
fi

# ---------------------------------------------------------------- A7
if selected A7; then
  if [ "$SPAWNABLE" = yes ]; then
    git_case() { # git_case <name> <STUB_MODE> <report pattern> <commits agy itself made>
      newwork "$1"
      local base; base=$(git -C "$W" rev-parse HEAD)
      STUB_MODE=$2 runw
      local rc=$?
      check "A7 ($1): the run does not succeed" "$([ "$rc" -ne 0 ] && echo failed || echo ok)" "failed"
      check "A7 ($1): the status line never says DONE" "$(status_line | grep -c 'status=DONE')" "0"
      check "A7 ($1): the wrapper committed nothing" "$(git -C "$W" log --format=%s | grep -c 'feat(stub): add out')" "0"
      check "A7 ($1): the branch gained only the commits agy made itself" "$(git -C "$W" rev-list --count "$base..HEAD" | tr -d ' ')" "$4"
      check "A7 ($1): the task record is blocked" "$(jq -r .phase "$(state_file "$W" "$TID")" 2>/dev/null)" "blocked"
      matches "A7 ($1): the report names what moved" "$(cat "$R" "$TMP/err" "$TMP/out" 2>/dev/null)" "$3"
    }
    git_case commit git-commit 'refs/heads/wt-commit|HEAD' 1
    git_case stash git-stash 'refs/stash' 0
    git_case branch git-branch 'refs/heads/stub-branch' 0
    git_case index index '[Ii]ndex' 0
    # Control: an unrelated string never blocks.
    newwork ctl7
    runw
    check "A7: control: a clean run is not blocked" "$(jq -r .phase "$(state_file "$W" "$TID")")" "complete"
  else
    skip "A7: node cannot spawn a bash stub on this host"
  fi
fi

# ---------------------------------------------------------------- A8
if selected A8; then
  if [ "$SPAWNABLE" = yes ]; then
    i=0
    for text in 'Quota exceeded for this account' 'Rate limit reached, slow down' 'RESOURCE_EXHAUSTED: try later' 'HTTP 429 Too Many Requests' 'rate_limit hit'; do
      i=$((i + 1))
      fresh_session "quota$i"
      newwork "q$i"
      STUB_MODE=error STUB_ERROR="$text" runw
      check "A8 [$text]: the failing run is not DONE" "$(status_line | grep -c 'status=DONE')" "0"
      g=$(gate)
      matches "A8 [$text]: agy-gate prints lane=false" "$g" 'lane=false'
      has "A8 [$text]: agy-gate prints reason=quota" "$g" 'reason=quota'
      g=$(gate --refresh)
      matches "A8 [$text]: agy-gate --refresh prints lane=false" "$g" 'lane=false'
      has "A8 [$text]: agy-gate --refresh prints reason=quota" "$g" 'reason=quota'
      before=$(pcalls)
      newwork "q$i-next"
      runw
      check "A8 [$text]: the next wrapper call exits 2" "$?" "2"
      check "A8 [$text]: and never runs agy" "$(pcalls)" "$before"
    done
    # A different error text leaves the lane open.
    fresh_session quota-ctl
    newwork qctl
    STUB_MODE=error STUB_ERROR='something failed' runw
    matches "A8: control: a non-quota error leaves the lane on" "$(gate --refresh)" 'lane=true'
  else
    skip "A8: node cannot spawn a bash stub on this host"
  fi
fi

# ---------------------------------------------------------------- A9
if selected A9; then
  if [ "$SPAWNABLE" = yes ]; then
    fresh_session wrapper
    for first in done blocked; do
      newwork "a9-$first"
      STUB_MODE=$first STUB_CONV=conv-pin runw
      rec=$(cat "$(state_file "$W" "$TID")")
      has "A9 ($first): the record pins the thread" "$rec" "conv-pin"
      has "A9 ($first): the record pins the model" "$rec" "claude-sonnet-5-5"
      has "A9 ($first): the record pins the effort" "$rec" '"medium"'
      STUB_CONV=conv-pin runw --resume conv-pin
      check "A9 ($first): a matching resume succeeds" "$?" "0"
      check "A9 ($first): a resume passes --conversation with the thread" "$(arg_after --conversation)" "conv-pin"
      check "A9 ($first): a resume passes the pinned model" "$(arg_after --model)" "claude-sonnet-5-5"
      check "A9 ($first): a resume passes the pinned effort" "$(arg_after --effort)" "medium"
      n=$(pcalls)
      runw --resume other-thread
      check "A9 ($first): another thread is refused" "$([ "$?" -ne 0 ] && echo refused || echo ran)" "refused"
      runw --effort high --resume conv-pin
      check "A9 ($first): another effort is refused" "$([ "$?" -ne 0 ] && echo refused || echo ran)" "refused"
      runw --model claude-opus-5-5 --effort high --resume conv-pin
      check "A9 ($first): another model is refused" "$([ "$?" -ne 0 ] && echo refused || echo ran)" "refused"
      check "A9 ($first): a refused resume never reaches agy" "$(pcalls)" "$n"
    done
    newwork a9-fresh
    runw
    check "A9: a fresh run passes no --conversation" "$(lastprint | grep -c '^ARG:--conversation$')" "0"
  else
    skip "A9: node cannot spawn a bash stub on this host"
  fi
fi

# ---------------------------------------------------------------- A10
if selected A10; then
  if [ "$SPAWNABLE" = yes ]; then
    fresh_session wrapper
    pointer_re='^Your complete instructions are in (.+)\. Read the whole file first and follow it\.$'
    sizes=(small huge)
    for size in "${sizes[@]}"; do
      newwork "a10-$size"
      marker="BRIEFMARKER-$size"
      if [ "$size" = small ]; then printf '%s\nDo it.\n' "$marker" > "$TMP/brief-$size.md"
      else { for _ in $(seq 1 5000); do printf '%s %s\n' "$marker" "a long line of brief text that pads the file well past the argument limit padding padding"; done; } > "$TMP/brief-$size.md"; fi
      runw --brief "$TMP/brief-$size.md"
      check "A10 ($size): the run succeeds" "$?" "0"
      p=$(arg_after -p)
      matches "A10 ($size): the -p argument is the fixed pointer sentence" "$p" "$pointer_re"
      check "A10 ($size): the -p argument is short" "$([ "${#p}" -lt 600 ] && echo short || echo long)" "short"
      check "A10 ($size): no argument carries the brief" "$(lastprint | grep -c "$marker")" "0"
      check "A10 ($size): the whole argument vector is small" "$([ "$(lastprint | wc -c | tr -d ' ')" -lt 8000 ] && echo small || echo large)" "small"
      pointed=$(sed -E "s/$pointer_re/\1/" <<<"$p")
      check "A10 ($size): the pointed file exists" "$([ -f "$pointed" ] && echo yes || echo no)" "yes"
      check "A10 ($size): the pointed file holds the brief" "$(grep -c "$marker" "$pointed" 2>/dev/null)" "$(grep -c "$marker" "$TMP/brief-$size.md")"
      statedir=$(dirname "$(state_file "$W" "$TID")")
      adds=$(args_after --add-dir)
      check "A10 ($size): --add-dir is given" "$([ -n "$adds" ] && echo yes || echo no)" "yes"
      allsafe=yes; covers=no
      while IFS= read -r d; do
        [ -n "$d" ] || continue
        [ "$d" -ef "$statedir" ] && allsafe=no
        [ -e "$d/state.json" ] && allsafe=no
        [ "$d" -ef "$(dirname "$pointed")" ] && covers=yes
      done <<<"$adds"
      check "A10 ($size): no --add-dir names the directory holding state.json" "$allsafe" "yes"
      check "A10 ($size): --add-dir names the directory of the pointed file" "$covers" "yes"
      [ "$size" = small ] && small_p=$p
    done
    norm() { sed -E "s/$pointer_re/POINTER/" <<<"$1"; }
    check "A10: the sentence is the same for a small and a huge brief" "$(norm "$small_p")" "$(norm "$(arg_after -p)")"
  else
    skip "A10: node cannot spawn a bash stub on this host"
  fi
fi

# ---------------------------------------------------------------- A11
if selected A11; then
  if [ "$SPAWNABLE" = yes ]; then
    conf set agyLane true
    gate_case() { # gate_case <label> <usable> <lane> <reason ERE> <env...>: one fresh session, one run
      local label=$1 usable=$2 lane=$3 reason=$4; shift 4
      fresh_session "a11-${label//[^a-z0-9]/}"
      local g; g=$(env "$@" bash "$S/agy-gate" 2>&1 | tr -d '\r')
      matches "A11 ($label): usable=$usable lane=$lane" "$g" "^agy-gate usable=$usable reason=($reason) review=false lane=$lane "
    }
    gate_case "all conditions hold" true true 'ok|-|' DR_AGY_POLICY="$POLICY_PASS"
    gate_case "smoke not pass" true false '[^ ]*' DR_AGY_POLICY="$POLICY_FAIL"
    gate_case "not installed" false false 'plugin-not-installed' PATH="$SEAL"
    gate_case "version below the floor" false false 'plugin-version:1\.4\.11' STUB_VERSION=1.4.11
    gate_case "major above the ceiling" false false 'plugin-version:2\.0\.0' STUB_VERSION=2.0.0
    gate_case "logged out" false false 'logged-out' STUB_AUTH=logged-out
    gate_case "probe failed" false false 'probe-failed' STUB_AUTH=broken
    conf set agyLane false
    gate_case "setting off" false false 'setting'
    conf set agyLane true
    gate_case "setting back on" true true '[^ ]*'
    fresh_session a11-refresh
    gate >/dev/null
    matches "A11: --refresh repeats the answer" "$(gate --refresh)" '^agy-gate usable=true reason=[^ ]* review=false lane=true '
  else
    skip "A11: node cannot spawn a bash stub on this host"
  fi
fi

# ---------------------------------------------------------------- A14
if selected A14; then
  cons="$REPO_ROOT/docs/superpowers/distilled/constraints.md"
  entry=$(doc "$cons")
  has "A14: the constraints file carries the Antigravity lane entry" "$entry" "The Antigravity executor lane is on"
  matches "A14: the entry says to tick agy without asking when the gate says lane=true" "$entry" 'lane=true.*ticks `agy` without asking|ticks `agy` without asking'
  check "A14: the shipped policy has trust.smoke pass" "$(jq -r .trust.smoke "$PLUGIN/reference/agy-policy.json")" "pass"
  if [ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" = false ]; then
    introduced=$(git -C "$REPO_ROOT" log --format=%H --diff-filter=A -S'The Antigravity executor lane is on' -- docs/superpowers/distilled/constraints.md 2>/dev/null; \
                 git -C "$REPO_ROOT" log --format=%H -S'The Antigravity executor lane is on' -- docs/superpowers/distilled/constraints.md 2>/dev/null)
    first=$(printf '%s\n' "$introduced" | awk 'NF && !seen[$0]++' | tail -1)
    check "A14: the entry was introduced by exactly one commit" "$(printf '%s\n' "$introduced" | awk 'NF && !seen[$0]++' | wc -l | tr -d ' ')" "1"
    if [ -n "$first" ]; then
      check "A14: that commit flips trust.smoke to pass" "$(git -C "$REPO_ROOT" show "$first:plugins/dforge/reference/agy-policy.json" | jq -r .trust.smoke)" "pass"
      check "A14: trust.smoke was not pass in the parent commit" "$(git -C "$REPO_ROOT" show "$first^:plugins/dforge/reference/agy-policy.json" | jq -r .trust.smoke)" "fail"
      check "A14: the entry is absent from the parent commit" \
        "$(git -C "$REPO_ROOT" show "$first^:docs/superpowers/distilled/constraints.md" | grep -c 'The Antigravity executor lane is on')" "0"
      check "A14: the flip is in the same commit as the entry" \
        "$(git -C "$REPO_ROOT" show --name-only --format= "$first" | grep -cE '^(plugins/dforge/reference/agy-policy\.json|docs/superpowers/distilled/constraints\.md)$' | tr -d ' ')" "2"
    fi
    # Never before: no commit on the way to the flip has the entry without the flip.
    bad=0
    for c in $(git -C "$REPO_ROOT" log --format=%H -S'The Antigravity executor lane is on' -- docs/superpowers/distilled/constraints.md); do
      [ "$(git -C "$REPO_ROOT" show "$c:plugins/dforge/reference/agy-policy.json" | jq -r .trust.smoke)" = pass ] || bad=$((bad + 1))
    done
    check "A14: no commit holds the entry while trust.smoke is not pass" "$bad" "0"
  else
    skip "A14: the clone is shallow, so the history is not there"
  fi
fi

# ---------------------------------------------------------------- A15
if selected A15; then
  if [ "$SPAWNABLE" = yes ]; then
    fresh_session wrapper
    for mode in print-timeout print-timeout-done; do
      newwork "a15-$mode"
      base=$(git -C "$W" rev-parse HEAD)
      STUB_MODE=$mode runw
      rc=$?
      line=$(status_line)
      check "A15 ($mode): the run does not succeed" "$([ "$rc" -ne 0 ] && echo failed || echo ok)" "failed"
      has "A15 ($mode): the status line is BLOCKED with exit 124" "$line" " status=BLOCKED exit=124 "
      has "A15 ($mode): the status line says timed-out" "$line" " note=timed-out"
      lacks "A15 ($mode): the status line is never DONE" "$line" "status=DONE"
      check "A15 ($mode): the report has reason=timeout" "$(grep -c '^reason=timeout$' "$R")" "1"
      check "A15 ($mode): the report has timedOut=true" "$(grep -c '^timedOut=true$' "$R")" "1"
      check "A15 ($mode): nothing was committed" "$(git -C "$W" rev-list --count "$base..HEAD" | tr -d ' ')" "0"
    done
  else
    skip "A15: node cannot spawn a bash stub on this host"
  fi
fi

# ---------------------------------------------------------------- A16
if selected A16; then
  rank() { # rank <model/effort>
    local model=${1%/*} effort=${1#*/} m e
    case "$model" in gemini-*) m=0 ;; claude-sonnet-5-5) m=1 ;; claude-opus-5-5) m=2 ;; *) m=9 ;; esac
    case "$effort" in low) e=0 ;; medium) e=1 ;; high) e=2 ;; *) e=9 ;; esac
    echo $((m * 10 + e))
  }
  succ=$(block agy-successor)
  check "A16: the successor block has rows" "$([ -n "$succ" ] && echo yes || echo no)" "yes"
  worse=""
  while read -r src nxt; do
    [ "$nxt" = HANDBACK ] && continue
    [ "$(rank "$nxt")" -gt "$(rank "$src")" ] || worse="$worse$src->$nxt "
  done <<<"$succ"
  check "A16: every successor ranks strictly above its source" "$worse" ""
  check "A16: HANDBACK appears" "$(awk '$2 == "HANDBACK"' <<<"$succ" | wc -l | tr -d ' ')" "1"
  starts=$( { awk '{ print $1 }' <<<"$succ"; block agy-assignment | awk '{ print $2 "/" $3 }'; } | sort -u)
  stuck=""
  while read -r start; do
    [ -n "$start" ] || continue
    cur=$start; steps=0
    while [ "$cur" != HANDBACK ] && [ "$steps" -le 40 ]; do
      cur=$(awk -v c="$cur" '$1 == c { print $2; exit }' <<<"$succ")
      steps=$((steps + 1))
      [ -n "$cur" ] || { cur=DEAD; break; }
    done
    [ "$cur" = HANDBACK ] || stuck="$stuck$start "
  done <<<"$starts"
  check "A16: every walk from a source row or an assignment rung reaches HANDBACK" "$stuck" ""
  suite=$(grep -l 'agy-successor' "$HERE"/*.test.sh 2>/dev/null | grep -v 'antigravity-executor-lane.acceptance' | head -1)
  check "A16: a maintained suite checks the successor column" "$([ -n "$suite" ] && echo yes || echo no)" "yes"
fi

# ---------------------------------------------------------------- A17
if selected A17; then
  out=$(cd "$REPO_ROOT" && timeout 300 node scripts/validate-repository.mjs 2>&1); rc=$?
  check "A17: node scripts/validate-repository.mjs passes" "$rc" "0"
  if [ -n "$CLAUDE_BIN" ] && [ -x "$CLAUDE_BIN" ] && [ -z "${AGY_LANE_QA_NESTED:-}" ]; then
    rc=$(cd "$REPO_ROOT" && timeout 120 "$CLAUDE_BIN" plugin validate . >/dev/null 2>&1; echo $?)
    check "A17: claude plugin validate passes on the marketplace" "$rc" "0"
    for plugin in "$REPO_ROOT"/plugins/*/; do
      name=$(basename "$plugin")
      [ -f "$plugin/.claude-plugin/plugin.json" ] || continue
      rc=$(cd "$REPO_ROOT" && timeout 120 "$CLAUDE_BIN" plugin validate "plugins/$name" >/dev/null 2>&1; echo $?)
      check "A17: claude plugin validate passes on $name" "$rc" "0"
    done
    if [ "${DR_TEST_ALL:-}" != 1 ]; then
      rc=$(cd "$REPO_ROOT" && AGY_LANE_QA_NESTED=1 timeout 400 "$CLAUDE_BIN" plugin test plugins/dforge >/dev/null 2>&1; echo $?)
      check "A17: claude plugin test plugins/dforge passes" "$rc" "0"
    fi
  else
    skip "A17: no claude binary; the claude plugin checks run in their own CI steps"
  fi
  if [ "${QA_RUN_SUITES:-}" = 1 ] && [ "${DR_TEST_ALL:-}" != 1 ]; then
    rc=$(cd "$REPO_ROOT" && timeout 3000 node scripts/test-all.mjs >"$TMP/test-all.log" 2>&1; echo $?)
    check "A17: node scripts/test-all.mjs passes" "$rc" "0"
  fi
fi

# ---------------------------------------------------------------- A18
if selected A18; then
  BREAKER="$S/lane-breaker"
  BREPO="$TMP/brepo"
  git init -q "$BREPO"
  mkdir -p "$BREPO/docs"
  printf '# Breaker Plan\n\n### Task 1: One\n\n**Files:**\n- Create: `a.txt`\n' > "$BREPO/docs/plan.md"
  ws=$(cd "$BREPO" && bash "$S/sdd-workspace" docs/plan.md)
  LEDGER="$ws/progress.md"
  breaker() { (cd "$BREPO" && bash "$BREAKER" docs/plan.md "$1" 2>&1 | tr -d '\r'); }
  ledger() { printf '%s\n' '# SDD ledger — plan: docs/plan.md' "$@" > "$LEDGER"; }
  HB() { printf 'Task %s: implementer impl-sonnet-low (assigned; base aaaaaaa; executor %s HANDBACK - reason)' "$1" "$2"; }
  AS() { printf 'Task %s: implementer impl-sonnet-low (assigned; base aaaaaaa; executor %s claude-sonnet-5-5/medium, thread t%s)' "$1" "$2" "$1"; }
  rm -f "$LEDGER"
  check "A18: no ledger: open, no handbacks" "$(breaker agy)" "lane-breaker agy state=open handbacks=0"
  ledger "$(AS 1 agy)" "$(HB 1 agy)"
  check "A18: one handed-back agy task leaves the lane open" "$(breaker agy)" "lane-breaker agy state=open handbacks=1"
  ledger "$(AS 1 agy)" "$(HB 1 agy)" "$(HB 1 agy)"
  check "A18: the same task handed back twice counts once" "$(breaker agy)" "lane-breaker agy state=open handbacks=1"
  ledger "$(HB 1 agy)" "$(HB 2 codex)" "$(HB 3 codex)"
  check "A18: codex handbacks do not count against agy" "$(breaker agy)" "lane-breaker agy state=open handbacks=1"
  ledger "$(HB 1 agy)" "$(HB 2 agy)"
  check "A18: two handed-back agy tasks trip the breaker" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=2"
  ledger "$(HB 1 agy)" "$(HB 10 agy)"
  check "A18: Task 10 is not Task 1" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=2"
  ledger "Plan: executor agy off - unreliable (2 handbacks)"
  check "A18: a resumed controller reading only the plan line keeps the lane off" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=0"
  check "A18: and it is a new process each time: the answer is the ledger's" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=0"
  check "A18: the plan line does not turn codex off" "$(breaker codex)" "lane-breaker codex state=open handbacks=0"
  ledger "$(HB 1 agy)" "$(HB 2 agy)" 'Plan: executor agy off - unreliable (2 handbacks)'
  check "A18: with the plan line and two handbacks it stays tripped" "$(breaker agy)" "lane-breaker agy state=tripped handbacks=2"
  lane=$(doc "$PLUGIN/reference/executor-lane.md")
  has "A18: the lane reference states the ledger line" "$lane" 'Plan: executor agy off - unreliable (2 handbacks)'
  has "A18: and sends a tripped agy task to its Implementer agent" "$lane" "On \`state=tripped\` run neither the gate, the roster nor the wrapper: dispatch the task's \`**Implementer:**\` agent"
  has "A18: and tells a resumed controller the ledger is enough" "$lane" "A resumed controller needs nothing more"
fi

# ---------------------------------------------------------------- A19
if selected A19; then
  ref="$PLUGIN/reference/executor-lane.md"
  section=$(tr -d '\r' < "$ref" | awk '/^## Per-executor: agy$/ { f = 1; next } f && /^## / { exit } f' | tr '\n' ' ' | tr -s ' ')
  check "A19: the lane reference has a Per-executor: agy section" "$(grep -c '^## Per-executor: agy' "$ref")" "1"
  matches "A19: the section states agy is unsandboxed" "$section" '[Uu]nsandboxed'
  matches "A19: the section states the fingerprints cover only the linked worktree and its refs" "$section" 'fingerprints cover only the linked worktree and its refs'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
