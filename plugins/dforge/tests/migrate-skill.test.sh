#!/usr/bin/env bash
# The migrate skill is a document: what makes it safe is its order (a dry run
# before anything writes, a confirmation before the migration and before the
# commit) and the names it hands the human. A model is not needed to check them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL="$P/skills/migrate/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1))
  else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
line_of() { grep -nF -- "$2" "$1" | head -n 1 | cut -d: -f1; }

check "exists: skills/migrate/SKILL.md" "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"
present "named migrate" "$SKILL" "name: migrate"
dry=$(line_of "$SKILL" 'scripts/dforge-migrate --dry-run')
real=$(line_of "$SKILL" 'Run `bash <plugin-root>/scripts/dforge-migrate` and show')
confirm=$(line_of "$SKILL" 'Run nothing')
check "the dry run comes first" "$([ -n "$dry" ] && [ -n "$real" ] && [ "$dry" -lt "$real" ] && echo yes || echo no)" "yes"
check "the confirmation comes before the migration" "$([ -n "$confirm" ] && [ "$confirm" -lt "$real" ] && echo yes || echo no)" "yes"
present "asks before migrating" "$SKILL" "that writes before a yes"
present "asks before committing" "$SKILL" "human partner agrees, and stage nothing"
present "commits only what the commit lines name" "$SKILL" "stage nothing the lines do not name"
present "names the plugin uninstall" "$SKILL" '`dr-forge@darkraise` and `dr-superpowers@darkraise`'
present "names the webhook keys dforge does not read" "$SKILL" '`notifyUrl` and `notifyMention`'
present "names the webhook command" "$SKILL" '`/cockpit notify url <url>`'
present "names the mention command" "$SKILL" '`/cockpit notify mention <id>`'
webhook=$(line_of "$SKILL" '`notifyUrl` and `notifyMention`')
uninstall=$(line_of "$SKILL" '`dr-forge@darkraise` and `dr-superpowers@darkraise`')
check "the webhook is copied before the uninstall" "$([ -n "$webhook" ] && [ -n "$uninstall" ] && [ "$webhook" -lt "$uninstall" ] && echo yes || echo no)" "yes"
present "names the environment rename" "$SKILL" '`DFORGE_*` environment variables in place of `DR_FORGE_*`'
present "writes nothing itself" "$SKILL" "This skill writes nothing"
present "the entry point routes to it" "$P/skills/using-dforge/SKILL.md" "| dforge:migrate |"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
