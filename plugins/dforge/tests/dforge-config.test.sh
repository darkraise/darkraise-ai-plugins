#!/usr/bin/env bash
# dforge-config: environment over file over default, set/unset, refusals, and
# the one-time import of the pre-2.0 settings.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CMD="$HERE/../scripts/dforge-config"
command -v node > /dev/null 2>&1 || { echo "dforge-config tests: node is required but not on PATH" >&2; exit 2; }

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1))
  else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
if command -v cygpath > /dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
unset CLAUDE_CONFIG_DIR DFORGE_BUDGET DR_SUPERPOWERS_BUDGET CLAUDE_PROJECT_DIR
fc() { bash "$CMD" "$@" 2> "$TMP/stderr"; }
fresh() { export HOME="$TMP/home-$1"; mkdir -p "$HOME"; FILE="$HOME/.dforge/config.json"; }

# --- defaults, set, get, unset ---
fresh a
check "default" "$(fc get warnAt)" "80"
check "first run writes the file" "$(cat "$FILE" | tr -d ' \n')" "{}"
fc set warnAt 70; check "set: exit 0" "$?" "0"
check "set then get" "$(fc get warnAt)" "70"
fc set layout compact
check "get --json" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log(v.warnAt, v.layout, v.openAtStart)')" "70 compact true"
fc set warnAt 80
check "a default value is not stored" "$(node -e 'console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))).join(","))' "$FILE")" "layout"
fc unset layout
check "unset" "$(fc get layout)" "auto"
fc set darkmemEnabled false
check "a keepDefault key is stored at its default" "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).darkmemEnabled)' "$FILE")" "false"
fc unset darkmemEnabled

# --- refusals leave the file unchanged ---
before=$(cat "$FILE")
fc set nope 1; check "unknown key: exit 2" "$?" "2"
fc set warnAt 500; check "out of range: exit 2" "$?" "2"
fc set layout tiles; check "not an option: exit 2" "$?" "2"
fc set guardAttribution maybe; check "not a boolean: exit 2" "$?" "2"
fc get; check "usage: exit 2" "$?" "2"
fc get constructor; check "an inherited name is unknown: exit 2" "$?" "2"
fc unset toString; check "unset of an inherited name: exit 2" "$?" "2"
check "refusals change nothing" "$(cat "$FILE")" "$before"

# --- environment over file ---
fc set handoffTokens 300000
check "file value" "$(fc get handoffTokens)" "300000"
check "DFORGE_BUDGET wins" "$(DFORGE_BUDGET=400000 fc get handoffTokens)" "400000"
check "the pre-2.0 DR_SUPERPOWERS_BUDGET is not read" "$(DR_SUPERPOWERS_BUDGET=450000 fc get handoffTokens)" "300000"
check "an invalid override is ignored" "$(DFORGE_BUDGET=junk fc get handoffTokens)" "300000"
check "and warned about" "$(grep -c 'DFORGE_BUDGET' "$TMP/stderr")" "1"

# --- a file that is not JSON is refused, not overwritten ---
printf 'not json' > "$FILE"
fc set warnAt 70; check "bad file: exit 1" "$?" "1"
check "bad file kept" "$(cat "$FILE")" "not json"

# --- one-time import ---
fresh b
mkdir -p "$HOME/.claude" "$HOME/.dr-superpowers"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"layout":"compact","warnAt":80,"breakdownRows":"x"}}}}' > "$HOME/.claude/settings.json"
printf '%s' '{"darkmem":{"url":"http://d.test","api_key_env":"DM_KEY","repos":{"/r":{"project":"p"}}}}' > "$HOME/.dr-superpowers/config.json"
fc get layout > /dev/null
DM='{"url":"http://d.test","api_key_env":"DM_KEY","repos":{"/r":{"project":"p"}}}'
check "import: options only, not the pre-2.0 home" "$(node -e 'const v = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); console.log(JSON.stringify(v))' "$FILE")" '{"layout":"compact"}'
printf '{"layout":"compact","darkmem":%s}\n' "$DM" > "$FILE"
fc set warnAt 70
fc unset warnAt
fc set notifyDetail brief
check "set and unset keep the darkmem mapping whole" "$(node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).darkmem))' "$FILE")" "$DM"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"layout":"full"}}}}' > "$HOME/.claude/settings.json"
check "import runs once" "$(fc get layout)" "compact"

# --- CLAUDE_CONFIG_DIR names the settings to import ---
fresh c
mkdir -p "$TMP/alt"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"notifyDetail":"brief"}}}}' > "$TMP/alt/settings.json"
check "import from CLAUDE_CONFIG_DIR" "$(CLAUDE_CONFIG_DIR="$TMP/alt" fc get notifyDetail)" "brief"

# --- two first runs at once: exactly one import lands, whole ---
fresh d
mkdir -p "$TMP/c1" "$TMP/c2"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"layout":"compact"}}}}' > "$TMP/c1/settings.json"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"layout":"full","warnAt":70}}}}' > "$TMP/c2/settings.json"
CLAUDE_CONFIG_DIR="$TMP/c1" bash "$CMD" get layout > /dev/null 2>&1 &
p1=$!
CLAUDE_CONFIG_DIR="$TMP/c2" bash "$CMD" get layout > /dev/null 2>&1 &
p2=$!
wait "$p1" "$p2"
case $(tr -d ' \n' < "$FILE") in '{"layout":"compact"}'|'{"layout":"full","warnAt":70}') whole=yes ;; *) whole=no ;; esac
check "concurrent first runs: one whole import" "$whole" "yes"
check "concurrent first runs: no temporary file left" "$(ls "$HOME/.dforge" | grep -c '\.import$')" "0"

# --- the workflow keys: defaults and refusals ---
fresh w
check "workflow keys: defaults" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log([v.handoffMode, v.codexLane, v.codexReview, v.executionStrategy, v.executionMode, v.worktree, v.processBias, v.designApproval, v.specReview, v.questionStyle, v.finishAction, v.finishTimeout].join(" "))')" \
  "strict true true ask auto ask standard sections true single ask 30"
# Each key: its default, a value it accepts, and one it refuses.
while read -r key default valid invalid; do
  fresh "m-$key"
  check "$key: default" "$(fc get "$key")" "$default"
  fc set "$key" "$valid"; check "$key: a valid value: exit 0" "$?" "0"
  check "$key: the value is read back" "$(fc get "$key")" "$valid"
  fc set "$key" "$invalid"; check "$key: an invalid value: exit 2" "$?" "2"
  check "$key: a refusal keeps the value" "$(fc get "$key")" "$valid"
done <<'ROWS'
handoffMode strict relaxed loose
codexLane true false maybe
codexReview true false 0
lensCap 4 2 10
executionStrategy ask parallel fast
executionMode auto subagent agent
worktree ask always sometimes
processBias standard heavier heavy
designApproval sections whole none
specReview true false no
questionStyle single batched many
finishAction ask merge discard
finishTimeout 30 45 3
documentStore darkmem local remote
progressSource darkmem local remote
ROWS

fresh lens-env
check "lensCap: the environment wins" "$(DFORGE_LENS_CAP=1 fc get lensCap)" "1"

# --- Claude's own settings file: one key changed, everything else kept ---
fresh k
keys() { node -e 'console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))).join(","))' "$1"; }
at() { node -e 'console.log(JSON.stringify(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))[process.argv[2]]))' "$1" "$2"; }
mkdir -p "$HOME/.claude"
CS="$HOME/.claude/settings.json"
check "claude: defaults with no file" "$(fc get autoCompactWindow) $(fc get autoCompactEnabled)" "0 true"
printf '%s\n' '{"permissions":{"allow":["Bash(ls:*)"]},"autoCompactWindow":650000,"hooks":{}}' > "$CS"
check "claude: read from the settings file" "$(fc get autoCompactWindow)" "650000"
fc set autoCompactWindow 800000; check "claude set: exit 0" "$?" "0"
check "claude set: the value" "$(at "$CS" autoCompactWindow)" "800000"
check "claude set: every other key and the order kept" "$(keys "$CS")" "permissions,autoCompactWindow,hooks"
check "claude set: the permissions untouched" "$(at "$CS" permissions)" '{"allow":["Bash(ls:*)"]}'
check "claude set: nothing in the dforge file" "$(keys "$FILE")" ""
fc set autoCompactWindow 50000; check "claude: below the floor: exit 2" "$?" "2"
fc set autoCompactWindow 1050000; check "claude: above the maximum: exit 2" "$?" "2"
check "claude: a refusal changes nothing" "$(at "$CS" autoCompactWindow)" "800000"
fc set autoCompactEnabled false
check "claude: a new key goes last" "$(keys "$CS")" "permissions,autoCompactWindow,hooks,autoCompactEnabled"
fc set autoCompactEnabled true
check "claude: the default boolean is written, not dropped" "$(at "$CS" autoCompactEnabled)" "true"
fc set autoCompactWindow 0
check "claude: 0 removes the key" "$(keys "$CS")" "permissions,hooks,autoCompactEnabled"
fc unset autoCompactEnabled
check "claude: unset removes the key" "$(keys "$CS")" "permissions,hooks"
check "claude: get --json carries both" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log(v.autoCompactWindow, v.autoCompactEnabled, v.warnAt)')" "0 true 80"

# A file that cannot be parsed is never replaced, and the dforge keys still resolve.
printf 'not json' > "$CS"
fc set autoCompactWindow 800000; check "claude: an unparseable file: exit 1" "$?" "1"
check "claude: an unparseable file is left byte-identical" "$(cat "$CS")" "not json"
check "claude: the file is named" "$(grep -c 'settings.json is not valid JSON' "$TMP/stderr")" "1"
check "claude: dforge keys still resolve" "$(fc get warnAt)" "80"
check "claude: the unreadable file reads as the default" "$(fc get autoCompactWindow)" "0"
rm -f "$CS"
fc set autoCompactWindow 800000
check "claude: a missing file is created with the one key" "$(tr -d ' \n' < "$CS")" '{"autoCompactWindow":800000}'
check "claude: no temporary file left" "$(ls "$HOME/.claude" | grep -c '\.tmp$')" "0"

# CLAUDE_CONFIG_DIR names the file.
mkdir -p "$TMP/alt-k"
printf '%s\n' '{"model":"opus"}' > "$TMP/alt-k/settings.json"
CLAUDE_CONFIG_DIR="$TMP/alt-k" fc set autoCompactWindow 500000
check "claude: CLAUDE_CONFIG_DIR is written" "$(keys "$TMP/alt-k/settings.json")" "model,autoCompactWindow"
check "claude: the home file is left alone" "$(at "$CS" autoCompactWindow)" "800000"

# A symlinked settings file stays a symlink, and its mode is kept. Neither holds on Windows.
if ! command -v cygpath > /dev/null 2>&1; then
  mkdir -p "$TMP/dotfiles"
  printf '%s\n' '{"model":"opus"}' > "$TMP/dotfiles/settings.json"
  chmod 600 "$TMP/dotfiles/settings.json"
  rm -f "$CS"; ln -s "$TMP/dotfiles/settings.json" "$CS"
  fc set autoCompactWindow 700000
  check "claude: a symlink stays a symlink" "$([ -L "$CS" ] && echo yes || echo no)" "yes"
  check "claude: the real file is written" "$(keys "$TMP/dotfiles/settings.json")" "model,autoCompactWindow"
  check "claude: the mode is kept" "$(node -e 'console.log((require("fs").statSync(process.argv[1]).mode & 0o777).toString(8))' "$TMP/dotfiles/settings.json")" "600"
  # A link whose destination does not exist yet is written through, not replaced.
  rm -f "$CS"; ln -s "$TMP/dotfiles/later.json" "$CS"
  fc set autoCompactWindow 600000
  check "claude: a dangling symlink stays a symlink" "$([ -L "$CS" ] && echo yes || echo no)" "yes"
  check "claude: its destination is created" "$(tr -d ' \n' < "$TMP/dotfiles/later.json")" '{"autoCompactWindow":600000}'
fi

# claude-restore puts back what /model and /effort save, and touches nothing else.
mkdir -p "$TMP/alt-r"
RS="$TMP/alt-r/settings.json"
printf '%s\n' '{"permissions":{"allow":[]},"model":"sonnet","modelSettings":{"claude-sonnet-5-5":{"effortLevel":"high"}},"hooks":{}}' > "$RS"
CLAUDE_CONFIG_DIR="$TMP/alt-r" fc claude-restore '{"model":"opus[1m]","modelSettings":null}'
check "claude-restore: exit 0" "$?" "0"
check "claude-restore: the model is put back" "$(at "$RS" model)" '"opus[1m]"'
check "claude-restore: null removes a key, the others keep their order" "$(keys "$RS")" "permissions,model,hooks"
CLAUDE_CONFIG_DIR="$TMP/alt-r" fc claude-restore '{"model":null,"modelSettings":{"claude-opus-5-5":{"effortLevel":"max"}}}'
check "claude-restore: an object value is written" "$(at "$RS" modelSettings)" '{"claude-opus-5-5":{"effortLevel":"max"}}'
check "claude-restore: the model removed" "$(keys "$RS")" "permissions,hooks,modelSettings"
before=$(cat "$RS")
CLAUDE_CONFIG_DIR="$TMP/alt-r" fc claude-restore '{"permissions":null}'; check "claude-restore: another key: exit 2" "$?" "2"
CLAUDE_CONFIG_DIR="$TMP/alt-r" fc claude-restore '["model"]'; check "claude-restore: not an object: exit 2" "$?" "2"
CLAUDE_CONFIG_DIR="$TMP/alt-r" fc claude-restore 'nope'; check "claude-restore: not JSON: exit 2" "$?" "2"
check "claude-restore: a refusal changes nothing" "$(cat "$RS")" "$before"

# Each Claude key: its default, a value it accepts, and one it refuses.
while read -r key default valid invalid; do
  fresh "m-$key"
  check "$key: default" "$(fc get "$key")" "$default"
  fc set "$key" "$valid"; check "$key: a valid value: exit 0" "$?" "0"
  check "$key: the value is read back" "$(fc get "$key")" "$valid"
  fc set "$key" "$invalid"; check "$key: an invalid value: exit 2" "$?" "2"
  check "$key: a refusal keeps the value" "$(fc get "$key")" "$valid"
done <<'ROWS'
autoCompactWindow 0 100000 99999
autoCompactEnabled true false maybe
ROWS

# --- the workflow line: the skill-enforced keys that differ from their defaults ---
fresh x
check "workflow: nothing at the defaults" "$(fc workflow)" ""
fc workflow > /dev/null; check "workflow: exit 0" "$?" "0"
fc set designApproval whole; fc set worktree always; fc set codexLane false; fc set finishAction merge
check "workflow: only skill keys, in schema order" "$(fc workflow)" \
  "dforge settings in force (each replaces the matching question or default in the skills): worktree=always; designApproval=whole"
fc workflow extra; check "workflow takes no argument: exit 2" "$?" "2"

# --- dforge_setting: the value in force, or the default when the command cannot answer ---
. "$HERE/../scripts/lib/dforge-env.sh"
check "dforge_setting reads the file" "$(dforge_setting worktree ask)" "always"
check "dforge_setting: an unknown key gives the default" "$(dforge_setting nope fallback)" "fallback"
printf 'not json' > "$FILE"
check "dforge_setting: a broken file gives the default" "$(dforge_setting worktree ask)" "ask"
dforge_setting worktree ask > /dev/null; check "dforge_setting never fails" "$?" "0"
fresh y
check "dforge_setting: a first read answers the default" "$(dforge_setting worktree ask)" "ask"
check "dforge_setting: a read never creates the settings file" "$([ -e "$FILE" ] && echo created || echo absent)" "absent"
fc set worktree never
check "DFORGE_NO_SETTINGS answers the default" "$(DFORGE_NO_SETTINGS=1 dforge_setting worktree ask)" "ask"
# Git Bash with path conversion off hands node the module path as written.
check "the command runs with path conversion off" "$(MSYS_NO_PATHCONV=1 fc get worktree)" "never"
# A number setting is a whole number.
fc set finishTimeout 5.5; check "a fraction: exit 2" "$?" "2"
fc set warnAt 72.5; check "a fraction of an older key: exit 2" "$?" "2"

# The settings view gives each group a tab and the tabs the hotkeys 1, 2, ….
groups=$(node --input-type=module -e "const { default: schema } = await import(process.argv[1]); console.log(new Set(Object.values(schema).map(spec => spec.group)).size)" "$(cd "$HERE/../config" && pwd)/schema.mjs")
check "the README's tab hotkeys cover every settings group" "$(grep -c "press \`1\` to \`$groups\` to switch" "$HERE/../README.md")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
