#!/usr/bin/env bash
# next-step --print computes the block and changes nothing; a normal run
# writes the block into its keyed handoff followed by a marker line naming what the
# block was computed from, which the printed block never carries.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../plugins/dagents/scripts/next-step"

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
D="$REPO/docs/dagents"
PLAN=docs/dagents/plans/2026-11-01-demo.md
mkdir -p "$D/plans" "$D/specs" "$D/registers"
printf '.dagents/\n' > "$REPO/.gitignore"
: > "$D/specs/demo.md"
printf '# Draft\n' > "$D/specs/draft.md"
{
  printf '# Demo\n\n**Spec:** docs/dagents/specs/demo.md\n'
  printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n\n'
  printf '### Task 1: One\n\nBody.\n\n### Task 2: Two\n\nBody.\n'
} > "$REPO/$PLAN"
printf '# Completed plans\n\n- 2026-10-01 — `docs/dagents/plans/2026-10-01-a.md` — merged\n- 2026-10-02 — `docs/dagents/plans/2026-10-02-b.md` — merged\n' \
  > "$D/plans/completed.md"
printf '# M2\n\n**Source:** roadmap\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Epic | - | - | done | - |\n' \
  > "$D/registers/m2.md"
cp "$D/registers/m2.md" "$D/registers/m1.md"
{
  printf '# Shop — roadmap\n\n**Product:** a shop\n**Spec:** docs/dagents/specs/demo.md\n\n'
  printf '| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n'
  printf '| M1 | One | done | docs/dagents/registers/m1.md | closed | audit |\n'
  printf '| M2 | Two | done | docs/dagents/registers/m2.md | open | - |\n'
} > "$D/roadmap.md"
git -C "$REPO" add -A && git -C "$REPO" commit -qm init
LATEST="$REPO/.dagents/handoff/latest.md"
# The session the adhoc and project writes run as.
S0=a0000000-0000-0000-0000-000000000000
FINISH="$REPO/.dagents/sdd/finish.json"

snapshot() { # snapshot — hashes, mtimes and the file list under .dagents
  (cd "$REPO" && find .dagents -print 2>/dev/null | LC_ALL=C sort)
  for f in "$LATEST" "$FINISH"; do
    [ -f "$f" ] && printf '%s %s\n' "$(digest "$f")" "$(mtime "$f")"
  done
}

# --- --print changes nothing ---
for mode in plain --complete --kept --project; do
  mkdir -p "$REPO/.dagents/handoff" "$REPO/.dagents/sdd"
  printf '# Handoff\n\n## Notes\n\nkeep me\n' > "$LATEST"
  printf '{"action":"merge"}\n' > "$FINISH"
  touch -t 200101010000 "$LATEST" "$FINISH"
  before=$(snapshot)
  case $mode in plain) args=("$PLAN") ;; --project) args=(--project) ;; *) args=("$mode" "$PLAN") ;; esac
  out=$(cd "$REPO" && timeout 60 bash "$SCRIPT" --print "${args[@]}" 2>&1)
  check "--print $mode: exits 0" "$?" 0
  has "--print $mode: prints the block" "$out" "## Next session"
  check "--print $mode: changes no file under .dagents" "$(snapshot)" "$before"
done
rm -rf "$REPO/.dagents"
out=$(cd "$REPO" && timeout 60 bash "$SCRIPT" --print "$PLAN" 2>&1)
check "--print without .dagents: exits 0" "$?" 0
check "--print without .dagents: creates nothing" "$([ -e "$REPO/.dagents" ] && echo created || echo none)" none

# --- --print ignores running background work ---
cp -R "$HERE/../../plugins/dagents/scripts" "$TMP/scripts"
cp -R "$HERE/../../plugins/dagents/config" "$TMP/config"
printf '#!/usr/bin/env bash\nprintf -- "- shell b1 10:00 idle 1m sleep\\n"\nexit 1\n' > "$TMP/scripts/in-flight"
out=$(cd "$REPO" && timeout 60 bash "$TMP/scripts/next-step" --print "$PLAN" 2>&1)
check "in flight: --print exits 0" "$?" 0
has "in flight: --print prints the block" "$out" "## Next session"
out=$(cd "$REPO" && timeout 60 bash "$TMP/scripts/next-step" "$PLAN" 2>&1)
check "in flight: a plain run still refuses" "$?" 5

# --- the handoff carries the marker and the block does not ---
MARK_RE='^<!-- next-step: kind=(plan|complete|kept|draft|adhoc)( branch=[^ ]+)? key=[A-Za-z0-9._-]+ session=[^ ]+ done=[0-9]+ closed=[0-9]+ subject=.+ at=[0-9]+ -->$'
section_last() { # the last non-blank line of $LATEST's Next session section
  awk '/^## Next session[ \t\r]*$/ { on = 1; next } on && /^## / { exit } on && NF { last = $0 } END { print last }' "$LATEST"
}
for mode in plan complete kept draft adhoc; do
  case $mode in
    plan) args=("$PLAN") subject=$PLAN ;;
    complete) args=(--complete "$PLAN") subject=$PLAN ;;
    kept) args=(--kept "$PLAN") subject=$PLAN ;;
    draft) args=(--draft docs/dagents/specs/draft.md --next "x") subject=docs/dagents/specs/draft.md ;;
    adhoc) args=(--adhoc --phase build --next "x") subject=- ;;
  esac
  LATEST=$(cd "$REPO" && CLAUDE_CODE_SESSION_ID=$S0 timeout 60 bash "$SCRIPT" --target "${args[@]}")
  out=$(cd "$REPO" && CLAUDE_CODE_SESSION_ID=$S0 timeout 60 bash "$SCRIPT" "${args[@]}" 2>&1)
  check "marker $mode: exits 0" "$?" 0
  lacks "marker $mode: the printed block has no marker" "$out" "<!-- next-step:"
  last=$(section_last)
  has "marker $mode: the key is the file's name" "$last" " key=$(basename "$LATEST" .md) "
  has "marker $mode: the session is named" "$last" " session=$S0 "
  check "marker $mode: the section ends with a well-formed marker" "$(grep -cE "$MARK_RE" <<<"$last")" 1
  has "marker $mode: the kind is named" "$last" "kind=$mode "
  has "marker $mode: done counts completed.md entries" "$last" " done=2 "
  has "marker $mode: closed counts closed milestones" "$last" " closed=1 "
  has "marker $mode: the subject is named" "$last" " subject=$subject at="
  if [ "$mode" = kept ]; then has "marker kept: the branch is named" "$last" " branch=main "
  else lacks "marker $mode: no branch outside kept" "$last" "branch="; fi
  check "marker $mode: one marker in the file" "$(grep -c '^<!-- next-step:' "$LATEST")" 1
done

# --- an indexed plan is answered as complete ---
INDEXED=docs/dagents/plans/2026-10-01-a.md
sed 's/^# Demo$/# A/' "$REPO/$PLAN" > "$REPO/$INDEXED"
git -C "$REPO" add -A && git -C "$REPO" commit -qm indexed
plain=$(cd "$REPO" && timeout 60 bash "$SCRIPT" --print "$INDEXED" 2>&1 | grep '^\*\*Next:\*\*')
completed_next=$(cd "$REPO" && timeout 60 bash "$SCRIPT" --print --complete "$INDEXED" 2>&1 | grep '^\*\*Next:\*\*')
check "indexed: a plain run answers as --complete does" "$plain" "$completed_next"
lacks "indexed: an indexed plan does not start at Task 1" "$plain" "Start at Task 1"

# --- a ledger in a linked worktree is found from the primary ---
THREE=docs/dagents/plans/2026-11-02-three.md
{
  printf '# Three\n\n**Spec:** docs/dagents/specs/demo.md\n'
  printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n\n'
  printf '### Task 1: One\n\nBody.\n\n### Task 2: Two\n\nBody.\n\n### Task 3: Three\n\nBody.\n'
} > "$REPO/$THREE"
git -C "$REPO" add -A && git -C "$REPO" commit -qm three
git -C "$REPO" worktree add -q "$TMP/wt" -b feat
WT=$(git -C "$TMP/wt" rev-parse --show-toplevel)
WLEDGER="$TMP/wt/.dagents/sdd/2026-11-02-three/progress.md"
mkdir -p "$(dirname "$WLEDGER")"
printf '# SDD ledger — plan: %s\nTask 1: complete (commits a..b, unreviewed)\n' "$THREE" > "$WLEDGER"
out=$(cd "$REPO" && timeout 60 bash "$SCRIPT" --print "$THREE" 2>&1)
has "worktree ledger: the tasks done are counted" "$out" "1 of 3 tasks complete"
has "worktree ledger: the next task resumes" "$out" "**Next:** Resume at Task 2"
has "worktree ledger: the prompt starts in the worktree" "$out" "Start in \`$WT\` (branch feat)"
printf 'x\n' > "$TMP/wt/x.txt"
git -C "$TMP/wt" add x.txt && git -C "$TMP/wt" commit -qm work
whead=$(git -C "$TMP/wt" rev-parse --short HEAD)
printf 'Task 2: complete (commits a..b, unreviewed)\nTask 3: complete (commits a..b, unreviewed)\nFinal review: clean (commits abc1234..%s)\n' "$whead" >> "$WLEDGER"
out=$(cd "$REPO" && timeout 60 bash "$SCRIPT" --print "$THREE" 2>&1)
has "worktree ledger: the clean review is read against the worktree" "$out" "the final review is clean"
lacks "worktree ledger: the reviewed head is not taken as rewritten" "$out" "no longer in the branch history"

# --- the auto run still reads the first prompt ---
out=$(cd "$REPO" && timeout 60 bash "$SCRIPT" "$PLAN" 2>&1)
. "$HERE/../../plugins/dagents/scripts/lib/auto-run.sh"
prompt=$(awk '/^Paste as the first prompt:/ { on = 1; next } on && /^```$/ { if (f) exit; f = 1; next } f' <<<"$out")
launch=$(awk '/^Launch in / { on = 1; next } on && /^```$/ { if (f) exit; f = 1; next } f' <<<"$out")
check "auto run: the first prompt reads unchanged" "$(ar_fenced "$REPO/.dagents/handoff/2026-11-01-demo.md" 'Paste as the first prompt:')" "$prompt"
check "auto run: the launch command reads unchanged" "$(ar_fenced "$REPO/.dagents/handoff/2026-11-01-demo.md" 'Launch in ')" "$launch"
has "auto run: the launch command is the plan's" "$launch" "claude --model sonnet --effort high"

# --- --print --handoff on a stored block in the plan's handoff file ---
L="$TMP/latest"
lfixture() { # lfixture — a fresh repository in $L with plan P (3 tasks) and completed.md of one entry
  rm -rf "$L"; git init -q -b main "$L"
  LD="$L/docs/dagents"; mkdir -p "$LD/plans" "$LD/specs" "$LD/registers" "$L/.dagents/handoff"
  printf '.dagents/\n' > "$L/.gitignore"
  : > "$LD/specs/demo.md"
  {
    printf '# P\n\n**Spec:** docs/dagents/specs/demo.md\n'
    printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n\n'
    printf '### Task 1: One\n\nBody.\n\n### Task 2: Two\n\nBody.\n\n### Task 3: Three\n\nBody.\n'
  } > "$LD/plans/2026-11-01-p.md"
  printf '# Completed plans\n\n- 2026-10-01 — `docs/dagents/plans/2026-10-01-a.md` — merged\n' > "$LD/plans/completed.md"
  git -C "$L" add -A && git -C "$L" commit -qm init
  LL="$L/.dagents/handoff/2026-11-01-p.md"
}
P=docs/dagents/plans/2026-11-01-p.md
stored() { # stored <marker or empty> [status line] [next line] — write $LL by hand
  { printf '# Handoff\n\n## Notes\n\nmine\n\n## Next session\n\n**Status:** %s\n**Next:** %s\n' "${2:-Stored status.}" "${3:-Stored next.}"
    [ -z "$1" ] || printf '%s\n' "$1"; } > "$LL"
}
latest() { # latest [FILE] — run --print --handoff FILE (default $LL) in $L; sets out, err, status
  out=$(cd "$L" && timeout 120 bash "$SCRIPT" --print --handoff "${1:-$LL}" 2>"$TMP/lerr"); status=$?
  err=$(cat "$TMP/lerr")
}
index_p() { printf -- '- 2026-11-10 — `%s` — merged\n' "$P" >> "$LD/plans/completed.md"; }

lfixture
stored "<!-- next-step: kind=adhoc done=1 closed=0 subject=- at=1 -->"
latest
check "latest adhoc: matching counts exit 0" "$status" 0
has "latest adhoc: matching counts print the stored block" "$out" "**Next:** Stored next."
check "latest adhoc: the marker is the last line" "$(tail -n 1 <<<"$out")" "<!-- next-step: kind=adhoc done=1 closed=0 subject=- at=1 -->"
printf -- '- 2026-10-02 — `docs/dagents/plans/2026-10-02-b.md` — merged\n' >> "$LD/plans/completed.md"
latest
check "latest adhoc: a newer completed plan never supersedes it" "$status" 0
has "latest adhoc: the stored block is still printed" "$out" "**Next:** Stored next."
lfixture
printf '# M1\n\n**Source:** roadmap\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | E | - | - | done | - |\n' > "$LD/registers/m1.md"
printf '# R\n\n**Product:** p\n**Spec:** docs/dagents/specs/demo.md\n\n| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n| M1 | One | x | docs/dagents/registers/m1.md | closed | audit |\n' > "$LD/roadmap.md"
stored "<!-- next-step: kind=adhoc done=1 closed=0 subject=- at=1 -->"
latest
check "latest adhoc: a newly closed milestone never supersedes it" "$status" 0

lfixture
printf '# D\n' > "$LD/specs/D.md"
stored "<!-- next-step: kind=draft done=1 closed=0 subject=docs/dagents/specs/D.md at=1 -->"
latest
check "latest draft: a draft with no plan prints the stored block" "$status" 0
sed 's#docs/dagents/specs/demo.md#docs/dagents/specs/D.md#' "$L/$P" > "$LD/plans/2026-11-02-d.md"
latest
check "latest draft: a plan naming the draft supersedes it" "$status" 6
lfixture
printf '# D\n' > "$LD/specs/my draft.md"
stored "<!-- next-step: kind=draft done=1 closed=0 subject=docs/dagents/specs/my draft.md at=1 -->"
sed 's#^\*\*Spec:\*\* docs/dagents/specs/demo.md#**Spec:** `docs/dagents/specs/my draft.md`#' "$L/$P" > "$LD/plans/2026-11-02-d.md"
latest
check "latest draft: a Spec path with a space supersedes the draft" "$status" 6

lfixture
stored ""
latest
check "latest no marker: exits 0" "$status" 0
has "latest no marker: prints the stored block" "$out" "**Next:** Stored next."
check "latest no marker: the kind=none line carries the mtime" "$(tail -n 1 <<<"$out")" "<!-- next-step: kind=none subject=- at=$(mtime "$LL") -->"

lfixture
git -C "$L" checkout -q -b feat && printf 'x\n' > "$L/x.txt" && git -C "$L" add x.txt && git -C "$L" commit -qm feat && git -C "$L" checkout -q main
KEPT="<!-- next-step: kind=kept branch=feat done=1 closed=0 subject=$P at=1 -->"
stored "$KEPT"
latest
check "latest kept: an unmerged branch exits 0" "$status" 0
has "latest kept: an unmerged branch prints the stored block" "$out" "**Next:** Stored next."
index_p
want=$(cd "$L" && bash "$SCRIPT" --print --complete "$P" 2>/dev/null | grep '^\*\*Next:\*\*')
latest
has "latest kept: once indexed it is the --complete block" "$out" "$want"
sed -i.bak '$d' "$LD/plans/completed.md" && rm -f "$LD/plans/completed.md.bak"
git -C "$L" branch -q -D feat
latest
check "latest kept: a deleted branch exits 6" "$status" 6
lfixture
git -C "$L" checkout -q -b feat && printf 'x\n' > "$L/x.txt" && git -C "$L" add x.txt && git -C "$L" commit -qm feat && git -C "$L" checkout -q main
git -C "$L" merge -q --no-ff -m merge feat
stored "$KEPT"
latest
check "latest kept: a merged branch exits 6" "$status" 6

lfixture
stored "<!-- next-step: kind=plan done=1 closed=0 subject=$P at=1 -->" "Plan \`$P\`: 2 of 3 tasks complete (ledger \`x\`)." "Resume at Task 3 (Three)."
latest
check "latest plan: a lost ledger never restarts the plan" "$status" 6
has "latest plan: the reason is named" "$err" "the ledger is gone and the plan is unrecorded"
check "latest plan: nothing on stdout" "$out" ""
lfixture
stored "<!-- next-step: kind=plan done=1 closed=0 subject=$P at=1 -->" "Plan \`$P\`: all 3 tasks complete." "Run the final review."
latest
check "latest plan: a lost ledger with all tasks complete never restarts the plan" \
  "$status:$(grep -cF "next-step: the ledger is gone and the plan is unrecorded: $P" <<<"$err")" "6:1"
mkdir -p "$L/.dagents/sdd/2026-11-01-p"
printf '# SDD ledger — plan: %s\nTask 1: complete (x)\nTask 2: complete (x)\n' "$P" > "$L/.dagents/sdd/2026-11-01-p/progress.md"
PM="<!-- next-step: kind=plan done=1 closed=0 subject=$P at=1 -->"
stored "$PM" "Plan \`$P\`: 1 of 3 tasks complete." "Resume at Task 2 (Two)."
latest
check "latest plan: recomputed exits 0" "$status" 0
has "latest plan: recomputed from the ledger" "$out" "**Next:** Resume at Task 3 (Three)."
check "latest plan: the stored marker is the last line" "$(tail -n 1 <<<"$out")" "$PM"

for kind in plan project; do
  if [ "$kind" = plan ]; then mk=$PM; else mk="<!-- next-step: kind=project done=1 closed=0 subject=- at=1 -->"; fi
  stored "$mk"
  touch -t 200101010000 "$LL"
  before=$( (cd "$L" && find .dagents -print | LC_ALL=C sort); digest "$LL"; mtime "$LL")
  latest
  # With no register the project block is terminal (C10): exit 6.
  check "latest $kind: exits $( [ "$kind" = plan ] && echo 0 || echo 6)" "$status" "$( [ "$kind" = plan ] && echo 0 || echo 6)"
  check "latest $kind: changes nothing" "$( (cd "$L" && find .dagents -print | LC_ALL=C sort); digest "$LL"; mtime "$LL")" "$before"
done

lfixture
printf '# R\n\n**Source:** s\n**Covers:** -\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Thing | - | - | open | - |\n' > "$LD/registers/r.md"
LA="$L/.dagents/handoff/adhoc-a0000000.md"
(cd "$L" && CLAUDE_CODE_SESSION_ID=$S0 timeout 120 bash "$SCRIPT" --host codex --project >/dev/null 2>&1)
has "latest host: a Codex write names its host in the marker" "$(grep '^<!-- next-step: ' "$LA")" " host=codex "
latest "$LA"
has "latest host: a Codex project block recomputes with the Codex launch" "$out" "codex -m"
lacks "latest host: a Codex project block names no Claude launch" "$out" "claude --model"
(cd "$L" && CLAUDE_CODE_SESSION_ID=$S0 timeout 120 bash "$SCRIPT" --project >/dev/null 2>&1)
lacks "latest host: a Claude write adds no host word" "$(grep '^<!-- next-step: ' "$LA")" "host="

rm -f "$L/.dagents/handoff/"*.md; latest
check "latest edges: no handoff file exits 6" "$status" 6
printf '# Handoff\n\n## Notes\n\nx\n' > "$LL"; latest
check "latest edges: no Next session section is unreadable, exit 2" "$status" 2
(cd "$L" && timeout 60 bash "$SCRIPT" --print --latest >/dev/null 2>&1); check "latest edges: --latest is no option" "$?" 2
stored "<!-- next-step: kind=plan done=1 closed=0 subject=docs/dagents/plans/missing.md at=1 -->"; latest
check "latest edges: a missing plan passes exit 2 through" "$status" 2

# --- --print --handoff: complete markers, an indexed plan, malformed markers ---
lfixture
index_p
want=$(cd "$L" && bash "$SCRIPT" --print --complete "$P" 2>/dev/null | grep '^\*\*Next:\*\*')
stored "<!-- next-step: kind=complete done=2 closed=0 subject=$P at=1 -->"
latest
check "latest complete: a terminal --complete block exits 6" "$status" 6
check "latest complete: the recomputed Next is terminal" "${want#\*\*Next:\*\* Nothing — }" "the plan records no follow-on work."
check "latest complete: nothing on stdout" "$out" ""
want=$(cd "$L" && bash "$SCRIPT" --print "$P" 2>/dev/null | grep '^\*\*Next:\*\*')
stored "<!-- next-step: kind=plan done=1 closed=0 subject=$P at=1 -->" "Plan \`$P\`: 2 of 3 tasks complete (ledger \`x\`)." "Resume at Task 3 (Three)."
latest
check "latest plan: a plan in completed.md exits 6" "$status" 6
has "latest plan: the reason is named" "$err" "the plan is finished"
for bad in --latest -x docs/dagents/plans/p.txt; do
  stored "<!-- next-step: kind=plan done=1 closed=0 subject=$bad at=1 -->" "Plan \`$P\`: 0 of 3 tasks complete." "Start at Task 1 (One)."
  latest
  check "latest edges: the subject $bad is unreadable, exit 2" "$status" 2
  has "latest edges: the subject $bad is named malformed" "$err" "malformed marker subject"
done
stored "<!-- next-step: kind=adhoc done=1x closed=0 subject=- at=1 -->"
latest
check "latest edges: non-numeric counts are unreadable, exit 2" "$status" 2
stored "<!-- next-step: kind=bogus done=0 closed=0 subject=- at=1 -->"
latest
check "latest edges: an unknown kind is unreadable, exit 2" "$status" 2

# --- --print --handoff FILE: per-kind exit 6 (C10) ---
handoff() { # handoff FILE — run --print --handoff FILE in $L; sets out, err, status
  out=$(cd "$L" && timeout 120 bash "$SCRIPT" --print --handoff "$1" 2>"$TMP/lerr"); status=$?
  err=$(cat "$TMP/lerr")
}
hstore() { # hstore FILE MARKER — a handoff written by hand
  mkdir -p "$(dirname "$1")"
  printf '# Handoff\n\n## Next session\n\n**Status:** Stored status.\n**Next:** Stored next.\n%s\n' "$2" > "$1"
}
lfixture
HD="$L/.dagents/handoff"
printf '# D\n' > "$LD/specs/D.md"
hstore "$HD/D.md" "<!-- next-step: kind=draft key=D session=- done=1 closed=0 subject=docs/dagents/specs/D.md at=1 -->"
handoff "$HD/D.md"
check "handoff_exit6_per_kind: a draft with no plan exits 0" "$status" 0
printf -- '- 2026-10-02 — `docs/dagents/plans/2026-10-02-b.md` — merged\n' >> "$LD/plans/completed.md"
handoff "$HD/D.md"
check "handoff_exit6_per_kind: a draft after done= grew exits 0" "$status" 0
{ printf '# Q\n\n**Spec:** docs/dagents/specs/demo.md\n**Program:** docs/dagents/specs/D.md — sub-project 1\n'
  printf '**Execution:** inline — `claude --model sonnet --effort high` — small\n\n### Task 1: One\n\nBody.\n'; } > "$LD/plans/2026-11-03-q.md"
handoff "$HD/D.md"
check "handoff_exit6_per_kind: a draft named only by a Program line exits 0" "$status" 0
sed 's#docs/dagents/specs/demo.md#docs/dagents/specs/D.md#' "$L/$P" > "$LD/plans/2026-11-02-d.md"
handoff "$HD/D.md"
check "handoff_exit6_per_kind: a draft named by a Spec line exits 6" "$status" 6
rm -f "$LD/plans/2026-11-02-d.md" "$LD/specs/D.md"
handoff "$HD/D.md"
check "handoff_exit6_per_kind: a deleted draft exits 6" "$status" 6
has "handoff_exit6_per_kind: the deleted draft is named" "$err" "is gone"
hstore "$HD/adhoc-0a1b2c3d.md" "<!-- next-step: kind=adhoc key=adhoc-0a1b2c3d session=- done=0 closed=0 subject=- at=1 -->"
handoff "$HD/adhoc-0a1b2c3d.md"
check "handoff_exit6_per_kind: an adhoc handoff exits 0" "$status" 0
lfixture
HD="$L/.dagents/handoff"
index_p
hstore "$HD/C.md" "<!-- next-step: kind=complete key=2026-11-01-p session=- done=2 closed=0 subject=$P at=1 -->"
(cd "$L" && timeout 60 bash "$SCRIPT" --handoff "$HD/C.md" >/dev/null 2>&1)
check "handoff: --handoff without --print is a usage error" "$?" 2

# handoff_prompt_names_file
lfixture
HD="$L/.dagents/handoff"
hstore "$HD/D.md" "<!-- next-step: kind=plan key=2026-11-01-p session=- done=1 closed=0 subject=$P at=1 -->"
handoff "$HD/D.md"
check "handoff_prompt_names_file: exits 0" "$status" 0
has "handoff_prompt_names_file: the first prompt names the file" "$out" "its handoff is \`$HD/D.md\`"
handoff .dagents/handoff/D.md
has "handoff_prompt_names_file: a relative file is named absolute" "$out" "its handoff is \`$L/.dagents/handoff/D.md\`"

# --- a kept detached HEAD is recorded as a commit and recomputed as one ---
lfixture
git -C "$L" checkout -q --detach
printf 'y\n' > "$L/y.txt" && git -C "$L" add y.txt && git -C "$L" commit -qm detached
sha=$(git -C "$L" rev-parse --short HEAD)
(cd "$L" && timeout 60 bash "$SCRIPT" --kept "$P" >/dev/null 2>&1)
has "kept detached: the marker records the commit" "$(LATEST=$L/.dagents/handoff/2026-11-01-p.md section_last)" "kind=kept branch=detached:$sha "
git -C "$L" checkout -q main
latest
check "kept detached: an unmerged commit exits 0" "$status" 0
has "kept detached: an unmerged commit prints the stored block" "$out" "**Next:**"
git -C "$L" merge -q --no-ff -m merge "$sha"
latest
check "kept detached: a merged commit exits 6" "$status" 6

# --- the supersession counts are the primary's, wherever the block is written ---
lfixture
printf -- '- 2026-10-02 — `docs/dagents/plans/2026-10-02-b.md` — merged\n' >> "$LD/plans/completed.md"
git -C "$L" add -A && git -C "$L" commit -qm index
git -C "$L" worktree add -q --detach "$TMP/latest-wt" HEAD~1
(cd "$TMP/latest-wt" && CLAUDE_CODE_SESSION_ID=$S0 timeout 60 bash "$SCRIPT" --adhoc --phase build --next "Fix the thing." >/dev/null 2>&1)
has "counts: a block written in an older worktree counts the primary's index" "$(LATEST="$TMP/latest-wt/.dagents/handoff/adhoc-a0000000.md" section_last)" " done=2 "
out=$(cd "$TMP/latest-wt" && timeout 120 bash "$SCRIPT" --print --handoff "$TMP/latest-wt/.dagents/handoff/adhoc-a0000000.md" 2>/dev/null); status=$?
check "counts: that block is not superseded in its worktree" "$status" 0
git -C "$L" worktree remove --force "$TMP/latest-wt"

# --- timing: 1,000 rows across 10 registers and 25 plans naming one spec ---
lfixture
: > "$LD/specs/big.md"
for i in $(seq -w 1 25); do
  sed 's#docs/dagents/specs/demo.md#docs/dagents/specs/big.md#' "$L/$P" > "$LD/plans/2026-10-$i-big.md"
  printf -- '- 2026-10-01 — `docs/dagents/plans/2026-10-%s-big.md` — merged\n' "$i" >> "$LD/plans/completed.md"
done
for r in $(seq 1 10); do
  { printf '# R%s\n\n**Source:** test\n**Covers:** docs/dagents/specs/big.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n' "$r"
    for i in $(seq 1 100); do printf '| %s | Row %s | docs/dagents/specs/big.md | - | open | - |\n' "$i" "$i"; done
  } > "$LD/registers/r$r.md"
done
stored "<!-- next-step: kind=project done=26 closed=0 subject=- at=1 -->"
t0=${EPOCHREALTIME:-$(date +%s)}
latest
t1=${EPOCHREALTIME:-$(date +%s)}
ms=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%d", (b - a) * 1000 }')
printf 'next-step-print: --print --handoff took %s ms\n' "$ms"
check "timing: the recompute exits 0" "$status" 0
has "timing: the follow-up route is computed" "$out" "write a follow-up plan"
if [ "$(uname -s)" = Linux ]; then
  check "timing: under 10 s on Linux" "$([ "$ms" -lt 10000 ] && echo fast || echo "slow ($ms ms)")" fast
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
