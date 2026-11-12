#!/usr/bin/env bash
# dforge-config: file over default, set/unset, refusals, a file an earlier
# release wrote, and the one-time import of the pre-2.0 settings.
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
unset CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR
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
check "isValidValue: a retired name, any case, is accepted" "$(vv '{ type: "string", values: ["a"], retired: ["old"] }' '"a,OLD"')" "true"
check "isValidValue: retired does not widen an enum" "$(vv '{ type: "enum", values: ["a"], retired: ["old"] }' '"old"')" "false"

# --- defaults, set, get, unset ---
fresh a
check "default" "$(fc get breakdownRows)" "6"
check "first run writes the file" "$(cat "$FILE" | tr -d ' \n')" "{}"
fc set breakdownRows 4; check "set: exit 0" "$?" "0"
check "set then get" "$(fc get breakdownRows)" "4"
fc set layout compact
check "get --json" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log(v.breakdownRows, v.layout, v.openAtStart)')" "4 compact true"
fc set breakdownRows 6
check "a default value is not stored" "$(node -e 'console.log(Object.keys(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"))).join(","))' "$FILE")" "layout"
fc unset layout
check "unset" "$(fc get layout)" "auto"
fc set darkmemEnabled false
check "a keepDefault key is stored at its default" "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).darkmemEnabled)' "$FILE")" "false"
fc unset darkmemEnabled

# --- refusals leave the file unchanged ---
before=$(cat "$FILE")
fc set nope 1; check "unknown key: exit 2" "$?" "2"
fc set breakdownRows 500; check "out of range: exit 2" "$?" "2"
fc set layout tiles; check "not an option: exit 2" "$?" "2"
fc set guardAttribution maybe; check "not a boolean: exit 2" "$?" "2"
fc set sections "plan, sesions"; check "a misspelt section: exit 2" "$?" "2"
fc set notifyOn none; check "notifyOn none is a valid list" "$?" "0"
fc unset notifyOn
fc get; check "usage: exit 2" "$?" "2"
fc workflow; check "workflow is not a command: exit 2" "$?" "2"
fc claude-restore '{"model":null}'; check "claude-restore is not a command: exit 2" "$?" "2"
fc get constructor; check "an inherited name is unknown: exit 2" "$?" "2"
fc unset toString; check "unset of an inherited name: exit 2" "$?" "2"
check "refusals change nothing" "$(cat "$FILE")" "$before"

# --- a file that is not JSON is refused, not overwritten ---
printf 'not json' > "$FILE"
fc set breakdownRows 4; check "bad file: exit 1" "$?" "1"
check "bad file kept" "$(cat "$FILE")" "not json"

# --- one-time import ---
fresh b
mkdir -p "$HOME/.claude" "$HOME/.dr-superpowers"
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"layout":"compact","notifyAfter":60,"breakdownRows":"x"}}}}' > "$HOME/.claude/settings.json"
printf '%s' '{"darkmem":{"url":"http://d.test","api_key_env":"DM_KEY","repos":{"/r":{"project":"p"}}}}' > "$HOME/.dr-superpowers/config.json"
fc get layout > /dev/null
DM='{"url":"http://d.test","api_key_env":"DM_KEY","repos":{"/r":{"project":"p"}}}'
check "import: options only, not the pre-2.0 home" "$(node -e 'const v = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); console.log(JSON.stringify(v))' "$FILE")" '{"layout":"compact"}'
printf '{"layout":"compact","darkmem":%s}\n' "$DM" > "$FILE"
fc set breakdownRows 4
fc unset breakdownRows
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
printf '%s' '{"pluginConfigs":{"dr-cockpit@darkraise":{"options":{"layout":"full","breakdownRows":4}}}}' > "$TMP/c2/settings.json"
CLAUDE_CONFIG_DIR="$TMP/c1" bash "$CMD" get layout > /dev/null 2>&1 &
p1=$!
CLAUDE_CONFIG_DIR="$TMP/c2" bash "$CMD" get layout > /dev/null 2>&1 &
p2=$!
wait "$p1" "$p2"
case $(tr -d ' \n' < "$FILE") in '{"layout":"compact"}'|'{"layout":"full","breakdownRows":4}') whole=yes ;; *) whole=no ;; esac
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
slow_set notifyDetail brief &
p2=$!
wait "$p1" "$p2"
check "concurrent setters: both keys kept" "$(fc get notifyAfter) $(fc get notifyDetail)" "120 brief"

# --- run through a symbolic link to the scripts directory, it still runs ---
fresh linked
ln -s "$(cd "$HERE/../scripts" && pwd)" "$TMP/linked-scripts"
check "through a linked directory: get answers" "$(node "$TMP/linked-scripts/lib/dforge-config.mjs" get breakdownRows 2>&1)" "6"

# --- the darkmem store keys: defaults and refusals ---
# Each key: its default, a value it accepts, and one it refuses.
while read -r key default valid invalid; do
  fresh "m-$key"
  check "$key: default" "$(fc get "$key")" "$default"
  fc set "$key" "$valid"; check "$key: a valid value: exit 0" "$?" "0"
  check "$key: the value is read back" "$(fc get "$key")" "$valid"
  fc set "$key" "$invalid"; check "$key: an invalid value: exit 2" "$?" "2"
  check "$key: a refusal keeps the value" "$(fc get "$key")" "$valid"
done <<'ROWS'
documentStore darkmem local remote
progressSource darkmem local remote
ROWS

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
check "claude: get --json carries both" "$(fc get --json | node -e 'const v = JSON.parse(require("fs").readFileSync(0, "utf8")); console.log(v.autoCompactWindow, v.autoCompactEnabled, v.breakdownRows)')" "0 true 6"

# A file that cannot be parsed is never replaced, and the dforge keys still resolve.
printf 'not json' > "$CS"
fc set autoCompactWindow 800000; check "claude: an unparseable file: exit 1" "$?" "1"
check "claude: an unparseable file is left byte-identical" "$(cat "$CS")" "not json"
check "claude: the file is named" "$(grep -c 'settings.json is not valid JSON' "$TMP/stderr")" "1"
check "claude: dforge keys still resolve" "$(fc get breakdownRows)" "6"
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
    import { pathToFileURL } from "node:url";
    const { main } = await import(pathToFileURL(process.env.DFORGE_CONFIG_MJS).href);
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

# Git Bash with path conversion off hands node the module path as written.
fresh y
fc set layout full
check "the command runs with path conversion off" "$(MSYS_NO_PATHCONV=1 fc get layout)" "full"
# A number setting is a whole number.
fc set notifyAfter 5.5; check "a fraction: exit 2" "$?" "2"

# --- a file an earlier release wrote loads with no warning ---
# Keys that no longer exist are ignored, and a list naming a retired item
# (run on a band line; blocked, budget or task among the events) is accepted:
# the cockpit drops the name when it reads the list.
fresh stale
mkdir -p "$HOME/.dforge"
printf '%s\n' '{"handoffTokens":300000,"handoffMode":"relaxed","warnAt":70,"nudgeModel":false,"codexLane":false,"lensCap":2,"executionMode":"inline","worktree":"always","autoRun":"off","processBias":"lighter","fastMode":"off","specReview":false,"finishAction":"merge","finishTimeout":45,"bandLine1":"dir,run,git","bandLine2":"run","notifyOn":"ask,blocked,budget,task","layout":"compact"}' > "$FILE"
json=$(fc get --json); code=$?
check "stale file: get --json exits 0" "$code" "0"
check "stale file: no warning" "$(cat "$TMP/stderr")" ""
check "stale file: removed keys are not read" "$(node -e 'const v = JSON.parse(process.argv[1]); console.log(["handoffTokens", "handoffMode", "warnAt", "nudgeModel", "codexLane", "lensCap", "executionMode", "worktree", "autoRun", "processBias", "fastMode", "specReview", "finishAction", "finishTimeout"].filter(key => key in v).join(",") || "none")' "$json")" "none"
check "stale file: the kept keys are read" "$(node -e 'const v = JSON.parse(process.argv[1]); console.log(v.layout, v.bandLine1, v.bandLine2, v.notifyOn)' "$json")" "compact dir,run,git run ask,blocked,budget,task"
fc get bandLine1 > /dev/null; check "stale file: a band line naming run: exit 0" "$?" "0"
check "stale file: and no warning" "$(cat "$TMP/stderr")" ""
fc get notifyOn > /dev/null; check "stale file: events naming retired kinds: exit 0" "$?" "0"
check "stale file: and no warning" "$(cat "$TMP/stderr")" ""
fc get finishAction > /dev/null 2>&1; check "stale file: naming a removed key is an error: exit 2" "$?" "2"
check "stale file: the environment variable of a removed key is ignored" "$(DFORGE_BUDGET=400000 fc get --json > /dev/null; cat "$TMP/stderr")" ""
fc set notifyDetail brief
check "stale file: a save keeps the stale keys untouched" "$(node -e 'const v = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); console.log(v.handoffTokens, v.finishAction, v.notifyDetail)' "$FILE")" "300000 merge brief"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
