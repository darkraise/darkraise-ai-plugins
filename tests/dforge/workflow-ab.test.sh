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
unset DFORGE_BUDGET CLAUDE_CONFIG_DIR
printf '#!/bin/sh\necho "9.9.9 (Claude Code)"\n' > "$TMP/claude"
chmod +x "$TMP/claude"
mkdir -p "$TMP/claude-config"
printf '{"autoCompactWindow": 500000}\n' > "$TMP/claude-config/settings.json"
printf '{"handoffTokens": 250000}\n' > "$TMP/owner-dforge.json"
export WAB_ROOT="$TMP/root" WAB_CLAUDE="$TMP/claude" WAB_CLAUDE_CONFIG="$TMP/claude-config" \
  WAB_DFORGE_CONFIG="$TMP/owner-dforge.json" WAB_PLAN="$PLAN"

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

# --- prepare_check_blocks ---
make_source "$TMP/src-false" 's/^\*\*Integration check:\*\* .*/**Integration check:** `false`/'
WAB_SOURCE="$TMP/src-false" WAB_BASE=$(git -C "$TMP/src-false" rev-list --max-parents=0 HEAD) prep dforge 2 --check
check "prepare_check_blocks: a failing Integration check exits 1" "$status" "1"
check "prepare_check_blocks: and writes check-failed" "$(cat "$WAB_ROOT/dforge-2/state" 2>/dev/null)" "check-failed"
make_source "$TMP/src-true" 's/^\*\*Integration check:\*\* .*/**Integration check:** `true`/'
WAB_SOURCE="$TMP/src-true" WAB_BASE=$(git -C "$TMP/src-true" rev-list --max-parents=0 HEAD) prep dforge 3 --check
check "prepare_check_blocks: a passing Integration check exits 0" "$status" "0"
check "prepare_check_blocks: and writes no state" "$([ -e "$WAB_ROOT/dforge-3/state" ] && echo written || echo none)" "none"

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
[ -e "\$T/hang" ] && exec sleep 300
exit 0
EOF
STUB_PLUGINS="$TMP/stub-plugins"
mkdir -p "$STUB_PLUGINS/plugins/dforge/scripts"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\n' "$TMP/auto-run.log" > "$STUB_PLUGINS/plugins/dforge/scripts/auto-run"
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
  "1|$run1/home|$TMP/claude-config|file|false|0|$run1/gh"
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
check "launch_timeout: stops the bound run" "$(cat "$TMP/auto-run.log")" "--session $(head -n 1 "$WAB_ROOT/dforge-6/sessions") stop"
check "launch_timeout: kills its own tmux session" "$(grep -c '^kill-session -t =wab-dforge-6$' "$TMP/tmux.log")" "1"
sleep 1
check "launch_timeout: the nested session is gone" "$(kill -0 "$(cat "$TMP/claude.pid")" 2>/dev/null && echo alive || echo gone)" "gone"

# --- a launch stopped by a signal ---
: > "$TMP/auto-run.log"
prep dforge 11
(MAXS=60 launch dforge 11) &
lpid=$!
for _ in $(seq 50); do [ -f "$TMP/tmux-wab-dforge-11.pid" ] && break; sleep 0.2; done
kill -TERM $(pgrep -f "evals/workflow-ab/launch dforge 11$")
wait "$lpid" 2>/dev/null
check "launch_interrupted: a signalled launch writes stopped and stops its run" \
  "$(cat "$WAB_ROOT/dforge-11/state") $(grep -c ' stop$' "$TMP/auto-run.log") $([ -f "$TMP/tmux-wab-dforge-11.pid" ] && echo left || echo killed)" "stopped 1 killed"

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
kill -TERM $(pgrep -f "evals/workflow-ab/launch dforge 12$")
wait "$lpid" 2>/dev/null
check "settings_repair_after_kill: a symlinked settings.json keeps its link, the key removed at its target" \
  "$([ -L "$TMP/link-config/settings.json" ] && echo link) $(cmp -s "$TMP/dotfiles/settings.json" "$TMP/dotfiles.orig" && echo equal || echo differs)" "link equal"
check "settings_repair_after_kill: a key present before is kept" "$(cat "$WAB_ROOT/dforge-5/settings-key") $(cmp -s "$cfg/settings.json" "$TMP/settings.orig" && echo equal || echo differs)" "keyBefore=present equal"
rm -f "$TMP/hang"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
