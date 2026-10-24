#!/usr/bin/env bash
# The ui-ux hooks: after an edit to a UI file, PostToolUse returns ui-lint's
# findings and names dforge:ui-ux once per session; at a stop, a turn that
# leaves UI changes without a passing proof is held once.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EDIT="$HERE/../scripts/ui-edit-hook.sh"
HOOKS="$HERE/../hooks/hooks.json"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION DFORGE_BUDGET CLAUDE_PROJECT_DIR

REPO="$TMP/repo"
git init -q "$REPO"
cd "$REPO" || exit 1
git config user.email t@example.com && git config user.name t
mkdir -p src
printf 'export const App = () => <main>Hi</main>;\n' > src/App.tsx
printf '# readme\n' > README.md
git add . && git commit -q -m base

edit() { # edit <session> <file> [transcript]
  jq -n --arg sid "$1" --arg cwd "$REPO" --arg f "$2" --arg tp "${3:-}" \
    '{hook_event_name:"PostToolUse",session_id:$sid,cwd:$cwd,transcript_path:$tp,tool_name:"Edit",tool_input:{file_path:$f}}' | bash "$EDIT"
}
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$1" 2>/dev/null; }

# --- PostToolUse ---
check "edit: a non-UI file prints nothing" "$(edit e-1 "$REPO/README.md")" ""
out=$(edit e-1 "$REPO/src/App.tsx")
check "edit: the first UI edit names the skill" "$(ctx "$out" | grep -c 'Load dforge:ui-ux')" "1"
check "edit: the event name" "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" "PostToolUse"
check "edit: never a decision" "$(jq -r '.decision // "none"' <<<"$out")" "none"
check "edit: a clean UI file after the reminder prints nothing" "$(edit e-1 "$REPO/src/App.tsx")" ""
printf '<img src="a.png">\n' > src/Bad.tsx
out=$(edit e-1 "$REPO/src/Bad.tsx")
check "edit: lint findings name the rule and line" "$(ctx "$out" | grep -c 'src/Bad.tsx:1: img-alt')" "1"
check "edit: no second reminder" "$(ctx "$out" | grep -c 'Load dforge:ui-ux')" "0"
TR="$TMP/skill.jsonl"
jq -nc '{type:"assistant",message:{content:[{type:"tool_use",name:"Skill",input:{skill:"dforge:ui-ux"}}]}}' > "$TR"
check "edit: a session that loaded the skill gets no reminder" "$(edit e-2 "$REPO/src/App.tsx" "$TR")" ""
check "edit: a relative path resolves against cwd" "$(ctx "$(edit e-3 src/Bad.tsx)" | grep -c 'img-alt')" "1"
check "edit: malformed stdin exits 0 silently" "$(printf 'nope' | bash "$EDIT"; echo "exit $?")" "exit 0"
rm src/Bad.tsx

# --- hooks.json wiring ---
check "hooks.json registers the edit hook's matcher" "$(jq -r '.hooks.PostToolUse[0].matcher' "$HOOKS")" "Edit|Write|MultiEdit"
check "hooks.json runs ui-edit-hook.sh" "$(jq -r '.hooks.PostToolUse[0].hooks[0].command' "$HOOKS")" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/ui-edit-hook.sh"'
check "hooks.json: the edit hook is synchronous, bash, 30 s" \
  "$(jq -r '.hooks.PostToolUse[0].hooks[0] | [.async, .shell, .timeout] | map(tostring) | join(",")' "$HOOKS")" "false,bash,30"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
