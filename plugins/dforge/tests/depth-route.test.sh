#!/usr/bin/env bash
# depth-route is the review-depth rule as code: seven trigger ids give the spec
# checkpoint, and a plan's spec depth and task risk scores give the plan
# checkpoint. Each case below pins one row of that rule.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
ROUTE="$P/scripts/depth-route"
FIX="$HERE/fixtures/depth-route"
. "$P/scripts/lib/plan.sh"
. "$P/scripts/lib/depth.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s] in [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
# The darkmem cases below set their own home; every other case reads this one,
# never the developer's ~/.dforge.
export HOME="$TMP/home"
mkdir -p "$HOME"

REPO="$TMP/repo"
git init -q "$REPO"
mkdir -p "$REPO/docs/dforge/specs" "$REPO/docs/dforge/plans"
cp "$FIX"/spec-*.md "$REPO/docs/dforge/specs/"

route() { (cd "$REPO" && bash "$ROUTE" "$@" 2>&1); }

# mkplan NAME SPEC EXTRA RISK... — docs/dforge/plans/NAME.md with one task per
# RISK. SPEC is a spec fixture's basename ("" for no Spec line), EXTRA a header
# line ("" for none). A RISK of "-" writes a task with no Evaluation line, "?" an
# Evaluation line that does not parse, and "3t8" risk 3 with a total of 8.
mkplan() {
  local name=$1 spec=$2 extra=$3 n=0 r total
  shift 3
  {
    sed 's/^|//' <<'HEAD'
|# Depth Fixture Plan
|
|**Goal:** Fixture.
|
HEAD
    [ -z "$spec" ] || printf '**Spec:** docs/dforge/specs/%s.md\n\n' "$spec"
    [ -z "$extra" ] || printf '%s\n\n' "$extra"
    printf '## Task index\n\n'
    for r in "$@"; do
      n=$((n + 1))
      printf '### Task %d: fixture task\n\n' "$n"
      case $r in
        -) ;;
        '?') printf '**Evaluation:** files one, spec none\n\n' ;;
        *t*) total=${r#*t}; printf '**Evaluation:** files 1 - spec 1 - coupling 1 - risk %s = %s\n\n' "${r%%t*}" "$total" ;;
        *) printf '**Evaluation:** files 0 - spec 0 - coupling 0 - risk %s = %s\n\n' "$r" "$r" ;;
      esac
    done
  } > "$REPO/docs/dforge/plans/$name.md"
}
plan_line() { route "docs/dforge/plans/$1.md"; }

# --- the library functions ---
check "depth_rank light" "$(depth_rank light)" "0"
check "depth_rank standard" "$(depth_rank standard)" "1"
check "depth_rank full" "$(depth_rank full)" "2"
out=$(depth_rank medium); st=$?
check "depth_rank of another word prints nothing" "$out" ""
check "depth_rank of another word exits 1" "$st" "1"
check "depth_name 0" "$(depth_name 0)" "light"
check "depth_name 1" "$(depth_name 1)" "standard"
check "depth_name 2" "$(depth_name 2)" "full"
out=$(depth_name 3); st=$?
check "depth_name 3 prints nothing, exits 1" "$out:$st" ":1"
check "the seven trigger ids" "${DEPTH_TRIGGERS[*]}" "new-subsystem interface unenumerable approach risk intricate asked"
. "$P/scripts/lib/depth.sh"
check "sourcing the lib twice is harmless" "$?" "0"
check "depth_spec_file reads the first word" "$(depth_spec_file "$FIX/spec-standard.md")" "standard"
check "depth_spec_file of a missing file" "$(depth_spec_file "$TMP/none.md")" "none"
check "depth_spec_file of an unknown word" "$(depth_spec_file "$FIX/spec-bad-word.md")" "none"
check "depth_spec_file with no Depth line" "$(depth_spec_file "$FIX/spec-no-depth.md")" "none"
printf '# Fixture\n\n```\n**Depth:** full — quoted\n```\n\n**Depth:** light — real\n' > "$TMP/fenced-spec.md"
check "depth_spec_file ignores a Depth line inside a fenced block" "$(depth_spec_file "$TMP/fenced-spec.md")" "light"
sed 's/$/\r/' "$FIX/spec-full.md" > "$TMP/crlf-spec.md"
check "depth_spec_file tolerates CRLF" "$(depth_spec_file "$TMP/crlf-spec.md")" "full"

# --- A1: the spec checkpoint ---
check "risk alone is full" "$(route --spec-triggers risk)" "depth=full reason=risk"
check "new-subsystem alone is full" "$(route --spec-triggers new-subsystem)" "depth=full reason=new-subsystem"
check "risk outranks interface" "$(route --spec-triggers interface,risk)" "depth=full reason=risk"
check "both full triggers are named in a fixed order" "$(route --spec-triggers new-subsystem,asked,risk)" "depth=full reason=risk,new-subsystem"
check "interface alone is standard" "$(route --spec-triggers interface)" "depth=standard reason=interface"
check "interface with light triggers is standard" "$(route --spec-triggers unenumerable,interface,approach)" "depth=standard reason=interface"
check "light triggers are all named in the order given" "$(route --spec-triggers intricate,approach)" "depth=light reason=intricate,approach"
for id in unenumerable approach intricate asked; do
  check "$id alone is light" "$(route --spec-triggers $id)" "depth=light reason=$id"
done

# --- A2: the spec checkpoint refuses what it cannot route ---
for bad in "" "," "bogus" "risk,bogus" "Risk"; do
  out=$(route --spec-triggers "$bad"); st=$?
  check "list [$bad] exits 2" "$st" "2"
  absent "list [$bad] prints no depth line" "$out" "depth="
done
check "an empty list says why" "$(route --spec-triggers "")" "depth-route: no trigger given"
check "an unknown id is named" "$(route --spec-triggers interface,bogus)" "depth-route: unknown trigger: bogus"
out=$(route); st=$?
check "no argument exits 2" "$st" "2"
out=$(route --bogus); st=$?
check "an unknown option exits 2" "$st:$out" "2:depth-route: unknown option: --bogus"
out=$(route --spec-triggers); st=$?
check "--spec-triggers without a list exits 2" "$st" "2"
out=$(route docs/dforge/plans/missing.md); st=$?
check "a missing plan exits 2" "$st" "2"
check "a missing plan is named" "${out%%:*}:$(grep -c 'no such plan file' <<<"$out")" "depth-route:1"

# --- A3, A4, A6: the plan checkpoint ---
mkplan l-low spec-light "" 0 1
check "light spec, risks 0 and 1: light" "$(plan_line l-low)" "depth=light spec=light tasks=light reason=spec,task-risk:2"
mkplan l-two spec-light "" 0 2 1
check "light spec, highest risk 2: standard" "$(plan_line l-two)" "depth=standard spec=light tasks=standard reason=task-risk:2"
mkplan l-three spec-light "" 1 3
check "light spec, a risk 3 task: full" "$(plan_line l-three)" "depth=full spec=light tasks=full reason=task-risk:2"
mkplan s-low spec-standard "" 0 1
check "standard spec, low risks: standard" "$(plan_line s-low)" "depth=standard spec=standard tasks=light reason=spec"
mkplan s-two spec-standard "" 2
check "standard spec, risk 2: both inputs named" "$(plan_line s-two)" "depth=standard spec=standard tasks=standard reason=spec,task-risk:1"
mkplan s-three spec-standard "" 3
check "standard spec, risk 3: full" "$(plan_line s-three)" "depth=full spec=standard tasks=full reason=task-risk:1"
mkplan f-zero spec-full "" 0 0
check "full spec, risk 0 tasks: the plan never lowers it" "$(plan_line f-zero)" "depth=full spec=full tasks=light reason=spec"
mkplan f-three spec-full "" 3
check "full spec, risk 3: both inputs named" "$(plan_line f-three)" "depth=full spec=full tasks=full reason=spec,task-risk:1"
mkplan empty spec-light ""
check "a plan with no tasks is light on tasks" "$(plan_line empty)" "depth=light spec=light tasks=light reason=spec"

# --- A4: task count and totals never raise the depth ---
risks=()
for ((i = 1; i <= 40; i++)); do
  if [ $((i % 3)) -eq 0 ]; then risks+=("1t8"); else risks+=("$((i % 2))"); fi
done
mkplan forty spec-light "" "${risks[@]}"
check "40 tasks at risk 1 or below with totals of 8: light" "$(plan_line forty)" "depth=light spec=light tasks=light reason=spec,task-risk:1"

# --- A5: what routes at full ---
mkplan no-spec-line "" "" 0
check "no Spec line: full" "$(plan_line no-spec-line)" "depth=full spec=none tasks=light reason=no-spec-depth"
mkplan no-depth-line spec-no-depth "" 0
check "a spec with no Depth line: full" "$(plan_line no-depth-line)" "depth=full spec=none tasks=light reason=no-spec-depth"
mkplan bad-word spec-bad-word "" 0
check "a spec whose Depth word is unknown: full" "$(plan_line bad-word)" "depth=full spec=none tasks=light reason=no-spec-depth"
mkplan gone-spec spec-gone "" 0
check "a Spec path that does not exist: full" "$(plan_line gone-spec)" "depth=full spec=none tasks=light reason=no-spec-depth"
mkplan no-spec-risk3 "" "" 3
check "no spec depth and a risk 3 task name both" "$(plan_line no-spec-risk3)" "depth=full spec=none tasks=full reason=no-spec-depth,task-risk:1"
mkplan unscored spec-light "" 1 -
check "a task with no Evaluation line: full" "$(plan_line unscored)" "depth=full spec=light tasks=full reason=unscored:2"
mkplan unparsable spec-light "" '?' 0
check "an unparsable Evaluation line: full" "$(plan_line unparsable)" "depth=full spec=light tasks=full reason=unscored:1"
mkplan unscored-risk3 spec-light "" - 3
check "an unscored task is named before a risk 3 task" "$(plan_line unscored-risk3)" "depth=full spec=light tasks=full reason=unscored:1"
mkplan codex spec-light "Host: codex" 0
check "Host: codex: full" "$(plan_line codex)" "depth=full spec=light tasks=light reason=codex-host"
mkplan codex-bold spec-full "**Host:** codex" 3
check "a bold Host: codex line is read, and names only codex-host" "$(plan_line codex-bold)" "depth=full spec=full tasks=full reason=codex-host"

# --- A13: an owner line is the spec's depth ---
mkplan owner-low spec-owner-light "" 1
check "an owner light line is spec=light" "$(plan_line owner-low)" "depth=light spec=light tasks=light reason=spec,task-risk:1"
mkplan owner-two spec-owner-light "" 2
check "a risk 2 task still raises an owner light spec" "$(plan_line owner-two)" "depth=standard spec=light tasks=standard reason=task-risk:1"
mkplan owner-three spec-owner-light "" 3
check "a risk 3 task still raises an owner light spec to full" "$(plan_line owner-three)" "depth=full spec=light tasks=full reason=task-risk:1"

# --- A3: the plan is read with its amendments applied ---
mkplan amend spec-light "" 1 1
check "before the amendment: light" "$(plan_line amend)" "depth=light spec=light tasks=light reason=spec,task-risk:1"
mkdir -p "$REPO/.dforge/sdd/amend"
sed 's/^|//' > "$REPO/.dforge/sdd/amend/amendments.md" <<'AMEND'
|## A1 — Task 2
|
|### Old
|
|````
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 1 = 1
|````
|
|### New
|
|````
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3
|````
AMEND
check "after the amendment: full" "$(plan_line amend)" "depth=full spec=light tasks=full reason=task-risk:2"
sed 's/risk 1 = 1/risk 2 = 2/' "$REPO/.dforge/sdd/amend/amendments.md" > "$TMP/broken-amend.md"
cp "$TMP/broken-amend.md" "$REPO/.dforge/sdd/amend/amendments.md"
out=$(plan_line amend); st=$?
check "an amendment that does not apply exits 2" "$st:$out" "2:depth-route: an amendment does not apply; run plan-lint"
rm -rf "$REPO/.dforge/sdd/amend"

# --- A16: the Depth line is read by its first word, in the darkmem mirror too ---
mkplan first-word spec-standard "" 0
check "a Depth line with trailing text gives spec=standard" "$(plan_line first-word | grep -o 'spec=[a-z]*')" "spec=standard"
sed 's/$/\r/' "$REPO/docs/dforge/specs/spec-light.md" > "$REPO/docs/dforge/specs/spec-crlf.md"
mkplan crlf spec-crlf "" 0
check "a CRLF spec is read" "$(plan_line crlf | grep -o 'spec=[a-z]*')" "spec=light"

. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"; git init -q "$SR"
M=$(stores_home "$SH" "$SR" proj darkmem darkmem)
mkdir -p "$M/dforge/specs" "$M/dforge/plans"
cp "$FIX/spec-standard.md" "$M/dforge/specs/s.md"
printf '# P\n\n**Goal:** Fixture.\n\n**Spec:** docs/dforge/specs/s.md\n\n## Task index\n\n### Task 1: One\n\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0\n' > "$M/dforge/plans/p.md"
out=$(cd "$SR" && HOME=$SH bash "$ROUTE" docs/dforge/plans/p.md 2>&1)
check "a spec in the darkmem mirror resolves as plan-lint resolves it" "$out" "depth=standard spec=standard tasks=light reason=spec"
out=$(cd "$SR" && HOME=$SH bash "$ROUTE" "$M/dforge/plans/p.md" 2>&1)
check "the mirror plan is also found by its absolute path" "$out" "depth=standard spec=standard tasks=light reason=spec"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
