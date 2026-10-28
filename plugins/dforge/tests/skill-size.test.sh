#!/usr/bin/env bash
# Every SKILL.md stays at or under 20,000 bytes: after a compaction Claude Code
# re-attaches only the first 5,000 tokens of an invoked skill, so text past the
# cap is lost to a long session. Text a step reads only at that step lives in
# references/, linked from the step by a "Read [x](references/x) before you ..."
# line.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
CAP=20000

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

over_cap() { # over_cap <skills dir> — one line per SKILL.md over the cap
  local f bytes
  for f in "$1"/*/SKILL.md; do
    [ -f "$f" ] || continue
    bytes=$(wc -c < "$f" | tr -d ' \r')
    [ "$bytes" -le "$CAP" ] || printf 'skill-size: plugins/dforge/skills/%s/SKILL.md %s bytes (cap %s)\n' "$(basename "$(dirname "$f")")" "$bytes" "$CAP"
  done
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/at" "$TMP/over" "$TMP/way-over"
head -c 20000 /dev/zero | tr '\0' x > "$TMP/at/SKILL.md"
head -c 20001 /dev/zero | tr '\0' x > "$TMP/over/SKILL.md"
head -c 30000 /dev/zero | tr '\0' x > "$TMP/way-over/SKILL.md"
check "a skill at the cap passes; each skill over it is named with its size" "$(over_cap "$TMP")" \
  "$(printf 'skill-size: plugins/dforge/skills/over/SKILL.md 20001 bytes (cap 20000)\nskill-size: plugins/dforge/skills/way-over/SKILL.md 30000 bytes (cap 20000)')"

over=$(over_cap "$P/skills")
[ -z "$over" ] || printf '%s\n' "$over"
check "every SKILL.md is at most $CAP bytes" "$over" ""

linked() { # linked <skill> <reference> — SKILL.md has the Read line and the file exists
  check "$1 links references/$2" \
    "$(grep -cF "Read [$2](references/$2) before you " "$P/skills/$1/SKILL.md") $([ -s "$P/skills/$1/references/$2" ] && echo present || echo missing)" "1 present"
}
for ref in setup.md recovery.md ruling-seat.md switching.md finish-rulings.md rationalizations.md; do linked executing-plans "$ref"; done
for ref in ui-proof.md execute-choice.md cleanup.md rationalizations.md; do linked finishing-a-development-branch "$ref"; done
for ref in discovery-optimization.md match-the-form.md; do linked writing-skills "$ref"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
