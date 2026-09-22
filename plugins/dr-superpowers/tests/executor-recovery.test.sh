#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/run-codex-task.sh"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
pass=0 fail=0
check() { if [ "$2" = "$3" ]; then printf 'ok - %s\n' "$1"; pass=$((pass+1)); else printf 'FAIL - %s: got [%s], want [%s]\n' "$1" "$2" "$3"; fail=$((fail+1)); fi; }
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

# The runner marks this session's Codex gate file off on a quota error. A fixed
# session id and a temporary directory keep the machine's real file out of it.
export DR_CODEX_SESSION_DIR="$fixture/sessions" CLAUDE_CODE_SESSION_ID=executor-recovery-test

# The runner resolves its plugin root through scripts/codex-plugin, which reads
# the profile settings and the policy file. Both are fixtures here, and
# CLAUDE_PROJECT_DIR is cleared because the locator also reads a project's own
# .claude/settings*.json - without this a run under Claude Code reads this
# repository's settings.
STUB_PLUGIN="$HERE/fixtures/stub-codex-plugin"
export CLAUDE_PROJECT_DIR=
export CLAUDE_CONFIG_DIR="$fixture/config"
mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
jq -nc --arg p "$STUB_PLUGIN" \
  '{version:2, plugins:{"codex@openai-codex":[{scope:"user", installPath:$p, version:"1.0.3"}]}}' \
  > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"
export DR_CODEX_POLICY="$fixture/policy.json"
jq -nc '{plugin:"codex@openai-codex", min_version:"1.0.3", max_major:1,
         trust:{calibration:"pending", smoke:"pending"}}' > "$DR_CODEX_POLICY"

export STUB_MODE=ok STUB_EVENT_LOG="$fixture/events.log"
final_message() { printf '{"status":"%s","summary":"fixture","commit_subject":"feat(test): produce file","questions":[],"discovered_issues":["fixture issue"],"assumptions":[]}' "${1:-DONE}"; }
export STUB_FINAL_MESSAGE="$(final_message DONE)" STUB_WRITE_PATH=produced.txt STUB_WRITE_CONTENT=produced
launches() { grep -c '^runAppServerTurn' "$STUB_EVENT_LOG" 2>/dev/null || echo 0; }

run() { bash "$SCRIPT" --cwd "$fixture/work" --task-id task-one --write-set "$fixture/scope.json" \
  --brief "$fixture/brief.md" --report "$fixture/report.md" --model gpt-6-sol --effort medium "$@" > "$fixture/out" 2> "$fixture/err"; }
printf 'unrelated\n' > "$fixture/work/unrelated.txt"
before="$(git -C "$fixture/work" rev-parse HEAD)"
run
check 'dirty initial task rejected' "$?" 2
check 'dirty initial task never launches model' "$(launches)" 0
check 'dirty initial task preserves HEAD' "$(git -C "$fixture/work" rev-parse HEAD)" "$before"
rm -f "$fixture/work/unrelated.txt"
run
check 'clean linked task succeeds' "$?" 0
check 'success commits produced file' "$(git -C "$fixture/work" show HEAD:produced.txt 2>/dev/null)" produced
check 'report lists discovered issues' \
  "$(grep -A2 '^## Discovered issues (not fixed)$' "$fixture/report.md" | tail -1 | tr -d '\r')" '- fixture issue'
check 'report says None for empty assumptions' \
  "$(grep -A2 '^## Assumptions made$' "$fixture/report.md" | tail -1 | tr -d '\r')" 'None'
gitdir="$(git -C "$fixture/work" rev-parse --absolute-git-dir)"
task_key="$(printf task-one | git -C "$fixture/work" hash-object --stdin)"
state="$gitdir/dr-superpowers/tasks/$task_key/state.json"
check 'success persists complete state' "$(jq -r .phase "$state" 2>/dev/null)" complete
check 'success persists thread' "$(jq -r .thread "$state" 2>/dev/null)" stub-thread
STUB_WRITE_CONTENT=review-fix run --resume stub-thread --review-round 1 --report "$fixture/fix-report.md"
check 'review fix resumes after successful commit' "$?" 0
check 'review fix commits changed bytes' "$(git -C "$fixture/work" show HEAD:produced.txt 2>/dev/null)" review-fix
check 'changed report retains task attempts' "$(jq '.attempts | length' "$state" 2>/dev/null)" 2
check 'review round is recorded explicitly' "$(jq .review_rounds "$state")" 1
run --resume wrong-thread
check 'thread mismatch rejected' "$?" 2
STUB_WRITE_PATH= run --resume stub-thread
check 'no-change success remains resumable' "$?" 0
check 'transport or clarification resume preserves review count' "$(jq .review_rounds "$state")" 1
STUB_FINAL_MESSAGE="$(final_message BLOCKED)" STUB_WRITE_CONTENT=partial run --resume stub-thread
check 'executed incomplete task returns one' "$?" 1
check 'partial run persists pending state' "$(jq -r .phase "$state" 2>/dev/null)" pending
STUB_WRITE_CONTENT=retried run
check 'fresh retry accepts exact pending state' "$?" 0
printf '#!/usr/bin/env bash\nexit 1\n' > "$fixture/primary/.git/hooks/pre-commit"
chmod +x "$fixture/primary/.git/hooks/pre-commit"
STUB_WRITE_CONTENT=commit-recovery run
check 'commit hook failure exits two' "$?" 2
check 'commit failure persists blocked state' "$(jq -r .phase "$state" 2>/dev/null)" blocked
rm -f "$fixture/primary/.git/hooks/pre-commit"
launches="$(launches)"
bash "$SCRIPT" --cwd "$fixture/work" --task-id task-one --recover-commit > "$fixture/out" 2> "$fixture/err"
check 'commit recovery succeeds without model' "$?" 0
check 'commit recovery does not launch a child' "$(launches)" "$launches"
check 'recovered commit contains expected bytes' "$(git -C "$fixture/work" show HEAD:produced.txt 2>/dev/null)" commit-recovery
STUB_WRITE_PATH=outside.txt run
check 'out-of-scope output blocks committing' "$?" 2
check 'out-of-scope output preserved' "$(cat "$fixture/work/outside.txt" 2>/dev/null)" produced
check 'out-of-scope output is not committed' "$(git -C "$fixture/work" ls-tree --name-only HEAD outside.txt)" ''

git -C "$fixture/primary" worktree add -qb timeout-case "$fixture/timeout"
STUB_MODE=hang run --cwd "$fixture/timeout" --timeout 1
check 'timeout returns executed non-DONE' "$?" 1
check "timeout interrupts the turn" "$(grep -c '^interruptAppServerTurn stub-thread stub-turn' "$STUB_EVENT_LOG")" 1

git -C "$fixture/primary" worktree add -qb handback-case "$fixture/handback"
STUB_FINAL_MESSAGE="$(final_message BLOCKED)" run --cwd "$fixture/handback"
check 'handback fixture has pending work' "$?" 1
bash "$SCRIPT" --cwd "$fixture/handback" --task-id task-one --handback > "$fixture/out" 2> "$fixture/err"
check 'handback transfers stopped pending task' "$?" 0
run --cwd "$fixture/handback"
check 'handed-back task cannot resume' "$?" 2

git -C "$fixture/primary" worktree add -qb release-case "$fixture/release"
STUB_WRITE_PATH= run --cwd "$fixture/release"
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
STUB_WRITE_PATH='new file.txt' STUB_DELETE_PATH=base.txt run --cwd "$fixture/paths"
check 'deletion and path with spaces commit' "$?" 0
check 'deletion is present in commit' "$(git -C "$fixture/paths" ls-tree --name-only HEAD base.txt)" ''
check 'space-containing path has intended bytes' "$(git -C "$fixture/paths" show 'HEAD:new file.txt')" produced
path_gitdir="$(git -C "$fixture/paths" rev-parse --absolute-git-dir)"
path_state="$path_gitdir/dr-superpowers/tasks/$task_key/state.json"
jq --slurpfile staged "$(dirname "$path_state")/staged-snapshot.json" \
  '.phase="committing" | .expected_head=.candidate.parent | .pending=$staged[0]' "$path_state" > "$fixture/crash-state.json"
cp "$fixture/crash-state.json" "$path_state"
launches="$(launches)"
bash "$SCRIPT" --cwd "$fixture/paths" --task-id task-one --recover-commit > "$fixture/out" 2> "$fixture/err"
check 'crash after commit adopts exact candidate' "$?" 0
check 'adoption never launches Codex again' "$(launches)" "$launches"

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

# --- consecutive offloads in one worktree -----------------------------------
# tests/executor-recovery.test.sh:112-117 already proves that --release lets a
# released worktree take a new task, so that case is not repeated. What is new
# is the refusal the release prevents, and the instruction that makes the
# release part of the loop rather than a recovery step somebody remembers.
git -C "$fixture/primary" worktree add -qb consecutive "$fixture/consecutive"

# produced.txt, not a fresh name: run() passes the suite's shared --write-set,
# which holds only base.txt, produced.txt and "new file.txt", so any other path
# is refused as out of scope (lines 93-96) before ownership is ever reached.
STUB_WRITE_PATH=produced.txt run --cwd "$fixture/consecutive" --task-id offload-one
check 'first offloaded task succeeds' "$?" 0

STUB_WRITE_PATH=produced.txt run --cwd "$fixture/consecutive" --task-id offload-two; rc=$?
# The exit status alone would go green for any refusal at all; the reason is
# pinned with it so only the owner.json check at task-state.sh:125-127 counts.
check 'a second task without a release is refused for ownership' \
  "$([ "$rc" -ne 0 ] && grep -qF 'reserved by another task' "$fixture/err" && echo refused || echo allowed)" refused

# The deliverable is the instruction, so assert it directly.
LOOP="$HERE/../reference/delegated-task.md"
check 'the loop tells the controller to release the worktree' \
  "$(grep -c 'Release the worktree when the task is complete' "$LOOP")" 1
check 'the release resolves the wrapper through the registry' \
  "$(grep -cF 'executors" path <id> wrapper' "$LOOP")" 1
check 'a HANDBACK reconciles instead of releasing' \
  "$(grep -c 'reconcile rather than release' "$LOOP")" 1

present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then printf 'ok - %s\n' "$1"; pass=$((pass+1))
  else printf 'FAIL - %s: missing [%s] in %s\n' "$1" "$3" "$2"; fail=$((fail+1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2" 2>/dev/null; then printf 'FAIL - %s: unexpected [%s] in %s\n' "$1" "$3" "$2"; fail=$((fail+1))
  else printf 'ok - %s\n' "$1"; pass=$((pass+1)); fi
}
REC="$(cd "$(dirname "$SCRIPT")/.." && pwd)/reference/external-task-recovery.md"
present "the recovery guide resolves the wrapper through the registry" "$REC" 'path <id> wrapper'
absent "the recovery guide no longer hardcodes the Codex wrapper" "$REC" 'run-codex-task.sh'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
