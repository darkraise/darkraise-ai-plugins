#!/usr/bin/env bash
# A skill-enforced setting is only as good as the skill text that names it:
# each key must be named where its decision is made.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
command -v node > /dev/null 2>&1 || { echo "settings-skills tests: node is required but not on PATH" >&2; exit 2; }

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" && echo yes || echo no)" "yes"
}

B="$P/skills/brainstorming/SKILL.md"

names "brainstorming: the fast Process line" "$B" '`Process: fast — <why>`'
H="$P/skills/handoff/SKILL.md"
names "handoff: a design phase writes the Draft line" "$H" '- Draft: `<spec path>`'

# Every skill-enforced key in the schema is named by at least one skill, as
# `key` or key=value: a bare word such as "worktree" is not a naming.
keys=$(node -e 'const { pathToFileURL } = require("url"); import(pathToFileURL(process.argv[1]).href).then(m => console.log(Object.entries(m.default).filter(([, spec]) => spec.enforcedBy === "skill").map(([key]) => key).join(" ")))' "$P/config/schema.mjs")
check "the schema has skill-enforced keys" "$([ -n "$keys" ] && echo yes || echo no)" "yes"
for key in $keys; do
  check "a skill names $key" "$(grep -lE -- "\`$key\`|$key=" "$P"/skills/*/SKILL.md | head -n 1 | grep -c .)" "1"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
