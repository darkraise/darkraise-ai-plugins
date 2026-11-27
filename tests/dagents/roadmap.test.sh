#!/usr/bin/env bash
# scripts/roadmap computes a milestone's progress from its registers and is the
# only writer of `closed`. These cases pin the parts that stop a session from
# claiming a phase is done: an open epic, an epic marked done while its spec's
# requirements are open, and a milestone closed out of order.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RM="$HERE/../../plugins/dagents/scripts/roadmap"
REG="$HERE/../../plugins/dagents/scripts/register"
. "$HERE/../../plugins/dagents/scripts/lib/roadmap.sh"

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
export HOME="$TMP/home"
mkdir -p "$HOME"

ROOT="$TMP/repo"
git init -q -b main "$ROOT"
D="$ROOT/docs/dagents"
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
  "$(grep -c 'docs/dagents/registers/billing.md #2 Refund — open' <<<"$OUT")" "1"
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
run bash "$RM" settle --root "$ROOT" --spec docs/dagents/specs/2026-10-08-billing-design.md
check "settle: the other docs prefix still refuses while open" "$(grep -c '^not settled' <<<"$OUT")" "1"
# A row waiting on the owner's check is built work: it never holds the epic,
# while an open row beside it still does.
bash "$REG" set "$D/registers/billing.md" 1 verify --note "invoice demo owed" >/dev/null
run bash "$RM" settle --root "$ROOT" --spec "$BILLING"
check "settle: an open row beside a verify row still refuses" "$(grep -c '^not settled' <<<"$OUT")" "1"
bash "$REG" set "$D/registers/billing.md" 2 done >/dev/null
run bash "$RM" settle --root "$ROOT" --spec "$BILLING"
check "settle: a register with only verify rows left settles the epic" \
  "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $5 }')" "verify"
check "settle: the verify row itself is left for the owner" \
  "$(register_rows "$D/registers/billing.md" | awk -F'\t' '$1 == 1 { print $5 }')" "verify"
bash "$REG" set "$D/registers/m1.md" 1 doing >/dev/null
bash "$REG" set "$D/registers/billing.md" 1 done >/dev/null
bash "$REG" set "$D/registers/billing.md" 2 done >/dev/null
run bash "$RM" settle --root "$ROOT" --spec "$BILLING"
check "settle: exits 0" "$RC" "0"
check "settle: the epic moves to verify, never done" "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $5 }')" "verify"
check "settle: with the owner note" "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $6 }')" "built; owner confirms at the milestone audit"
run bash "$RM" settle --root "$ROOT" --spec "$BILLING"
check "settle: idempotent" "$(grep -c '^no open epic row' <<<"$OUT")" "1"
bash "$REG" set "$D/registers/m1.md" 1 doing >/dev/null
run bash "$RM" settle --root "$ROOT" --spec docs/dagents/specs/2026-10-08-billing-design.md
check "settle: an epic matches its spec under the other docs prefix" \
  "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $5 }')" "verify"

check "settle: a second settle does not repeat its note" \
  "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $6 }')" "built; owner confirms at the milestone audit"
bash "$REG" set "$D/registers/m1.md" 1 doing --note "owner ruling: keep" >/dev/null
run bash "$RM" settle --root "$ROOT" --spec "$BILLING"
check "settle keeps an existing note: the row is verify" "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $5 }')" "verify"
check "settle keeps an existing note" \
  "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $6 }')" "built; owner confirms at the milestone audit; owner ruling: keep"
bash "$REG" set "$D/registers/m1.md" 1 doing >/dev/null
run bash "$RM" settle --root "$ROOT" --spec "$BILLING"
check "settle keeps an existing note: once" \
  "$(register_rows "$D/registers/m1.md" | awk -F'\t' '$1 == 1 { print $6 }')" "built; owner confirms at the milestone audit; owner ruling: keep"

# verify is unresolved: the owner's confirmation is still owed.
run bash "$RM" close --root "$ROOT" M1 --note "audit"
check "verify: close refused" "$RC" "1"

# --- close ---
bash "$REG" set "$D/registers/m1.md" 1 done >/dev/null
run bash "$RM" open --root "$ROOT"
check "ready: open exits 0" "$RC" "0"
check "ready: says so" "$OUT" "M1: nothing open — ready to close"
run bash "$RM" status --root "$ROOT"
check "ready: status names the skill" "$(tail -n 1 <<<"$OUT")" "Current: M1 MVP — ready to close with dagents:closing-a-milestone"
run bash "$RM" close --root "$ROOT" M1
check "close: a note is required" "$RC" "2"
run bash "$RM" close --root "$ROOT" M1 --note "audit 2026-10-09: 2 MET"
check "close: written" "$RC" "0"
check "close: state" "$(roadmap_row "$D/roadmap.md" M1 | cut -f5)" "closed"
check "close: note" "$(roadmap_row "$D/roadmap.md" M1 | cut -f6)" "audit 2026-10-09: 2 MET"
run bash "$RM" status --root "$ROOT" --line
check "all closed: the hook line" "$OUT" "Roadmap: every milestone is closed (docs/dagents/roadmap.md)."
run bash "$RM" check --root "$ROOT"
check "close: the written roadmap checks clean" "$RC" "0"

# --- a dagents checkout keeps its roadmap in docs/dagents ---
FROOT="$TMP/dagents"
git init -q -b main "$FROOT"
mkdir -p "$FROOT/docs"
cp -R "$D" "$FROOT/docs/dagents"
for f in "$FROOT"/docs/dagents/roadmap.md "$FROOT"/docs/dagents/registers/*.md; do
  sed 's#docs/superpowers/#docs/dagents/#g' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
done
run bash "$RM" status --root "$FROOT" --line
check "docs/dagents: the hook line names its roadmap" "$OUT" "Roadmap: every milestone is closed (docs/dagents/roadmap.md)."
run bash "$RM" check --root "$FROOT"
check "docs/dagents: the roadmap checks clean" "$RC" "0"

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

# --- close refuses evidence it cannot read ---
R2="$TMP/repo2"
git init -q -b main "$R2"
D2="$R2/docs/dagents"
mkdir -p "$D2/registers" "$D2/specs"
printf '# Product design\n' > "$D2/specs/2026-10-07-shop-design.md"
cat > "$D2/roadmap.md" <<EOF
# Shop — roadmap

**Product:** an online shop
**Spec:** $PRODUCT

| M | Name | Exit criteria | Register | State | Note |
|---|---|---|---|---|---|
| M1 | MVP |  | docs/superpowers/registers/gone.md | open | - |
EOF
run bash "$RM" close --root "$R2" M1 --note "audit"
check "close: a missing register is refused" "$RC:$(grep -c 'register does not exist' <<<"$OUT")" "1:1"
check "close: an empty cell does not shift the register" "$(grep -c 'gone.md' <<<"$OUT")" "1"
register "$D2/registers/gone.md" "$PRODUCT" '| 1 | Epic |  | x | garbage | done |'
run bash "$RM" close --root "$R2" M1 --note "audit"
check "close: a register failing check is refused" "$RC:$(grep -c 'fails register check' <<<"$OUT")" "1:1"
check "close: the roadmap is unchanged" "$(roadmap_row "$D2/roadmap.md" M1 | cut -f5)" "open"
register "$D2/registers/gone.md" "$PRODUCT" '| 1 | Epic | - | x | done | - |'
run bash "$RM" close --root "$R2" M1 --note $'audit\nsecond line'
check "close: a multiline note is refused" "$RC" "2"
run bash "$RM" close --root "$R2" M1 --note "audit"
check "close: readable evidence closes" "$RC" "0"
for i in 1 2 3 4; do bash "$RM" add --root "$R2" "Next $i" --exit x --register docs/superpowers/registers/gone.md >/dev/null 2>&1 & done
wait
check "add: concurrent additions get distinct milestones" "$(roadmap_rows "$D2/roadmap.md" | cut -f1 | sort -u | tr '\n' ' ')" "M1 M2 M3 M4 M5 "
for i in 1 2 3 4; do DAGENTS_FLOCK=no-such-flock bash "$RM" add --root "$R2" "Later $i" --exit x --register docs/superpowers/registers/gone.md >/dev/null 2>&1 & done
wait
check "no flock: concurrent additions get distinct milestones" "$(roadmap_rows "$D2/roadmap.md" | cut -f1 | sort -u | tr '\n' ' ')" "M1 M2 M3 M4 M5 M6 M7 M8 M9 "
check "no flock: the lock directory is gone" "$(find "$R2" -name '*.lockd' | grep -c .)" "0"

# --- an epic whose spec file is gone still has its covering register read ---
R3="$TMP/repo3"
git init -q -b main "$R3"
D3="$R3/docs/dagents"
mkdir -p "$D3/registers" "$D3/specs"
printf '# Product design\n' > "$D3/specs/2026-10-07-shop-design.md"
register "$D3/registers/m1.md" "$PRODUCT" '| 1 | Epic | `docs/dagents/specs/gone.md` | x | done | - |'
register "$D3/registers/gone-reqs.md" docs/dagents/specs/gone.md '| 1 | Requirement | - | - | open | - |'
cat > "$D3/roadmap.md" <<EOF
# Shop — roadmap

**Product:** an online shop
**Spec:** $PRODUCT

| M | Name | Exit criteria | Register | State | Note |
|---|---|---|---|---|---|
| M1 | MVP | x | docs/dagents/registers/m1.md | open | - |
EOF
run bash "$RM" close --root "$R3" M1 --note x
# The covering register names a spec that is gone, so register check refuses
# it first; before the fix it was never read and close went through.
check "missing spec: close refused while its register is open" \
  "$RC:$(grep -c '^refused: docs/dagents/registers/gone-reqs.md fails register check:' <<<"$OUT"):$(roadmap_row "$D3/roadmap.md" M1 | cut -f5):$(roadmap_unresolved "$R3" docs/dagents/registers/m1.md | cut -f1,2 | tr '\t' '#')" \
  "1:1:open:docs/dagents/registers/gone-reqs.md#1"

# --- close holds every register's lock; reopen keeps milestones in order ---
R4="$TMP/repo4"
git init -q -b main "$R4"
D4="$R4/docs/dagents"
mkdir -p "$D4/registers" "$D4/specs"
printf '# P\n' > "$D4/specs/product.md"
printf '# E\n' > "$D4/specs/e.md"
register "$D4/registers/m1.md" docs/dagents/specs/product.md '| 1 | Epic | docs/dagents/specs/e.md | x | done | - |'
register "$D4/registers/m2.md" docs/dagents/specs/product.md '| 1 | Later | - | x | done | - |'
register "$D4/registers/e.md" docs/dagents/specs/e.md '| 1 | Requirement | - | - | done | - |'
cat > "$D4/roadmap.md" <<EOF
# Shop — roadmap

**Product:** an online shop
**Spec:** docs/dagents/specs/product.md

| M | Name | Exit criteria | Register | State | Note |
|---|---|---|---|---|---|
| M1 | MVP | x | docs/dagents/registers/m1.md | open | - |
| M2 | Next | x | docs/dagents/registers/m2.md | open | - |
EOF
if command -v flock >/dev/null 2>&1; then
  printf '#!/usr/bin/env bash\nprintf "x\\n" >> "%s"\nexec flock "$@"\n' "$TMP/flock.log" > "$TMP/flock-log"
  chmod +x "$TMP/flock-log"
  run env DAGENTS_FLOCK="$TMP/flock-log" bash "$RM" close --root "$R4" M1 --note x
  check "close: holds each register's lock" "$RC:$(wc -l < "$TMP/flock.log" | tr -d ' ')" "0:3"
else
  printf "skip - close: holds each register's lock: no flock\n"
fi
[ "$(roadmap_row "$D4/roadmap.md" M1 | cut -f5)" = closed ] || bash "$RM" close --root "$R4" M1 --note x >/dev/null
bash "$RM" close --root "$R4" M2 --note y >/dev/null
before=$(cksum < "$D4/roadmap.md")
run bash "$RM" reopen --root "$R4" M1 --note x
check "reopen: refused while a later milestone is closed" \
  "$RC:$(grep -c '^refused: reopen M2 first — a later milestone cannot stay closed$' <<<"$OUT"):$(cksum < "$D4/roadmap.md"):$(bash "$RM" check --root "$R4" >/dev/null 2>&1; echo $?)" \
  "1:1:$before:0"

run bash "$RM"
check "usage: no verb" "$RC" "2"
run bash "$RM" frobnicate --root "$ROOT"
check "usage: unknown verb" "$RC" "2"

# --- the roadmap and its registers are read in the docs root by name ---
SH="$TMP/stores-home"; mkdir -p "$SH"
SR="$TMP/stores-repo"; git init -q -b main "$SR"
M="$(git -C "$SR" rev-parse --show-toplevel)/docs"
mkdir -p "$M/dagents/registers"
printf '# Roadmap\n' > "$M/dagents/roadmap.md"
register "$M/dagents/registers/m1.md" "docs/dagents/specs/x.md" \
  '| 1 | A | - | - | done | - |' '| 2 | B | - | - | open | - |'
check "roadmap_file: the docs root's roadmap" "$(HOME=$SH roadmap_file "$SR")" "$M/dagents/roadmap.md"
check "roadmap_epic_counts: a register name resolves in the docs root" \
  "$(HOME=$SH roadmap_epic_counts "$SR" docs/dagents/registers/m1.md)" "1 2"
check "roadmap_unresolved: rows named by register name" \
  "$(HOME=$SH roadmap_unresolved "$SR" docs/dagents/registers/m1.md | cut -f1,2)" "$(printf 'docs/dagents/registers/m1.md\t2')"

mkdir -p "$M/dagents/specs"
printf '# X\n' > "$M/dagents/specs/x.md"
register "$M/dagents/registers/m9.md" "docs/dagents/specs/x.md" \
  '| 1 | Epic | docs/dagents/specs/x.md | - | open | - |'
check "roadmap_unresolved: the milestone register under the other prefix is not listed twice" \
  "$(HOME=$SH roadmap_unresolved "$SR" docs/superpowers/registers/m9.md | cut -f1,2 | tr '\n' '|')" \
  "$(printf 'docs/superpowers/registers/m9.md\t1|docs/dagents/registers/m1.md\t2|')"

# --- an empty cell keeps its place ---
# Tab-split reads collapse an empty cell, which shifts every later cell left:
# the state would read as the note, and an epic's spec as its Item.
printf '# Gift design\n' > "$D/specs/2026-10-09-gift-design.md"
GIFT=docs/dagents/specs/2026-10-09-gift-design.md
register "$D/registers/gift.md" "$GIFT" '| 1 | Wrap |  | - | open | - |'
register "$D/registers/m5.md" "$GIFT" \
  '| 1 |  | - | - | open | - |' \
  "| 2 |  | $GIFT | - | done | - |"
check "roadmap_unresolved: an empty cell keeps its place" \
  "$(roadmap_unresolved "$ROOT" docs/dagents/registers/m5.md | tr '\t' ',' | tr '\n' '|')" \
  "docs/dagents/registers/m5.md,1,,open,-|docs/dagents/registers/gift.md,1,Wrap,open,-|"

# --- a milestone of built rows closes after sign-off (A30) ---
# Shaped as darkpanel's M5: every epic built from one spec whose plans are all
# indexed and whose requirement register is resolved.
B="$TMP/built"
git init -q -b main "$B"
BD="$B/docs/dagents"
mkdir -p "$BD/plans" "$BD/specs" "$BD/registers"
printf '.dagents/\n' > "$B/.gitignore"
TS=docs/dagents/specs/2026-10-17-tailscale-design.md
printf '# Tailscale design\n' > "$B/$TS"
printf '# Product\n' > "$BD/specs/product.md"
printf '# Tailscale\n\n**Spec:** %s\n**Execution:** inline — `claude --model sonnet --effort high` — small\n\n### Task 1: One\n\nBody.\n' "$TS" > "$BD/plans/2026-10-18-tailscale.md"
printf '# Completed plans\n\n- 2026-10-20 — `docs/dagents/plans/2026-10-18-tailscale.md` — merged\n' > "$BD/plans/completed.md"
register "$BD/registers/m5-tailscale.md" docs/dagents/specs/product.md \
  "| 1 | Node management | $TS | - | doing | - |" \
  "| 2 | Tailnet management | $TS | - | doing | - |" \
  "| 3 | DERP servers | $TS | - | doing | - |" \
  "| 4 | ACL editor | $TS | - | open | - |"
register "$BD/registers/tailscale.md" "$TS" '| 1 | Join a node | docs/dagents/plans/2026-10-18-tailscale.md | - | done | - |'
{
  printf '# Panel — roadmap\n\n**Product:** a panel\n**Spec:** docs/dagents/specs/product.md\n\n'
  printf '| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n'
  printf '| M5 | Tailscale | every epic resolved | docs/dagents/registers/m5-tailscale.md | open | - |\n'
} > "$BD/roadmap.md"
git -C "$B" add -A && git -C "$B" -c user.name=t -c user.email=t@example.invalid commit -qm fixture
OUT=$(cd "$B" && timeout 60 bash "$HERE/../../plugins/dagents/scripts/next-step" --print --project 2>&1)
check "built rows: next-step names M5's audit" \
  "$(grep -cF 'Built, awaiting the audit: #1, #2, #3, #4. Milestone M5 (Tailscale) has nothing else open: audit and close it with dagents:closing-a-milestone.' <<<"$OUT")" "1"
for row in 1 2 3 4; do bash "$REG" set "$BD/registers/m5-tailscale.md" "$row" done >/dev/null; done
run bash "$RM" close --root "$B" M5 --note x
check "built rows: close exits 0 once the rows are signed off" "$RC" "0"
check "built rows: the roadmap reads M5 closed" "$(roadmap_row "$BD/roadmap.md" M5 | cut -f5)" "closed"
run bash "$RM" status --root "$B"
check "built rows: status reads M5 closed" "$(grep -c '^M5 Tailscale — closed — x$' <<<"$OUT")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
