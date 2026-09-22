#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok - %s\n' "$1"; pass=$((pass+1)); else printf 'FAIL - %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
check 'state library exists' "$([ -f "$HERE/../scripts/lib/task-state.sh" ] && echo yes || echo no)" yes
[ "$fail" -eq 0 ] || exit 1
source "$HERE/../scripts/lib/task-state.sh"
git init -q "$fixture/primary"
git -C "$fixture/primary" config user.email fixture@example.com
git -C "$fixture/primary" config user.name Fixture
git -C "$fixture/primary" config core.autocrlf false
printf 'base\n' > "$fixture/primary/base.txt"
git -C "$fixture/primary" add base.txt
git -C "$fixture/primary" commit -qm 'test: seed fixture'
git -C "$fixture/primary" worktree add -qb task "$fixture/work"
printf '["base.txt","new file.txt"]\n' > "$fixture/scope.json"
dr_task_open "$fixture/primary" task-1 "$fixture/scope.json" 2>/dev/null
check 'primary checkout is rejected' "$?" 2
dr_task_open "$fixture/work" task-1 "$fixture/scope.json"
check 'linked clean worktree is accepted' "$?" 0
check 'task starts ready' "$(jq -r .phase "$DR_TASK_DIR/state.json")" ready
dr_snapshot "$fixture/work" "$fixture/before.json"
printf 'unrelated\n' > "$fixture/work/unrelated.txt"
dr_task_assert_snapshot "$fixture/before.json" >/dev/null 2>&1
check 'untracked drift rejects recovery' "$?" 1
dr_task_validate_scope "$fixture/before.json" >/dev/null 2>&1
check 'unrelated file is outside approved scope' "$?" 1
rm -f "$fixture/work/unrelated.txt"
printf 'new\n' > "$fixture/work/new file.txt"
dr_task_validate_scope "$fixture/before.json"
check 'literal path with spaces is accepted' "$?" 0
rm -f "$fixture/work/new file.txt"
printf 'tracked drift\n' > "$fixture/work/base.txt"
dr_task_assert_snapshot "$fixture/before.json" >/dev/null 2>&1
check 'tracked drift invalidates review snapshot' "$?" 1
git -C "$fixture/work" add base.txt
dr_task_assert_snapshot "$fixture/before.json" >/dev/null 2>&1
check 'index drift invalidates review snapshot' "$?" 1
git -C "$fixture/work" commit -qm 'test: move HEAD'
dr_task_assert_snapshot "$fixture/before.json" >/dev/null 2>&1
check 'HEAD drift invalidates review snapshot' "$?" 1
git -C "$fixture/work" reset -q --hard HEAD~1
(dr_task_open "$fixture/work" task-2 "$fixture/scope.json") >/dev/null 2>&1
check 'another invocation cannot steal locked worktree' "$?" 2
dr_task_unlock
(dr_task_open "$fixture/work" task-2 "$fixture/scope.json") >/dev/null 2>&1
check 'persistent owner survives unlocking' "$?" 2
dr_task_open "$fixture/work" task-1 "$fixture/scope.json"
check 'same task can reopen after unlock' "$?" 0
dr_task_unlock
printf '{broken' > "$DR_TASK_DIR/state.json"
(dr_task_open "$fixture/work" task-1 "$fixture/scope.json") >/dev/null 2>&1
check 'malformed state cannot become a fresh task' "$?" 2

# Batched JSON serialization must preserve filenames and deleted entries.
git -C "$fixture/primary" worktree add -q --detach "$fixture/encoding" HEAD
odd="space [brackets] 'quote'.txt"
case "${OSTYPE:-}" in
  msys*|cygwin*) ;;
  *) odd+=$'\tnewline\n"backslash\\.txt' ;;
esac
printf 'special content\n' > "$fixture/encoding/$odd"
rm "$fixture/encoding/base.txt"
dr_snapshot "$fixture/encoding" "$fixture/encoding.json"
check 'special filenames and deletions can be snapshotted' "$?" 0
jq -e --arg path "$odd" '.files | any(.path == $path and .kind == "file" and .mode == "100644" and (.hash | length > 0))' \
  "$fixture/encoding.json" >/dev/null
check 'filename characters survive JSON serialization' "$?" 0
jq -e '.files | any(.path == "base.txt" and .kind == "deleted" and .mode == "0" and .hash == "")' \
  "$fixture/encoding.json" >/dev/null
check 'deleted files retain their empty hash and mode' "$?" 0
dr_task_assert_snapshot "$fixture/encoding.json" >/dev/null 2>&1
check 'special filenames and deletions round-trip' "$?" 0

# --- a worktree large enough to exceed the OS argument limit ----------------
# dr_snapshot passed the base64 index and the whole file manifest to jq as
# command-line arguments. Windows caps a command line at 32767 bytes, so on any
# repository of a few hundred files jq never started and every delegated task
# died at "cannot snapshot worktree" before its executor ran. Every other case
# in this suite uses a one-file fixture, which is why the ceiling went unseen.
git -C "$fixture/primary" worktree add -q --detach "$fixture/big" HEAD
i=0
while [ "$i" -lt 700 ]; do
  printf 'content %s\n' "$i" > "$fixture/big/file-with-a-longish-name-$i.txt"
  i=$((i + 1))
done
git -C "$fixture/big" add -A
git -C "$fixture/big" commit -qm 'test: many files'
dr_snapshot "$fixture/big" "$fixture/big.json"
check 'a large worktree can be snapshotted' "$?" 0
check 'the large snapshot lists every file' \
  "$(jq -r '.files | length' "$fixture/big.json" 2>/dev/null)" 701
dr_task_assert_snapshot "$fixture/big.json" >/dev/null 2>&1
check 'a large snapshot round-trips against its own worktree' "$?" 0

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
