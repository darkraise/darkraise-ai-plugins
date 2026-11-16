#!/usr/bin/env bash
# repo-audit replaces a resuming session's orientation calls with one read-only
# snapshot: branch, worktrees, dirty files, plans in flight, handoff staleness,
# the CLAUDE.md compaction section, the budget line and recent commits.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/repo-audit"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DFORGE_BUDGET DFORGE_JQ DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q -b main "$REPO"
mkdir -p "$REPO/docs"
printf '# Plan\n\n### Task 1: One\n\n### Task 2: Two\n\n### Task 3: Three\n' > "$REPO/docs/plan.md"
printf '# Project\n\nNo compaction notes.\n' > "$REPO/CLAUDE.md"
printf '.dforge/\n' > "$REPO/.gitignore"
git -C "$REPO" add -A && git -C "$REPO" commit -qm init
ROOT="$(git -C "$REPO" rev-parse --show-toplevel)"

WT="$TMP/wt"
git -C "$REPO" worktree add -q -b feat "$WT"
WT_ROOT="$(git -C "$WT" rev-parse --show-toplevel)"
WS="$WT/.dforge/sdd/plan"
mkdir -p "$WS"
printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commits a..b, review clean)\nTask 2: fix round 1/5 (1 addressed, 1 open — x)\n' > "$WS/progress.md"
printf '# Handoff notes\n' > "$WS/handoff.md"

mkdir -p "$REPO/.dforge/handoff"
printf '# Handoff\n\n## Next session\n\n**Status:** Plan `docs/plan.md`: 1 of 3 tasks complete.\n**Next:** Resume at Task 2 (Two).\n' \
  > "$REPO/.dforge/handoff/latest.md"
touch -d '1 hour ago' "$REPO/.dforge/handoff/latest.md"
printf 'later\n' > "$REPO/later.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm second

run() { out=$(cd "$1" && bash "$SCRIPT" "${@:2}" 2>"$TMP/stderr"); status=$?; }

# --- primary checkout ---
run "$REPO"
check "primary: exit 0" "$status" "0"
has "primary: heading" "$out" "# Repo audit"
has "primary: root" "$out" "- Root: \`$ROOT\`"
has "primary: branch" "$out" "- Branch: \`main\` at "
has "primary: budget line" "$out" "- budget: unknown of 790k — unknown — no transcript found"
has "primary: worktree listed with branch" "$out" "[feat]"
has "primary: clean tree" "$out" "## Dirty files (0)"
has "primary: plan in flight" "$out" "- \`docs/plan.md\` in \`$WT_ROOT\`: 1 of 3 tasks complete; handoff.md: yes"
has "primary: last ledger line" "$out" "  - last ledger line: Task 2: fix round 1/5 (1 addressed, 1 open — x)"
has "primary: handoff status" "$out" "- **Status:** Plan \`docs/plan.md\`: 1 of 3 tasks complete."
has "primary: handoff staleness" "$out" "- Commits on the primary checkout's HEAD since it was written: 2"
has "primary: no compact section" "$out" "- CLAUDE.md has no Compact Instructions section"
has "primary: recent commits" "$out" " second"

# --- dirty tree and a Compact Instructions section ---
printf '# Project\n\n# Compact instructions\n\nKeep paths.\n' > "$REPO/CLAUDE.md"
run "$REPO"
has "dirty: counted" "$out" "## Dirty files (1)"
has "compact section: found" "$out" "- CLAUDE.md has a Compact Instructions section"

# --- from the worktree ---
run "$WT"
has "worktree: primary named" "$out" "- Primary checkout: \`$ROOT\`"
has "worktree: branch" "$out" "- Branch: \`feat\` at "

# --- errors ---
mkdir -p "$TMP/notrepo"
run "$TMP/notrepo"
check "outside a repository: exit 2" "$status" "2"
run "$REPO" extra
check "usage: exit 2" "$status" "2"

git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1

# --- item registers ---
OUT=$(cd "$REPO" && bash "$SCRIPT" 2>&1)
has "audit: the section exists" "$OUT" "## Item registers"
# Scoped to the section: "- none" is already printed by Plans in flight and
# Handoff, so an unscoped assertion would pass against a stub.
SECTION=$(sed -n '/## Item registers/,/^$/p' <<<"$OUT")
has "audit: no registers says so" "$SECTION" "- none"

mkdir -p "$REPO/docs/dforge/registers"
cat > "$REPO/docs/dforge/registers/r.md" <<'REG'
# R — item register

**Source:** owner list
**Covers:** -

| # | Item | Assigned | Acceptance | State | Note |
|---|---|---|---|---|---|
| 1 | Done thing | - | - | done | - |
| 2 | Open thing | - | - | planned | - |
| 3 | Owner check | - | live check | verify | owner live check owed |
REG
OUT=$(cd "$REPO" && bash "$SCRIPT" 2>&1)
has "audit: counts open rows" "$OUT" "2 open"
has "audit: counts rows awaiting the owner" "$OUT" "1 awaiting your check"
has "audit: counts the whole register" "$OUT" "of 3 rows"
has "audit: names the register" "$OUT" "docs/dforge/registers/r.md"

# --- roadmap ---
OUT=$(cd "$REPO" && bash "$SCRIPT" 2>&1)
SECTION=$(sed -n '/## Roadmap/,/^$/p' <<<"$OUT")
has "audit: the roadmap section exists" "$OUT" "## Roadmap"
has "audit: no roadmap says so" "$SECTION" "- none"
mkdir -p "$REPO/docs/dforge/specs" "$REPO/docs/dforge/registers"
: > "$REPO/docs/dforge/specs/shop-design.md"
printf '# M1 — item register\n\n**Source:** roadmap\n**Covers:** docs/superpowers/specs/shop-design.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Search | - | - | open | - |\n' \
  > "$REPO/docs/dforge/registers/m1.md"
printf '# Shop — roadmap\n\n**Product:** a shop\n**Spec:** docs/superpowers/specs/shop-design.md\n\n| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n| M1 | MVP | every epic resolved | docs/superpowers/registers/m1.md | open | - |\n' \
  > "$REPO/docs/dforge/roadmap.md"
OUT=$(cd "$REPO" && bash "$SCRIPT" 2>&1)
SECTION=$(sed -n '/## Roadmap/,/^$/p' <<<"$OUT")
has "audit: lists the milestone" "$SECTION" "- M1 MVP — open — 0 of 1 epics resolved; open: #1 Search (open)"
has "audit: names the current milestone" "$SECTION" "- Current: M1 MVP"

# --- progress kept in darkmem: the mirror's ledgers and latest.md ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
M=$(stores_home "$SH" "$REPO" proj local darkmem)
mkdir -p "$M/work/sdd/plan"
printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commits a..b, review clean)\n' > "$M/work/sdd/plan/progress.md"
printf '# Handoff\n\n**Status:** mirror status\n' > "$M/work/handoff/latest.md"
out=$(cd "$REPO" && HOME=$SH bash "$SCRIPT")
has "darkmem: the mirror's ledger" "$out" "- \`docs/plan.md\` in the darkmem mirror: 1 of 3 tasks complete"
has "darkmem: the mirror's latest.md" "$out" "- \`$M/work/handoff/latest.md\`"
has "darkmem: its status" "$out" "**Status:** mirror status"

# --- a plan with lettered headings has an unknown task count, not zero ---
printf '# Plan\n\n### Task A1: One\n' > "$REPO/docs/lettered.md"
mkdir -p "$REPO/.dforge/sdd/lettered"
printf '# SDD ledger — plan: docs/lettered.md\n' > "$REPO/.dforge/sdd/lettered/progress.md"
out=$(cd "$REPO" && bash "$SCRIPT")
has "lettered: the task total is unknown" "$out" "- \`docs/lettered.md\` in \`$ROOT\`: 0 of ? tasks complete"
rm -rf "$REPO/docs/lettered.md" "$REPO/.dforge/sdd/lettered"

# --- an older directory is named with the skill that moves it ---
check "4.0 layout: no migration line" "$(grep -c 'older layout' <<<"$out")" "0"
W2="$TMP/wt2"
git -C "$REPO" worktree add -q --detach "$W2"
W2_ROOT="$(git -C "$W2" rev-parse --show-toplevel)"
mkdir -p "$REPO/.superpowers" "$W2/docs/superpowers"
out=$(cd "$W2" && bash "$SCRIPT" 2>&1)
has "older layout: the worktree's and the primary's directories, with the migrate command" "$out" \
  "- dforge: this repository still uses an older layout ($ROOT/.superpowers, $W2_ROOT/docs/superpowers); run the dforge:migrate skill (/dforge:migrate)"
git -C "$REPO" worktree remove --force "$W2" >/dev/null 2>&1
rm -rf "$REPO/.superpowers"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
