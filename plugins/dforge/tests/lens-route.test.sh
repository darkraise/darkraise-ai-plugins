#!/usr/bin/env bash
# lens-route picks the specialist review lenses for a final review or a risk-3
# task. Each case pins one selection rule against a throwaway repository.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTE="$HERE/../scripts/lens-route"
export DR_FORGE_NO_SETTINGS=1
unset DR_FORGE_LENS_CAP CLAUDE_CONFIG_DIR

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
short() { sed -E 's/ criteria=[^ ]*//; s/ seat=[^ ]*//; s/ reason=(always|added|paths:[^ ]*)$//' | tr '\n' ';'; }

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
check "final: a shell-only change gets security and lang-bash" "$(short <<<"$out")" "lens security;lens lang-bash;"
check "final: no lens whose clauses all fail" "$(grep -cE '^lens (lang-csharp|lang-python|lang-typescript|type-design)' <<<"$out")" "0"
check "final: the seat and reason" "$(grep -c '^lens security criteria=[^ ]* seat=dforge:judge-sonnet-high reason=always$' <<<"$out")" "1"
crit=$(sed -n 's/^lens lang-bash criteria=\([^ ]*\) .*/\1/p' <<<"$out")
check "final: the criteria path exists" "$([ -f "$crit" ] && echo yes || echo no)" "yes"
check "final: the reason names the glob" "$(grep -c '^lens lang-bash .* reason=paths:\*\.sh$' <<<"$out")" "1"

# A2: more applicable lenses than the cap.
commit_file tests/a.test.ts 'try { run() } catch (e) {}'
commit_file README.md 'Docs.'
HEAD2=$(git rev-parse HEAD)
out=$(DR_FORGE_LENS_CAP=2 bash "$ROUTE" plan.md --final "$BASE" "$HEAD2")
check "cap 2: two lenses, the rest skipped in order" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens-skipped test-quality reason=cap;lens-skipped lang-bash reason=cap;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
out=$(bash "$ROUTE" plan.md --final "$BASE" "$HEAD2")
check "default cap 4" "$(short <<<"$out")" \
  "lens security;lens silent-failures;lens test-quality;lens lang-bash;lens-skipped lang-typescript reason=cap;lens-skipped docs-comments reason=cap;"
out=$(DR_FORGE_LENS_CAP=0 bash "$ROUTE" plan.md --final "$BASE" "$HEAD2")
check "cap 0: lenses off" "$out" "lenses off"

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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
