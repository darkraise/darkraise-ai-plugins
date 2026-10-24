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

lint_out() { (cd "$WORK" && bash "$LINT" "$1"); }
printf '.btn { color: #1a56db; }\n:root { --ring: #1a56db; }\n' > "$WORK/theme.css"
check "a token file may hold raw colours" "$(lint_out theme.css)" ""
printf ':root { --ring: #1a56db; }\n' > "$WORK/main.css"
check "a custom property definition is not a raw colour" "$(lint_out main.css)" ""
printf '.btn { color: #1a56db; }\n' > "$WORK/main.css"
check "the same colour in an ordinary file is reported" "$(lint_out main.css | grep -c 'raw-color')" "1"
printf '<meta name="viewport" content="width=device-width, maximum-scale=1.5">\n' > "$WORK/zoom.html"
check "zoom: maximum-scale above 1 is allowed" "$(lint_out zoom.html)" ""
printf '<meta name="viewport" content="width=device-width, user-scalable=no">\n' > "$WORK/zoom.html"
check "zoom: user-scalable=no is reported" "$(lint_out zoom.html | grep -c 'zoom-disabled')" "1"
printf '<div tabIndex={0} />\n<div tabIndex={-1} />\n' > "$WORK/tab.tsx"
check "tabindex: 0 and -1 are allowed" "$(lint_out tab.tsx)" ""

mkdir -p "$WORK/badawk"
printf '#!/bin/sh\nexit 2\n' > "$WORK/badawk/awk"; chmod +x "$WORK/badawk/awk"
check "a crashed awk is exit 2, never a clean pass" "$(cd "$WORK" && PATH="$WORK/badawk:$PATH" bash "$LINT" main.css 2>/dev/null; echo "exit $?")" "exit 2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
