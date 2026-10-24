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

# --- Stop ---
END="$HERE/../scripts/ui-turn-end.sh"
START="$HERE/../scripts/turn-start.sh"
AR="$HERE/../scripts/auto-run"
prompt() { # prompt <session>
  jq -n --arg sid "$1" --arg cwd "$REPO" '{hook_event_name:"UserPromptSubmit",session_id:$sid,cwd:$cwd,prompt:"go"}' | bash "$START"
}
stop() { # stop <session> <last message> [stop_hook_active] [transcript]
  jq -n --arg sid "$1" --arg cwd "$REPO" --arg msg "$2" --argjson active "${3:-false}" --arg tp "${4:-}" \
    '{hook_event_name:"Stop",session_id:$sid,cwd:$cwd,transcript_path:$tp,stop_hook_active:$active,last_assistant_message:$msg}' | bash "$END"
}
decision() { jq -r '.decision // "none"' <<<"${1:-{\}}" 2>/dev/null || echo none; }

prompt s-1
printf '// change\n' >> src/App.tsx
git commit -q -am 'ui change'
check "stop: no profile and no skill run: passes" "$(stop s-1 'Done.')" ""

mkdir -p docs/dforge/ui-ux
printf '# UI profile\n\n**Platform:** web\n' > docs/dforge/ui-ux/profile.md
prompt s-2
printf '// change 2\n' >> src/App.tsx
git commit -q -am 'ui change 2'
out=$(stop s-2 'Done.')
check "stop: a committed UI change without proof is held" "$(decision "$out")" "block"
check "stop: the reason names the changed file" "$(jq -r .reason <<<"$out" | grep -c 'src/App.tsx')" "1"
check "stop: the reason names the pending line" "$(jq -r .reason <<<"$out" | grep -c 'UI proof: pending')" "1"
check "stop: tells the user why" "$(jq -r .systemMessage <<<"$out" | grep -c 'dforge held the stop')" "1"
check "stop: the user's message names the changed file" "$(jq -r .systemMessage <<<"$out" | grep -c 'src/App.tsx')" "1"
check "stop: the retry passes" "$(stop s-2 'Done.' true)" ""
check "stop: the pending line passes" "$(stop s-2 $'Done.\n\nUI proof: pending — no browser on this host')" ""
check "stop: a hyphen, backticks and trailing blank lines pass" "$(stop s-2 $'Done.\n`UI proof: pending - no browser`\n\n')" ""
check "stop: the pending line not at the end is held" \
  "$(decision "$(stop s-2 $'The hook asks for UI proof: pending — <why>.\n\nDone.')")" "block"
check "stop: the pending line with no reason is held" "$(decision "$(stop s-2 $'Done.\n\nUI proof: pending')")" "block"
check "stop: the pending line with an empty reason is held" "$(decision "$(stop s-2 $'Done.\n\nUI proof: pending —  ')")" "block"
prompt s-3
check "stop: a turn that changed no UI file passes" "$(stop s-3 'Done.')" ""

mv docs/dforge/ui-ux/profile.md "$TMP/profile.md"
prompt s-4
printf '// change 3\n' >> src/App.tsx
check "stop: no profile but the skill ran: held" "$(decision "$(stop s-4 'Done.' false "$TR")")" "block"
check "stop: no profile and no skill: passes" "$(stop s-4 'Done.')" ""
mv "$TMP/profile.md" docs/dforge/ui-ux/profile.md

mkdir -p "$HOME/.claude/dforge/sessions/cockpit"
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s-5"
(cd "$REPO" && bash "$AR" --session s-5 start --spec docs/s.md --register docs/r.md >/dev/null 2>&1)
prompt s-5
check "stop: an auto run bound to the session: passes" "$(stop s-5 'Done.')" ""
check "stop: another session in the checkout is still held" "$(decision "$(stop s-2 'Done.')")" "block"
check "stop: no stamp for the session: passes" "$(stop s-unknown 'Done.')" ""

UP="$HERE/../scripts/ui-proof"
prompt s-7
printf '// change 7\n' >> src/App.tsx
git commit -q -am 'ui change 7'
refs="$HOME/.claude/dforge/sessions/turns/s-7.refs"
sed 's/^[0-9a-f]\{40\}/0000000000000000000000000000000000000000/' "$refs" > "$refs.tmp" && mv "$refs.tmp" "$refs"
out=$(stop s-7 'Done.')
check "stop: a check that cannot run holds instead of passing" "$(decision "$out")" "block"
check "stop: the hold carries the check's own error" "$(jq -r .reason <<<"$out" | grep -c 'bad --base')" "1"

prompt s-6
printf '// change 6\n' >> src/App.tsx
git commit -q -am 'ui change 6'
PR=docs/dforge/ui-ux/proofs
mkdir -p "$PR" .dforge/ui-ux/t
printf '*\n' > .dforge/.gitignore
printf 'png' > .dforge/ui-ux/t/a.png
printf '# UI proof: t\n\n**Contract:** touch\n**Platform:** web\n**Evidence:** local\n\n## Delta\n\n**UI/UX depth:** touch — a fix\n\n- **UX-1** — the fix\n\n## Results\n\n| ID | Verdict | Evidence | Note |\n|---|---|---|---|\n| UX-1 | pass | .dforge/ui-ux/t/a.png | |\n' > "$PR/t.md"
bash "$UP" stamp "$PR/t.md" >/dev/null
fp=$(bash "$UP" fingerprint)
printf 'The proof holds.\n\nVerdict: ship %s\n' "$fp" > "$PR/t.judge.md"
printf '\n**Judge:** ship %s — %s/t.judge.md\n' "$fp" "$PR" >> "$PR/t.md"
check "stop: a passing proof releases the hold" "$(stop s-6 'Done.')" ""

check "hooks.json registers the UI Stop check once" \
  "$(jq -r '[.hooks.Stop[0].hooks[].command | select(contains("ui-turn-end.sh"))] | length' "$HOOKS")" "1"
check "hooks.json: the Stop check is synchronous, bash, 60 s" \
  "$(jq -r '.hooks.Stop[0].hooks[] | select(.command | contains("ui-turn-end.sh")) | [.async, .shell, .timeout] | map(tostring) | join(",")' "$HOOKS")" "false,bash,60"
check "hooks.json: turn-end.sh stays the first Stop hook" \
  "$(jq -r '.hooks.Stop[0].hooks[0].command' "$HOOKS")" 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/turn-end.sh"'
check "hooks.json: the description names the UI hooks" "$(jq -r .description "$HOOKS" | grep -c 'UI proof')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
