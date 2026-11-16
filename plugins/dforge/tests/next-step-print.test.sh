#!/usr/bin/env bash
# next-step --print computes the block and changes nothing; a normal run
# writes the block into latest.md followed by a marker line naming what the
# block was computed from, which the printed block never carries.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/next-step"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
unset CLAUDE_CODE_SESSION_ID CLAUDE_CONFIG_DIR AR_SESSION
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
digest() { if command -v sha256sum >/dev/null 2>&1; then sha256sum < "$1"; else shasum -a 256 < "$1"; fi; }

REPO="$TMP/repo"
git init -q -b main "$REPO"
D="$REPO/docs/dforge"
PLAN=docs/dforge/plans/2026-11-01-demo.md
mkdir -p "$D/plans" "$D/specs" "$D/registers"
printf '.dforge/\n' > "$REPO/.gitignore"
: > "$D/specs/demo.md"
printf '# Draft\n' > "$D/specs/draft.md"
{
  printf '# Demo\n\n**Spec:** docs/dforge/specs/demo.md\n'
  printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n\n'
  printf '### Task 1: One\n\nBody.\n\n### Task 2: Two\n\nBody.\n'
} > "$REPO/$PLAN"
printf '# Completed plans\n\n- 2026-10-01 — `docs/dforge/plans/2026-10-01-a.md` — merged\n- 2026-10-02 — `docs/dforge/plans/2026-10-02-b.md` — merged\n' \
  > "$D/plans/completed.md"
printf '# M2\n\n**Source:** roadmap\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Epic | - | - | done | - |\n' \
  > "$D/registers/m2.md"
cp "$D/registers/m2.md" "$D/registers/m1.md"
{
  printf '# Shop — roadmap\n\n**Product:** a shop\n**Spec:** docs/dforge/specs/demo.md\n\n'
  printf '| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n'
  printf '| M1 | One | done | docs/dforge/registers/m1.md | closed | audit |\n'
  printf '| M2 | Two | done | docs/dforge/registers/m2.md | open | - |\n'
} > "$D/roadmap.md"
git -C "$REPO" add -A && git -C "$REPO" commit -qm init
LATEST="$REPO/.dforge/handoff/latest.md"
FINISH="$REPO/.dforge/sdd/finish.json"

snapshot() { # snapshot — hashes, mtimes and the file list under .dforge
  (cd "$REPO" && find .dforge -print 2>/dev/null | LC_ALL=C sort)
  for f in "$LATEST" "$FINISH"; do
    [ -f "$f" ] && printf '%s %s\n' "$(digest "$f")" "$(mtime "$f")"
  done
}

# --- --print changes nothing ---
for mode in plain --complete --kept; do
  mkdir -p "$REPO/.dforge/handoff" "$REPO/.dforge/sdd"
  printf '# Handoff\n\n## Notes\n\nkeep me\n' > "$LATEST"
  printf '{"action":"merge"}\n' > "$FINISH"
  touch -t 200101010000 "$LATEST" "$FINISH"
  before=$(snapshot)
  if [ "$mode" = plain ]; then args=("$PLAN"); else args=("$mode" "$PLAN"); fi
  out=$(cd "$REPO" && timeout 60 bash "$SCRIPT" --print "${args[@]}" 2>&1)
  check "--print $mode: exits 0" "$?" 0
  has "--print $mode: prints the block" "$out" "## Next session"
  check "--print $mode: changes no file under .dforge" "$(snapshot)" "$before"
done
rm -rf "$REPO/.dforge"
out=$(cd "$REPO" && timeout 60 bash "$SCRIPT" --print "$PLAN" 2>&1)
check "--print without .dforge: exits 0" "$?" 0
check "--print without .dforge: creates nothing" "$([ -e "$REPO/.dforge" ] && echo created || echo none)" none

# --- --print ignores running background work ---
cp -R "$HERE/../scripts" "$TMP/scripts"
printf '#!/usr/bin/env bash\nprintf -- "- shell b1 10:00 idle 1m sleep\\n"\nexit 1\n' > "$TMP/scripts/in-flight"
out=$(cd "$REPO" && timeout 60 bash "$TMP/scripts/next-step" --print "$PLAN" 2>&1)
check "in flight: --print exits 0" "$?" 0
has "in flight: --print prints the block" "$out" "## Next session"
out=$(cd "$REPO" && timeout 60 bash "$TMP/scripts/next-step" "$PLAN" 2>&1)
check "in flight: a plain run still refuses" "$?" 5

# --- latest.md carries the marker and the block does not ---
MARK_RE='^<!-- next-step: kind=(plan|complete|kept|draft|adhoc)( branch=[^ ]+)? done=[0-9]+ closed=[0-9]+ subject=.+ at=[0-9]+ -->$'
section_last() { # the last non-blank line of latest.md's Next session section
  awk '/^## Next session[ \t\r]*$/ { on = 1; next } on && /^## / { exit } on && NF { last = $0 } END { print last }' "$LATEST"
}
for mode in plan complete kept draft adhoc; do
  case $mode in
    plan) args=("$PLAN") subject=$PLAN ;;
    complete) args=(--complete "$PLAN") subject=$PLAN ;;
    kept) args=(--kept "$PLAN") subject=$PLAN ;;
    draft) args=(--draft docs/dforge/specs/draft.md --next "x") subject=docs/dforge/specs/draft.md ;;
    adhoc) args=(--adhoc --phase build --next "x") subject=- ;;
  esac
  out=$(cd "$REPO" && timeout 60 bash "$SCRIPT" "${args[@]}" 2>&1)
  check "marker $mode: exits 0" "$?" 0
  lacks "marker $mode: the printed block has no marker" "$out" "<!-- next-step:"
  last=$(section_last)
  check "marker $mode: the section ends with a well-formed marker" "$(grep -cE "$MARK_RE" <<<"$last")" 1
  has "marker $mode: the kind is named" "$last" "kind=$mode "
  has "marker $mode: done counts completed.md entries" "$last" " done=2 "
  has "marker $mode: closed counts closed milestones" "$last" " closed=1 "
  has "marker $mode: the subject is named" "$last" " subject=$subject at="
  if [ "$mode" = kept ]; then has "marker kept: the branch is named" "$last" " branch=main "
  else lacks "marker $mode: no branch outside kept" "$last" "branch="; fi
  check "marker $mode: one marker in the file" "$(grep -c '^<!-- next-step:' "$LATEST")" 1
done

# --- the auto run still reads the first prompt ---
out=$(cd "$REPO" && timeout 60 bash "$SCRIPT" "$PLAN" 2>&1)
. "$HERE/../scripts/lib/auto-run.sh"
prompt=$(awk '/^Paste as the first prompt:/ { on = 1; next } on && /^```$/ { if (f) exit; f = 1; next } f' <<<"$out")
launch=$(awk '/^Launch in / { on = 1; next } on && /^```$/ { if (f) exit; f = 1; next } f' <<<"$out")
check "auto run: the first prompt reads unchanged" "$(ar_fenced "$LATEST" 'Paste as the first prompt:')" "$prompt"
check "auto run: the launch command reads unchanged" "$(ar_fenced "$LATEST" 'Launch in ')" "$launch"
has "auto run: the launch command is the plan's" "$launch" "claude --model sonnet --effort high"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
