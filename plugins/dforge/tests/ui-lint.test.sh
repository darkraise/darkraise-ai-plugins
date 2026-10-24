#!/usr/bin/env bash
# ui-lint holds only high-precision UI defect patterns: every rule reports its
# failing fixture and stays silent on its passing one. Fixtures are stored as
# *.fixture (tsc type-checks tests/) and copied to their real extension here;
# android ones under res/layout/, where the rule applies.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LINT="$HERE/../scripts/ui-lint"
FIX="$HERE/fixtures/ui-lint"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

RULES="raw-color outline-removed click-non-interactive img-alt transition-all zoom-disabled tabindex-positive paste-blocked xaml-hardcoded-brush android-hardcoded-color android-hardcoded-text android-image-description"
for rule in $RULES; do
  check "$rule: has a failing and a passing fixture" "$(ls "$FIX" | grep -cE "^$rule\.(bad|good)\.[a-z]+\.fixture$")" "2"
done

for f in "$FIX"/*.fixture; do
  name=$(basename "$f" .fixture)          # <rule>.<bad|good>.<ext>
  rule=${name%%.*}
  rest=${name#*.}
  kind=${rest%%.*}
  case $rule in android-*) rel="res/layout/$name" ;; *) rel=$name ;; esac
  mkdir -p "$WORK/$(dirname "$rel")"
  cp "$f" "$WORK/$rel"
  out=$(cd "$WORK" && bash "$LINT" "$rel"); st=$?
  if [ "$kind" = bad ]; then
    check "$rule: the failing fixture is reported" "$(grep -c "^$rel:[0-9]*: $rule " <<<"$out")" "1"
    check "$rule: exit 1 on findings" "$st" "1"
  else
    check "$rule: the passing fixture is silent" "$out" ""
    check "$rule: exit 0 without findings" "$st" "0"
  fi
done

printf '<div>ok</div>\n' > "$WORK/plain.md"
check "a file of no UI kind is skipped" "$(cd "$WORK" && bash "$LINT" plain.md; echo "exit $?")" "exit 0"
bash "$LINT" >/dev/null 2>&1; check "usage: no file exits 2" "$?" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
