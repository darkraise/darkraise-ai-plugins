#!/usr/bin/env bash
# Acceptance tests for the review-depth spec
# (docs/dforge/specs/2026-10-27-review-depth-design.md), statements A1-A8,
# A10, A12, A13 and A16. Written from the statements' text and run through the
# public surface: depth-route, review-route, lens-route and plan-lint as
# commands.
# Usage:
#   bash review-depth-qa.acceptance.test.sh            run every test
#   bash review-depth-qa.acceptance.test.sh A5 A9      run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
S="$PLUGIN/scripts"
DR="$S/depth-route"
ROUTE="$S/review-route"
LENS="$S/lens-route"
LINT="$S/plan-lint"
BASE_SHA=7884cb791eb6e397f72306f5db8db796f6129034

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%.600s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected match: [%s]\n       in: [%.600s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
# MSYS_NO_PATHCONV below hands git.exe this path untranslated, so it must be a
# Windows path or git initialises a repository somewhere else.
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export HOME="$TMP/home"; mkdir -p "$HOME/.claude"
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR DFORGE_LENS_CAP DFORGE_LENS_MINOR_FROM
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 DFORGE_NO_SETTINGS=1 MSYS_NO_PATHCONV=1
export GIT_AUTHOR_NAME=Darkraise GIT_AUTHOR_EMAIL=quangtc94@gmail.com GIT_COMMITTER_NAME=Darkraise GIT_COMMITTER_EMAIL=quangtc94@gmail.com
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" CLAUDE_CODE_SESSION_ID=review-depth-qa

WANT=("$@")
want() { # want <A-id> — true when no filter was given or the id is listed
  local w
  [ ${#WANT[@]} -eq 0 ] && return 0
  for w in "${WANT[@]}"; do [ "$w" = "$1" ] && return 0; done
  return 1
}

# --- fixtures: one repository holding specs and plans ---
REPO="$TMP/repo"
mkdir -p "$REPO/docs/dforge/specs" "$REPO/docs/dforge/plans"
git -C "$REPO" init -q -b main
SPECS="$REPO/docs/dforge/specs"

mkspec() { # mkspec NAME DEPTH_LINE — a spec whose Depth line is DEPTH_LINE ("" for none)
  {
    printf '# Spec %s\n\n**Execution strategy:** sequential\n\n' "$1"
    [ -z "$2" ] || printf '%s\n\n' "$2"
    printf '## Decisions\n\n- x\n\nProcess: architectural, inline, depth full — risk, new-subsystem\n'
  } > "$SPECS/$1.md"
}
mkspec s-light '**Depth:** light — unenumerable'
mkspec s-standard '**Depth:** standard — interface'
mkspec s-full '**Depth:** full — risk'
mkspec s-none ''
mkspec s-owner-light '**Depth:** light — owner'
mkspec s-handset '**Depth:** standard — interface (set by hand)'
mkspec s-badword '**Depth:** fullish — risk'

ev() { # ev TOKEN — rRtT is an Evaluation line at risk R, total T; none omits it; bad does not parse
  case $1 in
    none) ;;
    bad) printf '**Evaluation:** this is not a score\n' ;;
    r*t*) local r=${1#r}; r=${r%%t*}; local t=${1#*t}
      printf '**Evaluation:** files %s - spec 0 - coupling 0 - risk %s = %s\n' "$((t - r))" "$r" "$t" ;;
  esac
}

mkplan() { # mkplan NAME SPEC_NAME|- HOST REVIEW_LINE TOKEN... — a plan in docs/dforge/plans
  local name=$1 spec=$2 host=$3 review=$4 n=0 tok i
  shift 4
  {
    printf '# %s Implementation Plan\n\n' "$name"
    [ "$host" != codex ] || printf 'Host: codex\nRouting policy: codex-v4\n\n'
    printf '**Goal:** Demo.\n\n'
    [ "$spec" = - ] || printf '**Spec:** `docs/dforge/specs/%s.md`\n\n' "$spec"
    printf '**Execution:** inline — `claude --model sonnet --effort high` — demo\n\n'
    [ -z "$review" ] || printf '%s\n\n' "$review"
    printf '## Global Constraints\n\n- None.\n\n## Contracts\n\nNone\n\n## Assumptions (evidence)\n\n- None.\n\n## Task index\n\n'
    for tok in "$@"; do n=$((n + 1)); printf '%s. Thing %s\n' "$n" "$n"; done
    printf '\n'
    i=0
    for tok in "$@"; do
      i=$((i + 1))
      printf '### Task %s: Thing %s\n\n**Files:**\n- Create: `f%s.txt`\n\n**Implementer:** dforge:impl-sonnet-low\n' "$i" "$i" "$i"
      ev "$tok"
      printf '\n- [ ] **Step 1: Do it**\n\n'
    done
  } > "$REPO/docs/dforge/plans/$name.md"
  printf '%s\n' "$REPO/docs/dforge/plans/$name.md"
}

mkcodex() { # mkcodex NAME SPEC_NAME TOTAL — a one-task Host: codex plan whose raw total is TOTAL
  local name=$1 spec=$2 total=$3
  {
    printf '# %s Codex Plan\n\nHost: codex\nRouting policy: codex-v4\n\n**Goal:** Demo.\n\n' "$name"
    printf '**Spec:** `docs/dforge/specs/%s.md`\n\n' "$spec"
    printf '**Execution:** subagent — codex gpt-6.1-sol / high — native pair\n\n'
    printf '**Plan review:** 2026-10-27 — codex gpt-6-astra / high — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)\n\n'
    printf '## Global Constraints\n\n- None.\n\n## Contracts\n\nNone\n\n## Assumptions (evidence)\n\n- None.\n\n## Task index\n\n1. One\n\n'
    printf '### Task 1: One\n\n**Files:**\n- Create: `b.txt`\n\n**Implementer:** codex gpt-6.1-sol / low\n'
    printf '**Evaluation:** files=%s, spec=0, coupling=0, risk=0; weighted routing score=%s\n**Assignment source:** rubric\n' "$total" "$total"
  } > "$REPO/docs/dforge/plans/$name.md"
  printf '%s\n' "$REPO/docs/dforge/plans/$name.md"
}

route() { # route PLAN — sets out and status of depth-route PLAN, run from the repository
  out=$(cd "$REPO" && timeout 60 bash "$DR" "$1" 2>&1); status=$?
}
depth_of() { sed -nE 's/^depth=([a-z]+) .*/\1/p' <<<"$out" | head -n 1; }
spec_of() { sed -nE 's/.* spec=([a-z]+) .*/\1/p' <<<"$out" | head -n 1; }

# A throwaway commit history for the lens cases.
git -C "$REPO" add -A >/dev/null 2>&1
git -C "$REPO" commit -q -m base
BASE_C=$(git -C "$REPO" rev-parse HEAD)
mkdir -p "$REPO/src" "$REPO/tests"
printf '#!/usr/bin/env bash\nfoo 2>/dev/null\n' > "$REPO/src/a.sh"
printf 'print(1)\n' > "$REPO/src/b.py"
printf '# notes\n' > "$REPO/src/notes.md"
printf 'export interface Foo { a: number }\n' > "$REPO/src/c.ts"
printf 'it("x", () => {})\n' > "$REPO/tests/x.test.ts"
git -C "$REPO" add -A >/dev/null 2>&1
git -C "$REPO" commit -q -m head
HEAD_C=$(git -C "$REPO" rev-parse HEAD)

# The code as it stood before the spec, for "unchanged" comparisons.
BASE_DIR="$TMP/base"
have_base=0
if git -C "$REPO_ROOT" cat-file -e "$BASE_SHA^{commit}" 2>/dev/null; then
  mkdir -p "$BASE_DIR"
  if git -C "$REPO_ROOT" archive "$BASE_SHA" plugins/dforge 2>/dev/null | tar -x -C "$BASE_DIR" 2>/dev/null \
     && [ -f "$BASE_DIR/plugins/dforge/scripts/review-route" ]; then have_base=1; fi
fi
[ "$have_base" -eq 1 ] || echo "note: BASE $BASE_SHA is not in this clone; the unchanged-output comparisons are skipped"

# =====================================================================
if want A1; then
  for pair in \
    "risk:full:risk" "new-subsystem:full:new-subsystem" "interface,risk:full:risk" \
    "risk,interface:full:risk" "interface,new-subsystem:full:new-subsystem" \
    "unenumerable,approach,risk:full:risk" "asked,intricate,new-subsystem,approach:full:new-subsystem" \
    "risk,new-subsystem:full:risk"; do
    list=${pair%%:*} rest=${pair#*:} want=${rest%%:*} id=${rest#*:}
    out=$(timeout 30 bash "$DR" --spec-triggers "$list" 2>&1); status=$?
    check "A1: $list exits 0" "$status" 0
    present "A1: $list -> depth=$want" "$out" "^depth=$want reason="
    present "A1: $list reason names $id" "$out" "reason=.*$id"
  done
  for list in interface "interface,unenumerable" "approach,interface,asked" "intricate,interface"; do
    out=$(timeout 30 bash "$DR" --spec-triggers "$list" 2>&1); status=$?
    check "A1: $list exits 0" "$status" 0
    present "A1: $list -> depth=standard" "$out" "^depth=standard reason="
    present "A1: $list reason names interface" "$out" "reason=.*interface"
  done
  for list in unenumerable approach intricate asked "unenumerable,approach" "approach,intricate,asked" "unenumerable,approach,intricate,asked"; do
    out=$(timeout 30 bash "$DR" --spec-triggers "$list" 2>&1); status=$?
    check "A1: $list exits 0" "$status" 0
    present "A1: $list -> depth=light" "$out" "^depth=light reason="
    for id in ${list//,/ }; do present "A1: $list reason names $id" "$out" "reason=.*$id"; done
  done
fi

# =====================================================================
if want A2; then
  for arg in "" "," "bogus" "risk,bogus" "bogus,risk" "Risk" "risk,,bogus" "interface,nope"; do
    out=$(timeout 30 bash "$DR" --spec-triggers "$arg" 2>&1); status=$?
    check "A2: [$arg] exits 2" "$status" 2
    absent "A2: [$arg] prints no depth= line" "$out" "depth="
  done
  out=$(timeout 30 bash "$DR" --spec-triggers 2>&1); status=$?
  check "A2: no list exits 2" "$status" 2
  absent "A2: no list prints no depth= line" "$out" "depth="
fi

# =====================================================================
if want A3; then
  p=$(mkplan a3-light-light s-light - "" r0t1 r1t2 r1t1)
  route "$p"; check "A3: light spec, risks 0-1 -> exit 0" "$status" 0
  check "A3: light spec, risks 0-1 -> light" "$(depth_of)" light
  p=$(mkplan a3-l2 s-light - "" r0t1 r2t4 r1t1)
  route "$p"; check "A3: light spec, highest risk 2 -> standard" "$(depth_of)" standard
  p=$(mkplan a3-l3 s-light - "" r0t1 r2t4 r3t5)
  route "$p"; check "A3: light spec, a risk 3 -> full" "$(depth_of)" full
  p=$(mkplan a3-s0 s-standard - "" r0t1 r1t1)
  route "$p"; check "A3: standard spec, risks 0-1 -> standard" "$(depth_of)" standard
  p=$(mkplan a3-s2 s-standard - "" r2t3 r1t1)
  route "$p"; check "A3: standard spec, highest risk 2 -> standard" "$(depth_of)" standard
  p=$(mkplan a3-s3 s-standard - "" r3t3 r0t1)
  route "$p"; check "A3: standard spec, a risk 3 -> full" "$(depth_of)" full
  p=$(mkplan a3-f0 s-full - "" r0t1)
  route "$p"; check "A3: full spec, risk 0 -> full" "$(depth_of)" full
  p=$(mkplan a3-f3 s-full - "" r3t3)
  route "$p"; check "A3: full spec, a risk 3 -> full" "$(depth_of)" full

  # amendments.md is applied: raising and lowering a task's risk both count.
  p=$(mkplan a3-amend-up s-light - "" r1t2 r1t2)
  route "$p"; check "A3: before the amendment -> light" "$(depth_of)" light
  adir="$REPO/.dforge/sdd/a3-amend-up"; mkdir -p "$adir"
  {
    printf '## A1 — Task 2\n\nReason: scope grew\n\nCost if wrong: none\n\n### Old\n\n````\n'
    printf '**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2\n'
    printf '````\n\n### New\n\n````\n'
    printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3\n'
    printf '````\n'
  } > "$adir/amendments.md"
  route "$p"; check "A3: amendments.md raising a task to risk 3 -> exit 0" "$status" 0
  check "A3: amendments.md raising a task to risk 3 -> full" "$(depth_of)" full
  p=$(mkplan a3-amend-down s-light - "" r3t3 r1t2)
  route "$p"; check "A3: before the lowering amendment -> full" "$(depth_of)" full
  adir="$REPO/.dforge/sdd/a3-amend-down"; mkdir -p "$adir"
  {
    printf '## A1 — Task 1\n\nReason: split off\n\nCost if wrong: none\n\n### Old\n\n````\n'
    printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3\n'
    printf '````\n\n### New\n\n````\n'
    printf '**Evaluation:** files 1 - spec 0 - coupling 0 - risk 1 = 2\n'
    printf '````\n'
  } > "$adir/amendments.md"
  route "$p"; check "A3: amendments.md lowering the risk -> light" "$(depth_of)" light
fi

# =====================================================================
if want A4; then
  toks=()
  for i in $(seq 1 40); do
    case $((i % 4)) in 0) toks+=(r1t8) ;; 1) toks+=(r0t1) ;; 2) toks+=(r1t2) ;; 3) toks+=(r0t8) ;; esac
  done
  p=$(mkplan a4-forty s-light - "" "${toks[@]}")
  route "$p"
  check "A4: 40 tasks at risk <= 1, spec light -> exit 0" "$status" 0
  check "A4: 40 tasks at risk <= 1, totals up to 8, spec light -> light" "$(depth_of)" light
  p=$(mkplan a4-forty-std s-standard - "" "${toks[@]}")
  route "$p"
  check "A4: the same 40 tasks under a standard spec -> standard, not more" "$(depth_of)" standard
  p=$(mkplan a4-one s-light - "" r1t8)
  route "$p"
  check "A4: one task with total 8 at risk 1 -> light" "$(depth_of)" light
fi

# =====================================================================
if want A5; then
  p=$(mkplan a5-control s-light - "" r0t1 r1t2)
  route "$p"; check "A5: control (no defect) is light" "$(depth_of)" light

  p=$(mkplan a5-nodepth s-none - "" r0t1 r0t1)
  route "$p"; check "A5: spec without a Depth line -> exit 0" "$status" 0
  check "A5: spec without a Depth line -> full" "$(depth_of)" full

  p=$(mkplan a5-nospecline - - "" r0t1 r0t1)
  route "$p"; check "A5: plan without a Spec line -> exit 0" "$status" 0
  check "A5: plan without a Spec line -> full" "$(depth_of)" full

  p=$(mkplan a5-unscored s-light - "" r0t1 none r0t1)
  route "$p"; check "A5: an unscored task -> exit 0" "$status" 0
  check "A5: an unscored task -> full" "$(depth_of)" full

  p=$(mkplan a5-unparsable s-light - "" r0t1 bad r0t1)
  route "$p"; check "A5: an unparsable task -> exit 0" "$status" 0
  check "A5: an unparsable task -> full" "$(depth_of)" full

  p=$(mkplan a5-codex s-light codex "" r0t1 r0t1)
  route "$p"; check "A5: Host: codex -> exit 0" "$status" 0
  check "A5: Host: codex (spec light, risks 0) -> full" "$(depth_of)" full

  p=$(mkplan a5-nofile s-missing - "" r0t1)
  route "$p"; check "A5: a spec path that cannot be read -> full" "$(depth_of)" full

  p=$(mkplan a5-badword s-badword - "" r0t1)
  route "$p"; check "A5: a Depth line whose first word is not a depth -> full" "$(depth_of)" full
fi

# =====================================================================
if want A6; then
  p=$(mkplan a6-full-r0 s-full - "" r0t0 r0t1 r0t0)
  route "$p"; check "A6: spec full, every task at risk 0 -> exit 0" "$status" 0
  check "A6: spec full, every task at risk 0 -> full" "$(depth_of)" full
  check "A6: spec full is reported as spec=full" "$(spec_of)" full
  p=$(mkplan a6-full-r1 s-full - "" r1t2)
  route "$p"; check "A6: spec full, a task at risk 1 -> full" "$(depth_of)" full
  p=$(mkplan a6-std-r0 s-standard - "" r0t0)
  route "$p"; check "A6: spec standard, risk 0 -> standard (never lowered)" "$(depth_of)" standard
fi

# =====================================================================
if want A7; then
  rr() { # rr PLAN ROUND — sets out and status of review-route PLAN --plan-round ROUND
    out=$(cd "$REPO" && timeout 60 bash "$ROUTE" "$1" --plan-round "$2" 2>&1); status=$?
  }
  pl=$(mkplan a7-light s-light - "" r0t1 r1t2)
  rr "$pl" 1
  check "A7: light, round 1 exits 0" "$status" 0
  # Register row 1 of the review-depth register ruled that light keeps one plan-review round.
  present "A7 (register row 1): light, round 1 prints cap=1" "$out" "cap=1"
  absent "A7 (register row 1): light, round 1 routes to a seat" "$out" "primary=none"
  rr "$pl" 2; check "A7: light, round 2 exits 2" "$status" 2
  rr "$pl" 3; check "A7: light, round 3 exits 2" "$status" 2

  ps=$(mkplan a7-standard s-light - "" r0t1 r2t4)
  rr "$ps" 1
  check "A7: standard (task risk 2), round 1 exits 0" "$status" 0
  present "A7: standard, round 1 prints cap=1" "$out" "cap=1"
  absent "A7: standard, round 1 is not primary=none" "$out" "primary=none"
  rr "$ps" 2; check "A7: standard, round 2 exits 2" "$status" 2
  ps2=$(mkplan a7-standard-spec s-standard - "" r0t1)
  rr "$ps2" 1
  present "A7: standard (spec standard), round 1 prints cap=1" "$out" "cap=1"
  rr "$ps2" 2; check "A7: standard (spec standard), round 2 exits 2" "$status" 2

  pf=$(mkplan a7-full s-full - "" r0t1)
  rr "$pf" 1
  check "A7: full, round 1 exits 0" "$status" 0
  present "A7: full, round 1 prints cap=2" "$out" "cap=2"
  absent "A7: full, round 1 is not primary=none" "$out" "primary=none"
  rr "$pf" 2
  check "A7: full, round 2 exits 0" "$status" 0
  present "A7: full, round 2 prints cap=2" "$out" "cap=2"
  rr "$pf" 3; check "A7: full, round 3 exits 2" "$status" 2
  pf3=$(mkplan a7-full-r3 s-light - "" r3t4)
  rr "$pf3" 1
  present "A7: full by task risk 3, round 1 prints cap=2" "$out" "cap=2"
  pn=$(mkplan a7-nospec - - "" r0t1)
  rr "$pn" 1
  present "A7: a plan with no Spec line keeps cap=2" "$out" "cap=2"

  # A Host: codex plan keeps the cap it had before: 1 up to total 3, 2 for 4-5, 3 from 6.
  for t in 3 5 6; do
    case $t in 3) wcap=1 ;; 5) wcap=2 ;; 6) wcap=3 ;; esac
    pc=$(mkcodex "a7-codex-$t" s-light "$t")
    rr "$pc" 1
    check "A7: Host: codex total $t, round 1 exits 0" "$status" 0
    present "A7: Host: codex total $t (spec light) prints cap=$wcap" "$out" "cap=$wcap"
    absent "A7: Host: codex total $t is never primary=none" "$out" "primary=none"
    rr "$pc" "$((wcap + 2))"; check "A7: Host: codex total $t, round $((wcap + 2)) exits 2" "$status" 2
    if [ "$have_base" -eq 1 ]; then
      for r in 1 "$((wcap + 1))" "$((wcap + 2))"; do
        rr "$pc" "$r"; new_out=$out new_st=$status
        old_out=$(cd "$REPO" && timeout 60 bash "$BASE_DIR/plugins/dforge/scripts/review-route" "$pc" --plan-round "$r" 2>&1); old_st=$?
        check "A7: Host: codex total $t round $r matches the pre-spec output" "$new_st|$new_out" "$old_st|$old_out"
      done
    fi
  done
fi

# =====================================================================
if want A8; then
  # A copy of the scripts and lenses whose security lens does not apply, to reach the Applies check.
  CP="$TMP/pcopy"
  mkdir -p "$CP"
  for d in "$PLUGIN"/*/; do [ "$(basename "$d")" = tests ] || cp -R "$d" "$CP/"; done
  sed -i 's/^Applies: always$/Applies: paths *.nomatch/' "$CP/criteria/lenses/security.md"

  lr() { # lr PLAN [ENV...] — sets out and status of lens-route --final on the throwaway history
    local plan=$1; shift
    out=$(cd "$REPO" && env "$@" timeout 60 bash "$LENS" "$plan" --final "$BASE_C" "$HEAD_C" 2>&1); status=$?
  }
  lens_lines() { if [ "$status" -ne 0 ]; then printf 'status=%s\n' "$status"; else grep -c '^lens ' <<<"$out"; fi; }

  pl=$(mkplan a8-light s-light - "" r0t1 r1t2)
  lr "$pl" DFORGE_LENS_CAP=4
  check "A8: light exits 0" "$status" 0
  present "A8: light prints the security lens" "$out" "^lens security "
  check "A8: light prints exactly one lens line" "$(lens_lines)" 1
  present "A8: light skips another applicable lens with reason=depth" "$out" "^lens-skipped (silent-failures|test-quality|lang-bash|lang-python|lang-typescript|type-design|docs-comments) reason=depth$"
  absent "A8: light never skips security" "$out" "^lens-skipped security"
  absent "A8: light prints no reason=cap line" "$out" "reason=cap"
  skipped=$(grep -c '^lens-skipped .* reason=depth$' <<<"$out")
  if [ "$skipped" -ge 3 ]; then printf 'ok   - A8: light skips at least 3 other applicable lenses (%s)\n' "$skipped"; pass=$((pass + 1))
  else printf 'FAIL - A8: light skips at least 3 other applicable lenses (got %s)\n' "$skipped"; fail=$((fail + 1)); fi
  # Every lens that applies at full and is not security is skipped, with a reason=depth, at light.
  lr "$pl" DFORGE_LENS_CAP=9
  light_skipped=$(grep -E '^lens-skipped ' <<<"$out" | awk '{print $2}' | sort | tr '\n' ' ')
  pf=$(mkplan a8-full s-full - "" r0t1)
  lr "$pf" DFORGE_LENS_CAP=9
  full_ids=$(grep -E '^lens ' <<<"$out" | awk '{print $2}' | grep -vx security | sort | tr '\n' ' ')
  check "A8: the lenses skipped at light are the other lenses that apply at full" "$light_skipped" "$full_ids"

  # security does not apply: no lens line for it, and no skip line either.
  out=$(cd "$REPO" && env DFORGE_LENS_CAP=4 timeout 60 bash "$CP/scripts/lens-route" "$pl" --final "$BASE_C" "$HEAD_C" 2>&1); status=$?
  check "A8: light, security not applicable, exits 0" "$status" 0
  absent "A8: light, security not applicable, prints no security lens" "$out" "^lens security "
  absent "A8: light, security not applicable, prints no security skip" "$out" "lens-skipped security"
  check "A8: light, security not applicable, prints no lens line" "$(lens_lines)" 0
  present "A8: light, security not applicable, still skips the others by depth" "$out" "^lens-skipped .* reason=depth$"

  # standard: at most 2 lens lines besides test-quality, which this change set needs.
  ps=$(mkplan a8-standard s-light - "" r0t1 r2t4)
  lr "$ps" DFORGE_LENS_CAP=4
  check "A8: standard, lensCap 4, prints 3 lens lines with test-quality" "$(lens_lines)" 3
  present "A8: standard past the cap prints reason=cap" "$out" "^lens-skipped .* reason=cap$"
  absent "A8: standard prints no reason=depth" "$out" "reason=depth"
  lr "$ps" DFORGE_LENS_CAP=9
  check "A8: standard, lensCap 9, still prints 3 lens lines" "$(lens_lines)" 3
  lr "$ps" DFORGE_LENS_CAP=1
  check "A8: standard, lensCap 1, prints 1 lens line" "$(lens_lines)" 1
  lr "$ps" DFORGE_LENS_CAP=2
  check "A8: standard, lensCap 2, prints 2 lens lines" "$(lens_lines)" 2
  lr "$ps" DFORGE_LENS_CAP=0
  present "A8: standard, lensCap 0, prints lenses off" "$out" "^lenses off$"
  ps2=$(mkplan a8-standard-spec s-standard - "" r0t1)
  lr "$ps2" DFORGE_LENS_CAP=4
  check "A8: standard by the spec, lensCap 4, prints 3 lens lines with test-quality" "$(lens_lines)" 3

  # full: up to lensCap, as before.
  lr "$pf" DFORGE_LENS_CAP=4
  check "A8: full, lensCap 4, prints 4 lens lines" "$(lens_lines)" 4
  absent "A8: full prints no reason=depth" "$out" "reason=depth"
  present "A8: full prints reason=cap past the cap" "$out" "^lens-skipped .* reason=cap$"
  lr "$pf" DFORGE_LENS_CAP=3
  check "A8: full, lensCap 3, prints 3 lens lines" "$(lens_lines)" 3
  if [ "$have_base" -eq 1 ]; then
    norm() { sed -E 's#criteria=[^ ]*/criteria/#criteria=#; s#reason=paths:[^ ]*#reason=paths#'; }
    for cap in 0 1 2 3 4 9; do
      lr "$pf" DFORGE_LENS_CAP=$cap; new=$(norm <<<"$out")
      old=$(cd "$REPO" && env DFORGE_LENS_CAP=$cap timeout 60 bash "$BASE_DIR/plugins/dforge/scripts/lens-route" "$pf" --final "$BASE_C" "$HEAD_C" 2>&1 | norm)
      check "A8: full, lensCap $cap, output equals the pre-spec output" "$new" "$old"
    done
  fi
fi

# =====================================================================
if want A10; then
  today=$(date +%F)
  lintp=$(mkplan a10-lint s-light - "**Plan review:** $today — skipped (depth light)" r0t1 r1t2)
  lint_out=$(cd "$REPO" && timeout 60 bash "$LINT" "$lintp" 2>&1); lint_st=$?
  check "A10: plan-lint still accepts an older light plan's skipped line (exit 0)" "$lint_st" 0
  present "A10: plan-lint reports 0 errors" "$lint_out" "0 errors"
  absent "A10: plan-lint prints no Plan review header warning" "$lint_out" "Plan review"
  absent "A10: plan-lint prints no header error" "$lint_out" "ERROR header"
  nolint=$(mkplan a10-nolint s-light - "" r0t1 r1t2)
  lint_out=$(cd "$REPO" && timeout 60 bash "$LINT" "$nolint" 2>&1)
  present "A10: control: without the line plan-lint does warn" "$lint_out" "Plan review"
fi

# =====================================================================
if want A12; then
  # The whole-branch Claude review is routed at every depth.
  for spec in s-light s-standard s-full; do
    p=$(mkplan "a12-$spec" "$spec" - "" r0t1)
    out=$(cd "$REPO" && timeout 60 bash "$ROUTE" "$p" --final 2>&1); status=$?
    check "A12: review-route --final exits 0 under $spec" "$status" 0
    present "A12: review-route --final names the Claude review seat under $spec" "$out" "^review-seat final primary=dforge:judge-opus "
  done
  p=$(mkplan a12-light-final s-light - "" r0t1)
  out=$(cd "$REPO" && timeout 60 bash "$ROUTE" "$p" --final-fix src/a.sh 2>&1); status=$?
  check "A12: review-route --final-fix still routes at light" "$status" 0
  absent "A12: the fix wave seat is not none at light" "$out" "primary=none"
  lo=$(cd "$REPO" && DFORGE_LENS_CAP=4 timeout 60 bash "$LENS" "$p" --final "$BASE_C" "$HEAD_C" 2>&1)
  present "A12: lens-route still runs the security lens at light" "$lo" "^lens security "
fi

# =====================================================================
if want A13; then
  p=$(mkplan a13-r1 s-owner-light - "" r0t1 r1t2)
  route "$p"
  check "A13: owner light line -> exit 0" "$status" 0
  check "A13: owner light line -> spec=light" "$(spec_of)" light
  check "A13: owner light line -> depth=light (risk <= 1)" "$(depth_of)" light
  p=$(mkplan a13-r2 s-owner-light - "" r0t1 r2t4)
  route "$p"
  check "A13: owner light line stays spec=light with a risk-2 task" "$(spec_of)" light
  check "A13: owner light line, a risk-2 task -> standard" "$(depth_of)" standard
  p=$(mkplan a13-r3 s-owner-light - "" r3t3)
  route "$p"
  check "A13: owner light line, a risk-3 task -> full" "$(depth_of)" full
  check "A13: owner light line stays spec=light with a risk-3 task" "$(spec_of)" light
fi

# =====================================================================
if want A16; then
  p=$(mkplan a16-hand s-handset - "" r0t1)
  route "$p"
  check "A16: a hand-set Depth line with free text -> exit 0" "$status" 0
  check "A16: '**Depth:** standard — interface (set by hand)' gives spec=standard" "$(spec_of)" standard
  check "A16: ... and depth=standard" "$(depth_of)" standard
  mkspec s-bare '**Depth:** light'
  p=$(mkplan a16-bare s-bare - "" r0t1)
  route "$p"; check "A16: a bare '**Depth:** light' gives spec=light" "$(spec_of)" light
  mkspec s-spaced '**Depth:**   standard   — interface'
  p=$(mkplan a16-spaced s-spaced - "" r0t1)
  route "$p"; check "A16: extra spaces after the label still give spec=standard" "$(spec_of)" standard
  mkspec s-crlf '**Depth:** light — x'
  sed -i 's/$/\r/' "$SPECS/s-crlf.md"
  p=$(mkplan a16-crlf s-crlf - "" r0t1)
  route "$p"; check "A16: a CRLF spec gives spec=light" "$(spec_of)" light
  p=$(mkplan a16-badword s-badword - "" r0t1)
  route "$p"; check "A16: a first word that is not a depth gives spec=none" "$(spec_of)" none

  # A spec in the darkmem mirror resolves as plan-lint resolves it.
  . "$HERE/fixtures/darkmem-stores.sh"
  MH="$TMP/mhome"; mkdir -p "$MH"
  MR="$TMP/mrepo"; mkdir -p "$MR"
  git -C "$MR" init -q -b main
  printf 'x\n' > "$MR/x.txt"; git -C "$MR" add -A >/dev/null 2>&1; git -C "$MR" commit -q -m init
  MIRROR=$(stores_home "$MH" "$MR" qaproj darkmem local)
  mkdir -p "$MIRROR/dforge/specs" "$MIRROR/dforge/plans"
  printf '# Mirror spec\n\n**Execution strategy:** sequential\n\n**Depth:** standard — interface (set by hand)\n\n## Decisions\n' > "$MIRROR/dforge/specs/m-spec.md"
  {
    printf '# Mirror Plan\n\n**Goal:** Demo.\n\n**Spec:** `docs/dforge/specs/m-spec.md`\n\n'
    printf '**Execution:** inline — `claude --model sonnet --effort high` — demo\n\n'
    printf '**Plan review:** 2026-10-27 — skipped (depth light)\n\n'
    printf '## Global Constraints\n\n- None.\n\n## Contracts\n\nNone\n\n## Assumptions (evidence)\n\n- None.\n\n## Task index\n\n1. Thing 1\n\n'
    printf '### Task 1: Thing 1\n\n**Files:**\n- Create: `f1.txt`\n\n**Implementer:** dforge:impl-sonnet-low\n'
    printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n\n- [ ] **Step 1: Do it**\n'
  } > "$MIRROR/dforge/plans/m-plan.md"
  lint_out=$(cd "$MR" && HOME="$MH" timeout 60 bash "$LINT" "$MIRROR/dforge/plans/m-plan.md" 2>&1)
  absent "A16: plan-lint resolves the mirror spec path (no 'Spec path does not exist')" "$lint_out" "Spec path does not exist"
  out=$(cd "$MR" && HOME="$MH" timeout 60 bash "$DR" "$MIRROR/dforge/plans/m-plan.md" 2>&1); status=$?
  check "A16: a mirror spec path routes (exit 0)" "$status" 0
  present "A16: a mirror spec path gives spec=standard" "$out" " spec=standard "
  present "A16: a mirror spec path gives depth=standard" "$out" "^depth=standard "
  # The same plan with the spec absent from the mirror falls to none, proving the spec was read from there.
  mv "$MIRROR/dforge/specs/m-spec.md" "$MIRROR/dforge/specs/m-spec.moved"
  out=$(cd "$MR" && HOME="$MH" timeout 60 bash "$DR" "$MIRROR/dforge/plans/m-plan.md" 2>&1)
  present "A16: control: with the mirror spec gone the plan routes at full with spec=none" "$out" "^depth=full spec=none "
fi

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
