#!/usr/bin/env bash
# Acceptance tests for the review-depth spec
# (docs/dforge/specs/2026-10-27-review-depth-design.md), statements A1-A16.
# Each test is written from the statement's text and reaches the behaviour
# through the scripts the spec names (depth-route, review-route, lens-route,
# plan-lint) or, where the statement is about what a skill tells a session to
# do, through the line grammar the shipped skills and references must carry.
# Usage:
#   bash review-depth.acceptance.test.sh            run every test
#   bash review-depth.acceptance.test.sh A5 A9      run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
S="$PLUGIN/scripts"
DEPTH="$S/depth-route"
ROUTE="$S/review-route"
LENS="$S/lens-route"
LINT="$S/plan-lint"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n' "$1" "$3"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
matches() { # matches <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n' "$1" "$3"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
# MSYS_NO_PATHCONV below hands git.exe this path untranslated, so it must be a
# Windows path or git initialises a repository somewhere else.
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR DFORGE_LENS_CAP
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export DFORGE_LENS_MINOR_FROM=0
# No session gate file exists, so every plan round routes with reason=codex-off.
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=review-depth-acceptance
printf '%s\n' '#!/usr/bin/env bash' "echo '[{\"id\":\"codex\",\"usable\":true,\"reason\":null}]'" > "$TMP/roster-stub"
export PLAN_LINT_ROSTER="$TMP/roster-stub"

doc() { tr -d '\r' < "$1" | tr '\n' ' ' | tr -s ' '; } # a file as one line, whitespace collapsed
between() { # between <text> <start> <end> — the text after the first <start> up to the next <end>
  local t=${1#*"$2"}
  [ "$t" != "$1" ] || { printf ''; return 0; }
  printf '%s' "${t%%"$3"*}"
}

# --- fixtures: a repository holding specs and plans ------------------------

R="$TMP/repo"
git init -q "$R"
git -C "$R" config user.email t@example.com
git -C "$R" config user.name t
git -C "$R" commit -q --allow-empty -m base
mkdir -p "$R/docs/dforge/specs" "$R/docs/dforge/plans"

mkspec() { # mkspec <file> [<Depth line>]
  { printf '# Fixture spec\n\n**Execution strategy:** parallel\n\n'
    [ -z "${2:-}" ] || printf '%s\n\n' "$2"
    printf '## Decisions\n\nFinish: merge\n\n## Problem\n\nSecurity, data loss and migration risk are named here on purpose.\n'
  } > "$R/docs/dforge/specs/$1"
}
mkspec spec-light.md '**Depth:** light — unenumerable'
mkspec spec-standard.md '**Depth:** standard — interface (set by hand)'
mkspec spec-full.md '**Depth:** full — risk'
mkspec spec-owner.md '**Depth:** light — owner'
mkspec spec-none.md
mkspec spec-weird.md '**Depth:** medium — nothing'

# mkplan <file> <spec file|-> <host|-> <task>... — a task is a risk digit, big
# (risk 1 with a total of 8), none (no Evaluation line) or bad (one that does
# not parse).
mkplan() {
  local f=$1 spec=$2 host=$3 i=0 t
  shift 3
  {
    printf '# Fixture Plan\n\n'
    [ "$host" = - ] || printf 'Host: codex\n\n'
    printf '**Goal:** Fixture.\n\n'
    [ "$spec" = - ] || printf '**Spec:** docs/dforge/specs/%s\n\n' "$spec"
    printf '**Execution:** subagent — `claude --model sonnet --effort high` — fixture\n\n'
    printf '**Parallelism:** sequential — fixture\n\n'
    [ -z "${PLAN_REVIEW:-}" ] || printf '%s\n\n' "$PLAN_REVIEW"
    printf '## Task index\n\n'
    for t in "$@"; do i=$((i + 1)); printf '%d. task %d\n' "$i" "$i"; done
    printf '\n'
    i=0
    for t in "$@"; do
      i=$((i + 1))
      printf '### Task %d: task %d\n\n' "$i" "$i"
      case $t in
        none) ;;
        bad) printf '**Evaluation:** not a score\n\n' ;;
        big) printf '**Evaluation:** files 3 - spec 3 - coupling 1 - risk 1 = 8\n\n' ;;
        *) printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk %d = %d\n\n' "$t" "$t" ;;
      esac
    done
  } > "$R/docs/dforge/plans/$f"
}

dt() { out=$(cd "$R" && timeout 60 bash "$DEPTH" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
depth_of() { # depth_of <plan file> — the depth-route line for a plan in the fixture repository
  dt "docs/dforge/plans/$1"
}
rr() { out=$(cd "$R" && timeout 60 bash "$ROUTE" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
lr() { out=$(cd "$R" && timeout 60 bash "${LENS_SCRIPT:-$LENS}" "$@" 2>"$TMP/err"); rc=$?; err=$(cat "$TMP/err"); }
short() { sed -E 's/ criteria=[^ ]*//; s/ seat=[^ ]*//; s/ reason=(always|added|ui-paths|paths:[^ ]*)$//' | tr '\n' ';'; }

# --- A1-A6, A13, A16: depth-route ------------------------------------------

a1() {
  local row list depth reason
  for row in \
    "risk|full|risk" "new-subsystem|full|new-subsystem" \
    "risk,new-subsystem|full|risk,new-subsystem" "new-subsystem,risk|full|risk,new-subsystem" \
    "asked,interface,risk|full|risk" "interface,new-subsystem|full|new-subsystem" \
    "interface|standard|interface" "asked,interface|standard|interface" \
    "unenumerable|light|unenumerable" "asked|light|asked" \
    "approach,intricate,asked|light|approach,intricate,asked"; do
    IFS='|' read -r list depth reason <<<"$row"
    dt --spec-triggers "$list"
    check "A1: [$list] routes depth=$depth reason=$reason" "$rc:$out" "0:depth=$depth reason=$reason"
  done
}

a2() {
  local list
  dt --spec-triggers ""
  check "A2: an empty list exits 2" "$rc" "2"
  check "A2: an empty list prints nothing on stdout" "$out" ""
  has "A2: an empty list is refused in depth-route's voice" "$err" "depth-route:"
  dt --spec-triggers
  check "A2: a missing list exits 2" "$rc" "2"
  check "A2: a missing list prints no depth= line" "$(grep -c '^depth=' <<<"$out")" "0"
  for list in bogus risk,bogus bogus,risk Risk; do
    dt --spec-triggers "$list"
    check "A2: [$list] exits 2" "$rc" "2"
    check "A2: [$list] prints no depth= line" "$(grep -c 'depth=' <<<"$out")" "0"
    has "A2: [$list] names the unknown id" "$err" "unknown trigger:"
  done
}

a3() {
  mkplan p3a.md spec-light.md - 0 3 1
  depth_of p3a.md
  check "A3: a task at risk 3 gives full" "$rc:$out" "0:depth=full spec=light tasks=full reason=task-risk:2"
  mkplan p3b.md spec-light.md - 1 2 0 2
  depth_of p3b.md
  check "A3: a highest risk of 2 gives standard" "$rc:$out" "0:depth=standard spec=light tasks=standard reason=task-risk:2"
  mkplan p3c.md spec-light.md - 0 1 1
  depth_of p3c.md
  check "A3: a highest risk of 1 gives light" "$rc:$out" "0:depth=light spec=light tasks=light reason=spec,task-risk:2"
  mkplan p3d.md spec-standard.md - 0 1
  depth_of p3d.md
  check "A3: the spec's standard outranks light tasks" "$rc:$out" "0:depth=standard spec=standard tasks=light reason=spec"
  mkplan p3e.md spec-standard.md - 1 3
  depth_of p3e.md
  check "A3: a risk-3 task outranks the spec's standard" "$rc:$out" "0:depth=full spec=standard tasks=full reason=task-risk:2"
  mkplan p3f.md spec-full.md - 2
  depth_of p3f.md
  check "A3: the spec's full outranks standard tasks" "$rc:$out" "0:depth=full spec=full tasks=standard reason=spec"
  mkplan p3g.md spec-standard.md - 2 0
  depth_of p3g.md
  check "A3: equal inputs name both" "$rc:$out" "0:depth=standard spec=standard tasks=standard reason=spec,task-risk:1"

  # An amendment that raises a task is read: the plan with its amendments applied.
  mkplan p3h.md spec-light.md - 1 1
  depth_of p3h.md
  check "A3: before the amendment the plan is light" "$rc:$out" "0:depth=light spec=light tasks=light reason=spec,task-risk:1"
  mkdir -p "$R/.dforge/sdd/p3h"
  {
    printf '## A1 — Task 2\n\n### Old\n\n````\n'
    printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk 1 = 1\n'
    printf '````\n\n### New\n\n````\n'
    printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3\n'
    printf '````\n'
  } > "$R/.dforge/sdd/p3h/amendments.md"
  depth_of p3h.md
  check "A3: an amendment that raises Task 2 to risk 3 gives full" "$rc:$out" "0:depth=full spec=light tasks=full reason=task-risk:2"
  rm -rf "$R/.dforge/sdd/p3h"
}

a4() {
  local i args=()
  for i in $(seq 1 40); do
    if [ $((i % 5)) -eq 0 ]; then args+=(big); else args+=($((i % 2))); fi
  done
  mkplan p4.md spec-light.md - "${args[@]}"
  check "A4: the fixture holds 40 tasks" "$(grep -c '^### Task ' "$R/docs/dforge/plans/p4.md")" "40"
  check "A4: and tasks with a total of 8" "$(grep -c '= 8$' "$R/docs/dforge/plans/p4.md")" "8"
  depth_of p4.md
  check "A4: 40 tasks at risk 1 or below stay light" "$rc:$out" "0:depth=light spec=light tasks=light reason=spec,task-risk:1"
}

a5() {
  mkplan p5a.md spec-none.md - 0
  depth_of p5a.md
  check "A5: a spec with no Depth line is full" "$rc:$out" "0:depth=full spec=none tasks=light reason=no-spec-depth"
  mkplan p5b.md - - 0
  depth_of p5b.md
  check "A5: a plan with no Spec line is full" "$rc:$out" "0:depth=full spec=none tasks=light reason=no-spec-depth"
  mkplan p5c.md missing.md - 0
  depth_of p5c.md
  check "A5: a Spec path that cannot be read is full" "$rc:$out" "0:depth=full spec=none tasks=light reason=no-spec-depth"
  mkplan p5d.md spec-weird.md - 0
  depth_of p5d.md
  check "A5: a Depth word outside the three is full" "$rc:$out" "0:depth=full spec=none tasks=light reason=no-spec-depth"
  mkplan p5e.md spec-light.md - 0 none 1
  depth_of p5e.md
  check "A5: a task with no Evaluation line is full" "$rc:$out" "0:depth=full spec=light tasks=full reason=unscored:2"
  mkplan p5f.md spec-light.md - 0 1 bad
  depth_of p5f.md
  check "A5: a task whose Evaluation does not parse is full" "$rc:$out" "0:depth=full spec=light tasks=full reason=unscored:3"
  mkplan p5g.md spec-light.md codex 0
  depth_of p5g.md
  check "A5: a Host: codex plan is full" "$rc:$out" "0:depth=full spec=light tasks=light reason=codex-host"
}

a6() {
  mkplan p6a.md spec-full.md - 0 0
  depth_of p6a.md
  check "A6: a full spec with every task at risk 0 stays full" "$rc:$out" "0:depth=full spec=full tasks=light reason=spec"
  mkplan p6b.md spec-full.md - 0 1 1
  depth_of p6b.md
  check "A6: and with tasks at risk 1" "$rc:$out" "0:depth=full spec=full tasks=light reason=spec"
}

a13() {
  mkplan p13a.md spec-owner.md - 0 1
  depth_of p13a.md
  check "A13: an owner line reads as spec=light whatever the spec says of its risks" "$rc:$out" "0:depth=light spec=light tasks=light reason=spec,task-risk:2"
  mkplan p13b.md spec-owner.md - 0 2
  depth_of p13b.md
  check "A13: a task at risk 2 still raises it to standard" "$rc:$out" "0:depth=standard spec=light tasks=standard reason=task-risk:2"
  mkplan p13c.md spec-owner.md - 3 0
  depth_of p13c.md
  check "A13: a task at risk 3 still raises it to full" "$rc:$out" "0:depth=full spec=light tasks=full reason=task-risk:1"
}

a16() {
  mkplan p16a.md spec-standard.md - 0
  depth_of p16a.md
  check "A16: a Depth line is read by its first word" "$rc:$out" "0:depth=standard spec=standard tasks=light reason=spec"

  . "$HERE/fixtures/darkmem-stores.sh"
  local SH="$TMP/stores-home" SR="$TMP/stores-repo" M
  mkdir -p "$SH"
  git init -q "$SR"
  M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
  mkdir -p "$M/dforge/specs" "$M/dforge/plans" "$SR/docs/dforge/specs"
  printf '# Spec\n\n**Depth:** light — unenumerable\n' > "$M/dforge/specs/s.md"
  printf '# Stale local copy\n\n**Depth:** full — risk\n' > "$SR/docs/dforge/specs/s.md"
  {
    printf '# P\n\n**Goal:** Fixture.\n\n**Spec:** docs/dforge/specs/s.md\n\n## Task index\n\n1. one\n\n'
    printf '### Task 1: one\n\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n'
  } > "$M/dforge/plans/p.md"
  out=$(cd "$SR" && HOME="$SH" timeout 60 bash "$DEPTH" docs/dforge/plans/p.md 2>"$TMP/err"); rc=$?
  check "A16: a Spec path in the darkmem mirror resolves as plan-lint resolves it" "$rc:$out" \
    "0:depth=light spec=light tasks=light reason=spec,task-risk:1"
  out=$(cd "$SR" && HOME="$SH" timeout 60 bash "$LINT" docs/dforge/plans/p.md --no-probe 2>&1)
  check "A16: plan-lint finds the plan and resolves the same path" "$(grep -c -e 'Spec path does not exist' -e 'No such plan file' <<<"$out")" "0"
}

# --- A7: review-route's plan-round cap -------------------------------------

a7() {
  mkplan p7l.md spec-light.md - 0 1
  mkplan p7s.md spec-standard.md - 1
  mkplan p7f.md spec-full.md - 0
  rr docs/dforge/plans/p7l.md --plan-round 1
  check "A7: light round 1 routes to no seat, cap 0" "$rc:$out" "0:review-seat plan-round=1 primary=none fallback=- reason=depth-light cap=0"
  rr docs/dforge/plans/p7l.md --plan-round 2
  check "A7: light round 2 exits 2" "$rc" "2"
  has "A7: and says the round is past the cap" "$err" "plan round 2 is past the cap (0)"
  rr docs/dforge/plans/p7s.md --plan-round 1
  check "A7: standard round 1 has cap 1" "$rc:$out" "0:review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=codex-off cap=1"
  rr docs/dforge/plans/p7s.md --plan-round 2
  check "A7: standard round 2 exits 2" "$rc" "2"
  rr docs/dforge/plans/p7f.md --plan-round 1
  check "A7: full round 1 has cap 2" "$rc:$out" "0:review-seat plan-round=1 primary=dforge:judge-opus fallback=- reason=codex-off cap=2"
  rr docs/dforge/plans/p7f.md --plan-round 2
  check "A7: full round 2 is a round within cap 2" "$rc:$out" "0:review-seat plan-round=2 primary=dforge:judge-opus fallback=- reason=round cap=2"
  rr docs/dforge/plans/p7f.md --plan-round 3
  check "A7: full round 3 exits 2" "$rc" "2"

  # A Host: codex plan keeps its own cap rule, from its highest raw total.
  local spec
  for spec in spec-light.md -; do
    {
      printf '# Native Fixture\n\n**Host:** codex\n**Routing policy:** codex-v4\n'
      [ "$spec" = - ] || printf '**Spec:** docs/dforge/specs/%s\n' "$spec"
      printf '**Execution:** inline — codex gpt-6.1-sol / high — x\n\n### Task 1: low\n\n'
      printf '**Implementer:** codex gpt-6-luna / high\n'
      printf '**Evaluation:** files=0, spec=0, coupling=0, risk=0; weighted routing score=0\n'
      printf '**Assignment source:** rubric\n'
    } > "$R/docs/dforge/plans/p7n${spec%%.*}.md"
  done
  rr docs/dforge/plans/p7nspec-light.md --plan-round 1
  local with=$out
  rr docs/dforge/plans/p7n-.md --plan-round 1
  check "A7: a Codex plan's round 1 does not read the spec's depth" "$with" "$out"
  matches "A7: and keeps the cap its raw total sets (1)" "$with" 'plan-round=1 primary=native:[^ ]+ fallback=- reason=round cap=1$'
  rr docs/dforge/plans/p7nspec-light.md --plan-round 2
  matches "A7: a Codex plan keeps its cap-critical round" "$rc:$out" '^0:review-seat plan-round=2 .* reason=cap-critical cap=1$'
}

# --- A8: lens-route at each depth ------------------------------------------

a8() {
  local base head out_full out_std
  base=$(git -C "$R" rev-parse HEAD)
  mkdir -p "$R/scripts" "$R/tests"
  printf 'echo hi 2>/dev/null\n' > "$R/scripts/foo.sh"
  printf 'print(1)\n' > "$R/scripts/foo.py"
  printf 'try { run() } catch (e) {}\n' > "$R/tests/a.test.ts"
  printf 'Docs.\n' > "$R/NOTES.md"
  git -C "$R" add scripts tests NOTES.md
  git -C "$R" commit -q -m lens-fixture
  head=$(git -C "$R" rev-parse HEAD)
  mkplan p8l.md spec-light.md - 0 1
  mkplan p8s.md spec-standard.md - 1
  mkplan p8f.md spec-full.md - 0

  lr docs/dforge/plans/p8f.md --final "$base" "$head"
  out_full=$out
  check "A8: full prints every lens up to the cap of 4, the rest skipped for the cap" "$(short <<<"$out_full")" \
    "lens security;lens silent-failures;lens test-quality;lens lang-bash;lens-skipped lang-python reason=cap;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"

  lr docs/dforge/plans/p8l.md --final "$base" "$head"
  check "A8: light prints a lens line for security alone" "$(grep -c '^lens ' <<<"$out")" "1"
  check "A8: light keeps security" "$(grep -c '^lens security ' <<<"$out")" "1"
  check "A8: light skips every other applicable lens for the depth" "$(short <<<"$out")" \
    "lens security;lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped lang-bash reason=depth;lens-skipped lang-python reason=depth;lens-skipped lang-typescript reason=depth;lens-skipped docs-comments reason=depth;"
  check "A8: light skips no lens for the cap" "$(grep -c 'reason=cap' <<<"$out")" "0"

  lr docs/dforge/plans/p8s.md --final "$base" "$head"
  out_std=$out
  check "A8: standard prints at most 2 lens lines" "$(grep -c '^lens ' <<<"$out_std")" "2"
  check "A8: standard skips the rest for the cap" "$(short <<<"$out_std")" \
    "lens security;lens silent-failures;lens-skipped test-quality reason=cap;lens-skipped lang-bash reason=cap;lens-skipped lang-python reason=cap;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
  out=$(cd "$R" && DFORGE_LENS_CAP=1 timeout 60 bash "$LENS" docs/dforge/plans/p8s.md --final "$base" "$head" 2>&1)
  check "A8: standard with lensCap 1 prints 1 lens line" "$(grep -c '^lens ' <<<"$out")" "1"

  out=$(cd "$R" && DFORGE_LENS_CAP=0 timeout 60 bash "$LENS" docs/dforge/plans/p8l.md --final "$base" "$head" 2>&1)
  check "A8: lenses off is unchanged at light" "$out" "lenses off"

  # Security prints only when its Applies clause matches: a copy of the lenses
  # whose security lens applies to nothing in this change.
  local copy="$TMP/plugin-copy"
  mkdir -p "$copy"
  cp -R "$S" "$copy/scripts"
  cp -R "$PLUGIN/criteria" "$PLUGIN/config" "$copy/"
  sed -i.bak 's#^Applies: .*#Applies: paths docs/never/*#' "$copy/criteria/lenses/security.md"
  LENS_SCRIPT="$copy/scripts/lens-route" lr docs/dforge/plans/p8l.md --final "$base" "$head"
  check "A8: light prints no security line when its clause does not match" "$(grep -c 'security' <<<"$out")" "0"
  check "A8: and still skips the other lenses for the depth" "$(grep -c '^lens-skipped .* reason=depth$' <<<"$out")" "6"
  LENS_SCRIPT="$copy/scripts/lens-route" lr docs/dforge/plans/p8f.md --final "$base" "$head"
  check "A8: full is unchanged without a matching security lens" "$(grep -c '^lens ' <<<"$out")" "4"
}

# --- text statements: the line grammar the shipped skills carry ------------

BS="$PLUGIN/skills/brainstorming/SKILL.md"
UD="$PLUGIN/skills/using-dforge/SKILL.md"
AR="$PLUGIN/reference/auto-run.md"
WP="$PLUGIN/skills/writing-plans/SKILL.md"
HO="$PLUGIN/skills/handoff/SKILL.md"
FR="$PLUGIN/reference/final-review.md"
EP="$PLUGIN/skills/executing-plans/SKILL.md"
SD="$PLUGIN/skills/subagent-driven-development/SKILL.md"
. "$HERE/fixtures/sdd-text.sh"
FIN="$PLUGIN/skills/finishing-a-development-branch/SKILL.md"

a9() {
  local bs
  bs=$(doc "$BS")
  has "A9: brainstorming reports the skipped critic at light" "$bs" 'Critic: skipped (depth light)'
  lacks "A9: the fold no longer keys on the Process line's triggers" "$bs" 'names neither irreducible risk nor a new'
  matches "A9: the spec review message carries the depth" "$bs" 'Depth: <[a-z]+> — <reason'
  has "A9: standard runs no second Fable round" "$bs" 'No second Fable round runs at standard'
  has "A9: full keeps the separate critic" "$bs" 'At `full`, the separate critic round runs, then Fable for one or two rounds'
  has "A9: the fold is decided by the depth, not the trigger list" "$bs" 'The depth decides, not the trigger list'
}

a10() {
  local wp ho out_with out_without
  wp=$(doc "$WP"); ho=$(doc "$HO")
  has "A10: writing-plans records the skipped plan review at light" "$wp" '**Plan review:** <YYYY-MM-DD> — skipped (depth light)'
  has "A10: writing-plans runs the handoff steps first" "$wp" 'handoff steps 0-4'
  has "A10: a light plan of 1-3 tasks is the one that continues" "$wp" 'A light plan of 1-3 tasks runs'
  has "A10: and measures the budget with plain context-size" "$wp" 'plain `scripts/context-size`'
  has "A10: and continues in the session only on ok" "$wp" 'On `ok`, say in one line'
  has "A10: and ends as a handoff on any other result" "$wp" 'On any other result, run handoff step 5'
  has "A10: a light plan skips the Codex gate probe" "$wp" "At depth light (step 1's line) skip \`scripts/codex-gate\`"
  has "A10: standard and full keep the hard stop" "$wp" 'The exception is a plan at depth light, which is no hard stop outside an auto run'
  has "A10: a light plan of 4 or more tasks keeps the handoff" "$wp" 'A light plan of 4 or more tasks still ends with dforge:handoff as above.'
  has "A10: handoff makes a light plan a stop only from 4 tasks or without room" "$ho" 'A saved plan at depth light is a stop only when it has 4 or more tasks'
  lacks "A10: handoff no longer calls every saved plan a hard stop" "$ho" '(plan saved outside an auto run, or a switch'

  mkplan p10.md spec-light.md - 0
  out_without=$(cd "$R" && timeout 60 bash "$LINT" docs/dforge/plans/p10.md --no-probe 2>&1)
  has "A10: plan-lint warns while the header has no Plan review line" "$out_without" 'no **Plan review:** line yet'
  PLAN_REVIEW='**Plan review:** 2026-10-27 — skipped (depth light)' mkplan p10b.md spec-light.md - 0
  out_with=$(cd "$R" && timeout 60 bash "$LINT" docs/dforge/plans/p10b.md --no-probe 2>&1)
  lacks "A10: plan-lint accepts the skipped line with no Plan review warning" "$out_with" 'no **Plan review:** line yet'
  check "A10: and no header warning mentions it" "$(grep -ci 'WARN header.*plan review' <<<"$out_with")" "0"
}

a11() {
  local fr ep sd head0 step05 step2
  fr=$(doc "$FR"); ep=$(doc "$EP"); sd=$(doc "$SDD_LEDGER")
  has "A11: final-review.md skips acceptance QA at light with the ledger line" "$fr" 'Acceptance QA: skipped (depth light)'
  matches "A11: recovery treats the skipped line as complete" "$fr" 'skipped \(depth light\).{0,300}complete|complete.{0,300}skipped \(depth light\)'
  has "A11: the Codex round skipped is said in one line" "$fr" 'codex round skipped (depth'
  has "A11: the review logs its depth" "$fr" 'Review depth: <'
  head0=${fr%%'0. **Gates.**'*}
  has "A11: the depth is logged before step 0" "$head0" 'Review depth: <'
  step05=$(between "$fr" '- 0.5 **Acceptance QA.**' '1. **Claude review.**')
  has "A11: step 0.5 carries the light skip" "$step05" 'skipped (depth light)'
  step2=$(between "$fr" '2. **Codex round.**' '3. **Wait for QA.**')
  has "A11: step 2 carries the Codex skip" "$step2" 'codex round skipped (depth'
  has "A11: step 2 skips the round at light and at standard" "$step2" 'At depth light or standard, skip it'
  has "A11: step 3 waits for no runner at light or standard" "$(between "$fr" '3. **Wait for QA.**' '**Dedupe and verify')" 'or depth light or standard'
  has "A11: executing-plans lists the Review depth ledger line" "$ep" 'Review depth: <'
  has "A11: executing-plans lists the skipped QA ledger line" "$ep" 'Acceptance QA: skipped (depth light)'
  has "A11: subagent-driven-development lists the Review depth ledger line" "$sd" 'Review depth: <'
  has "A11: and the skipped QA ledger line" "$sd" 'Acceptance QA: skipped (depth light)'
}

a12() {
  local fr gates ui claude claudehead fixwave p bs gate step5 step5rest
  mkplan p12l.md spec-light.md - 0 1
  mkplan p12s.md spec-standard.md - 1
  mkplan p12f.md spec-full.md - 0 1
  for p in p12l p12s p12f; do
    rr "docs/dforge/plans/$p.md" --final
    check "A12: review-route --final still routes the whole-branch Claude review ($p)" "$rc:$out" \
      "0:review-seat final primary=dforge:judge-opus fallback=- reason=plain"
  done
  fr=$(doc "$FR")
  gates=$(between "$fr" '0. **Gates.**' '- 0.2 **UI proof.**')
  ui=$(between "$fr" '- 0.2 **UI proof.**' '- 0.5 **Acceptance QA.**')
  claude=$(between "$fr" 'Then run `scripts/review-route PLAN_FILE --final` and dispatch the `primary` it prints' '2. **Codex round.**')
  claudehead=$(between "$fr" '1. **Claude review.**' '**Lenses.**')
  fixwave=${fr#*'## Fixing what it finds'}
  bs=$(doc "$BS")
  gate=$(between "$bs" 'In an auto run (`scripts/auto-run status` exits 0), skip this gate' 'Otherwise, after posting')
  step5=$(between "$bs" '5. **The spec review**, the one stop' '6. **Start the run.**')
  step5rest=${step5//'`specReview=false` does not skip this stop'/}
  check "A12: the Gates step is found" "$([ -n "$gates" ] && echo yes || echo no)" "yes"
  check "A12: the UI proof step is found" "$([ -n "$ui" ] && echo yes || echo no)" "yes"
  check "A12: the Claude review dispatch is found" "$([ -n "$claude" ] && echo yes || echo no)" "yes"
  check "A12: the Claude review heading is found" "$([ -n "$claudehead" ] && echo yes || echo no)" "yes"
  check "A12: the fix wave section is found" "$([ -n "$fixwave" ] && [ "$fixwave" != "$fr" ] && echo yes || echo no)" "yes"
  check "A12: the spec review stop is found" "$([ -n "$step5" ] && echo yes || echo no)" "yes"
  check "A12: the User Review Gate skip rules are found" "$([ -n "$gate" ] && echo yes || echo no)" "yes"
  lacks "A12: gates are not cut by a depth" "$gates" 'depth'
  lacks "A12: the UI proof is not cut by a depth" "$ui" 'depth'
  lacks "A12: the Claude review dispatch is not cut by a depth" "$claude" 'depth'
  lacks "A12: nor is the Claude review dispatch skipped at light" "$claude" 'light'
  lacks "A12: the Claude review heading is not cut by a depth" "$claudehead" 'depth'
  lacks "A12: nor is the Claude review skipped at light" "$claudehead" 'light'
  lacks "A12: the fix wave is not cut by a depth" "$fixwave" 'depth'
  lacks "A12: nor is the fix wave skipped at light" "$fixwave" 'light'
  lacks "A12: the User Review Gate skip rules name no depth" "$gate" 'depth'
  lacks "A12: nor does the gate skip name light" "$gate" 'light'
  has "A12: the spec review stop is not skipped by specReview=false" "$step5" '`specReview=false` does not skip this stop'
  lacks "A12: the spec review stop is not skipped by a depth" "$step5" 'skip the spec review'
  lacks "A12: the spec review stop has no other skip" "$step5rest" 'skip '
  lacks "A12: nor is the stop said to be skipped" "$step5rest" 'is skipped'
  has "A12: the light approve option says the plan is not a stop" "$(doc "$BS")" 'depth light: the plan is not a stop'
}

a14() {
  local ud bs spec_text
  ud=$(doc "$UD"); bs=$(doc "$BS")
  has "A14: using-dforge states the architectural Process line" "$ud" 'Process: architectural, <inline|subagent>, depth <d> — <triggers>'
  has "A14: brainstorming states it too" "$bs" 'Process: architectural, <inline|subagent>, depth <d> — <triggers>'
  matches "A14: brainstorming writes the Depth line" "$bs" '\*\*Depth:\*\* <[^>]+> — <reason'
  matches "A14: and the owner's Depth line" "$bs" '\*\*Depth:\*\* <[^>]+> — owner'
  spec_text="$REPO_ROOT/docs/dforge/specs/2026-10-27-review-depth-design.md"
  check "A14: this spec carries Depth below Execution strategy" \
    "$(awk '/^\*\*Execution strategy:\*\*/ { e = NR } /^\*\*Depth:\*\*/ { d = NR } END { print (e > 0 && d > e) ? "yes" : "no" }' "$spec_text")" "yes"
}

a15() {
  local fr step4 fin ar
  fr=$(doc "$FR"); fin=$(doc "$FIN"); ar=$(doc "$AR")
  step4=$(between "$fr" '4. **Report.**' '## Fixing what it finds')
  check "A15: final-review.md step 4 is found" "$([ -n "$step4" ] && echo yes || echo no)" "yes"
  has "A15: step 4 writes lens-skipped lines to the ledger" "$step4" 'final review lens-skipped'
  lacks "A15: step 4 no longer writes only reason=cap" "$step4" 'lens-skipped <id> reason=cap'
  has "A15: finishing reads the ledger's lens-skipped lines" "$fin" 'final review lens-skipped'
  lacks "A15: finishing no longer reads only reason=cap" "$fin" 'lens-skipped <id> reason=cap'
  lacks "A15: auto-run.md's Finishing no longer reads only reason=cap" "$ar" 'lens-skipped <id> reason=cap'
  has "A15: finishing lists the unverified test statements at light" "$fin" 'not verified (depth light)'
  has "A15: from the statements tagged test" "$fin" 'tagged `test`'
  has "A15: an attended finish lists the lens-skipped lines at Step 3" "$(between "$fin" '**Lenses skipped.**' '## Step 4: Present Options')" 'final review lens-skipped <id> reason=<reason>'
  has "A15: auto-run.md's Finishing lists them too" "$ar" 'not verified (depth light)'
}

ALL="a1 a2 a3 a4 a5 a6 a7 a8 a9 a10 a11 a12 a13 a14 a15 a16"
if [ $# -gt 0 ]; then
  sel=""
  for n in "$@"; do
    n=$(tr 'A-Z' 'a-z' <<<"$n")
    case " $ALL " in
      *" $n "*) sel="$sel $n" ;;
      *) echo "unknown test: $n" >&2; exit 2 ;;
    esac
  done
else
  sel=$ALL
fi
for t in $sel; do "$t"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
