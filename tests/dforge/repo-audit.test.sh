#!/usr/bin/env bash
# repo-audit replaces a resuming session's orientation calls with one read-only
# snapshot: branch, worktrees, dirty files, plans in flight, handoff staleness,
# the CLAUDE.md compaction section, the budget line and recent commits.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../plugins/dforge/scripts/repo-audit"

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
  > "$REPO/.dforge/handoff/plan.md"
touch -d '1 hour ago' "$REPO/.dforge/handoff/plan.md"
printf 'later\n' > "$REPO/later.txt"
git -C "$REPO" add -A && git -C "$REPO" commit -qm second

run() { out=$(cd "$1" && bash "$SCRIPT" "${@:2}" 2>"$TMP/stderr"); status=$?; }

# --- primary checkout ---
run "$REPO"
check "primary: exit 0" "$status" "0"
has "primary: heading" "$out" "# Repo audit"
has "primary: root" "$out" "- Root: \`$ROOT\`"
has "primary: branch" "$out" "- Branch: \`main\` at "
has "primary: budget line" "$out" "- budget: unknown — unknown — no transcript found"
has "primary: worktree listed with branch" "$out" "[feat]"
has "primary: clean tree" "$out" "## Dirty files (0)"
has "primary: plan in flight" "$out" "- \`docs/plan.md\` in \`$WT_ROOT\`: 1 of 3 tasks complete; handoff.md: yes"
has "primary: last ledger line" "$out" "  - last ledger line: Task 2: fix round 1/5 (1 addressed, 1 open — x)"
has "primary: handoff status" "$out" "- **Status:** Plan \`docs/plan.md\`: 1 of 3 tasks complete."
check "primary: no session id, so no handoff carries the commit count" "$(grep -c "Commits on this checkout's HEAD" <<<"$out")" "0"
has "primary: no compact section" "$out" "- CLAUDE.md has no Compact Instructions section"
has "primary: recent commits" "$out" " second"

# --- dirty tree and a Compact Instructions section ---
printf '# Project\n\n# Compact instructions\n\nKeep paths.\n' > "$REPO/CLAUDE.md"
run "$REPO"
has "dirty: counted" "$out" "## Dirty files (1)"
has "compact section: found" "$out" "- CLAUDE.md has a Compact Instructions section"
{ printf '# Project\n\n# Compact instructions\n\n'; head -c 200000 /dev/zero | tr '\0' 'x' | fold -w 100; } > "$REPO/CLAUDE.md"
run "$REPO"
has "compact section: found in a CLAUDE.md over 64 KiB" "$out" "- CLAUDE.md has a Compact Instructions section"

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

# --- progress kept in darkmem: the mirror's ledgers and handoffs ---
. "$HERE/fixtures/darkmem-stores.sh"
SH="$TMP/stores-home"; mkdir -p "$SH"
M=$(stores_home "$SH" "$REPO" proj local darkmem)
mkdir -p "$M/work/sdd/plan"
printf '# SDD ledger — plan: docs/plan.md\nTask 1: complete (commits a..b, review clean)\n' > "$M/work/sdd/plan/progress.md"
printf '# Handoff\n\n## Next session\n\n**Status:** mirror status\n' > "$M/work/handoff/plan.md"
out=$(cd "$REPO" && HOME=$SH bash "$SCRIPT")
has "darkmem: the mirror's ledger" "$out" "- \`docs/plan.md\` in the darkmem mirror: 1 of 3 tasks complete"
has "darkmem: the mirror's handoff" "$out" "- \`$M/work/handoff/plan.md\`"
has "darkmem: its status" "$out" "**Status:** mirror status"
# A mirror handoff is recomputed from the primary: a gone draft's is removed.
printf '# Handoff\n\n## Next session\n\n**Status:** s\n**Next:** n\n<!-- next-step: kind=draft key=gone-design session=- done=0 closed=0 subject=docs/gone-design.md at=1 -->\n' > "$M/work/handoff/gone-design.md"
out=$(cd "$REPO" && HOME=$SH bash "$SCRIPT")
has "darkmem: a finished mirror handoff is recomputed and removed" "$out" "- removed finished handoff $M/work/handoff/gone-design.md — the draft docs/gone-design.md is gone"
check "darkmem: the mirror handoff is gone" "$([ -e "$M/work/handoff/gone-design.md" ] && echo yes || echo no)" "no"

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
mkdir -p "$REPO/.superpowers" "$W2/docs/superpowers" "$W2/.dforge/handoff"
printf '# Handoff\n<!-- next-step: kind=plan session=- done=0 closed=0 subject=docs/dforge/plans/old.md at=1 -->\n' > "$W2/.dforge/handoff/latest.md"
out=$(cd "$W2" && bash "$SCRIPT" 2>&1)
has "older layout notice: a remaining latest.md is named with its subject and the migrate skill" "$out" \
  "- dforge: $W2_ROOT/.dforge/handoff/latest.md is a handoff in an older layout (subject docs/dforge/plans/old.md); run the dforge:migrate skill (/dforge:migrate)"
has "older layout: the worktree's and the primary's directories, with the migrate command" "$out" \
  "- dforge: this repository still uses an older layout ($ROOT/.superpowers, $W2_ROOT/docs/superpowers); run the dforge:migrate skill (/dforge:migrate)"
git -C "$REPO" worktree remove --force "$W2" >/dev/null 2>&1
rm -rf "$REPO/.superpowers"

# --- the Handoff section recomputes the stored block ---
H="$TMP/handoff"
git init -q -b main "$H"
H_ROOT="$(git -C "$H" rev-parse --show-toplevel)"
mkdir -p "$H/docs/dforge/plans" "$H/.dforge/sdd/2026-11-01-p" "$H/.dforge/handoff"
printf '.dforge/\n' > "$H/.gitignore"
printf '# P\n\n**Spec:** docs/dforge/specs/p.md\n**Execution:** inline — `claude --model sonnet --effort high` — x\n\n### Task 1: One\n\n### Task 2: Two\n\n### Task 3: Three\n' \
  > "$H/docs/dforge/plans/2026-11-01-p.md"
git -C "$H" add -A && git -C "$H" commit -qm init
printf '# SDD ledger — plan: docs/dforge/plans/2026-11-01-p.md\nTask 1: complete (x)\nTask 2: complete (x)\n' > "$H/.dforge/sdd/2026-11-01-p/progress.md"
hstored() { # hstored <marker> — a handoff by hand, its Next line stale
  printf '# Handoff\n\n## Next session\n\n**Status:** Plan stored status.\n**Next:** Resume at Task 2 (Two).\n%s\n' "$1" > "$H/.dforge/handoff/2026-11-01-p.md"
}
handoff_section() { (cd "$H" && bash "$SCRIPT" 2>/dev/null) | sed -n '/^## Handoff/,/^$/p'; }
hstored "<!-- next-step: kind=plan done=0 closed=0 subject=docs/dforge/plans/2026-11-01-p.md at=1 -->"
SECTION=$(handoff_section)
has "handoff: the lines are recomputed" "$SECTION" "- recomputed from the repository"
has "handoff: the recomputed Next line" "$SECTION" "- **Next:** Resume at Task 3"
# An adhoc block is never superseded (C10); a finished plan's is.
printf '# Completed plans\n\n- 2026-11-01 — `docs/dforge/plans/2026-11-01-p.md` — merged\n' > "$H/docs/dforge/plans/completed.md"
hstored "<!-- next-step: kind=plan done=0 closed=0 subject=docs/dforge/plans/2026-11-01-p.md at=1 -->"
has "handoff: a finished plan's block is removed" "$(handoff_section)" "- removed finished handoff $H_ROOT/.dforge/handoff/2026-11-01-p.md — the plan is finished: docs/dforge/plans/2026-11-01-p.md"
hstored "<!-- next-step: kind=plan done=1 closed=0 subject=docs/dforge/plans/missing.md at=1 -->"
SECTION=$(handoff_section)
has "handoff: a failed recompute is named" "$SECTION" "- stored, not recomputed: next-step: no such file"
has "handoff: a failed recompute prints the stored Status" "$SECTION" "- **Status:** Plan stored status."
has "handoff: a failed recompute prints the stored Next" "$SECTION" "- **Next:** Resume at Task 2 (Two)."
# A marker next-step cannot read is no finished handoff: it is kept and listed.
hstored "<!-- next-step: kind=plan done=1x closed=0 subject=docs/dforge/plans/2026-11-01-p.md at=1 -->"
has "handoff: a malformed marker is listed as stored" "$(handoff_section)" "- stored, not recomputed: next-step: malformed marker counts"
check "handoff: a malformed marker's handoff is kept" "$([ -f "$H/.dforge/handoff/2026-11-01-p.md" ] && echo kept || echo removed)" "kept"

# --- every checkout's handoff (spec A10) ---
A10="$TMP/a10"; git -C "$REPO" worktree add -q -b a10 "$A10"
A10_ROOT=$(git -C "$A10" rev-parse --show-toplevel)
mkdir -p "$A10/.dforge/handoff"
printf '# Handoff\n\n## Next session\n\n**Status:** a10 status\n**Next:** a10 next\n<!-- next-step: kind=adhoc done=0 closed=0 subject=- at=%s -->\n' "$(( $(date +%s) - 7200 ))" > "$A10/.dforge/handoff/adhoc-0a100000.md"
touch -d '2 hours ago' "$A10/.dforge/handoff/adhoc-0a100000.md"
NOH="$TMP/noh"; git -C "$REPO" worktree add -q -b noh "$NOH"
NOH_ROOT=$(git -C "$NOH" rev-parse --show-toplevel)
git -C "$REPO" worktree add -q -b gone "$TMP/gone"
GONE_ROOT=$(git -C "$TMP/gone" rev-parse --show-toplevel); rm -rf "$TMP/gone"
run "$REPO"
HSEC=$(sed -n '/^## Handoff/,/^## /p' <<<"$out")
has "A10: the own handoff first" "$(sed -n 2p <<<"$HSEC")" "- \`$ROOT/.dforge/handoff/plan.md\`"
has "A10: the worktree's handoff listed with its key, kind, age and claim" "$HSEC" "- \`$A10_ROOT/.dforge/handoff/adhoc-0a100000.md\` — key adhoc-0a100000, kind adhoc, 2h old, unclaimed"
has "A10: marked stored" "$HSEC" "- stored (kind adhoc is not recomputed)"
has "A10: its stored status" "$HSEC" "- **Status:** a10 status"
check "A10: a checkout with no handoff gets no entry" "$(grep -cF -- "$NOH_ROOT" <<<"$HSEC")" "0"
has "A10: a missing worktree is skipped" "$HSEC" "- skipped \`$GONE_ROOT\`: prunable or missing"
. "$HERE/fixtures/git-without-z.sh"
git_without_z "$TMP/noz"
PATH="$TMP/noz:$PATH" run "$REPO"
has "worktree list: a git without -z still lists the worktrees" "$(sed -n '/^## Worktrees/,/^## /p' <<<"$out")" "[a10]"
has "worktree list: a git without -z still skips a missing worktree" "$(sed -n '/^## Handoff/,/^## /p' <<<"$out")" "- skipped \`$GONE_ROOT\`: prunable or missing"
git -C "$REPO" worktree remove --force "$A10"; git -C "$REPO" worktree remove --force "$NOH"; git -C "$REPO" worktree prune

# --- keyed handoffs: listing, claims and cleanup (spec A10, A16, A20) ---
OWN=11111111-1111-4111-8111-111111111111
LIVE=22222222-2222-4222-8222-222222222222
GONE=33333333-3333-4333-8333-333333333333
beat() { # beat <session> — the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "${f%/*}"; date +%s > "$f"
}
beat "$LIVE"; beat "$OWN"
kh() { # kh <file> <kind> <session> <subject> <status> <next> — a keyed handoff as next-step writes it
  mkdir -p "${1%/*}"
  printf '# Handoff\n\n## Next session\n\n**Status:** %s\n**Next:** %s\n<!-- next-step: kind=%s key=%s session=%s done=1 closed=0 subject=%s at=%s -->\n' \
    "$5" "$6" "$2" "$(basename "$1" .md)" "$3" "$4" "$(date +%s)" > "$1"
}
kclaim() { # kclaim <checkout> <key> <session> — the claim file scripts/handoff claim writes
  mkdir -p "$1/.dforge/handoff/claims"
  printf 'session=%s\nat=%s\n' "$3" "$(date +%s)" > "$1/.dforge/handoff/claims/$2"
}
krepo() { # krepo <dir> — a repository whose plans q (Task 1 of 3 done) and others are committed
  git init -q -b main "$1"
  mkdir -p "$1/docs/dforge/plans" "$1/docs/dforge/specs"
  printf '.dforge/\n' > "$1/.gitignore"
  local p
  for p in 2026-11-01-q 2026-11-02-fin 2026-11-03-done 2026-11-04-named 2026-11-05-prog; do
    printf '# %s\n\n**Execution:** inline — `claude --model sonnet --effort high` — x\n\n### Task 1: One\n\n### Task 2: Two\n\n### Task 3: Three\n' "$p" > "$1/docs/dforge/plans/$p.md"
  done
  sed -i 's|^\*\*Execution:|**Spec:** docs/dforge/specs/named-design.md\n**Execution:|' "$1/docs/dforge/plans/2026-11-04-named.md"
  sed -i 's|^\*\*Execution:|**Program:** docs/dforge/specs/prog-design.md\n**Execution:|' "$1/docs/dforge/plans/2026-11-05-prog.md"
  git -C "$1" add -A && git -C "$1" commit -qm init
}
audit() { # audit <dir> [session] — repo-audit's Handoff and Stale handoffs sections
  out=$(cd "$1" && CLAUDE_CODE_SESSION_ID=${2:-} bash "$SCRIPT" 2>"$TMP/stderr"); status=$?
  HSEC=$(sed -n '/^## Handoff/,/^## Compaction/p' <<<"$out")
  STALE=$(sed -n '/^## Stale handoffs/,/^$/p' <<<"$out")
}

# lists_every_handoff_with_claims (A10)
K="$TMP/k"; krepo "$K"; K=$(git -C "$K" rev-parse --show-toplevel)
git -C "$K" worktree add -q -b kw "$TMP/kw"; KW=$(git -C "$TMP/kw" rev-parse --show-toplevel)
mkdir -p "$KW/.dforge/sdd/2026-11-01-q"
printf '# SDD ledger — plan: docs/dforge/plans/2026-11-01-q.md\nTask 1: complete (x)\n' > "$KW/.dforge/sdd/2026-11-01-q/progress.md"
kh "$KW/.dforge/handoff/2026-11-01-q.md" plan - docs/dforge/plans/2026-11-01-q.md "Plan stored q status." "Stored q next."
touch -d '3 hours ago' "$KW/.dforge/handoff/2026-11-01-q.md"
kclaim "$K" 2026-11-01-q "$OWN"
kh "$K/.dforge/handoff/adhoc-aaaaaaaa.md" adhoc "$LIVE" - "Unplanned work: live." "Carry on live."
kclaim "$K" adhoc-aaaaaaaa "$LIVE"
kh "$K/.dforge/handoff/adhoc-bbbbbbbb.md" adhoc "$GONE" - "Unplanned work: gone." "Carry on gone."
kclaim "$K" adhoc-bbbbbbbb "$GONE"
kh "$KW/.dforge/handoff/adhoc-cccccccc.md" adhoc - - "Unplanned work: free." "Carry on free."
touch -d '5 hours ago' "$K/.dforge/handoff/adhoc-aaaaaaaa.md" "$K/.dforge/handoff/adhoc-bbbbbbbb.md" "$KW/.dforge/handoff/adhoc-cccccccc.md"
audit "$K" "$OWN"
check "A10 keyed: exit 0" "$status" "0"
has "A10 keyed: this session's claimed handoff first, in another checkout" "$(sed -n 2p <<<"$HSEC")" \
  "- \`$KW/.dforge/handoff/2026-11-01-q.md\` — key 2026-11-01-q, kind plan, 3h old, claimed 11111111 live (this session's)"
has "A10 keyed: this session's handoff is recomputed" "$(sed -n 3p <<<"$HSEC")" "- recomputed from the repository"
has "A10 keyed: the recomputed Next line" "$HSEC" "- **Next:** Resume at Task 2"
has "A10 keyed: this session's handoff carries the commit count" "$HSEC" "- Commits on this checkout's HEAD since it was written: 1"
check "A10 keyed: the stored Next line is not shown for it" "$(grep -c 'Stored q next' <<<"$HSEC")" "0"
has "A10 keyed: a live claim" "$HSEC" "- \`$K/.dforge/handoff/adhoc-aaaaaaaa.md\` — key adhoc-aaaaaaaa, kind adhoc, 5h old, claimed 22222222 live"
has "A10 keyed: a gone claim" "$HSEC" "- \`$K/.dforge/handoff/adhoc-bbbbbbbb.md\` — key adhoc-bbbbbbbb, kind adhoc, 5h old, claimed 33333333 gone"
has "A10 keyed: an unclaimed handoff in the worktree" "$HSEC" "- \`$KW/.dforge/handoff/adhoc-cccccccc.md\` — key adhoc-cccccccc, kind adhoc, 5h old, unclaimed"
has "A10 keyed: another handoff's stored lines" "$HSEC" "- **Next:** Carry on live."
check "A10 keyed: every handoff listed once" "$(grep -c '^- `.*/handoff/.*\.md` — key ' <<<"$HSEC")" "4"
check "A10 keyed: no stale handoff" "$STALE" "## Stale handoffs
- none"
# The marker's session= names this session's handoff when it holds no claim.
rm -f "$K/.dforge/handoff/claims/2026-11-01-q"
kh "$K/.dforge/handoff/adhoc-dddddddd.md" adhoc "$OWN" - "Unplanned work: mine." "Carry on mine."
touch -d '2 hours ago' "$K/.dforge/handoff/adhoc-dddddddd.md"
audit "$K" "$OWN"
has "A10 keyed: a handoff this session wrote is first" "$(sed -n 2p <<<"$HSEC")" \
  "- \`$K/.dforge/handoff/adhoc-dddddddd.md\` — key adhoc-dddddddd, kind adhoc, 2h old, unclaimed (this session's)"
audit "$K"
check "A10 keyed: no session id, no handoff is this session's" "$(grep -c "(this session's)" <<<"$HSEC")" "0"
git -C "$K" worktree remove --force "$KW"

# cleans_finished_handoffs (A16)
C="$TMP/c"; krepo "$C"; C=$(git -C "$C" rev-parse --show-toplevel)
printf '# Completed plans\n\n- 2026-11-02 — `docs/dforge/plans/2026-11-02-fin.md` — merged\n' > "$C/docs/dforge/plans/completed.md"
CH="$C/.dforge/handoff"
kh "$CH/2026-11-02-fin.md" plan - docs/dforge/plans/2026-11-02-fin.md "s" "n"
kh "$CH/gone-design.md" draft - docs/dforge/specs/gone-design.md "s" "n"
: > "$C/docs/dforge/specs/named-design.md"
kh "$CH/named-design.md" draft - docs/dforge/specs/named-design.md "s" "n"
: > "$C/docs/dforge/specs/prog-design.md"
kh "$CH/prog-design.md" draft - docs/dforge/specs/prog-design.md "Draft prog." "Plan prog."
kh "$CH/2026-11-03-done.md" complete - docs/dforge/plans/2026-11-03-done.md "s" "n"
kh "$CH/fin-live.md" plan - docs/dforge/plans/2026-11-02-fin.md "Plan fin live." "Fin live next."
kclaim "$C" fin-live "$LIVE"
touch -d '1 hour ago' "$CH/fin-live.md"
kh "$CH/fin-gone.md" plan - docs/dforge/plans/2026-11-02-fin.md "s" "n"
kclaim "$C" fin-gone "$GONE"
kh "$CH/fin-own.md" plan - docs/dforge/plans/2026-11-02-fin.md "s" "n"
kclaim "$C" fin-own "$OWN"
kh "$CH/adhoc-eeeeeeee.md" adhoc - - "Unplanned work: old." "Old next."
touch -d '20 days ago' "$CH/adhoc-eeeeeeee.md"
cp "$CH/adhoc-eeeeeeee.md" "$TMP/adhoc-before"
audit "$C" "$OWN"
check "A16: exit 0" "$status" "0"
for row in \
  "2026-11-02-fin:no:a plan in completed.md" \
  "gone-design:no:a deleted draft" \
  "named-design:no:a draft a plan's Spec line names" \
  "prog-design:yes:a draft named only by a Program line" \
  "2026-11-03-done:no:a complete handoff whose block is terminal" \
  "fin-live:yes:a finished plan a live other session claims" \
  "fin-gone:no:a finished plan a gone session claims" \
  "fin-own:no:a finished plan this session claims" \
  "adhoc-eeeeeeee:yes:an adhoc handoff 20 days old"; do
  key=${row%%:*} rest=${row#*:}; want=${rest%%:*} what=${rest#*:}
  check "A16: $what — kept: $want" "$([ -e "$CH/$key.md" ] && echo yes || echo no)" "$want"
  if [ "$want" = no ]; then
    has "A16: $what — the removal line" "$HSEC" "- removed finished handoff $CH/$key.md"
  else
    has "A16: $what — listed" "$HSEC" "- \`$CH/$key.md\` — key $key, "
  fi
done
has "A16: a live claim is listed with its state" "$HSEC" "- \`$CH/fin-live.md\` — key fin-live, kind plan, 1h old, claimed 22222222 live"
has "A16: a kept finished handoff says why" "$HSEC" "- finished, kept while a live session claims it: the plan is finished: docs/dforge/plans/2026-11-02-fin.md"
has "A16: its stored Next line" "$HSEC" "- **Next:** Fin live next."
check "A16: the adhoc handoff is byte-identical" "$(cmp -s "$TMP/adhoc-before" "$CH/adhoc-eeeeeeee.md" && echo same || echo changed)" "same"
check "A16: stale handoffs, with age and path" "$STALE" "## Stale handoffs
- 20d \`$CH/adhoc-eeeeeeee.md\`"
check "A16: a removed handoff's own or gone claim goes, a live one stays" "$(ls "$CH/claims" | sort | paste -sd' ' -)" "fin-live"
# A handoff whose recompute fails some other way is listed as stored, never deleted.
kh "$CH/broken.md" plan - docs/dforge/plans/missing.md "Broken status." "Broken next."
audit "$C"
check "A16: a failed recompute keeps the handoff" "$([ -e "$CH/broken.md" ] && echo yes || echo no)" "yes"
has "A16: a failed recompute is named" "$HSEC" "- stored, not recomputed: next-step: no such file"
has "A16: and its stored lines shown" "$HSEC" "- **Next:** Broken next."

# unrelated_completion_keeps_draft_and_adhoc (A20)
U="$TMP/u"; krepo "$U"; U=$(git -C "$U" rev-parse --show-toplevel)
: > "$U/docs/dforge/specs/d-design.md"
kh "$U/.dforge/handoff/d-design.md" draft - docs/dforge/specs/d-design.md "Draft d." "Plan d."
kh "$U/.dforge/handoff/adhoc-ffffffff.md" adhoc - - "Unplanned work: u." "U next."
cp "$U/.dforge/handoff/d-design.md" "$TMP/d-before"; cp "$U/.dforge/handoff/adhoc-ffffffff.md" "$TMP/f-before"
git -C "$U" worktree add -q -b uw "$TMP/uw"; UW=$(git -C "$TMP/uw" rev-parse --show-toplevel)
printf '# Completed plans\n\n- 2026-11-01 — `docs/dforge/plans/2026-11-01-q.md` — merged\n' > "$UW/docs/dforge/plans/completed.md"
kh "$UW/.dforge/handoff/2026-11-01-q.md" plan - docs/dforge/plans/2026-11-01-q.md "s" "n"
audit "$UW"
check "A20: the worktree's finished plan handoff is removed" "$([ -e "$UW/.dforge/handoff/2026-11-01-q.md" ] && echo yes || echo no)" "no"
check "A20: the primary's draft handoff is untouched" "$(cmp -s "$TMP/d-before" "$U/.dforge/handoff/d-design.md" && echo same || echo changed)" "same"
check "A20: the primary's adhoc handoff is untouched" "$(cmp -s "$TMP/f-before" "$U/.dforge/handoff/adhoc-ffffffff.md" && echo same || echo changed)" "same"
has "A20: the draft is listed" "$HSEC" "- \`$U/.dforge/handoff/d-design.md\` — key d-design, kind draft"
audit "$U"
check "A20: from the primary, too" "$(ls "$U/.dforge/handoff" | grep -vx claims | sort | paste -sd' ' -)" "adhoc-ffffffff.md d-design.md"
git -C "$U" worktree remove --force "$UW"

# A listing that fails is named, not read as "no handoffs"; a handoff
# rewritten between its recompute and its removal stays.
FX="$TMP/fx"; rm -rf "$FX"; mkdir -p "$FX"
cp -R "$(dirname "$SCRIPT")" "$FX/scripts"
[ ! -d "$(dirname "$SCRIPT")/../config" ] || cp -R "$(dirname "$SCRIPT")/../config" "$FX/config"
printf '#!/usr/bin/env bash\necho "handoff: boom" >&2\nexit 3\n' > "$FX/scripts/handoff"
out=$(cd "$C" && bash "$FX/scripts/repo-audit" 2>&1)
HSEC=$(sed -n '/^## Handoff/,/^## /p' <<<"$out")
has "fix: a failed listing is named" "$HSEC" "- handoff list failed (exit 3): handoff: boom"
check "fix: a failed listing never says none" "$(grep -c '^- none$' <<<"$HSEC")" "0"
cp "$(dirname "$SCRIPT")/handoff" "$FX/scripts/handoff"
RW="$TMP/rw"; krepo "$RW"; RW=$(git -C "$RW" rev-parse --show-toplevel)
kh "$RW/.dforge/handoff/rewritten.md" plan - docs/dforge/plans/2026-11-02-fin.md "s" "n"
printf '#!/usr/bin/env bash\ntouch -d 2000-01-01 "$3"\necho "next-step: the plan is finished: x" >&2\nexit 6\n' > "$FX/scripts/next-step"
out=$(cd "$RW" && bash "$FX/scripts/repo-audit" 2>&1)
check "fix: a handoff rewritten during the audit stays" "$([ -e "$RW/.dforge/handoff/rewritten.md" ] && echo yes || echo no)" "yes"
has "fix: and says so" "$out" "- finished, kept: it was rewritten during this audit (the plan is finished: x)"
# A rewrite in the same second as the audit's first read keeps its mtime.
kh "$RW/.dforge/handoff/rewritten.md" plan - docs/dforge/plans/2026-11-02-fin.md "s" "n"
printf '#!/usr/bin/env bash\nm=$(stat -c %%Y "$3" 2>/dev/null || stat -f %%m "$3")\necho rewritten >> "$3"\ntouch -d "@$m" "$3"\necho "next-step: the plan is finished: x" >&2\nexit 6\n' > "$FX/scripts/next-step"
out=$(cd "$RW" && bash "$FX/scripts/repo-audit" 2>&1)
check "fix: a rewrite that keeps the mtime stays" "$(grep -c '^rewritten$' "$RW/.dforge/handoff/rewritten.md" 2>/dev/null)" "1"
has "fix: and says it was rewritten" "$out" "- finished, kept: it was rewritten during this audit (the plan is finished: x)"
# A handoff deleted during the audit prints no shell error.
kh "$RW/.dforge/handoff/vanished.md" plan - docs/dforge/plans/2026-11-02-fin.md "s" "n"
printf '#!/usr/bin/env bash\nrm -f "$3"\necho "next-step: the plan is finished: x" >&2\nexit 6\n' > "$FX/scripts/next-step"
out=$(cd "$RW" && bash "$FX/scripts/repo-audit" 2>&1)
check "fix: a handoff deleted during the audit prints no error" "$(grep -c 'No such file' <<<"$out")" "0"

# --- a removal with no claims directory takes the claims lock ---
HC="$TMP/hc"
git init -q -b main "$HC"
mkdir -p "$HC/docs/dforge/plans" "$HC/.dforge/handoff"
printf '.dforge/\n' > "$HC/.gitignore"
printf '# P\n\n**Spec:** docs/dforge/specs/p.md\n**Execution:** inline — `claude --model sonnet --effort high` — x\n\n### Task 1: One\n' > "$HC/docs/dforge/plans/2026-11-01-p.md"
printf '# Completed plans\n\n- 2026-11-01 — `docs/dforge/plans/2026-11-01-p.md` — merged\n' > "$HC/docs/dforge/plans/completed.md"
git -C "$HC" add -A && git -C "$HC" commit -qm init
printf '# Handoff\n\n## Next session\n\n**Status:** x\n**Next:** y\n<!-- next-step: kind=plan done=0 closed=0 subject=docs/dforge/plans/2026-11-01-p.md at=1 -->\n' > "$HC/.dforge/handoff/2026-11-01-p.md"
if command -v flock >/dev/null 2>&1; then
  (cd "$HC" && bash "$SCRIPT" >/dev/null 2>&1)
  check "fix: a removal with no claims directory takes the claims lock" \
    "$([ -e "$HC/.dforge/handoff/2026-11-01-p.md" ] && echo kept || echo removed):$([ -e "$HC/.dforge/handoff/claims/.lock" ] && echo locked || echo unlocked)" "removed:locked"
else
  printf "skip - fix: a removal with no claims directory takes the claims lock: no flock\n"
fi
# --- an empty repository ---
E="$TMP/empty"
git init -q -b main "$E"
out=$(cd "$E" && bash "$SCRIPT" 2>/dev/null); rc=$?
check "an empty repository: exit 0" "$rc:$(sed -n '/^## Recent commits/,$p' <<<"$out" | sed -n 2p)" "0:- (no commits)"
count_in() { # count_in TEXT NEEDLE — how many times NEEDLE occurs in TEXT
  local n=0 rest=$1
  while [[ $rest == *"$2"* ]]; do n=$((n + 1)); rest=${rest#*"$2"}; done
  echo "$n"
}
# --- a worktree whose path holds a newline ---
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) printf 'skip - worktree list: a path with a newline is listed once, whole (Windows file names cannot hold a newline)\n' ;;
  *)
    NR="$TMP/nl-audit"
    git init -q -b main "$NR"
    git -C "$NR" commit -q --allow-empty -m init
    NW="$TMP/nl"$'\n'"audit"
    git -C "$NR" worktree add -q -b nl "$NW"
    out=$(cd "$NR" && bash "$SCRIPT" 2>/dev/null)
    check "worktree list: a path with a newline is listed once, whole" \
      "$(count_in "$out" "- \`$NW\`"):$(grep -c 'skipped' <<<"$out")" "1:0"
    ;;
esac
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
