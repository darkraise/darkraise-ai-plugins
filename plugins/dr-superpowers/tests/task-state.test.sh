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
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
