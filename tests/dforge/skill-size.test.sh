#!/usr/bin/env bash
# Every SKILL.md body (the text after its frontmatter) stays at or under 19,500
# characters. After a compaction Claude Code re-attaches about the first 19,900
# characters of an invoked skill, counted after it strips the frontmatter and
# prepends a "Base directory for this skill: <path>" line, so text past that
# point is lost to a long session; the 400 between the two cover that line on
# a long install path. Text a step reads only at that step lives in
# references/, linked from the step by a "Read [x](references/x) before you ..."
# line.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/../../plugins/dforge"
CAP=19500

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

body_chars() { # body_chars <file> — characters after the frontmatter
  node -e '
const s = require("fs").readFileSync(process.argv[1], "utf8").replace(/\r/g, "");
const m = s.match(/^---\n[\s\S]*?\n---\n/);
console.log([...(m ? s.slice(m[0].length) : s)].length);
' "$1" | tr -d '\r'
}

over_cap() { # over_cap <skills dir> — one line per SKILL.md over the cap
  local f n
  for f in "$1"/*/SKILL.md; do
    [ -f "$f" ] || continue
    n=$(body_chars "$f")
    [ "$n" -le "$CAP" ] || printf 'skill-size: plugins/dforge/skills/%s/SKILL.md %s characters (cap %s)\n' "$(basename "$(dirname "$f")")" "$n" "$CAP"
  done
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/at" "$TMP/front" "$TMP/wide" "$TMP/over" "$TMP/way-over"
x() { head -c "$1" /dev/zero | tr '\0' x; }
x 19500 > "$TMP/at/SKILL.md"
{ printf -- '---\nname: front\ndescription: %s\n---\n' "$(x 300)"; x 19500; } > "$TMP/front/SKILL.md"
for _ in $(seq 19500); do printf 'é'; done > "$TMP/wide/SKILL.md"
x 19501 > "$TMP/over/SKILL.md"
x 30000 > "$TMP/way-over/SKILL.md"
check "a body at the cap passes, frontmatter and multibyte characters included; each one over it is named with its size" "$(over_cap "$TMP")" \
  "$(printf 'skill-size: plugins/dforge/skills/over/SKILL.md 19501 characters (cap 19500)\nskill-size: plugins/dforge/skills/way-over/SKILL.md 30000 characters (cap 19500)')"

over=$(over_cap "$P/skills")
[ -z "$over" ] || printf '%s\n' "$over"
check "every SKILL.md body is at most $CAP characters" "$over" ""

linked() { # linked <skill> <reference> — SKILL.md has the Read line and the file exists
  check "$1 links references/$2" \
    "$(grep -cF "Read [$2](references/$2) before you " "$P/skills/$1/SKILL.md") $([ -s "$P/skills/$1/references/$2" ] && echo present || echo missing)" "1 present"
}
for ref in setup.md recovery.md ruling-seat.md; do linked executing-plans "$ref"; done
for ref in ui-proof.md execute-choice.md cleanup.md; do linked finishing-a-development-branch "$ref"; done
for ref in discovery-optimization.md match-the-form.md; do linked writing-skills "$ref"; done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
