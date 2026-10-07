#!/usr/bin/env bash
# scripts/roadmap computes a milestone's progress from its registers and is the
# only writer of `closed`. These cases pin the parts that stop a session from
# claiming a phase is done: an open epic, an epic marked done while its spec's
# requirements are open, and a milestone closed out of order.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RM="$HERE/../scripts/roadmap"
REG="$HERE/../scripts/register"
. "$HERE/../scripts/lib/roadmap.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
run() { # run <args...> -> sets OUT and RC
  OUT=$("$@" 2>&1); RC=$?
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

ROOT="$TMP/repo"
git init -q -b main "$ROOT"
D="$ROOT/docs/superpowers"
mkdir -p "$D/registers" "$D/specs"
printf '# Product design\n' > "$D/specs/2026-10-07-shop-design.md"
printf '# Billing design\n' > "$D/specs/2026-10-08-billing-design.md"
printf '# Search design\n' > "$D/specs/2026-10-08-search-design.md"
PRODUCT=docs/superpowers/specs/2026-10-07-shop-design.md
BILLING=docs/superpowers/specs/2026-10-08-billing-design.md

register() { # register <file> <covers> <rows...>
  local f=$1 covers=$2; shift 2
  {
    printf '# %s — item register\n\n**Source:** roadmap\n**Covers:** %s\n\n' "$(basename "$f" .md)" "$covers"
    printf '| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n'
    printf '%s\n' "$@"
  } > "$f"
}

register "$D/registers/m0.md" "$PRODUCT" \
  '| 1 | Product brief approved | - | - | done | - |'
register "$D/registers/m1.md" "$PRODUCT" \
  "| 1 | Billing | $BILLING | invoices paid | doing | - |" \
  '| 2 | Search | docs/superpowers/specs/2026-10-08-search-design.md | results in 200ms | open | - |' \
  '| 3 | Chat | - | - | deferred | v2 |'
register "$D/registers/billing.md" "$BILLING" \
  '| 1 | Create invoice | docs/superpowers/plans/billing.md | - | planned | - |' \
  '| 2 | Refund | docs/superpowers/plans/billing.md | - | open | - |'

cat > "$D/roadmap.md" <<EOF
# Shop — roadmap

**Product:** an online shop
**Spec:** $PRODUCT
**Non-goals:** marketplace

| M | Name | Exit criteria | Register | State | Note |
|---|---|---|---|---|---|
| M0 | Discovery | brief approved | docs/superpowers/registers/m0.md | closed | audit: 1 MET |
| M1 | MVP | every epic resolved | \`docs/superpowers/registers/m1.md\` | open | - |
EOF

# --- parsing ---
check "rows: two milestones" "$(roadmap_rows "$D/roadmap.md" | cut -f1 | tr '\n' ' ')" "M0 M1 "
check "rows: backticks stripped from the register" \
  "$(roadmap_rows "$D/roadmap.md" | awk -F'\t' '$1 == "M1" { print $4 }')" "docs/superpowers/registers/m1.md"
check "current: the first open milestone" "$(roadmap_current "$D/roadmap.md" | cut -f1)" "M1"
check "epic counts: deferred counts as resolved" "$(roadmap_epic_counts "$ROOT" docs/superpowers/registers/m1.md)" "1 3"

# --- check ---
run bash "$RM" check --root "$ROOT"
check "check: clean" "$RC" "0"
check "check: summary" "$(tail -n 1 <<<"$OUT")" "roadmap: 0 errors"

run bash "$RM" status --root "$TMP"
check "status: no roadmap is usage" "$RC" "2"
run bash "$RM" status --root "$TMP" --line
check "status --line: no roadmap is silent" "$RC/$OUT" "0/"

# --- status and open ---
run bash "$RM" status --root "$ROOT"
check "status: exits 0" "$RC" "0"
check "status: the closed milestone carries its note" "$(grep -c '^M0 Discovery — closed — audit: 1 MET$' <<<"$OUT")" "1"
check "status: open epics named with their state" "$(grep -c '^M1 MVP — open — 1 of 3 epics resolved; open: #1 Billing (doing), #2 Search (open); 2 requirement rows open below its epics$' <<<"$OUT")" "1"
check "status: current" "$(tail -n 1 <<<"$OUT")" "Current: M1 MVP"

run bash "$RM" status --root "$ROOT" --line
check "status --line: one line" "$(grep -c . <<<"$OUT")" "1"
check "status --line: names the open epics" "$(grep -c 'M1 MVP, 1 of 3 epics resolved, open: #1 Billing, #2 Search' <<<"$OUT")" "1"

run bash "$RM" open --root "$ROOT"
check "open: rows open exits 1" "$RC" "1"
check "open: epic and requirement rows" "$(grep -c '^M1: ' <<<"$OUT")" "4"
check "open: a requirement row is attributed to its register" \
  "$(grep -c 'docs/superpowers/registers/billing.md #2 Refund — open' <<<"$OUT")" "1"
run bash "$RM" open --root "$ROOT" M0
check "open: a closed milestone with nothing open exits 0" "$RC" "0"
run bash "$RM" open --root "$ROOT" M9
check "open: unknown milestone is usage" "$RC" "2"

# --- the premature done ---
# An epic marked done while its spec's requirements are open is the failure
# this exists for: the epic row alone would say the milestone is finished.
bash "$REG" set "$D/registers/m1.md" 1 done >/dev/null
bash "$REG" set "$D/registers/m1.md" 2 n/a --note "dropped by owner" >/dev/null
run bash "$RM" open --root "$ROOT"
check "premature done: still open" "$RC" "1"
check "premature done: the requirement rows are listed" "$(grep -c 'billing.md' <<<"$OUT")" "2"
run bash "$RM" close --root "$ROOT" M1 --note "audit"
check "premature done: close refused" "$RC" "1"
check "premature done: milestone stays open" "$(roadmap_row "$D/roadmap.md" M1 | cut -f5)" "open"
run bash "$RM" status --root "$ROOT" --line
check "premature done: the hook line says requirements are open" "$(grep -c 'requirement rows below them are open' <<<"$OUT")" "1"

# --- settle ---
bash "$REG" set "$D/registers/m1.md" 1 doing >/dev/null
run bash "$RM" settle --root "$ROOT" --spec "$BILLING"
check "settle: refuses while the spec's register is open" "$(grep -c '^not settled' <<<"$OUT")" "1"
check "settle: the epic is untouched" "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $5 }')" "doing"
bash "$REG" set "$D/registers/billing.md" 1 done >/dev/null
bash "$REG" set "$D/registers/billing.md" 2 done >/dev/null
run bash "$RM" settle --root "$ROOT" --spec "$BILLING"
check "settle: exits 0" "$RC" "0"
check "settle: the epic moves to verify, never done" "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $5 }')" "verify"
check "settle: with the owner note" "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $6 }')" "built; owner confirms at the milestone audit"
run bash "$RM" settle --root "$ROOT" --spec "$BILLING"
check "settle: idempotent" "$(grep -c '^no open epic row' <<<"$OUT")" "1"

# verify is unresolved: the owner's confirmation is still owed.
run bash "$RM" close --root "$ROOT" M1 --note "audit"
check "verify: close refused" "$RC" "1"

# --- close ---
bash "$REG" set "$D/registers/m1.md" 1 done >/dev/null
run bash "$RM" open --root "$ROOT"
check "ready: open exits 0" "$RC" "0"
check "ready: says so" "$OUT" "M1: nothing open — ready to close"
run bash "$RM" status --root "$ROOT"
check "ready: status names the skill" "$(tail -n 1 <<<"$OUT")" "Current: M1 MVP — ready to close with dr-superpowers:closing-a-milestone"
run bash "$RM" close --root "$ROOT" M1
check "close: a note is required" "$RC" "2"
run bash "$RM" close --root "$ROOT" M1 --note "audit 2026-10-09: 2 MET"
check "close: written" "$RC" "0"
check "close: state" "$(roadmap_row "$D/roadmap.md" M1 | cut -f5)" "closed"
check "close: note" "$(roadmap_row "$D/roadmap.md" M1 | cut -f6)" "audit 2026-10-09: 2 MET"
run bash "$RM" status --root "$ROOT" --line
check "all closed: the hook line" "$OUT" "Roadmap: every milestone is closed (docs/superpowers/roadmap.md)."
run bash "$RM" check --root "$ROOT"
check "close: the written roadmap checks clean" "$RC" "0"

# --- add, order and reopen ---
register "$D/registers/m2.md" "$PRODUCT" '| 1 | Hardening review | - | - | open | - |'
register "$D/registers/m3.md" "$PRODUCT" '| 1 | Release | - | - | done | - |'
run bash "$RM" add --root "$ROOT" "Hardening" --exit "security review | perf" --register docs/superpowers/registers/m2.md
check "add: exits 0" "$RC" "0"
run bash "$RM" add --root "$ROOT" "Release" --exit "deployed" --register docs/superpowers/registers/m3.md
check "add: next identifiers" "$(roadmap_rows "$D/roadmap.md" | cut -f1 | tr '\n' ' ')" "M0 M1 M2 M3 "
check "add: a pipe survives" "$(roadmap_row "$D/roadmap.md" M2 | cut -f3)" "security review | perf"
run bash "$RM" close --root "$ROOT" M3 --note "audit"
check "order: a later milestone cannot close first" "$RC" "1"
check "order: names the earlier one" "$(grep -c 'close M2 first' <<<"$OUT")" "1"
run bash "$RM" reopen --root "$ROOT" M1 --note "audit missed refunds"
check "reopen: exits 0" "$RC" "0"
check "reopen: current moves back" "$(roadmap_current "$D/roadmap.md" | cut -f1)" "M1"

# --- check catches hand edits ---
cp "$D/roadmap.md" "$TMP/good.md"
sed -i 's/^| M2 | Hardening |\(.*\)| open | - |$/| M2 | Hardening |\1| closed | - |/' "$D/roadmap.md"
run bash "$RM" check --root "$ROOT"
check "check: a hand-closed milestone fails" "$RC" "1"
check "check: closed without a note" "$(grep -c 'closed M2 needs a note' <<<"$OUT")" "1"
check "check: closed after an open one" "$(grep -c 'M2 is closed while earlier M1 is open' <<<"$OUT")" "1"
check "check: closed with rows open" "$(grep -c 'M2 is closed but rows below it are unresolved' <<<"$OUT")" "1"
cp "$TMP/good.md" "$D/roadmap.md"
printf '| M1 | Again | x | docs/superpowers/registers/absent.md | finished | - |\n' >> "$D/roadmap.md"
run bash "$RM" check --root "$ROOT"
check "check: duplicate milestone" "$(grep -c 'duplicate milestone: M1' <<<"$OUT")" "1"
check "check: missing register" "$(grep -c 'register does not exist' <<<"$OUT")" "1"
check "check: unknown state" "$(grep -c 'unknown state: finished' <<<"$OUT")" "1"

run bash "$RM"
check "usage: no verb" "$RC" "2"
run bash "$RM" frobnicate --root "$ROOT"
check "usage: unknown verb" "$RC" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
