#!/usr/bin/env bash
# lens-route picks the specialist review lenses for a final review or a risk-3
# task. Each case pins one selection rule against a throwaway repository.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTE="$HERE/../../plugins/dforge/scripts/lens-route"
export DFORGE_NO_SETTINGS=1
unset DFORGE_LENS_CAP CLAUDE_CONFIG_DIR
# The floor cases set their own threshold; 0 keeps the other cases' output
# free of the lens-floor line.
export DFORGE_LENS_MINOR_FROM=0

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
short() { sed -E 's/ criteria=[^ ]*//; s/ parts=[^ ]*//; s/ seat=[^ ]*//; s/ reason=(always|added|ui-paths|paths:[^ ]*)$//' | tr '\n' ';'; }
parts() { sed -n 's/^lens code-quality parts=\([^ ]*\) .*/\1/p' | tr ',' '\n' | sed 's#.*/##' | tr '\n' ' '; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cd "$TMP" || exit 1
git init -q repo && cd repo || exit 1
git config user.email t@example.com && git config user.name t
git commit -q --allow-empty -m base
BASE=$(git rev-parse HEAD)
commit_file() { # commit_file <path> <content>
  mkdir -p "$(dirname "$1")"; printf '%s\n' "$2" > "$1"; git add "$1"; git commit -q -m "add $1"
}

# Fixture lines carry a leading | so a plan that quotes this suite still lints.
sed 's/^|//' > plan.md <<'EOF'
|# Lens Fixture Plan
|
|## Task index
|
|1. risky
|2. plain
|3. unknown
|
|### Task 1: risky
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3
|**Lenses:** security, lang-bash
|
|### Task 2: plain
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
|
|### Task 3: unknown
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3
|**Lenses:** nope
EOF

# A1/A3: a shell-only change set.
commit_file scripts/foo.sh 'echo hi'
HEAD1=$(git rev-parse HEAD)
out=$(bash "$ROUTE" plan.md --final "$BASE" "$HEAD1"); status=$?
check "final: exit 0" "$status" "0"
check "final: a shell-only change gets security and code-quality" "$(short <<<"$out")" "lens security;lens code-quality;"
check "final: code-quality carries only the matching part" "$(parts <<<"$out")" "lang-bash.md "
check "final: the seat and reason" "$(grep -c '^lens security criteria=[^ ]* seat=dforge:judge-sonnet-high reason=always$' <<<"$out")" "1"
crit=$(sed -n 's/^lens code-quality parts=\([^, ]*\).*/\1/p' <<<"$out")
check "final: the part path exists" "$([ -f "$crit" ] && echo yes || echo no)" "yes"
check "final: the reason names the first part's glob" "$(grep -c '^lens code-quality parts=[^ ]* seat=dforge:judge-sonnet-high reason=paths:\*\.sh$' <<<"$out")" "1"
# A9: no part applies, so code-quality prints no line of either kind.
git checkout -q "$HEAD1"
commit_file data.json '{}'
out=$(bash "$ROUTE" plan.md --final "$HEAD1" "$(git rev-parse HEAD)")
check "final: no part applies, no code-quality line" "$(grep -c 'code-quality' <<<"$out")" "0"
git reset -q --hard "$HEAD1"

# git quotes a non-ASCII name unless told not to, and a quoted name matches no glob.
commit_file $'scripts/caf\303\251.py' 'print(1)'
out=$(bash "$ROUTE" plan.md --final "$HEAD1" "$(git rev-parse HEAD)")
check "final: a non-ASCII file name still matches its part's paths" "$(parts <<<"$out")" "lang-python.md "
git reset -q --hard "$HEAD1"

# A2: more applicable lenses than the cap.
commit_file tests/a.test.ts 'try { run() } catch (e) {}'
commit_file README.md 'Docs.'
HEAD2=$(git rev-parse HEAD)
out=$(DFORGE_LENS_CAP=2 bash "$ROUTE" plan.md --final "$BASE" "$HEAD2")
check "cap 2: two lenses, the rest skipped in order" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens-skipped test-quality reason=cap;lens-skipped code-quality reason=cap;"
out=$(bash "$ROUTE" plan.md --final "$BASE" "$HEAD2")
check "default cap 5" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens code-quality;"
check "default cap: parts in their fixed order" "$(parts <<<"$out")" "lang-bash.md lang-typescript.md docs-comments.md "
out=$(DFORGE_LENS_CAP=0 bash "$ROUTE" plan.md --final "$BASE" "$HEAD2")
check "cap 0: lenses off" "$out" "lenses off"
# A change set git cannot read is an error, not an empty change set.
cp -R "$TMP/repo" "$TMP/broken"
tree=$(git rev-parse "$HEAD2^{tree}")
rm -f "$TMP/broken/.git/objects/${tree:0:2}/${tree:2}"
out=$(cd "$TMP/broken" && bash "$ROUTE" plan.md --final "$BASE" "$HEAD2" 2>"$TMP/broken.err"); status=$?
check "final: an unreadable change set exits 2" "$status:$(grep -c 'lens-route: cannot read the change set' "$TMP/broken.err")" "2:1"
rm -rf "$TMP/broken" "$TMP/broken.err"

# The Minor floor: the fixture plan has three tasks.
out=$(DFORGE_LENS_MINOR_FROM=4 bash "$ROUTE" plan.md --final "$BASE" "$HEAD1")
check "floor: a plan under the threshold gets the floor after the lenses" "$(short <<<"$out")" \
  "lens security;lens code-quality;lens-floor important tasks=3 from=4;"
out=$(DFORGE_LENS_MINOR_FROM=3 bash "$ROUTE" plan.md --final "$BASE" "$HEAD1")
check "floor: a plan at the threshold gets none" "$(grep -c '^lens-floor' <<<"$out")" "0"
out=$(DFORGE_LENS_MINOR_FROM=4 DFORGE_LENS_CAP=0 bash "$ROUTE" plan.md --final "$BASE" "$HEAD1")
check "floor: lenses off print no floor" "$out" "lenses off"
out=$(unset DFORGE_LENS_MINOR_FROM; bash "$ROUTE" plan.md --final "$BASE" "$HEAD1")
check "floor: the default threshold is 20" "$(grep -c '^lens-floor important tasks=3 from=20$' <<<"$out")" "1"

# A4: per-task lenses.
out=$(bash "$ROUTE" plan.md --task 1); status=$?
check "task: exit 0" "$status" "0"
check "task: the named lenses, uncapped" "$(sed -E 's/ criteria=[^ ]*//' <<<"$out" | tr '\n' ';')" "lens security;lens lang-bash;"
out=$(bash "$ROUTE" plan.md --task 2); status=$?
check "task without a Lenses line: exit 0" "$status" "0"
check "task without a Lenses line: no output" "$out" ""
bash "$ROUTE" plan.md --task 3 >/dev/null 2>&1; check "task: an unknown lens id exits 2" "$?" "2"
bash "$ROUTE" plan.md --task 9 >/dev/null 2>&1; check "task: a missing task exits 2" "$?" "2"
bash "$ROUTE" plan.md >/dev/null 2>&1; check "usage: exit 2" "$?" "2"
{ printf 'Host: codex\n\n'; cat plan.md; } > codex.md
bash "$ROUTE" codex.md --task 1 >/dev/null 2>&1; check "a Codex-host plan exits 2" "$?" "2"

# --- the depth of the plan sizes the final lenses ---
# A plan's depth is the higher of its spec's Depth line and its riskiest task
# (lib/depth.sh). Light keeps security only, standard at most two lenses
# besides test-quality, which it adds when it applies, full up to lensCap.
# The change set is HEAD2's: shell, a TypeScript test and a README.
mkdir -p specs
for d in light standard full; do
  printf '# Spec\n\n**Depth:** %s — fixture\n' "$d" > "specs/$d.md"
done
write_depth_plan() { # write_depth_plan <file> <spec name> <risk> - a one-task plan
  sed 's/^|//' > "$1" <<EOF2
|# Depth Fixture Plan
|
|**Spec:** \`specs/$2.md\`
|
|## Task index
|
|1. only
|
|### Task 1: only
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk $3 = $3
EOF2
}
write_depth_plan light-plan.md light 0
write_depth_plan standard-plan.md standard 0
write_depth_plan full-plan.md full 0
write_depth_plan light-risk2.md light 2
write_depth_plan light-risk3.md light 3
sed '/^\*\*Spec:\*\*/d' light-plan.md > nospec-plan.md
sed 's#specs/light.md#specs/gone.md#' light-plan.md > gone-spec-plan.md
out=$(bash "$ROUTE" light-plan.md --final "$BASE" "$HEAD2")
check "light: security only, every other applicable lens skipped for its depth" "$(short <<<"$out")" \
  "lens security;lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped code-quality reason=depth;"
out=$(DFORGE_LENS_CAP=1 bash "$ROUTE" light-plan.md --final "$BASE" "$HEAD2")
check "light: lensCap 1 still keeps security, the rest skipped for depth" "$(short <<<"$out")" \
  "lens security;lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped code-quality reason=depth;"
out=$(DFORGE_LENS_CAP=0 bash "$ROUTE" light-plan.md --final "$BASE" "$HEAD2")
check "light: lensCap 0 is still lenses off" "$out" "lenses off"
out=$(DFORGE_LENS_MINOR_FROM=4 bash "$ROUTE" light-plan.md --final "$BASE" "$HEAD1")
check "light: the floor counts the one lens printed" "$(short <<<"$out")" \
  "lens security;lens-skipped code-quality reason=depth;lens-floor important tasks=1 from=4;"
out=$(bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: code-quality and test-quality sit outside the two-lens limit" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens code-quality;"
out=$(DFORGE_LENS_CAP=1 bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: a lower lensCap wins" "$(grep -c '^lens ' <<<"$out")" "1"
out=$(DFORGE_LENS_CAP=2 bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: lensCap 2 skips test-quality and code-quality for the cap" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens-skipped test-quality reason=cap;lens-skipped code-quality reason=cap;"
out=$(DFORGE_LENS_CAP=3 bash "$ROUTE" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: lensCap 3 keeps test-quality as the third" "$(grep -c '^lens ' <<<"$out")" "3"
commit_file src/b.ts 'run() ?? fallback()'
commit_file NOTES.md 'Notes.'
HEAD3=$(git rev-parse HEAD)
out=$(bash "$ROUTE" standard-plan.md --final "$HEAD2" "$HEAD3")
check "standard: with no test file changed, code-quality still runs" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens code-quality;"
out=$(bash "$ROUTE" full-plan.md --final "$BASE" "$HEAD2")
check "full: the default cap of 5" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens code-quality;"
out=$(bash "$ROUTE" light-risk2.md --final "$BASE" "$HEAD2")
check "a light spec with a risk-2 task is standard: four lenses with test-quality and code-quality" "$(grep -c '^lens ' <<<"$out")" "4"
out=$(bash "$ROUTE" light-risk3.md --final "$BASE" "$HEAD2")
check "a light spec with a risk-3 task is full: four lenses" "$(grep -c '^lens ' <<<"$out")" "4"
out=$(bash "$ROUTE" nospec-plan.md --final "$BASE" "$HEAD2")
check "a risk-0 plan with no Spec line routes at full" "$(grep -c '^lens ' <<<"$out")" "4"
out=$(bash "$ROUTE" gone-spec-plan.md --final "$BASE" "$HEAD2")
check "a risk-0 plan whose Spec path does not exist routes at full" "$(grep -c '^lens ' <<<"$out")" "4"
# Security applies by its Applies clause; a copy of the script tree with a
# narrower clause shows light printing no lens line when it does not match.
mkdir -p "$TMP/plug/criteria"
cp -R "$HERE/../../plugins/dforge/scripts" "$HERE/../../plugins/dforge/config" "$TMP/plug/"
cp -R "$HERE/../../plugins/dforge/criteria/lenses" "$TMP/plug/criteria/lenses"
sed 's/^Applies: always$/Applies: paths nothing\/*/' "$HERE/../../plugins/dforge/criteria/lenses/security.md" > "$TMP/plug/criteria/lenses/security.md"
out=$(bash "$TMP/plug/scripts/lens-route" light-plan.md --final "$BASE" "$HEAD2")
check "light: security prints nothing when its Applies clause does not match" "$(short <<<"$out")" \
  "lens-skipped silent-failures reason=depth;lens-skipped test-quality reason=depth;lens-skipped code-quality reason=depth;"
out=$(bash "$TMP/plug/scripts/lens-route" standard-plan.md --final "$BASE" "$HEAD2")
check "standard: without security, test-quality and code-quality use no slot" "$(short <<<"$out")" \
  "lens silent-failures;lens test-quality;lens code-quality;"
printf '# lang-awk\n\nApplies: paths *.sh\n' > "$TMP/plug/criteria/lenses/lang-awk.md"
out=$(bash "$TMP/plug/scripts/lens-route" standard-plan.md --final "$BASE" "$HEAD2")
check "final: a new lang-* lens joins code-quality, sorted first" "$(parts <<<"$out" | cut -d' ' -f1-2)" "lang-awk.md lang-bash.md"
check "final: and routes no line of its own" "$(grep -c '^lens[^ ]* lang-awk' <<<"$out")" "0"
rm "$TMP/plug/criteria/lenses/lang-awk.md"
{ cat light-plan.md; printf '**Lenses:** lang-bash\n'; } > light-lenses.md
out=$(bash "$ROUTE" light-lenses.md --task 1); status=$?
check "light: --task names its lenses as before" "$status:$(sed -E 's/ criteria=[^ ]*//' <<<"$out")" "0:lens lang-bash"

# --- the ui-ux lens (dforge:ui-ux) ---
UIR="$TMP/uirepo"
git init -q "$UIR" && cd "$UIR" || exit 1
git config user.email t@example.com && git config user.name t
git commit -q --allow-empty -m base
UBASE=$(git rev-parse HEAD)
sed 's/^|//' > plan.md <<'EOF'
|# UI Fixture Plan
|
|## Task index
|
|1. ui
|
|### Task 1: ui
|
|**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
EOF
mkdir -p src tests
printf 'const v = a ?? b;\n' > src/App.tsx
printf 'test("x", () => {});\n' > tests/app.test.ts
git add src tests && git commit -q -m ui
UHEAD=$(git rev-parse HEAD)
uroute() { HOME="$TMP/uihome" bash "$ROUTE" "$@"; }
out=$(uroute plan.md --final "$UBASE" "$UHEAD")
check "ui-ux: no profile and no contract: not routed" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens code-quality;"
mkdir -p docs/dforge/ui-ux && printf '# UI profile\n\n**Platform:** web\n' > docs/dforge/ui-ux/profile.md
out=$(uroute plan.md --final "$UBASE" "$UHEAD")
check "ui-ux: with a profile it is second and survives the default cap" "$(short <<<"$out")" \
  "lens security;lens ui-ux;lens silent-failures;lens test-quality;lens code-quality;"
check "ui-ux: the reason" "$(grep -c '^lens ui-ux .* reason=ui-paths$' <<<"$out")" "1"
mkdir -p specs && printf '# Spec\n\n**Depth:** standard — fixture\n' > specs/standard.md
write_depth_plan ui-standard.md standard 0
out=$(uroute ui-standard.md --final "$UBASE" "$UHEAD")
check "standard: a third of security, ui-ux and silent-failures is skipped for the cap, code-quality kept" "$(short <<<"$out")" \
  "lens security;lens ui-ux;lens-skipped silent-failures reason=cap;lens test-quality;lens code-quality;"
rm docs/dforge/ui-ux/profile.md
printf '# Spec\n\n## UI/UX contract\n\n**UI/UX depth:** feature — x\n\n- **UX-1** — Escape closes the dialog.\n' > docs/s.md
{ printf '**Spec:** `docs/s.md`\n\n'; cat plan.md; } > plan-spec.md
out=$(uroute plan-spec.md --final "$UBASE" "$UHEAD")
check "ui-ux: a plan whose spec has a contract routes it" "$(grep -c '^lens ui-ux ' <<<"$out")" "1"
printf '# Plain\n\n## Notes\n\nnothing\n' > docs/plain.md
{ printf '**Spec:** `docs/plain.md`\n\n'; cat plan.md; } > plan-plain.md
out=$(uroute plan-plain.md --final "$UBASE" "$UHEAD")
check "ui-ux: a spec with no contract and no profile: not routed" "$(grep -c '^lens ui-ux ' <<<"$out")" "0"
{ printf '**Spec:** `docs/missing.md`\n\n'; cat plan.md; } > plan-missing.md
out=$(uroute plan-missing.md --final "$UBASE" "$UHEAD")
check "ui-ux: a spec path that does not exist: not routed" "$(grep -c '^lens ui-ux ' <<<"$out")" "0"
printf 'echo hi\n' > run.sh && git add run.sh && git commit -q -m sh
U2=$(git rev-parse HEAD)
out=$(uroute plan-spec.md --final "$UHEAD" "$U2")
check "ui-ux: no UI file changed: not routed" "$(grep -c '^lens ui-ux ' <<<"$out")" "0"
printf 'test("x", () => <App />);\n' > tests/app.test.tsx && git add tests && git commit -q -m tsx-test
U3=$(git rev-parse HEAD)
mkdir -p docs/dforge/ui-ux && printf '# UI profile\n\n**Platform:** web\n' > docs/dforge/ui-ux/profile.md
out=$(uroute plan.md --final "$U2" "$U3")
check "ui-ux: only a .test.tsx changed: not routed" "$(grep -c '^lens ui-ux ' <<<"$out")" "0"
rm docs/dforge/ui-ux/profile.md
printf '# T\n\n## Task index\n\n1. r\n\n### Task 1: r\n\n**Evaluation:** files 0 - spec 0 - coupling 0 - risk 3 = 3\n**Lenses:** ui-ux\n' > plan-task.md
check "ui-ux: a risk-3 task may name the lens" "$(uroute plan-task.md --task 1 | sed -E 's/ criteria=[^ ]*//')" "lens ui-ux"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
