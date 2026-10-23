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

# --- the value check lives in the schema module, shared with the cockpit ---
SCHEMA_MJS="$HERE/../config/schema.mjs"
# A module path reaches node as an argument, which Git Bash converts, and is
# imported as a file URL: a bare C:/… specifier reads as a URL scheme.
vv() { node --input-type=module -e "import { pathToFileURL } from 'node:url'; const { isValidValue } = await import(pathToFileURL(process.argv[1]).href); console.log(isValidValue($1, $2))" "$SCHEMA_MJS" 2>&1; }
check "schema exports isValidValue: boolean" "$(vv '{ type: "boolean" }' 'true')" "true"
check "isValidValue: a fraction is not a number setting" "$(vv '{ type: "number", min: 0 }' '1.5')" "false"
check "isValidValue: 0 under a floor means unset" "$(vv '{ type: "number", floor: 1000 }' '0')" "true"
check "isValidValue: under the floor" "$(vv '{ type: "number", floor: 1000 }' '5')" "false"
check "isValidValue: enum member" "$(vv '{ type: "enum", values: ["a"] }' '"a"')" "true"
check "isValidValue: unknown type" "$(vv '{ type: "list" }' '[]')" "false"
check "isValidValue: a list of known names, any case and separator" "$(vv '{ type: "string", values: ["a", "b"] }' '"B, a b"')" "true"
check "isValidValue: an empty list" "$(vv '{ type: "string", values: ["a"] }' '""')" "true"
check "isValidValue: a list naming an unknown name" "$(vv '{ type: "string", values: ["a"] }' '"a,typo"')" "false"

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
fc set sections "plan, sesions"; check "a misspelt section: exit 2" "$?" "2"
fc set notifyOn none; check "notifyOn none is a valid list" "$?" "0"
fc unset notifyOn
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

# --- two setters at once: both keys land ---
# Each setter holds its read of config.json for 300 ms, so without a lock both
# read the same file and the later rename drops the other's key.
fresh race
mkdir -p "$HOME/.dforge"
printf '{}\n' > "$FILE"
slow_set() { # slow_set KEY VALUE
  node --input-type=module -e '
    import fs from "node:fs";
    import { pathToFileURL } from "node:url";
    const { main } = await import(pathToFileURL(process.argv[1]).href);
    const read = fs.readFileSync;
    fs.readFileSync = function (file, ...rest) {
      const data = read.call(this, file, ...rest);
      if (String(file).endsWith("config.json")) { const until = Date.now() + 300; while (Date.now() < until); }
      return data;
    };
    process.exitCode = main(["set", process.argv[2], process.argv[3]]);
  ' "$HERE/../scripts/lib/dforge-config.mjs" "$1" "$2" > /dev/null 2>&1
}
slow_set notifyAfter 120 &
p1=$!
slow_set finishAction merge &
p2=$!
wait "$p1" "$p2"
check "concurrent setters: both keys kept" "$(fc get notifyAfter) $(fc get finishAction)" "120 merge"

# --- run through a symbolic link to the scripts directory, it still runs ---
fresh linked
ln -s "$(cd "$HERE/../scripts" && pwd)" "$TMP/linked-scripts"
check "through a linked directory: get answers" "$(node "$TMP/linked-scripts/lib/dforge-config.mjs" get warnAt 2>&1)" "80"

# --- the workflow keys: defaults and refusals ---
fresh w
check "workflow keys: defaults" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log([v.handoffMode, v.codexLane, v.codexReview, v.executionStrategy, v.executionMode, v.worktree, v.processBias, v.designApproval, v.specReview, v.questionStyle, v.finishAction, v.autoRun].join(" "))')" \
  "strict true false parallel auto ask standard sections true single ask on"
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
codexReview false true 0
lensCap 4 2 10
lensMinorFrom 20 10 501
executionStrategy parallel sequential fast
autoRun on ask maybe
executionMode auto subagent agent
worktree ask always sometimes
processBias standard heavier heavy
designApproval sections whole none
specReview true false no
questionStyle single batched many
finishAction ask merge discard
documentStore darkmem local remote
progressSource darkmem local remote
ROWS
fresh ar-off
fc set autoRun off; check "autoRun: off is accepted" "$?" "0"
check "autoRun: off is read back" "$(fc get autoRun)" "off"

fresh lens-env
check "lensCap: the environment wins" "$(DFORGE_LENS_CAP=1 fc get lensCap)" "1"
check "lensMinorFrom: the environment wins" "$(DFORGE_LENS_MINOR_FROM=0 fc get lensMinorFrom)" "0"

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
  # A dangling chain is followed to its end: no link in it is replaced by a file.
  rm -f "$CS"; ln -s "$TMP/dotfiles/end.json" "$TMP/dotfiles/hop.json"; ln -s "$TMP/dotfiles/hop.json" "$CS"
  fc set autoCompactWindow 550000
  check "claude: a dangling chain: the first link stays" "$([ -L "$CS" ] && echo yes || echo no)" "yes"
  check "claude: a dangling chain: the middle link stays" "$([ -L "$TMP/dotfiles/hop.json" ] && echo yes || echo no)" "yes"
  check "claude: a dangling chain: its end is created" "$(tr -d ' \n' < "$TMP/dotfiles/end.json" 2>/dev/null)" '{"autoCompactWindow":550000}'
  # A dangling chain of exactly 40 links, the most the loop allows, is still
  # followed: the 40th hop lands on the chain's final path.
  mkdir -p "$TMP/chain40"
  rm -f "$CS"; ln -s "$TMP/chain40/end.json" "$TMP/chain40/link39"
  for n in $(seq 38 -1 1); do ln -s "$TMP/chain40/link$((n + 1))" "$TMP/chain40/link$n"; done
  ln -s "$TMP/chain40/link1" "$CS"
  fc set autoCompactWindow 540000; check "claude: a 40-link dangling chain: exit 0" "$?" "0"
  check "claude: a 40-link dangling chain: its end is created" "$(tr -d ' \n' < "$TMP/chain40/end.json" 2>/dev/null)" '{"autoCompactWindow":540000}'
  check "claude: a 40-link dangling chain: the last link stays" "$([ -L "$TMP/chain40/link39" ] && echo yes || echo no)" "yes"
  # One link more is refused, and nothing is created at the chain's end. On
  # Linux the kernel's own 40-link limit refuses it (ELOOP) before the cap.
  mkdir -p "$TMP/chain41"
  rm -f "$CS"; ln -s "$TMP/chain41/end.json" "$TMP/chain41/link40"
  for n in $(seq 39 -1 1); do ln -s "$TMP/chain41/link$((n + 1))" "$TMP/chain41/link$n"; done
  ln -s "$TMP/chain41/link1" "$CS"
  fc set autoCompactWindow 530000; check "claude: a 41-link dangling chain: exit 1" "$?" "1"
  check "claude: a 41-link dangling chain: the refusal names the links" "$(grep -c 'symbolic links' "$TMP/stderr")" "1"
  check "claude: a 41-link dangling chain: nothing is created at its end" "$([ -e "$TMP/chain41/end.json" ] && echo yes || echo no)" "no"
  # The cap itself, reached by making realpath report the chain as missing, as
  # a system whose kernel allows longer chains would: the loop refuses it.
  capped=$(DFORGE_CONFIG_MJS="$HERE/../scripts/lib/dforge-config.mjs" node --input-type=module -e '
    import fs from "node:fs";
    const { main } = await import(process.env.DFORGE_CONFIG_MJS);
    // After the import: the module loader resolves paths with realpathSync too.
    fs.realpathSync = () => { throw Object.assign(new Error("ENOENT: realpath stubbed"), { code: "ENOENT" }); };
    process.exitCode = main(["set", "autoCompactWindow", "520000"]);
  ' 2>&1; printf 'exit %s\n' "$?")
  check "claude: the hop cap refuses a 41-link chain" "$(grep -c -e 'more than 40 symbolic links' -e '^exit 1$' <<<"$capped")" "2"
  check "claude: the hop cap creates nothing at the chain's end" "$([ -e "$TMP/chain41/end.json" ] && echo yes || echo no)" "no"
fi

# As root, a rewrite keeps the file's owner and group: the temporary file is
# created by root and would otherwise hand a user's settings file to root.
if [ "$(id -u)" = 0 ] && ! command -v cygpath > /dev/null 2>&1; then
  mkdir -p "$TMP/alt-o"
  printf '%s\n' '{"model":"opus"}' > "$TMP/alt-o/settings.json"
  chown 4321:4322 "$TMP/alt-o/settings.json"
  CLAUDE_CONFIG_DIR="$TMP/alt-o" fc set autoCompactWindow 500000
  check "claude: as root, the value is written" "$(at "$TMP/alt-o/settings.json" autoCompactWindow)" "500000"
  check "claude: as root, the owner and group are kept" "$(node -e 'const s = require("fs").statSync(process.argv[1]); console.log(s.uid + ":" + s.gid)' "$TMP/alt-o/settings.json")" "4321:4322"
else
  echo "skip - the owner is kept when root writes (not running as root)"
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
# A command that fails is never read for what it printed, with or without
# pipefail, and a caller under set -e and pipefail survives the failure.
mkdir -p "$TMP/fake/lib"
printf '#!/usr/bin/env bash\nprintf partial\nexit 1\n' > "$TMP/fake/dforge-config"
check "dforge_setting: a failed command's output is not used" "$(set +o pipefail; _DFORGE_ENV_DIR="$TMP/fake/lib"; dforge_setting worktree ask)" "ask"
check "dforge_setting: a set -e pipefail caller survives a failure" "$(set -eo pipefail; _DFORGE_ENV_DIR="$TMP/fake/lib"; dforge_setting worktree ask > /dev/null; echo survived)" "survived"
# Git Bash with path conversion off hands node the module path as written.
check "the command runs with path conversion off" "$(MSYS_NO_PATHCONV=1 fc get worktree)" "never"
# A number setting is a whole number.
fc set notifyAfter 5.5; check "a fraction: exit 2" "$?" "2"
# finishTimeout is retired: a value left in the file is ignored, and naming it is an error.
fresh retired
mkdir -p "$HOME/.dforge"
printf '{"finishAction":"merge","finishTimeout":45}\n' > "$FILE"
check "retired finishTimeout: get --json reads the rest" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log(v.finishAction + " " + ("finishTimeout" in v))')" "merge false"
fc get finishTimeout > /dev/null 2>&1; check "retired finishTimeout: get exits 2" "$?" "2"
check "finishAction: the title and description" "$(node --input-type=module -e "import { pathToFileURL } from 'node:url'; const { default: schema } = await import(pathToFileURL(process.argv[1]).href); console.log(schema.finishAction.title + ' | ' + schema.finishAction.description)" "$(cd "$HERE/../config" && pwd)/schema.mjs")" 'When the work is done | ask asks before the first task. merge, pr or keep skips the question and runs that action as soon as the final review is clean; wait skips it and shows the finish menu then.'
fc set warnAt 72.5; check "a fraction of an older key: exit 2" "$?" "2"

# The settings view gives each group a tab and the tabs the hotkeys 1, 2, ….
groups=$(node --input-type=module -e "import { pathToFileURL } from 'node:url'; const { default: schema } = await import(pathToFileURL(process.argv[1]).href); console.log(new Set(Object.values(schema).map(spec => spec.group)).size)" "$(cd "$HERE/../config" && pwd)/schema.mjs")
check "the README's tab hotkeys cover every settings group" "$(grep -c "press \`1\` to \`$groups\` to switch" "$HERE/../README.md")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
