#!/usr/bin/env bash
# scripts/review-record: the retained review record a finished plan leaves,
# and the per-plan test ratio its final review writes to the ledger.
set -uo pipefail
unset CLAUDE_CONFIG_DIR DFORGE_DOCUMENT_STORE DFORGE_PROGRESS_SOURCE CLAUDE_PROJECT_DIR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

ledger() { # ledger <checkout> <slug> <plan named> <line>...
  local dir="$1/.dforge/sdd/$2" named=$3
  shift 3
  mkdir -p "$dir"
  { printf '# SDD ledger — plan: %s\n' "$named"; printf '%s\n' "$@"; } > "$dir/progress.md"
}
exists() { if [ -e "$1" ]; then echo yes; else echo no; fi; }

# --- retain ---
REPO="$TMP/repo"
git init -q -b main "$REPO"
mkdir -p "$REPO/docs/dforge/plans"
printf '# P\n' > "$REPO/docs/dforge/plans/2026-01-01-p.md"
git -C "$REPO" add -A && git -C "$REPO" commit -q -m init
TOP=$(git -C "$REPO" rev-parse --show-toplevel)
git -C "$REPO" worktree add -q -b wt "$TMP/wt"
WT=$(git -C "$TMP/wt" rev-parse --show-toplevel)
PLAN="$TOP/docs/dforge/plans/2026-01-01-p.md"
REVIEW="$TOP/docs/dforge/reviews/2026-01-01-p.md"

ledger "$WT" 2026-01-01-p docs/dforge/plans/2026-01-01-p.md \
  'Review depth: standard (interface)' \
  'Task 1: complete (commits abc1234..bcd2345) — discovered: none' \
  'Acceptance QA: dispatched (base abc1234)' \
  'Ruling: Task 2 reworded — a reason — none' \
  'Acceptance QA: complete — 5 pass, 0 fail, 0 flaky, 0 cannot-test, 1 demo' \
  'final review lens-skipped docs-comments reason=cap' \
  'final review lens security — 0 Critical, 1 Important, 2 Minor; fixed 1, rejected 1' \
  'Test ratio: 40 test / 100 code lines (abc1234..def5678)' \
  'Final review: clean (commits abc1234..def5678)'
mkdir -p "$TOP/docs/dforge/plans/old"
printf '# Old\n' > "$TOP/docs/dforge/plans/old/2026-01-01-p.md"
ledger "$TOP" 2026-01-01-p "$TOP/docs/dforge/plans/old/2026-01-01-p.md" 'Review depth: full (risk)'

want=$(printf '%s\n' '# Review record: 2026-01-01-p' '' \
  'Plan: docs/dforge/plans/2026-01-01-p.md' "Retained: $(date +%Y-%m-%d)" '' \
  'Review depth: standard (interface)' \
  'Acceptance QA: complete — 5 pass, 0 fail, 0 flaky, 0 cannot-test, 1 demo' \
  'final review lens-skipped docs-comments reason=cap' \
  'final review lens security — 0 Critical, 1 Important, 2 Minor; fixed 1, rejected 1' \
  'Test ratio: 40 test / 100 code lines (abc1234..def5678)' \
  'Final review: clean (commits abc1234..def5678)')

out=$(cd "$TOP" && bash "$P/scripts/review-record" retain "$PLAN" --from "$WT"); rc=$?
check "A7: --from <worktree>: exit 0 and the record's path" "$rc:$out" "0:$REVIEW"
check "A5/A6: the record holds the review lines verbatim, in ledger order" "$(cat "$REVIEW" 2>/dev/null)" "$want"

rm -f "$REVIEW"
out=$(cd "$TOP" && bash "$P/scripts/review-record" retain "$PLAN"); rc=$?
check "A7/A13: no --from: the worktree ledger is found past a stale one" "$rc:$out" "0:$REVIEW"
check "A7/A13: no --from: the record comes from the worktree ledger" "$(cat "$REVIEW" 2>/dev/null)" "$want"

printf 'stale\n' > "$REVIEW"
(cd "$TOP" && bash "$P/scripts/review-record" retain "$PLAN" >/dev/null)
check "A9: a rerun replaces the record" "$(cat "$REVIEW" 2>/dev/null)" "$want"
check "A9: a rerun leaves one record" "$(ls "$TOP/docs/dforge/reviews" | wc -l | tr -d ' ')" 1

printf '# Q\n' > "$TOP/docs/dforge/plans/2026-01-01-q.md"
printf '# Q\n' > "$WT/docs/dforge/plans/2026-01-01-q.md"
ledger "$WT" 2026-01-01-q "$WT/docs/dforge/plans/2026-01-01-q.md" \
  'Task 1: complete (commits abc1234..bcd2345) — discovered: none' \
  'Acceptance QA: dispatched (base abc1234)'
(cd "$TOP" && bash "$P/scripts/review-record" retain "$TOP/docs/dforge/plans/2026-01-01-q.md" >/dev/null 2>&1); rc=$?
check "A8: a ledger with no review lines: exit 3" "$rc" 3
check "A8: a ledger with no review lines: no record" "$(exists "$TOP/docs/dforge/reviews/2026-01-01-q.md")" no

printf '# R\n' > "$TOP/docs/dforge/plans/2026-01-01-r.md"
err=$(cd "$TOP" && bash "$P/scripts/review-record" retain "$TOP/docs/dforge/plans/2026-01-01-r.md" 2>&1 >/dev/null); rc=$?
check "A8: no ledger: exit 4" "$rc" 4
check "A8: no ledger: names the worktree path it searched" "$(grep -cF "$WT/.dforge/sdd/2026-01-01-r/progress.md" <<<"$err")" 1
check "A8: no ledger: no record" "$(exists "$TOP/docs/dforge/reviews/2026-01-01-r.md")" no

(cd "$TOP" && bash "$P/scripts/review-record" retain >/dev/null 2>&1); rc=$?
check "retain: no plan is a usage error" "$rc" 2

# --- ratio ---
R="$TMP/ratio"
git init -q -b main "$R"
printf 'base\n' > "$R/README"
git -C "$R" add -A && git -C "$R" commit -q -m base
B=$(git -C "$R" rev-parse HEAD)
lines() { # lines <path> <count>
  mkdir -p "$(dirname "$R/$1")"
  seq "$2" | sed 's/^/line /' > "$R/$1"
}
short() { git -C "$R" rev-parse --short=7 "$1"; }

lines tests/a.test.sh 3
lines src/app.js 5
lines skills/x/SKILL.md 2
lines docs/guide.md 4
lines package-lock.json 7
lines tests/fixtures/data.txt 6
lines src/__snapshots__/a.snap 2
lines src/snapshots/b.txt 3
lines testdata/x.txt 1
lines gen/out.js 9
printf 'gen/* linguist-generated\n' > "$R/.gitattributes"
printf '\000\001\002' > "$R/bin.dat"
git -C "$R" add -A && git -C "$R" commit -q -m c1
H1=$(git -C "$R" rev-parse HEAD)
out=$(cd "$R" && bash "$P/scripts/review-record" ratio "$B" "$H1"); rc=$?
check "A1-A4: tests, code, Markdown and .gitattributes counted; fixtures, both snapshot dirs, testdata, generated, docs, lock and binary left out" \
  "$rc:$out" "0:Test ratio: 3 test / 8 code lines ($(short "$B")..$(short "$H1"))"

git -C "$R" mv src/app.js tests/app.test.js
echo 'line 6' >> "$R/tests/app.test.js"
git -C "$R" commit -q -am c2
H2=$(git -C "$R" rev-parse HEAD)
out=$(cd "$R" && bash "$P/scripts/review-record" ratio "$H1" "$H2"); rc=$?
check "A4: a rename counts only its changed lines, under its new path" "$rc:$out" "0:Test ratio: 1 test / 0 code lines ($(short "$H1")..$(short "$H2"))"

lines tests/b.test.sh 2
git -C "$R" add -A && git -C "$R" commit -q -m c3
H3=$(git -C "$R" rev-parse HEAD)
out=$(cd "$R" && bash "$P/scripts/review-record" ratio "$H2" "$H3"); rc=$?
check "A1: zero code lines still exits 0" "$rc:$out" "0:Test ratio: 2 test / 0 code lines ($(short "$H2")..$(short "$H3"))"

D="$TMP/ratio-dirs"
git init -q -b main "$D"
printf 'base\n' > "$D/README"
git -C "$D" add -A && git -C "$D" commit -q -m base
DB=$(git -C "$D" rev-parse HEAD)
for f in latest/a.txt contest/b.txt protests/c.txt src/latest_news.py test/a.txt pkg/test/b.txt tests/c.txt pkg/tests/d.txt test_e.py pkg/test_f.py; do
  mkdir -p "$(dirname "$D/$f")"; echo line > "$D/$f"
done
git -C "$D" add -A && git -C "$D" commit -q -m dirs
DH=$(git -C "$D" rev-parse HEAD)
out=$(cd "$D" && bash "$P/scripts/review-record" ratio "$DB" "$DH"); rc=$?
check "A1: only test directories and test files count as tests, not names that merely contain test" \
  "$rc:$out" "0:Test ratio: 6 test / 4 code lines ($(git -C "$D" rev-parse --short=7 "$DB")..$(git -C "$D" rev-parse --short=7 "$DH"))"

PLUG="$TMP/plug"
mkdir -p "$PLUG/criteria/lenses"
cp -R "$P/scripts" "$PLUG/scripts"
printf '# Test Quality Lens\n\nApplies: always\n' > "$PLUG/criteria/lenses/test-quality.md"
out=$(cd "$R" && bash "$PLUG/scripts/review-record" ratio "$B" "$H1" 2>"$TMP/err"); rc=$?
check "A14: a lens with no paths clause: exit 2, no line, the reason" \
  "$rc:$out:$(grep -c 'has no paths clause' "$TMP/err")" "2::1"

out=$(cd "$R" && bash "$P/scripts/review-record" ratio "$B" no-such-rev 2>"$TMP/err"); rc=$?
check "ratio: an unknown revision: exit 2, no line, the reason" \
  "$rc:$out:$(grep -c 'unknown revision no-such-rev' "$TMP/err")" "2::1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
