#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/run-codex-task.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok - %s\n' "$1"; pass=$((pass+1)); else printf 'FAIL - %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
mkdir -p "$fixture/bin"
git init -q "$fixture/primary"
git -C "$fixture/primary" config user.email fixture@example.com
git -C "$fixture/primary" config user.name Fixture
git -C "$fixture/primary" config core.autocrlf false
printf 'base\n' > "$fixture/primary/base.txt"
git -C "$fixture/primary" add base.txt
git -C "$fixture/primary" commit -qm 'test: seed fixture'
git -C "$fixture/primary" worktree add -qb task "$fixture/work"
printf 'Implement only the approved files.\n' > "$fixture/brief.md"
printf '["base.txt","produced.txt","new file.txt"]\n' > "$fixture/scope.json"
cat > "$fixture/bin/codex" <<'STUB'
#!/usr/bin/env bash
out='' cwd=''
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out="$2"; shift 2 ;; -C) cwd="$2"; shift 2 ;; *) shift ;; esac
done
printf 'launched\n' >> "$LAUNCH_LOG"
printf '{"type":"thread.started","thread_id":"thread-one"}\n'
if [ -n "${STUB_SLEEP:-}" ]; then
  sleep "$STUB_SLEEP" &
  child=$!
  [ -z "${STUB_CHILD_PID_FILE:-}" ] || printf '%s\n' "$child" > "$STUB_CHILD_PID_FILE"
  wait "$child"
fi
if [ -n "${STUB_DELETE:-}" ]; then rm -f -- "$cwd/$STUB_DELETE"; fi
if [ -z "${STUB_NO_WRITE:-}" ]; then printf '%s\n' "${STUB_CONTENT:-produced}" > "$cwd/${STUB_PATH:-produced.txt}"; fi
printf '{"status":"%s","summary":"fixture","commit_subject":"feat(test): produce file","questions":[]}\n' "${STUB_STATUS:-DONE}" > "$out"
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$fixture/bin/codex"
export PATH="$fixture/bin:$PATH" LAUNCH_LOG="$fixture/launch.log"
run() { bash "$SCRIPT" --cwd "$fixture/work" --task-id task-one --write-set "$fixture/scope.json" \
  --brief "$fixture/brief.md" --report "$fixture/report.md" --model gpt-5.5 --effort medium "$@" > "$fixture/out" 2> "$fixture/err"; }
printf 'unrelated\n' > "$fixture/work/unrelated.txt"
before="$(git -C "$fixture/work" rev-parse HEAD)"
run
check 'dirty initial task rejected' "$?" 2
check 'dirty initial task never launches model' "$([ -e "$LAUNCH_LOG" ] && echo yes || echo no)" no
check 'dirty initial task preserves HEAD' "$(git -C "$fixture/work" rev-parse HEAD)" "$before"
rm -f "$fixture/work/unrelated.txt"
run
check 'clean linked task succeeds' "$?" 0
check 'success commits produced file' "$(git -C "$fixture/work" show HEAD:produced.txt 2>/dev/null)" produced
gitdir="$(git -C "$fixture/work" rev-parse --absolute-git-dir)"
task_key="$(printf task-one | git -C "$fixture/work" hash-object --stdin)"
state="$gitdir/dr-superpowers/tasks/$task_key/state.json"
check 'success persists complete state' "$(jq -r .phase "$state" 2>/dev/null)" complete
check 'success persists thread' "$(jq -r .thread "$state" 2>/dev/null)" thread-one
STUB_CONTENT=review-fix run --resume thread-one --review-round 1 --report "$fixture/fix-report.md"
check 'review fix resumes after successful commit' "$?" 0
check 'review fix commits changed bytes' "$(git -C "$fixture/work" show HEAD:produced.txt 2>/dev/null)" review-fix
check 'changed report retains task attempts' "$(jq '.attempts | length' "$state" 2>/dev/null)" 2
check 'review round is recorded explicitly' "$(jq .review_rounds "$state")" 1
run --resume wrong-thread
check 'thread mismatch rejected' "$?" 2
STUB_NO_WRITE=1 run --resume thread-one
check 'no-change success remains resumable' "$?" 0
check 'transport or clarification resume preserves review count' "$(jq .review_rounds "$state")" 1
STUB_STATUS=BLOCKED STUB_CONTENT=partial run --resume thread-one
check 'executed incomplete task returns one' "$?" 1
check 'partial run persists pending state' "$(jq -r .phase "$state" 2>/dev/null)" pending
STUB_CONTENT=retried run
check 'fresh retry accepts exact pending state' "$?" 0
printf '#!/usr/bin/env bash\nexit 1\n' > "$fixture/primary/.git/hooks/pre-commit"
chmod +x "$fixture/primary/.git/hooks/pre-commit"
STUB_CONTENT=commit-recovery run
check 'commit hook failure exits two' "$?" 2
check 'commit failure persists blocked state' "$(jq -r .phase "$state" 2>/dev/null)" blocked
rm -f "$fixture/primary/.git/hooks/pre-commit"
launches="$(wc -l < "$LAUNCH_LOG" 2>/dev/null || echo 0)"
bash "$SCRIPT" --cwd "$fixture/work" --task-id task-one --recover-commit > "$fixture/out" 2> "$fixture/err"
check 'commit recovery succeeds without model' "$?" 0
check 'commit recovery does not launch a child' "$(wc -l < "$LAUNCH_LOG" 2>/dev/null || echo 0)" "$launches"
check 'recovered commit contains expected bytes' "$(git -C "$fixture/work" show HEAD:produced.txt 2>/dev/null)" commit-recovery
STUB_PATH=outside.txt run
check 'out-of-scope output blocks committing' "$?" 2
check 'out-of-scope output preserved' "$(cat "$fixture/work/outside.txt" 2>/dev/null)" produced
check 'out-of-scope output is not committed' "$(git -C "$fixture/work" ls-tree --name-only HEAD outside.txt)" ''

git -C "$fixture/primary" worktree add -qb timeout-case "$fixture/timeout"
STUB_SLEEP=30 STUB_CHILD_PID_FILE="$fixture/child.pid" run --cwd "$fixture/timeout" --timeout 1
check 'timeout returns executed non-DONE' "$?" 1
child="$(cat "$fixture/child.pid" 2>/dev/null)"
alive=no
if [ -n "$child" ] && kill -0 "$child" 2>/dev/null; then alive=yes; kill "$child" 2>/dev/null || true; fi
check 'timeout terminates the owned grandchild' "$alive" no

git -C "$fixture/primary" worktree add -qb handback-case "$fixture/handback"
STUB_STATUS=BLOCKED run --cwd "$fixture/handback"
check 'handback fixture has pending work' "$?" 1
bash "$SCRIPT" --cwd "$fixture/handback" --task-id task-one --handback > "$fixture/out" 2> "$fixture/err"
check 'handback transfers stopped pending task' "$?" 0
run --cwd "$fixture/handback"
check 'handed-back task cannot resume' "$?" 2

git -C "$fixture/primary" worktree add -qb release-case "$fixture/release"
STUB_NO_WRITE=1 run --cwd "$fixture/release"
check 'clean no-change task succeeds' "$?" 0
bash "$SCRIPT" --cwd "$fixture/release" --task-id task-one --release > "$fixture/out" 2> "$fixture/err"
check 'completed review can release ownership' "$?" 0
run --cwd "$fixture/release" --task-id task-two
check 'released worktree accepts a new task' "$?" 0

git -C "$fixture/primary" worktree add -qb staged-case "$fixture/staged"
printf 'unrelated staged change\n' > "$fixture/staged/base.txt"
git -C "$fixture/staged" add base.txt
run --cwd "$fixture/staged"
check 'initial staged changes are rejected' "$?" 2
git -C "$fixture/staged" reset -q HEAD -- base.txt
run --cwd "$fixture/staged"
check 'initial unstaged changes are rejected' "$?" 2

git -C "$fixture/primary" worktree add -qb paths-case "$fixture/paths"
STUB_PATH='new file.txt' STUB_DELETE=base.txt run --cwd "$fixture/paths"
check 'deletion and path with spaces commit' "$?" 0
check 'deletion is present in commit' "$(git -C "$fixture/paths" ls-tree --name-only HEAD base.txt)" ''
check 'space-containing path has intended bytes' "$(git -C "$fixture/paths" show 'HEAD:new file.txt')" produced
path_gitdir="$(git -C "$fixture/paths" rev-parse --absolute-git-dir)"
path_state="$path_gitdir/dr-superpowers/tasks/$task_key/state.json"
jq --slurpfile staged "$(dirname "$path_state")/staged-snapshot.json" \
  '.phase="committing" | .expected_head=.candidate.parent | .pending=$staged[0]' "$path_state" > "$fixture/crash-state.json"
cp "$fixture/crash-state.json" "$path_state"
launches="$(wc -l < "$LAUNCH_LOG")"
bash "$SCRIPT" --cwd "$fixture/paths" --task-id task-one --recover-commit > "$fixture/out" 2> "$fixture/err"
check 'crash after commit adopts exact candidate' "$?" 0
check 'adoption never launches Codex again' "$(wc -l < "$LAUNCH_LOG")" "$launches"

git -C "$fixture/primary" worktree add -qb recovery-guard "$fixture/recovery-guard"
cat > "$fixture/primary/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
printf 'hook write\n' > unrelated.txt
git add -- unrelated.txt
exit 1
HOOK
chmod +x "$fixture/primary/.git/hooks/pre-commit"
run --cwd "$fixture/recovery-guard"
check 'unexpected hook staging blocks task' "$?" 2
rm -f "$fixture/primary/.git/hooks/pre-commit"
bash "$SCRIPT" --cwd "$fixture/recovery-guard" --task-id task-one --recover-commit > "$fixture/out" 2> "$fixture/err"
check 'recovery refuses unrelated staged content' "$?" 2
check 'recovery preserves unrelated index entry' "$(git -C "$fixture/recovery-guard" show :unrelated.txt)" 'hook write'
printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
