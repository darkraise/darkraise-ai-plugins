#!/usr/bin/env bash
# The replay harness (evals/workflow-ab): the fixture plan's shape, and prepare's
# clone hygiene, per-arm conversion, pins and --check, against a scratch source
# built from the fixture.
set -uo pipefail

case ${OSTYPE:-} in
  msys*|cygwin*) echo 'skip - workflow-ab: Linux only'; exit 0 ;;
esac

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WAB="$HERE/../../evals/workflow-ab"
FIXTURE="$WAB/fixture"
PLAN=docs/dforge/plans/2026-01-01-fixture.md

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# The harness refuses a root under /tmp, so the scratch lives on disk.
TMP="$(mktemp -d "${WAB_TEST_TMP:-/var/tmp}/workflow-ab-test.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" GIT_CONFIG_NOSYSTEM=1 TZ=UTC
mkdir -p "$HOME"
git config --global user.name Tester
git config --global user.email tester@localhost
git config --global init.defaultBranch main
unset DFORGE_BUDGET CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION
printf '#!/bin/sh\necho "9.9.9 (Claude Code)"\n' > "$TMP/claude"
chmod +x "$TMP/claude"
mkdir -p "$TMP/claude-config"
printf '{"autoCompactWindow": 500000}\n' > "$TMP/claude-config/settings.json"
printf '{"claudeAiOauth": "owner"}\n' > "$TMP/claude-config/.credentials.json"
printf '{"handoffTokens": 250000}\n' > "$TMP/owner-dforge.json"
# A stand-in for the mount-namespace sandbox, which CI runners may refuse; the
# real one is tested on its own below.
cat > "$TMP/sandbox-rec" <<EOF
#!/usr/bin/env bash
printf '%q ' "\$@" >> "$TMP/sandbox.argv"
printf '\n' >> "$TMP/sandbox.argv"
if [ "\$1" = --check ]; then [ ! -e "$TMP/sandbox-refuse" ]; exit; fi
while [ \$# -gt 0 ] && [ "\$1" != -- ]; do shift; done
shift
exec "\$@"
EOF
export WAB_ROOT="$TMP/root" WAB_CLAUDE="$TMP/claude" WAB_CLAUDE_CONFIG="$TMP/claude-config" \
  WAB_DFORGE_CONFIG="$TMP/owner-dforge.json" WAB_PLAN="$PLAN" WAB_SANDBOX="$TMP/sandbox-rec"

C14='- This is a replay in a clone with no remote: no push, tag or workflow dispatch; a gate that needs one is recorded as not run.'

# make_source DIR [SED] — a source repository built from the fixture: the base
# holds everything but the plan, which a later commit adds (edited by SED),
# one more commit follows, and an origin remote holds both.
make_source() {
  local src=$1
  mkdir -p "$src"
  cp -R "$FIXTURE/." "$src/"
  mkdir -p "$src/.claude"
  printf '{"enabledPlugins": {"other@market": true, "off@market": false}}\n' > "$src/.claude/settings.json"
  mv "$src/$PLAN" "$TMP/plan.md"
  git -C "$src" init -q
  git -C "$src" add -A
  git -C "$src" commit -q -m base
  mv "$TMP/plan.md" "$src/$PLAN"
  [ -z "${2:-}" ] || sed -i -E "$2" "$src/$PLAN"
  git -C "$src" add -A
  git -C "$src" commit -q -m "docs: add the plan"
  printf 'later\n' > "$src/later.txt"
  git -C "$src" add -A
  git -C "$src" commit -q -m "chore: a later commit"
  git init -q --bare "$src.origin.git"
  git -C "$src" remote add origin "$src.origin.git"
  git -C "$src" push -q origin main
}
prep() { # prep ARM RUN [ARGS...] — out and status
  out=$(bash "$WAB/prepare" "$@" 2>&1); status=$?
}

make_source "$TMP/src"
export WAB_SOURCE="$TMP/src"
WAB_BASE=$(git -C "$TMP/src" rev-list --max-parents=0 HEAD)
export WAB_BASE

# --- fixture_plan_shape ---
fx="$FIXTURE/$PLAN"
check "fixture_plan_shape: the plan sits under docs/dforge/plans" "$([ -f "$fx" ] && echo yes)" "yes"
check "fixture_plan_shape: subagent Execution line" "$(grep -c '^\*\*Execution:\*\* subagent' "$fx")" "1"
check "fixture_plan_shape: one two-task wave" "$(grep -c '^\*\*Parallelism:\*\* waves — 1-2$' "$fx")" "1"
check "fixture_plan_shape: two tasks" "$(grep -c '^### Task ' "$fx")" "2"
check "fixture_plan_shape: sonnet-high Implementer on each task" "$(grep -c '^\*\*Implementer:\*\* dforge:impl-sonnet-high$' "$fx")" "2"
check "fixture_plan_shape: one unqualified Items line" "$(grep -c '^\*\*Items:\*\*' "$fx") $(grep -c '^\*\*Items:\*\* 1$' "$fx")" "1 1"

# --- prepare_clone_hygiene ---
prep dforge 1
check "prepare_clone_hygiene: prepare exits 0" "$status" "0"
clone="$WAB_ROOT/dforge-1/clone"
g() { git -C "$clone" "$@"; }
check "prepare_clone_hygiene: no remote" "$(g remote)" ""
new=$(g rev-list --all | grep -vxF -f <(git -C "$TMP/src" rev-list "$WAB_BASE"))
check "prepare_clone_hygiene: one commit beyond the base's ancestry" "$(grep -c . <<<"$new")" "1"
check "prepare_clone_hygiene: that commit is the replay plan by the clone identity" \
  "$(g log -1 --format='%s|%an <%ae>' "$new")" "chore: replay plan|Replay <replay@localhost>"
check "prepare_clone_hygiene: the commit's parent is the base" "$(g rev-parse "$new^")" "$WAB_BASE"
"$clone/.git/hooks/pre-push" >/dev/null 2>&1
check "prepare_clone_hygiene: pre-push refuses" "$?" "1"
g config --get core.hooksPath >/dev/null
check "prepare_clone_hygiene: core.hooksPath is unset" "$?" "1"
check "prepare_clone_hygiene: no alternates" "$([ -e "$clone/.git/objects/info/alternates" ] && echo present || echo absent)" "absent"
git -C "$TMP/src" cat-file -e "$WAB_BASE:$PLAN" 2>/dev/null
check "prepare_clone_hygiene: the plan is absent at the base" "$?" "128"
check "prepare_clone_hygiene: the clone has the plan" "$([ -f "$clone/$PLAN" ] && echo yes)" "yes"
WAB_ROOT=/tmp/workflow-ab prep dforge 9
check "prepare_clone_hygiene: a root under /tmp is refused" "$status $out" "2 workflow-ab: WAB_ROOT must not be under /tmp"

# --- prepare_converts_per_arm ---
dplan="$clone/$PLAN"
check "prepare_converts_per_arm: dforge Execution line" "$(grep '^\*\*Execution:\*\*' "$dplan")" \
  '**Execution:** inline — `claude --model sonnet --effort high` — replay of a subagent plan'
check "prepare_converts_per_arm: dforge Items qualified" "$(grep '^\*\*Items:\*\*' "$dplan")" "**Items:** 2026-01-01-fixture#1"
check "prepare_converts_per_arm: dforge Implementer lines kept" "$(grep -c '^\*\*Implementer:\*\* dforge:impl-sonnet-high$' "$dplan")" "2"
has "prepare_converts_per_arm: dforge plan-lint passed" "$(cat "$WAB_ROOT/dforge-1/out/plan-lint.txt")" "plan-lint: 0 errors"
prep dagents 1
check "prepare_converts_per_arm: dagents prepare exits 0" "$status" "0"
aclone="$WAB_ROOT/dagents-1/clone"
aplan="$aclone/docs/dagents/plans/2026-01-01-fixture.md"
check "prepare_converts_per_arm: dagents Implementer lines renamed" "$(grep -c '^\*\*Implementer:\*\* dagents:impl-sonnet-high$' "$aplan") $(grep -c 'dforge:impl-' "$aplan")" "2 0"
check "prepare_converts_per_arm: dagents Execution line unchanged" "$(grep '^\*\*Execution:\*\*' "$aplan")" "$(grep '^\*\*Execution:\*\*' "$fx")"
check "prepare_converts_per_arm: dagents Items unchanged" "$(grep '^\*\*Items:\*\*' "$aplan")" "**Items:** 1"
has "prepare_converts_per_arm: dagents plan-lint passed" "$(cat "$WAB_ROOT/dagents-1/out/plan-lint.txt")" "plan-lint: 0 errors"
for f in "$dplan" "$aplan"; do
  check "prepare_converts_per_arm: the replay line once, ending Global Constraints (${f#"$WAB_ROOT/"})" \
    "$(grep -cxF -- "$C14" "$f") $(awk -v l="$C14" '$0 == "## Global Constraints" { on = 1; next } on && /^## / { exit } on && NF { last = $0 } END { print (last == l) }' "$f")" "1 1"
done
make_source "$TMP/src-opus" '/^### Task 2/,$ { s/impl-sonnet-high/impl-opus-medium/; s/^\*\*Evaluation:\*\* .*/**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6/ }'
WAB_SOURCE="$TMP/src-opus" WAB_BASE=$(git -C "$TMP/src-opus" rev-list --max-parents=0 HEAD) prep dforge 4
check "prepare_converts_per_arm: an opus risk-3 variant exits 0" "$status" "0"
check "prepare_converts_per_arm: an opus risk-3 variant runs opus at high" \
  "$(grep '^\*\*Execution:\*\*' "$WAB_ROOT/dforge-4/clone/$PLAN")" \
  '**Execution:** inline — `claude --model opus --effort high` — replay of a subagent plan'

# --- prepare_pins ---
dcfg="$WAB_ROOT/dforge-1/home/.dforge/config.json"
check "prepare_pins: dforge pins" "$(jq -c '[.handoffTokens, .finishAction, .decisionApi, .codexReview, .agyReview]' "$dcfg")" '[250000,"keep","off",false,false]'
check "prepare_pins: every dforge apiBudget cap is 0" "$(jq -c '[to_entries[] | select(.key | startswith("apiBudget")) | .value]' "$dcfg")" '[0,0,0]'
acfg="$WAB_ROOT/dagents-1/home/.dagents/config.json"
check "prepare_pins: dagents pins" "$(jq -c '[.handoffTokens, .finishAction, .codexReview, .codexLane, .agyLane]' "$acfg")" '[250000,"keep",false,false,false]'
WAB_DFORGE_CONFIG="$TMP/absent.json" prep dforge 6
check "prepare_pins: no owner config, no DFORGE_BUDGET: 300000" "$(jq .handoffTokens "$WAB_ROOT/dforge-6/home/.dforge/config.json")" "300000"
WAB_DFORGE_CONFIG="$TMP/absent.json" DFORGE_BUDGET=275000 prep dforge 7
check "prepare_pins: no owner config: DFORGE_BUDGET" "$(jq .handoffTokens "$WAB_ROOT/dforge-7/home/.dforge/config.json")" "275000"
check "prepare_pins: enabled project plugins switched off" "$(jq -c .enabledPlugins "$clone/.claude/settings.local.json")" '{"other@market":false}'
check "prepare_pins: the local settings are not a change in the clone" "$(g status --porcelain)" ""
arm=$WAB_ROOT/dforge-1/arm.json
check "prepare_pins: arm.json records every field" \
  "$(jq -c '[has("pluginCommit"), has("pins"), has("model"), has("effort"), has("parallelism"), has("claudeVersion"), has("autoCompactWindow"), has("darkmem")] | all' "$arm")" "true"
check "prepare_pins: arm.json values" \
  "$(jq -c '[(.pluginCommit | test("^[0-9a-f]{40}$")), .pins.handoffTokens, .model, .effort, .parallelism, .claudeVersion, .autoCompactWindow, .darkmem]' "$arm")" \
  '[true,250000,"sonnet","high","sequential","9.9.9 (Claude Code)",500000,false]'
check "prepare_pins: dagents arm.json keeps the plan's waves" "$(jq -r '[.model, .effort, .parallelism, .plan] | join("|")' "$WAB_ROOT/dagents-1/arm.json")" \
  "sonnet|high|waves — 1-2|docs/dagents/plans/2026-01-01-fixture.md"
mkdir -p "$TMP/mcp-config"
cp "$TMP/claude-config/settings.json" "$TMP/mcp-config/"
printf '{"mcpServers": {"darkmem": {"type": "http", "url": "http://localhost:1"}}}\n' > "$TMP/mcp-config/.claude.json"
WAB_CLAUDE_CONFIG="$TMP/mcp-config" prep dforge 13
check "prepare_pins: a darkmem server in the config directory is recorded" "$status $(jq .darkmem "$WAB_ROOT/dforge-13/arm.json")" "0 true"
printf '{not json' > "$TMP/mcp-config/settings.json"
WAB_CLAUDE_CONFIG="$TMP/mcp-config" prep dforge 14
check "prepare_pins: unparsable owner settings fail prepare" "$status $(grep -c "cannot read $TMP/mcp-config/settings.json" <<<"$out")" "1 1"
check "prepare_pins: and write no arm.json" "$([ -e "$WAB_ROOT/dforge-14/arm.json" ] && echo written || echo none)" "none"

# --- prepare_check_blocks ---
make_source "$TMP/src-false" 's/^\*\*Integration check:\*\* .*/**Integration check:** `false`/'
WAB_SOURCE="$TMP/src-false" WAB_BASE=$(git -C "$TMP/src-false" rev-list --max-parents=0 HEAD) prep dforge 2 --check
check "prepare_check_blocks: a failing Integration check exits 1" "$status" "1"
check "prepare_check_blocks: and writes check-failed" "$(cat "$WAB_ROOT/dforge-2/state" 2>/dev/null)" "check-failed"
make_source "$TMP/src-true" 's/^\*\*Integration check:\*\* .*/**Integration check:** `env > check-env.txt`/'
WAB_SOURCE="$TMP/src-true" WAB_BASE=$(git -C "$TMP/src-true" rev-list --max-parents=0 HEAD) GH_TOKEN=secret SSH_AUTH_SOCK=/sock \
  prep dforge 3 --check
check "prepare_check_blocks: a passing Integration check exits 0" "$status" "0"
check "prepare_check_blocks: and writes no state" "$([ -e "$WAB_ROOT/dforge-3/state" ] && echo written || echo none)" "none"
cenv="$WAB_ROOT/dforge-3/clone/check-env.txt"
check "prepare_check_blocks: the check runs under the launch environment" \
  "$(grep -cxE "HOME=$WAB_ROOT/dforge-3/home|GOCACHE=$WAB_ROOT/dforge-3/gocache|GIT_ALLOW_PROTOCOL=file|GIT_SSH_COMMAND=false|GH_CONFIG_DIR=$WAB_ROOT/dforge-3/gh|IS_SANDBOX=1" "$cenv")" "6"
check "prepare_check_blocks: and none of the caller's tokens or sockets" "$(grep -cE '^(GH_TOKEN|SSH_AUTH_SOCK)=' "$cenv")" "0"
has "prepare_check_blocks: the check runs in the run's sandbox" "$(cat "$TMP/sandbox.argv")" \
  "-w $WAB_ROOT/dforge-3 -h $TMP/claude-config "

# --- sandbox: the real mount namespace, where this host allows one ---
sb="$TMP/sbx"
mkdir -p "$sb/rw" "$sb/ro" "$sb/secret"
printf 'key\n' > "$sb/secret/id"
printf 'token\n' > "$sb/netrc"
if bash "$WAB/sandbox" --check -w "$sb/rw" >/dev/null 2>&1; then
  probe="wab-sandbox-probe-$$"
  got=$(cd "$sb" && bash "$WAB/sandbox" -w "$sb/rw" -h "$sb/secret" -h "$sb/netrc" -h "$sb/absent" -- bash -c "
    touch rw/a && echo rw
    touch ro/b 2>/dev/null && echo ro-written || echo ro
    echo \$(ls secret | wc -l) \$(wc -c < netrc)
    echo x > /tmp/$probe && echo tmp" 2>&1)
  check "sandbox: only the -w directory is writable, -h paths are empty, /tmp is writable" \
    "$(tr '\n' ' ' <<<"$got")" "rw ro 0 0 tmp "
  check "sandbox: its /tmp is private" "$([ -e "/tmp/$probe" ] && echo shared || echo private)" "private"
  check "sandbox: the hidden files are untouched outside" "$(cat "$sb/secret/id" "$sb/netrc" | tr '\n' ' ')" "key token "
  got=$(bash "$WAB/sandbox" -w "$sb/rw" -h "$sb/secret" -- bash -c "
    mount -o remount,rw / 2>/dev/null && echo remounted || echo locked
    umount '$sb/secret' 2>/dev/null && echo unhidden || echo hidden
    [ -e /proc/$$ ] && echo host-pid-visible || echo host-pid-hidden" 2>&1)
  check "sandbox: the command cannot undo its mounts or see a host process" \
    "$(tr '\n' ' ' <<<"$got")" "locked hidden host-pid-hidden "
  bash "$WAB/sandbox" -w "$sb/secret/x" -h "$sb/secret" -- true 2>/dev/null
  check "sandbox: a writable directory under a hidden one is refused" "$?" "1"
  bash "$WAB/sandbox" -w /tmp -- true 2>/dev/null
  check "sandbox: /tmp cannot be kept writable" "$?" "1"
else
  printf 'skip - sandbox: this host refuses a mount namespace\n'
fi

# --- prepare_source_untouched ---
printf 'dirty\n' >> "$TMP/src/greet.sh"
git -C "$TMP/src" stash -q
printf 'untracked\n' > "$TMP/src/scratch.txt"
snapshot() {
  local s=$TMP/src
  git -C "$s" status --porcelain; git -C "$s" remote -v; git -C "$s" for-each-ref
  git -C "$s" worktree list --porcelain; git -C "$s" stash list; git -C "$s" rev-parse HEAD
}
before=$(snapshot)
prep dforge 5
check "prepare_source_untouched: prepare exits 0" "$status" "0"
check "prepare_source_untouched: status, remotes, refs, worktrees, stashes and HEAD unchanged" "$(snapshot)" "$before"

# --- launch: stubs for tmux, claude and the arm's auto-run ---
cat > "$TMP/tmux" <<EOF
#!/usr/bin/env bash
T=$TMP
printf '%s\n' "\$*" >> "\$T/tmux.log"
cmd=\$1
shift
name=""
for ((i = 1; i <= \$#; i++)); do
  case \${!i} in -t|-s) j=\$((i + 1)); name=\${!j#=}; name=\${name%:}; break ;; esac
done
case \$cmd in
  new-session) setsid bash -c "\${!#}" >/dev/null 2>&1 & echo \$! > "\$T/tmux-\$name.pid" ;;
  has-session) p=\$(cat "\$T/tmux-\$name.pid" 2>/dev/null) && kill -0 "\$p" 2>/dev/null; exit \$? ;;
  list-panes) cat "\$T/tmux-\$name.pid" ;;
  kill-session) p=\$(cat "\$T/tmux-\$name.pid" 2>/dev/null) && kill -TERM -- "-\$p" 2>/dev/null; rm -f "\$T/tmux-\$name.pid" ;;
  capture-pane) cat "\$T/pane.txt" 2>/dev/null ;;
esac
exit 0
EOF
cat > "$TMP/claude-rec" <<EOF
#!/usr/bin/env bash
T=$TMP
if [ "\${1:-}" = --version ]; then echo "9.9.9 (Claude Code)"; exit 0; fi
printf '%s\n' "\$@" > "\$T/claude.argv"
env > "\$T/claude.env"
echo \$\$ > "\$T/claude.pid"
if [ -e "\$T/orphan" ]; then setsid sleep 300 & echo \$! > "\$T/orphan.pid"; fi
if [ -e "\$T/beat" ] || [ -e "\$T/finish-then-exit" ]; then
  sid=\$(awk 'p { print; exit } \$0 == "--session-id" { p = 1 }' "\$T/claude.argv")
  mkdir -p "\$HOME/.claude/dforge/sessions/cockpit" .dforge/sdd
  : > "\$HOME/.claude/dforge/sessions/cockpit/\$sid"
fi
if [ -e "\$T/finish-then-exit" ]; then
  sleep 1
  printf '{"active":false,"phase":"finish"}\\n' > .dforge/sdd/auto-run.json
  exit 0
fi
[ -e "\$T/hang" ] && exec sleep 300
exit 0
EOF
STUB_PLUGINS="$TMP/stub-plugins"
mkdir -p "$STUB_PLUGINS/plugins/dforge/scripts"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n' "$TMP/auto-run.log" > "$STUB_PLUGINS/plugins/dforge/scripts/auto-run"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB_PLUGINS/plugins/dforge/scripts/next-step"
chmod +x "$TMP/tmux" "$TMP/claude-rec"
export WAB_TMUX="$TMP/tmux"
launch() { # launch ARM RUN [ARGS...] — out and status, with every stub and WAB_MAX_SECONDS ${MAXS:-3}
  out=$(WAB_PLUGINS="$STUB_PLUGINS" WAB_CLAUDE="$TMP/claude-rec" WAB_MAX_SECONDS="${MAXS:-3}" bash "$WAB/launch" "$@" 2>&1); status=$?
}
envval() { sed -n "s/^$1=//p" "$TMP/claude.env"; }
empty_dir() { [ -d "$1" ] && [ -z "$(ls -A "$1")" ] && echo empty || echo not-empty; }

# --- launch_environment ---
run1="$WAB_ROOT/dforge-1"
GH_TOKEN=x GITHUB_TOKEN=x SSH_AUTH_SOCK=x ANTHROPIC_API_KEY=x OPENAI_API_KEY=x WAB_LEAK=x launch dforge 1
check "launch_environment: launch exits 0" "$status" "0"
check "launch_environment: the session environment" \
  "$(envval IS_SANDBOX)|$(envval HOME)|$(envval CLAUDE_CONFIG_DIR)|$(envval GIT_ALLOW_PROTOCOL)|$(envval GIT_SSH_COMMAND)|$(envval GIT_TERMINAL_PROMPT)|$(envval GH_CONFIG_DIR)" \
  "1|$run1/home|$run1/claude-config|file|false|0|$run1/gh"
check "launch_environment: GH_CONFIG_DIR and WORKFLOW_GUARD_CLAUDE_DIR are empty directories" \
  "$(empty_dir "$(envval GH_CONFIG_DIR)") $(empty_dir "$(envval WORKFLOW_GUARD_CLAUDE_DIR)")" "empty empty"
check "launch_environment: no tokens, sockets, API keys or other inherited variables" \
  "$(grep -cE '^(GH_TOKEN|GITHUB_TOKEN|SSH_AUTH_SOCK|ANTHROPIC_API_KEY|OPENAI_API_KEY|WAB_LEAK)=' "$TMP/claude.env")" "0"
argv=$(cat "$TMP/claude.argv")
argafter() { awk -v a="$1" 'p { print; exit } $0 == a { p = 1 }' <<<"$argv"; }
check "launch_environment: --setting-sources project,local" "$(argafter --setting-sources)" "project,local"
check "launch_environment: --settings holds only the bypass-prompt key" "$(jq -c . "$(argafter --settings)")" '{"skipDangerousModePermissionPrompt":true}'
check "launch_environment: --plugin-dir is the arm's plugin" "$(argafter --plugin-dir)" "$STUB_PLUGINS/plugins/dforge"
check "launch_environment: --dangerously-skip-permissions" "$(grep -cx -- --dangerously-skip-permissions <<<"$argv")" "1"
sid=$(argafter --session-id)
check "launch_environment: --session-id is a uuid recorded in sessions" \
  "$([[ $sid =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && echo uuid) $(head -n 1 "$run1/sessions")" "uuid $sid"
check "launch_environment: tmux only touches wab- sessions" \
  "$(awk '{ for (i = 1; i < NF; i++) if ($i == "-t" || $i == "-s") { n = $(i + 1); sub(/^=/, "", n); if (n !~ /^wab-/) print n } }' "$TMP/tmux.log")" ""
check "launch_environment: a nested session that exits is stopped, not left to time out" "$(cat "$run1/state")" "stopped"
sbx=$(grep -v '^--check ' "$TMP/sandbox.argv" | tail -n 1)
has "launch_sandbox: the run directory is writable" "$sbx" "-w $run1 "
has "launch_sandbox: the owner's config directory is hidden" "$sbx" "-h $TMP/claude-config "
check "launch_sandbox: only the run directory is writable" "$(grep -o -- '-w [^ ]*' <<<"$sbx")" "-w $run1"
check "launch_sandbox: the run's config directory holds copies of the login and settings" \
  "$(cat "$run1/claude-config/.credentials.json" "$run1/claude-config/settings.json" | tr -d '\n') $(stat -c %a "$run1/claude-config/.credentials.json")" \
  '{"claudeAiOauth": "owner"}{"autoCompactWindow": 500000} 600'
has "launch_sandbox: the owner's ssh keys are hidden" "$sbx" "-h $HOME/.ssh "
has "launch_sandbox: claude runs inside it" "$sbx" "-- $TMP/claude-rec --dangerously-skip-permissions"
touch "$TMP/sandbox-refuse"
rm -f "$TMP/claude.argv"
prep dforge nosandbox
launch dforge nosandbox
check "launch_sandbox: no sandbox refuses the launch before claude runs" \
  "$status $(grep -c 'cannot sandbox the nested session' <<<"$out") $([ -e "$TMP/claude.argv" ] && echo ran || echo not-run) $(cat "$WAB_ROOT/dforge-nosandbox/state" 2>/dev/null)" "1 1 not-run "
rm -f "$TMP/sandbox-refuse"

# --- launch_push_blocked ---
pushed=$( (. "$WAB/lib.sh"; wab_env "$run1"; cd "$run1/clone" && env -i "${WAB_ENV[@]}" git push ssh://example.invalid/x HEAD) >/dev/null 2>&1; echo $?)
check "launch_push_blocked: an ssh push fails in the launch environment" "$([ "$pushed" -ne 0 ] && echo refused)" "refused"
check "launch_push_blocked: the clone has no remote" "$(git -C "$run1/clone" remote)" ""

# --- launch_one_plugin ---
rm -f "$WAB_ROOT/dforge-7/clone/.claude/settings.local.json" "$TMP/claude.argv"
launch dforge 7
check "launch_one_plugin: another enabled plugin refuses the launch" "$status $out" "1 workflow-ab: plugins other than dforge are enabled: other@market"
check "launch_one_plugin: before claude runs" "$([ -e "$TMP/claude.argv" ] && echo ran || echo not-run)" "not-run"

printf '{not json' > "$WAB_ROOT/dforge-7/clone/.claude/settings.json"
launch dforge 7
check "launch_one_plugin: unreadable project settings refuse the launch" "$status $(grep -c 'cannot read the clone' <<<"$out")" "1 1"
launch dforge 1.2
check "launch: a RUN outside [A-Za-z0-9_-] is a usage error" "$status" "2"

# --- launch_timeout ---
: > "$TMP/auto-run.log"
: > "$TMP/tmux.log"
touch "$TMP/hang"
MAXS=2 launch dforge 6
check "launch_timeout: exits 0" "$status" "0"
check "launch_timeout: timed-out" "$(cat "$WAB_ROOT/dforge-6/state")" "timed-out"
check "launch_timeout: stops the bound run" "$(cat "$TMP/auto-run.log")" "--session $(head -n 1 "$WAB_ROOT/dforge-6/sessions") stop --reason workflow-ab: timed-out"
check "launch_timeout: kills its own tmux session" "$(grep -c '^kill-session -t =wab-dforge-6$' "$TMP/tmux.log")" "1"
sleep 1
check "launch_timeout: the nested session is gone" "$(kill -0 "$(cat "$TMP/claude.pid")" 2>/dev/null && echo alive || echo gone)" "gone"

# --- launch_tree_before_session: a process that left the session's group still dies ---
touch "$TMP/orphan"
prep dforge tree
MAXS=2 launch dforge tree
sleep 1
check "launch_tree_before_session: a setsid child of the nested session is killed" \
  "$(kill -0 "$(cat "$TMP/orphan.pid")" 2>/dev/null && echo alive || echo gone)" "gone"
kill -KILL "$(cat "$TMP/orphan.pid")" 2>/dev/null
rm -f "$TMP/orphan"

# --- launch_finish_then_exit: a run that finishes as its session ends ---
touch "$TMP/finish-then-exit"
prep dforge finish
MAXS=20 launch dforge finish
check "launch_finish_then_exit: recorded finished, not stopped" "$(cat "$WAB_ROOT/dforge-finish/state")" "finished"
rm -f "$TMP/finish-then-exit"

# --- a launch stopped by a signal ---
: > "$TMP/auto-run.log"
prep dforge 11
mkdir -p "$TMP/sleepbin"
printf '#!/bin/sh\necho "$$ $*" >> %q\nexec %q "$@"\n' "$TMP/sleep.pids" "$(command -v sleep)" > "$TMP/sleepbin/sleep"
chmod +x "$TMP/sleepbin/sleep"
touch "$TMP/beat"
(PATH="$TMP/sleepbin:$PATH" MAXS=120 launch dforge 11) &
lpid=$!
for _ in $(seq 100); do [ -f "$TMP/tmux-wab-dforge-11.pid" ] && grep -q ' 30$' "$TMP/sleep.pids" 2>/dev/null && break; sleep 0.2; done
kill -TERM $(pgrep -f "evals/workflow-ab/launch dforge 11$")
t0=$(date +%s)
wait "$lpid" 2>/dev/null
# A sleep left running holds the launch's output open until it ends.
check "launch_interrupted: the watch loop's 30 s sleep ends with the launch" \
  "$(grep -c ' 30$' "$TMP/sleep.pids") $(($(date +%s) - t0 < 15))" "1 1"
rm -f "$TMP/beat"
check "launch_interrupted: a signalled launch writes stopped and stops its run" \
  "$(cat "$WAB_ROOT/dforge-11/state") $(grep -c ' stop --reason workflow-ab: stopped$' "$TMP/auto-run.log") $([ -f "$TMP/tmux-wab-dforge-11.pid" ] && echo left || echo killed)" "stopped 1 killed"

# --- settings_repair_after_kill ---
cfg="$TMP/repair-config"
mkdir -p "$cfg"
printf '{\n  "model": "opus",\n  "theme": "dark"\n}\n' > "$cfg/settings.json"
cp "$cfg/settings.json" "$TMP/settings.orig"
(WAB_CLAUDE_CONFIG="$cfg" MAXS=60 launch dforge 4) &
lpid=$!
for _ in $(seq 50); do [ -f "$WAB_ROOT/dforge-4/settings-key" ] && [ -f "$TMP/tmux-wab-dforge-4.pid" ] && break; sleep 0.2; done
check "settings_repair_after_kill: launch records keyBefore=absent" "$(cat "$WAB_ROOT/dforge-4/settings-key")" "keyBefore=absent"
jq '. + {"skipDangerousModePermissionPrompt": true}' < "$cfg/settings.json" > "$cfg/settings.json.new" && mv "$cfg/settings.json.new" "$cfg/settings.json"
kill_tree() { local c; for c in $(pgrep -P "$1"); do kill_tree "$c"; done; kill -KILL "$1" 2>/dev/null; }
kill_tree "$lpid"
wait "$lpid" 2>/dev/null
p=$(cat "$TMP/tmux-wab-dforge-4.pid" 2>/dev/null) && kill -KILL -- "-$p" 2>/dev/null
rm -f "$TMP/tmux-wab-dforge-4.pid"
check "settings_repair_after_kill: the killed launch left the key" "$(jq .skipDangerousModePermissionPrompt "$cfg/settings.json")" "true"
WAB_CLAUDE_CONFIG="$cfg" prep dforge 10
check "settings_repair_after_kill: the next prepare runs" "$status" "0"
check "settings_repair_after_kill: and removes the key, every other byte equal" "$(cmp -s "$cfg/settings.json" "$TMP/settings.orig" && echo equal || echo differs)" "equal"
printf '{\n  "skipDangerousModePermissionPrompt": true,\n  "theme": "dark"\n}\n' > "$cfg/settings.json"
cp "$cfg/settings.json" "$TMP/settings.orig"
WAB_CLAUDE_CONFIG="$cfg" MAXS=2 launch dforge 5
mkdir -p "$TMP/dotfiles" "$TMP/link-config"
printf '{\n  "theme": "dark"\n}\n' > "$TMP/dotfiles/settings.json"
cp "$TMP/dotfiles/settings.json" "$TMP/dotfiles.orig"
ln -s "$TMP/dotfiles/settings.json" "$TMP/link-config/settings.json"
prep dforge 12
(WAB_CLAUDE_CONFIG="$TMP/link-config" MAXS=60 launch dforge 12) &
lpid=$!
for _ in $(seq 50); do [ -f "$WAB_ROOT/dforge-12/settings-repair" ] && [ -f "$TMP/tmux-wab-dforge-12.pid" ] && break; sleep 0.2; done
jq '. + {"skipDangerousModePermissionPrompt": true}' < "$TMP/dotfiles/settings.json" > "$TMP/dotfiles/s.new" && mv "$TMP/dotfiles/s.new" "$TMP/dotfiles/settings.json"
prep dforge concurrent
check "settings_repair_live_launch: another command leaves a running launch's key and marker" \
  "$(jq .skipDangerousModePermissionPrompt "$TMP/dotfiles/settings.json") $([ -f "$WAB_ROOT/dforge-12/settings-repair" ] && echo kept)" "true kept"
kill -TERM $(pgrep -f "evals/workflow-ab/launch dforge 12$")
wait "$lpid" 2>/dev/null
check "settings_repair_after_kill: a symlinked settings.json keeps its link, the key removed at its target" \
  "$([ -L "$TMP/link-config/settings.json" ] && echo link) $(cmp -s "$TMP/dotfiles/settings.json" "$TMP/dotfiles.orig" && echo equal || echo differs)" "link equal"
check "settings_repair_after_kill: a key present before is kept" "$(cat "$WAB_ROOT/dforge-5/settings-key") $(cmp -s "$cfg/settings.json" "$TMP/settings.orig" && echo equal || echo differs)" "keyBefore=present equal"
rm -f "$TMP/hang"

# --- collect_runs_report ---
UFX="$HERE/fixtures/usage/basic"
CR="$WAB_ROOT/dforge-20"
mkdir -p "$CR/clone/docs/plans" "$CR/clone/.dforge/sdd/p"
git init -q "$CR/clone"
printf '{"arm": "dforge", "plan": "docs/plans/p.md"}\n' > "$CR/arm.json"
printf '# P\n\n### Task 1: one\n\n### Task 2: two\n\n### Task 3: three\n' > "$CR/clone/docs/plans/p.md"
printf '# SDD ledger — plan: docs/plans/p.md\nTask 1: complete (commits a..b, unreviewed)\n' > "$CR/clone/.dforge/sdd/p/progress.md"
CPROJ="$CR/claude-config/projects/$(printf '%s' "$CR/clone" | tr -c 'A-Za-z0-9' '-')"
mkdir -p "$CPROJ"
cp -R "$UFX/proj/." "$CPROJ/"
printf '%s\n' '{"type": "assistant", "isSidechain": false, "timestamp": "2026-01-01T00:03:00Z", "message": {"id": "m9", "model": "claude-opus-5-5", "content": [{"type": "tool_use", "id": "tu9", "name": "Agent", "input": {"subagent_type": "dforge:judge-opus", "prompt": "review"}}], "usage": {"input_tokens": 1, "cache_read_input_tokens": 10, "cache_creation_input_tokens": 0, "output_tokens": 5}}}' > "$CPROJ/s2.jsonl"
printf '{}\n' > "$CPROJ/s9.jsonl"
{
  cat "$UFX/markers.tsv"
  printf '2026-01-01T00:02:50Z\topen\tdforge\t5.1.1\t/plugin\tdocs/plans/p.md\t3\ts2\t\t0\t\ttask-brief:3\t\t\n'
  printf '2026-01-01T00:03:10Z\tclose\tdforge\t5.1.1\t/plugin\tdocs/plans/p.md\t3\ts2\t\t%s\t\ttask-close:3\tc..d\t\n' "$(wc -c < "$CPROJ/s2.jsonl" | tr -d ' ')"
} > "$CR/clone/.dforge/sdd/usage-markers.tsv"
printf 's1\ns2\n' > "$CR/sessions"
bash "$WAB/collect" dforge 20 2>"$TMP/collect.err"; status=$?
check "collect_runs_report: exit 0" "$status" "0"
check "collect_runs_report: the listed sessions' transcripts and subagents are copied, no other" \
  "$(cd "$CR/out/transcripts" && find . -type f | sort | tr '\n' ' ')" \
  "./s1.jsonl ./s1/subagents/agent-a1.jsonl ./s1/subagents/agent-a1.meta.json ./s2.jsonl "
check "collect_runs_report: report.json slices the run's three marked tasks, the second session's from its copy" \
  "$(jq -c '.plans[0] | [.tasks[] | [.tasks, .label, .turns]]' "$CR/out/report.json")" '[[[1],"marked",2],[[2],"marked",1],[[3],"marked",1]]'
check "collect_runs_report: report.json is the dforge core's json report" \
  "$(jq -c '.plans | length' "$CR/out/report.json")" "1"
check "collect_runs_report: dispatches.json counts per family" "$(jq -c . "$CR/out/dispatches.json")" '{"dforge:judge-opus":1}'
bash "$WAB/collect" dforge 21 >/dev/null 2>&1; status=$?
check "collect_runs_report: an unprepared run exits 1" "$status" "1"
CS="$WAB_ROOT/dforge-22"
cp -R "$CR" "$CS"
rm -rf "$CS/out"
mkdir -p "$CS/claude-config/projects"
cp -R "$CPROJ" "$CS/claude-config/projects/$(printf '%s' "$CS/clone" | tr -c 'A-Za-z0-9' '-')"
printf '# P\n\n**Spec:** `docs/dforge/specs/2026-01-01-s-design.md`\n\n### Task 1: one\n\n### Task 2: two\n\n### Task 3: three\n' > "$CS/clone/docs/plans/p.md"
mkdir -p "$CS/clone/docs/dforge/registers" "$CS/clone/docs/dforge/reviews"
printf '# A

**Covers:** 2026-01-01-other-design.md

| 1 | x | deferred |
' > "$CS/clone/docs/dforge/registers/a.md"
printf '# S

**Covers:** 2026-01-01-s-design.md

| 1 | x | deferred |
| 2 | y | deferred |
| 3 | z | done |
' > "$CS/clone/docs/dforge/registers/s reg.md"
printf '# Review

final review lens security — 0 Critical, 1 Important, 2 Minor
final review lens ui-ux — 1 Critical, 0 Important, 1 Minor
' > "$CS/clone/docs/dforge/reviews/p.md"
bash "$WAB/collect" dforge 22 2>"$TMP/collect.err"; status=$?
check "collect_runs_report: a plan naming its spec exits 0" "$status" "0"
check "collect_runs_report: the register whose Covers names the spec, the review record's lens lines" \
  "$(jq -c '.plans[0].quality | [.deferredRows, .findings]' "$CS/out/report.json")" '[2,{"Critical":1,"Important":1,"Minor":3}]'

# --- compare_note ---
CMP="$TMP/root-compare"
cmp_run() { # cmp_run NAME STATE ROWS — a run directory with arm.json, state and out/report.json holding ROWS
  local d="$CMP/$1"
  mkdir -p "$d/out"
  jq -n --arg arm "${1%%-*}" '{arm: $arm, plan: "docs/p.md", model: "opus", effort: "high"}' > "$d/arm.json"
  printf '%s\n' "$2" > "$d/state"
  jq -n --argjson rows "$3" '{plans: [{plan: "p.md", tasks: $rows}]}' > "$d/out/report.json"
}
row() { # row TASKS GROUP TURNS LOOKUPS GROWTH WRITES SUBTURNS
  jq -nc --argjson t "$1" --argjson g "$2" --argjson n "$3" --argjson l "$4" --argjson gr "$5" --argjson w "$6" --argjson s "$7" \
    '{tasks: $t, group: $g, turns: $n, lookups: $l, growth: $gr, cacheWrite5m: $w, cacheWrite1h: 0, subagents: (if $s > 0 then {"x:impl": {turns: $s}} else {} end)}'
}
cmp_run dforge-1 finished "[$(row '[1]' false 4 2 1000 10 0),$(row '[2]' false 2 1 500 20 0)]"
cmp_run dforge-2 finished "[$(row '[1]' false 3 3 800 30 0)]"
cmp_run dagents-1 finished "[$(row '[1,2]' true 10 4 4000 40 10)]"
cmp_run dagents-2 finished "[$(row '[1]' false 6 2 900 5 0),$(row '[2]' false 4 6 700 15 0)]"
cmp_run dagents-3 timed-out "[$(row '[1]' false 999 999 999 999 0)]"
cmp_run dforge-3 finished "[]"
rm -f "$CMP/dforge-3/state" "$CMP/dforge-3/out/report.json"
cmp_run dforge-4 finished "[]"
rm -f "$CMP/dforge-4/out/report.json"
WAB_ROOT="$CMP" bash "$WAB/compare" 2>"$TMP/compare.err"; status=$?
NOTE="$CMP/comparison.md"
check "compare_note: exit 0, the note at its default path" "$status:$([ -s "$NOTE" ] && echo written)" "0:written"
check "compare_note: the sections in order" "$(grep '^## ' "$NOTE" | tr '\n' '|')" \
  "## Runs|## Per-task distributions|## Spread across runs|## Groups|## What this replay cannot decide|"
section() { awk -v h="## $1" '$0 == h { f = 1; next } /^## / { f = 0 } f' "$NOTE"; }
check "compare_note: every run's arm.json is reproduced" "$(section Runs | grep -c '"model": "opus"')" "7"
has "compare_note: the timed-out run is marked" "$(section Runs)" "### dagents-3: timed-out — excluded from the figures"
has "compare_note: and listed" "$(section Runs)" "Excluded runs: dagents-3 (timed-out), dforge-3 (not launched, no report), dforge-4 (finished, no report)."
has "compare_note: a run with no state is not launched" "$(section Runs)" "### dforge-3: not launched — excluded from the figures"
has "compare_note: a finished run with no report is excluded" "$(section Runs)" "### dforge-4: finished — excluded from the figures"
DIST=$(section 'Per-task distributions')
has "compare_note: dforge turns over three tasks" "$DIST" "| dforge | turns | 3 | 2 | 3 | 4 |"
has "compare_note: a dagents group is one observation divided by its task count" "$DIST" "| dagents | turns | 3 | 4 | 5 | 6 |"
has "compare_note: cache writes per arm" "$DIST" "| dagents | cache writes | 3 | 5 | 15 | 20 |"
has "compare_note: subagent share per arm" "$DIST" "| dagents | subagent share | 3 | 0 | 0 | 0.5 |"
has "compare_note: lookups and growth too" "$DIST" "| dforge | growth | 3 | 500 | 800 | 1000 |"
check "compare_note: the timed-out run's figures are absent from the distributions" "$(grep -c 999 <<<"$DIST")" "0"
SPREAD=$(section 'Spread across runs')
has "compare_note: each run's median, run by run" "$SPREAD" "| dforge | lookups | dforge-1 | 2 | 1.5 |
| dforge | lookups | dforge-2 | 1 | 3 |"
has "compare_note: a group is one observation in its run's median" "$SPREAD" "| dagents | turns | dagents-1 | 1 | 5 |"
check "compare_note: excluded runs are absent from the spread" "$(grep -cE 'dagents-3|dforge-3|dforge-4|999' <<<"$SPREAD")" "0"
has "compare_note: the group row" "$(section Groups)" "- dagents-1 tasks 1, 2: turns 10 (5 per task), lookups 4 (2 per task)"
has "compare_note: the group sentence" "$(section Groups)" "Per-task spread inside a group is not measurable."
has "compare_note: the plan-level cost gap" "$(section 'What this replay cannot decide')" "plan-level cost gap"
has "compare_note: P1.1's effect" "$(section 'What this replay cannot decide')" "P1.1's effect"
WAB_ROOT="$CMP" bash "$WAB/compare" --out "$TMP/elsewhere/note.md" 2>/dev/null
check "compare_note: --out writes the note there" "$(cmp -s "$TMP/elsewhere/note.md" "$NOTE" && echo same)" "same"

# --- collect and compare finish a removal a killed launch left undone ---
rcfg="$TMP/repair-config-2"
mkdir -p "$rcfg"
printf '{\n  "model": "opus",\n  "theme": "dark"\n}\n' > "$rcfg/settings.json"
cp "$rcfg/settings.json" "$TMP/settings2.orig"
for cmd in collect compare; do
  mkdir -p "$CMP/rep-$cmd"
  printf 'keyBefore=absent\nfile=%s\n' "$rcfg/settings.json" > "$CMP/rep-$cmd/settings-repair"
  jq '. + {"skipDangerousModePermissionPrompt": true}' < "$rcfg/settings.json" > "$rcfg/s.new" && mv "$rcfg/s.new" "$rcfg/settings.json"
  if [ "$cmd" = collect ]; then WAB_ROOT="$CMP" bash "$WAB/collect" dforge 99 >/dev/null 2>&1
  else WAB_ROOT="$CMP" bash "$WAB/compare" --out "$TMP/repair-note.md" >/dev/null 2>&1; fi
  check "settings_repair_after_kill: $cmd removes the key, every other byte equal" \
    "$(cmp -s "$rcfg/settings.json" "$TMP/settings2.orig" && echo equal || echo differs)" "equal"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
