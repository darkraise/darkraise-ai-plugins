#!/usr/bin/env bash
# Acceptance tests for docs/dforge/specs/2026-10-25-typed-seats-and-drafting-design.md
# (the shell-reachable statements: A5, A6, A12, A13, A14 - A7, A9 and A10
# went with the plan drafter; the
# cockpit statements A1-A4 and A8 are in typed-seats-and-drafting.acceptance.test.ts).
# Each test is written from the spec's acceptance statement. Usage:
#   bash typed-seats-and-drafting.acceptance.sh            run every test
#   bash typed-seats-and-drafting.acceptance.sh A9 A10     run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO="$(git -C "$PLUGIN" rev-parse --show-toplevel)"
S="$PLUGIN/scripts"
SEL=("$@")

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
matches() { # matches <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
sel() { # sel <A-id> - whether that test is selected
  [ "${#SEL[@]}" -eq 0 ] && return 0
  local s; for s in "${SEL[@]}"; do [ "$s" = "$1" ] && return 0; done
  return 1
}
section() { # section <file> <heading line> - the lines under it up to the next ## heading, joined to one line
  awk -v h="$2" '$0 == h { on = 1; next } on && /^## / { exit } on { print }' "$1" | tr '\n' ' ' | tr -s ' '
}
fm() { # fm <file> <key> - one scalar key of the YAML frontmatter
  awk -v k="$2" '
    NR == 1 && $0 == "---" { inb = 1; next }
    inb && $0 == "---" { exit }
    inb && index($0, k ":") == 1 { sub("^" k ":[ \t]*", ""); print; exit }
  ' "$1"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

NOTE="$REPO/docs/dforge/notes/2026-10-25-drafter-measurement.md"
RCR="$PLUGIN/skills/requesting-code-review/SKILL.md"
CR="$PLUGIN/skills/requesting-code-review/references/code-reviewer.md"
UD="$PLUGIN/skills/using-dforge/SKILL.md"
WP="$PLUGIN/skills/writing-plans/SKILL.md"

if sel A5; then
  echo "# A5"
  rcr=$(tr '\n' ' ' < "$RCR" | tr -s ' ')
  cr=$(tr '\n' ' ' < "$CR" | tr -s ' ')
  matches "A5: requesting-code-review dispatches dforge:judge-opus" "$rcr" 'Dispatch `dforge:judge-opus`'
  matches "A5: code-reviewer.md names dforge:judge-opus as the seat" "$cr" 'Subagent \(dforge:judge-opus\):'
  absent "A5: requesting-code-review names no general-purpose seat" "$rcr" 'general-purpose'
  absent "A5: code-reviewer.md names no general-purpose seat" "$cr" 'general-purpose'
  matches "A5: requesting-code-review requires the diff file" "$rcr" '`\[DIFF_FILE\]` - REQUIRED'
  matches "A5: requesting-code-review writes the diff file with git diff for BASE..HEAD" "$rcr" 'git diff -U10 "\$BASE_SHA\.\.\$HEAD_SHA"'
  # An em dash is three bytes, so `.` would miss it in the C locale CI runs in.
  matches "A5: code-reviewer.md requires the diff file" "$cr" '`\[DIFF_FILE\]` (-|—) REQUIRED'
  absent "A5: code-reviewer.md offers no none option for the diff file" "$cr" '`none`|"none"'
  absent "A5: code-reviewer.md has no git fallback for the diff" "$cr" 'git diff \[BASE_SHA\]|derive it yourself'

  # The repository check (§1) runs on a copy of the skills, references and the check itself.
  mk() { # mk <dir> - a copy of what the repository check scans
    mkdir -p "$1/tests"
    cp -r "$PLUGIN/skills" "$PLUGIN/reference" "$PLUGIN/README.md" "$1/"
    cp "$HERE/seats.test.sh" "$1/tests/"
  }
  run_seats() { (cd "$1" && timeout 120 bash tests/seats.test.sh >/dev/null 2>&1; echo $?); }
  mk "$TMP/a5-clean"
  check "A5: the repository check passes on the repository as it is" "$(run_seats "$TMP/a5-clean")" "0"

  mk "$TMP/a5-block"
  mkdir -p "$TMP/a5-block/skills/probe"
  cat > "$TMP/a5-block/skills/probe/SKILL.md" <<'EOF'
Dispatch it:

```
Subagent (general-purpose):
  description: "Probe"
  prompt: |
    Probe it.
```
EOF
  check "A5: the repository check fails on a Subagent (general-purpose): block with no model" "$([ "$(run_seats "$TMP/a5-block")" != 0 ] && echo fails || echo passes)" "fails"

  mk "$TMP/a5-row"
  cat > "$TMP/a5-row/reference/probe.md" <<'EOF'
| Seat | Agent | Model argument |
|---|---|---|
| Verifier | general-purpose | None |
EOF
  check "A5: the repository check fails on a Seats row with no model" "$([ "$(run_seats "$TMP/a5-row")" != 0 ] && echo fails || echo passes)" "fails"

  mk "$TMP/a5-ok"
  mkdir -p "$TMP/a5-ok/skills/probe"
  cat > "$TMP/a5-ok/skills/probe/SKILL.md" <<'EOF'
```
Subagent (general-purpose):
  description: "Probe"
  model: sonnet
  prompt: |
    Probe it.
```

| Seat | Agent | Model argument |
|---|---|---|
| Verifier | general-purpose | `sonnet` |
EOF
  check "A5: the repository check passes a modelled block and row" "$(run_seats "$TMP/a5-ok")" "0"
fi

if sel A6; then
  echo "# A6"
  seats=$(section "$UD" "## Seats")
  matches "A6: using-dforge has a Seats section" "$seats" '.'
  matches "A6: typed seats only - a dforge: agent or a typed built-in" "$seats" 'names a seat: a `dforge:` agent or a typed built-in'
  matches "A6: general-purpose takes an explicit model" "$seats" '`general-purpose` takes an explicit `model`'
  decision=$(grep -m1 '^\*\*Decision:\*\*' "$NOTE" | sed 's/^\*\*Decision:\*\* *//')
  if [ "$decision" = typed ]; then
    matches "A6: forks are not allowed (no fork drafter was picked)" "$seats" 'No forks'
  else
    matches "A6: forks only for drafting (fork drafters were picked)" "$seats" '[Ff]orks?.*draft'
  fi
  matches "A6: read-only checks (register rows) go to a judge seat" "$seats" 'Read-only checks \(register rows[^)]*\) go to `dforge:judge-sonnet-high`'
  matches "A6: judge-opus for checks across several files" "$seats" '`dforge:judge-opus` across several files'
fi

if sel A12; then
  echo "# A12"
  # The note's table: Run | USD total | USD per task | lint errors | lint warnings | Critical | Important | Messages
  row() { awk -F'|' -v r="$1" -v c="$2" '{ k = $2; gsub(/ /, "", k) } k == r { v = $c; gsub(/ /, "", v); print v; exit }' "$NOTE"; }
  fork_cost=$(row fork 4); typed_cost=$(row typed 4)
  fork_crit=$(row fork 7); typed_crit=$(row typed 7)
  fork_imp=$(row fork 8); typed_imp=$(row typed 8)
  picked=$(awk -v tc="$typed_cost" -v fc="$fork_cost" -v tk="$typed_crit" -v fk="$fork_crit" -v ti="$typed_imp" -v fi="$fork_imp" '
    BEGIN { if (tc + 0 > fc + 0 || tk + 0 > fk + 0 || (ti + 0) - (fi + 0) > 1) print "fork"; else print "typed" }')
  decision=$(grep -m1 '^\*\*Decision:\*\*' "$NOTE" | sed 's/^\*\*Decision:\*\* *//')
  matches "A12: the note records both runs' figures" "$fork_cost $typed_cost $fork_crit $typed_crit $fork_imp $typed_imp" '^[0-9.]+ [0-9.]+ [0-9]+ [0-9]+ [0-9]+ [0-9]+$'
  check "A12: the rule applied to the note's own figures picks the note's decision" "$picked" "$decision"
  check "A12: the note's decision is typed (typed costs less per task, no extra Critical, no extra Important)" "$decision" "typed"
  check "A12: the per-task cost is the run's total over its six tasks (typed)" "$(awk -v t="$(row typed 3)" -v p="$typed_cost" 'BEGIN { printf "%.2f", t / 6 }')" "$typed_cost"
  check "A12: the per-task cost is the run's total over its six tasks (fork)" "$(awk -v t="$(row fork 3)" -v p="$fork_cost" 'BEGIN { printf "%.2f", t / 6 }')" "$fork_cost"
  matches "A12: the note states the tie goes to the typed drafter" "$(tr '\n' ' ' < "$NOTE" | tr -s ' ')" 'a tie goes to the typed drafter'
  check "A12: the Critical findings the note lists match its counts (fork)" "$(grep -c '^- Fork review Critical' "$NOTE")" "$fork_crit"
  check "A12: the Critical findings the note lists match its counts (typed)" "$(grep -c '^- Typed review Critical' "$NOTE")" "$typed_crit"
  # Forks still do not draft; the typed drafter itself was removed when plans
  # came to be drafted in the session.
  ff=$(grep -E '^export const FORK_DRAFTING = ' "$PLUGIN/hooks/cockpit/lib.ts" | sed 's/.*= *//')
  check "A12: the cockpit's FORK_DRAFTING is false" "$ff" "false"
fi

if sel A13; then
  echo "# A13"
  base=$(git -C "$REPO" merge-base HEAD main)
  check "A13: the branch never touched the measured plan" "$(git -C "$REPO" diff --name-only "$base" HEAD -- docs/dforge/plans/2026-10-24-ui-ux-skill.md | wc -l | tr -d ' ')" "0"
  check "A13: the branch committed no plan trimmed to six tasks or any file under .dforge/" "$(git -C "$REPO" diff --name-only "$base" HEAD | grep -cE '^\.dforge/|drafts/tasks-')" "0"
  check "A13: no drafts directory is left in the checkout's state directory" "$([ -e "$(cd "$REPO" && bash "$S/dforge-path" state)/drafts" ] && echo present || echo absent)" "absent"
  check "A13: no stray worktree of a measurement run is registered" "$(git -C "$REPO" worktree list --porcelain | grep '^worktree ' | grep -ciE 'drafter|measure|scratch|clone')" "0"
  check "A13: no measurement branch exists" "$(git -C "$REPO" branch --list | grep -ciE 'measure|drafter-|scratch')" "0"
  check "A13: the tracked tree has no draft slice file" "$(git -C "$REPO" ls-files | grep -cE 'tasks-[0-9]+-[0-9]+\.md$')" "0"
  matches "A13: the note reports its subject as a trimmed copy, not the real plan" "$(tr '\n' ' ' < "$NOTE" | tr -s ' ')" 'trimmed to its header and Task index rows 1-6'
fi

if sel A14; then
  echo "# A14"
  dt=$(section "$WP" "## Drafting the tasks")
  matches "A14: writing-plans has the session draft every task, on any host" "$dt" 'Draft every task in the session, at any plan size.'
  check "A14: no Codex reference dispatches a drafting seat" "$(grep -rilE 'drafter|drafting seat' "$PLUGIN/reference"/*codex* "$PLUGIN/.codex-plugin" 2>/dev/null | wc -l | tr -d ' ')" "0"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
