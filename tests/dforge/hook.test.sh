#!/usr/bin/env bash
# The SessionStart hook must inject the using-dforge entry point in the
# Claude Code JSON shape, persist the session record keyed by sanitized cwd and
# by session id, tolerate malformed stdin (inject anyway, persist nothing), and
# always exit 0.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../plugins/dforge/scripts/session-start.sh"
HOOKS="$HERE/../../plugins/dforge/hooks/hooks.json"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
export WORKFLOW_GUARD_CLAUDE_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_MANAGED_DIR="$TMP/workflow-guard" WORKFLOW_GUARD_PROJECT_DIR="$TMP/workflow-guard"
trap 'rm -rf "$TMP"' EXIT
unset CLAUDE_CODE_SESSION_ID AR_SESSION

payload() {
  MSYS_NO_PATHCONV=1 jq -n --arg tp '/tmp/fake-transcript.jsonl' --arg cwd 'D:\repo\example' \
    '{hook_event_name:"SessionStart",session_id:"s-123",transcript_path:$tp,cwd:$cwd,source:"startup"}'
}

# --- well-formed stdin ---
HOME_A="$TMP/a"; mkdir -p "$HOME_A"
out=$(payload | HOME="$HOME_A" bash "$SCRIPT" 2>/dev/null)
status=$?
check "well-formed: exits 0" "$status" "0"
check "well-formed: emits valid JSON" \
  "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
check "well-formed: event name is SessionStart" \
  "$(jq -r '.hookSpecificOutput.hookEventName // "MISSING"' <<<"$out" 2>/dev/null)" "SessionStart"
check "well-formed: names the plugin root" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c '^Plugin root: ')" "1"
check "well-formed: the plugin root line states the working-directory contract" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c ' — call scripts by this path, with the working directory inside the project$')" "1"
check "well-formed: additionalContext is non-empty" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"
check "well-formed: context names the entry-point skill" \
  "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out" 2>/dev/null | grep -c 'dforge:using-dforge')" "1"
check "well-formed: emits no permissionDecision" \
  "$(jq -r '.hookSpecificOutput.permissionDecision // "ABSENT"' <<<"$out" 2>/dev/null)" "ABSENT"

RECORD="$HOME_A/.claude/dforge/sessions/D--repo-example.json"
check "well-formed: persists the session record" "$([ -f "$RECORD" ] && echo yes || echo no)" "yes"
check "record: transcript_path" \
  "$(jq -r '.transcript_path // "MISSING"' "$RECORD" 2>/dev/null)" "/tmp/fake-transcript.jsonl"
check "record: session_id" "$(jq -r '.session_id // "MISSING"' "$RECORD" 2>/dev/null)" "s-123"
check "record: source" "$(jq -r '.source // "MISSING"' "$RECORD" 2>/dev/null)" "startup"
check "record: cwd" "$(jq -r '.cwd // "MISSING"' "$RECORD" 2>/dev/null)" 'D:\repo\example'

# --- a second session in the same cwd ---
# The cwd record is last writer wins; each session keeps a record of its own.
MSYS_NO_PATHCONV=1 jq -n --arg tp '/tmp/second-transcript.jsonl' --arg cwd 'D:\repo\example' \
  '{hook_event_name:"SessionStart",session_id:"s-456",transcript_path:$tp,cwd:$cwd,source:"startup"}' \
  | HOME="$HOME_A" bash "$SCRIPT" >/dev/null 2>&1
BYID="$HOME_A/.claude/dforge/sessions/by-id"
check "shared cwd: the cwd record names the later session" "$(jq -r '.session_id' "$RECORD" 2>/dev/null)" "s-456"
check "shared cwd: the first session keeps its own record" \
  "$(jq -r '.transcript_path' "$BYID/s-123.json" 2>/dev/null)" "/tmp/fake-transcript.jsonl"
check "shared cwd: the second session has its own record" \
  "$(jq -r '.transcript_path' "$BYID/s-456.json" 2>/dev/null)" "/tmp/second-transcript.jsonl"

# --- a native jq ends its output lines with CR (Git Bash): the hook strips it ---
CRJQ="$TMP/crjq"; mkdir -p "$CRJQ"
cat > "$CRJQ/jq" <<CRJQ_EOF
#!/usr/bin/env bash
"$(command -v jq)" "\$@" | sed 's/\$/\r/'
exit "\${PIPESTATUS[0]}"
CRJQ_EOF
chmod +x "$CRJQ/jq"
HOME_CR="$TMP/cr"; mkdir -p "$HOME_CR"
MSYS_NO_PATHCONV=1 jq -n --arg tp /tmp/cr-transcript.jsonl --arg cwd "$TMP" \
  '{hook_event_name:"SessionStart",session_id:"s-cr",transcript_path:$tp,cwd:$cwd,source:"startup"}' \
  | PATH="$CRJQ:$PATH" HOME="$HOME_CR" bash "$SCRIPT" >/dev/null 2>&1
check "a jq that ends lines with CR: session-start keys its records by the clean id" \
  "$([ -f "$HOME_CR/.claude/dforge/sessions/by-id/s-cr.json" ] && echo yes || echo no)|$([ -f "$HOME_CR/.claude/dforge/sessions/turns/s-cr.since" ] && echo yes || echo no)" "yes|yes"

# --- records a month old are pruned; the session's own and recent ones stay ---
printf '{}\n' > "$BYID/s-old.json"
printf '{}\n' > "$HOME_A/.claude/dforge/sessions/D--gone-worktree.json"
touch -d '40 days ago' "$BYID/s-old.json" "$HOME_A/.claude/dforge/sessions/D--gone-worktree.json" "$BYID/s-123.json"
payload | HOME="$HOME_A" bash "$SCRIPT" >/dev/null 2>&1
check "prune: an old session record is removed" "$([ -e "$BYID/s-old.json" ] && echo yes || echo no)" "no"
check "prune: an old checkout record is removed" "$([ -e "$HOME_A/.claude/dforge/sessions/D--gone-worktree.json" ] && echo yes || echo no)" "no"
check "prune: the starting session's record is rewritten, not removed" "$(jq -r '.session_id' "$BYID/s-123.json" 2>/dev/null)" "s-123"
check "prune: a recent record stays" "$([ -e "$BYID/s-456.json" ] && echo yes || echo no)" "yes"

# --- malformed stdin ---
HOME_B="$TMP/b"; mkdir -p "$HOME_B"
out=$(printf 'not json' | HOME="$HOME_B" bash "$SCRIPT" 2>/dev/null)
status=$?
check "malformed: exits 0" "$status" "0"
check "malformed: still injects the entry point" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"
check "malformed: persists nothing" \
  "$([ -d "$HOME_B/.claude" ] && echo yes || echo no)" "no"

# --- empty stdin ---
HOME_C="$TMP/c"; mkdir -p "$HOME_C"
out=$(printf '' | HOME="$HOME_C" bash "$SCRIPT" 2>/dev/null)
status=$?
check "empty: exits 0" "$status" "0"
check "empty: still injects the entry point" \
  "$(jq -r '(.hookSpecificOutput.additionalContext // "") | length > 0' <<<"$out" 2>/dev/null)" "true"

# --- compact source: the snapshot follows the entry point ---
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
REPO="$TMP/repo"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
mkdir -p "$REPO/.dforge/handoff"
# The compacted session's own handoff: its marker names the session (s-9).
printf '# Handoff\n\n## Next session\n\n**Next:** Resume at Task 4 (Four).\n<!-- next-step: kind=adhoc session=s-9 done=0 closed=0 subject=- at=%s -->\n' "$(date +%s)" > "$REPO/.dforge/handoff/adhoc-s9000000.md"
TR="$TMP/transcript.jsonl"
MSYS_NO_PATHCONV=1 jq -cn '{type:"user",isSidechain:false,origin:{kind:"human"},message:{role:"user",content:"keep the API stable"}}' > "$TR"
compact_payload() {
  MSYS_NO_PATHCONV=1 jq -n --arg tp "$TR" --arg cwd "$REPO" \
    '{hook_event_name:"SessionStart",session_id:"s-9",transcript_path:$tp,cwd:$cwd,source:"compact"}'
}
HOME_D="$TMP/d"; mkdir -p "$HOME_D"
out=$(compact_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
status=$?
ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$out" 2>/dev/null)
check "compact: exits 0" "$status" "0"
check "compact: emits valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$out" && echo yes || echo no)" "yes"
check "compact: entry point still injected" "$(grep -c 'dforge:using-dforge' <<<"$ctx")" "1"
check "compact: snapshot appended" "$(grep -c '^## Compaction snapshot' <<<"$ctx")" "1"
check "compact: carries the handoff next step" "$(grep -c 'Resume at Task 4 (Four)' <<<"$ctx")" "1"
check "compact: carries the owner prompt" "$(grep -c 'keep the API stable' <<<"$ctx")" "1"
check "compact: under the 10,000-character hook cap" "$([ "${#ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
check "an existing state directory ignores itself" "$(git -C "$REPO" status --porcelain --untracked-files=all -- .dforge)" ""
BARE="$TMP/bare-repo"
git init -q -b main "$BARE"
MSYS_NO_PATHCONV=1 jq -n --arg cwd "$BARE" '{hook_event_name:"SessionStart",session_id:"s-10",transcript_path:"",cwd:$cwd,source:"startup"}' \
  | HOME="$HOME_D" bash "$SCRIPT" >/dev/null 2>&1
check "a checkout without a state directory gains none" "$([ -e "$BARE/.dforge" ] && echo yes || echo no)" "no"
LINKED="$TMP/linked-repo"
git init -q -b main "$LINKED"
mkdir -p "$LINKED/.dforge" "$TMP/outside"
ln -s "$TMP/outside/planted" "$LINKED/.dforge/.gitignore"
MSYS_NO_PATHCONV=1 jq -n --arg cwd "$LINKED" '{hook_event_name:"SessionStart",session_id:"s-11",transcript_path:"",cwd:$cwd,source:"startup"}' \
  | HOME="$HOME_D" bash "$SCRIPT" >/dev/null 2>&1
check "the state ignore is never written through a link" "$([ -e "$TMP/outside/planted" ] && echo yes || echo no)" "no"
startup_ctx=$(payload | HOME="$HOME_A" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "startup: no snapshot" "$(grep -c '^## Compaction snapshot' <<<"$startup_ctx")" "0"

# A prompt holding pasted terminal output carries raw C0 controls; JSON forbids
# them unescaped inside a string, so the hook must not emit them.
MSYS_NO_PATHCONV=1 jq -cn --arg c "$(printf 'red \033[31malert\033[0m done')" \
  '{type:"user",isSidechain:false,origin:{kind:"human"},message:{role:"user",content:$c}}' > "$TR"
esc_out=$(compact_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
check "compact: control bytes keep the output valid JSON" \
  "$(jq -e . >/dev/null 2>&1 <<<"$esc_out" && echo yes || echo no)" "yes"
check "compact: control bytes stripped from the context" \
  "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$esc_out" 2>/dev/null | grep -c $'\033')" "0"

# --- a roadmap project: its position rides in every session ---
mkdir -p "$REPO/docs/dforge/registers" "$REPO/docs/dforge/specs"
: > "$REPO/docs/dforge/specs/shop-design.md"
printf '# M1 — item register\n\n**Source:** roadmap\n**Covers:** docs/superpowers/specs/shop-design.md\n\n| # | Item | Assigned | Acceptance | State | Note |\n|---|---|---|---|---|---|\n| 1 | Billing | - | - | done | - |\n| 2 | Search | - | - | open | - |\n' \
  > "$REPO/docs/dforge/registers/m1.md"
printf '# Shop — roadmap\n\n**Product:** a shop\n**Spec:** docs/superpowers/specs/shop-design.md\n\n| M | Name | Exit criteria | Register | State | Note |\n|---|---|---|---|---|---|\n| M1 | MVP | every epic resolved | docs/superpowers/registers/m1.md | open | - |\n' \
  > "$REPO/docs/dforge/roadmap.md"
startup_payload() {
  MSYS_NO_PATHCONV=1 jq -n --arg tp "$TR" --arg cwd "$REPO" \
    '{hook_event_name:"SessionStart",session_id:"s-10",transcript_path:$tp,cwd:$cwd,source:"startup"}'
}
rm_out=$(startup_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
check "roadmap: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$rm_out" && echo yes || echo no)" "yes"
check "roadmap: the position is injected" \
  "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$rm_out" | grep -c '^Roadmap: M1 MVP, 1 of 2 epics resolved, open: #2 Search\.')" "1"
rm_ctx=$(compact_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "roadmap: survives compaction alongside the snapshot" "$(grep -c '^Roadmap: M1 MVP' <<<"$rm_ctx")" "1"
check "roadmap: still under the 10,000-character hook cap" "$([ "${#rm_ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
check "no roadmap: nothing injected" "$(grep -c '^Roadmap:' <<<"$startup_ctx")" "0"

# --- the compaction snapshot shows only the session's handoff ---
git -C "$REPO" worktree add -q -b hc "$TMP/hc"; mkdir -p "$TMP/hc/.dforge/handoff"
printf '# Handoff\n\n## Next session\n\n**Next:** hc next\n<!-- next-step: kind=adhoc session=s-hc done=0 closed=0 subject=- at=%s -->\n' "$(date +%s)" > "$TMP/hc/.dforge/handoff/adhoc-0c000000.md"
hc_compact=$(compact_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "the compaction snapshot shows only the session's handoff" "$(grep -c 'hc next' <<<"$hc_compact"):$(grep -c 'Resume at Task 4 (Four)' <<<"$hc_compact")" "0:1"
git -C "$REPO" worktree remove --force "$TMP/hc"

# --- open_handoffs_count (spec A10): unclaimed or gone-claimed handoffs younger
# than three days, in every checkout, counted on every source; none deleted ---
OC="$TMP/oc"; git init -q -b main "$OC"; git -C "$OC" commit -q --allow-empty -m init
OC=$(git -C "$OC" rev-parse --show-toplevel)
git -C "$OC" worktree add -q -b ocw "$TMP/ocw"; OCW=$(git -C "$TMP/ocw" rev-parse --show-toplevel)
mkdir -p "$OC/.dforge/handoff/claims" "$OC/docs/dforge/plans" "$OCW/.dforge/handoff"
och() { # och <file> <kind> <subject>
  printf '# Handoff\n\n## Next session\n\n**Next:** n\n<!-- next-step: kind=%s key=%s session=- done=0 closed=0 subject=%s at=%s -->\n' \
    "$2" "$(basename "$1" .md)" "$3" "$(date +%s)" > "$1"
}
och "$OC/.dforge/handoff/adhoc-0000000a.md" adhoc -
och "$OCW/.dforge/handoff/adhoc-0000000b.md" adhoc -
och "$OC/.dforge/handoff/adhoc-0000000c.md" adhoc -
printf 'session=s-live\nat=%s\n' "$(date +%s)" > "$OC/.dforge/handoff/claims/adhoc-0000000c"
mkdir -p "$HOME_D/.claude/dforge/sessions/cockpit"; date +%s > "$HOME_D/.claude/dforge/sessions/cockpit/s-live"
printf '# Completed plans\n\n- 2026-11-01 — `docs/dforge/plans/2026-11-01-old.md` — merged\n' > "$OC/docs/dforge/plans/completed.md"
och "$OC/.dforge/handoff/2026-11-01-old.md" plan docs/dforge/plans/2026-11-01-old.md
touch -d '4 days ago' "$OC/.dforge/handoff/2026-11-01-old.md"
oc_before=$(cd "$OC" && find .dforge/handoff "$OCW/.dforge/handoff" -name '*.md' | sort)
oc_payload() { # oc_payload <source>
  MSYS_NO_PATHCONV=1 jq -n --arg tp "$TR" --arg cwd "$OC" --arg src "$1" \
    '{hook_event_name:"SessionStart",session_id:"s-oc",transcript_path:$tp,cwd:$cwd,source:$src}'
}
for src in startup compact; do
  oc_ctx=$(oc_payload "$src" | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
  check "A10 count: $src counts two open handoffs" "$(grep -c '^2 open handoffs [(]scripts/repo-audit lists them)\.$' <<<"$oc_ctx")" "1"
done
check "A10 count: no handoff is deleted" "$(cd "$OC" && find .dforge/handoff "$OCW/.dforge/handoff" -name '*.md' | sort)" "$oc_before"
printf 'session=s-gone\nat=%s\n' "$(date +%s)" > "$OC/.dforge/handoff/claims/adhoc-0000000a"
oc_ctx=$(oc_payload startup | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "A10 count: a gone session's claim still counts" "$(grep -c '^2 open handoffs ' <<<"$oc_ctx")" "1"
touch -d '4 days ago' "$OC/.dforge/handoff/adhoc-0000000a.md" "$OCW/.dforge/handoff/adhoc-0000000b.md"
oc_ctx=$(oc_payload startup | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "A10 count: no line when none is open" "$(grep -c 'open handoffs' <<<"$oc_ctx")" "0"
git -C "$OC" worktree remove --force "$OCW"

# --- an older directory left behind is named, with the skill that moves it ---
check "4.0 layout: no migration line" "$(grep -c 'still uses an older layout' <<<"$rm_ctx")" "0"
mkdir -p "$REPO/.superpowers"
lg_out=$(startup_payload | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null)
check "older layout: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$lg_out" && echo yes || echo no)" "yes"
check "older layout: the migration line is injected" \
  "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$lg_out" | grep -cF "dforge: this repository still uses an older layout ($(git -C "$REPO" rev-parse --show-toplevel)/.superpowers); run the dforge:migrate skill (/dforge:migrate)")" "1"
rm -rf "$REPO/.superpowers"

# --- a latest.md an older plugin wrote is named, with its subject and the migrate skill ---
mkdir -p "$TMP/lh/.dforge/handoff"
git init -q -b main "$TMP/lh"
printf '# Handoff\n<!-- next-step: kind=plan session=- done=0 closed=0 subject=docs/dforge/plans/old.md at=1 -->\n' > "$TMP/lh/.dforge/handoff/latest.md"
lh_ctx=$(MSYS_NO_PATHCONV=1 jq -n --arg cwd "$TMP/lh" '{hook_event_name:"SessionStart",session_id:"s-lh",cwd:$cwd,source:"startup"}' \
  | HOME="$HOME_D" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
check "older layout notice: session start names a remaining latest.md with its subject" \
  "$(grep -cxF "dforge: $(git -C "$TMP/lh" rev-parse --show-toplevel)/.dforge/handoff/latest.md is a handoff in an older layout (subject docs/dforge/plans/old.md); run the dforge:migrate skill (/dforge:migrate)" <<<"$lh_ctx")" "1"

# --- workflow settings ride in every session as one line ---
if command -v node >/dev/null 2>&1; then
  HOME_S="$TMP/s"; mkdir -p "$HOME_S/.dforge"
  s_ctx=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
  check "settings: nothing injected at the defaults" "$(grep -c '^dforge settings in force' <<<"$s_ctx")" "0"
  # The line reads only config.json, so with none there is no node start for it.
  mkdir -p "$TMP/node-log"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> %q\nexec %q "$@"\n' "$TMP/node-log/calls" "$(command -v node)" > "$TMP/node-log/node"
  chmod +x "$TMP/node-log/node"
  payload | HOME="$HOME_S" PATH="$TMP/node-log:$PATH" bash "$SCRIPT" >/dev/null 2>&1
  check "settings: no config.json starts no node for the line" "$(grep -c 'dforge-config.mjs' "$TMP/node-log/calls")" "0"
  check "settings: every key the line reads lives in config.json" \
    "$(cd "$HERE/../../plugins/dforge" && node --input-type=module -e "const S = (await import('./config/schema.mjs')).default; console.log(Object.values(S).filter(s => s.enforcedBy === 'skill').flatMap(s => [s, ...(s.inertWhen ? [S[s.inertWhen.key]] : [])]).every(s => s.target === 'dforge' && s.env === undefined))")" "true"
  printf '{"worktree":"always","processBias":"lighter","codexReview":false}\n' > "$HOME_S/.dforge/config.json"
  s_out=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null)
  check "settings: output stays valid JSON" "$(jq -e . >/dev/null 2>&1 <<<"$s_out" && echo yes || echo no)" "yes"
  check "settings: the changed skill keys are injected" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c '^dforge settings in force (each replaces the matching question or default in the skills): worktree=always; processBias=lighter$')" "1"
  s_ctx=$(compact_payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""')
  check "settings: the line survives compaction" "$(grep -c '^dforge settings in force' <<<"$s_ctx")" "1"
  check "settings: still under the 10,000-character hook cap" "$([ "${#s_ctx}" -lt 10000 ] && echo yes || echo no)" "yes"
  printf 'not json' > "$HOME_S/.dforge/config.json"
  s_out=$(payload | HOME="$HOME_S" bash "$SCRIPT" 2>/dev/null); status=$?
  check "settings: a broken file still exits 0" "$status" "0"
  check "settings: a broken file injects no line" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c '^dforge settings in force')" "0"
  check "settings: a broken file injects its problem line" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c '^dforge: .*config.json is not a JSON object')" "1"
  check "settings: a broken file keeps the entry point" \
    "$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$s_out" | grep -c 'dforge:using-dforge')" "1"
fi

# --- hooks.json wiring ---
check "hooks.json is valid JSON" \
  "$(jq -e . "$HOOKS" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "hooks.json registers SessionStart with the full matcher" \
  "$(jq -r '.hooks.SessionStart[0].matcher // "MISSING"' "$HOOKS" 2>/dev/null)" "startup|resume|clear|compact|fork"
check "hooks.json is synchronous" \
  "$(jq -r '.hooks.SessionStart[0].hooks[0].async // false' "$HOOKS" 2>/dev/null)" "false"
check "hooks.json forces the bash interpreter" \
  "$(jq -r '.hooks.SessionStart[0].hooks[0].shell // "MISSING"' "$HOOKS" 2>/dev/null)" "bash"
check "hooks.json has no PreToolUse entry" \
  "$(jq -r 'if .hooks.PreToolUse then "present" else "ABSENT" end' "$HOOKS" 2>/dev/null)" "ABSENT"
check "session-start.sh parses" \
  "$(bash -n "$SCRIPT" 2>/dev/null && echo yes || echo no)" "yes"

# The entry point rides in every session's baseline and shares the hook's
# 10,000-character cap with the compaction snapshot; 5,500 bytes leaves the
# snapshot about 4,500.
check "entry point is at most 5,500 bytes" \
  "$([ "$(wc -c < "$HERE/../../plugins/dforge/skills/using-dforge/SKILL.md")" -le 5500 ] && echo yes || echo no)" "yes"

# --- no node while darkmem is applied: one warning per session (row 15, A13) ---
. "$HERE/fixtures/darkmem-stores.sh"
nonode_path() { # PATH with no node: a directory holding node is dropped, or, when it holds git or jq too, stood in for by links to its other programs
  local d f m out='' IFS=:
  for d in $PATH; do
    if [ -x "$d/node" ] || [ -x "$d/node.exe" ]; then
      [ -x "$d/git" ] || [ -x "$d/git.exe" ] || [ -x "$d/jq" ] || [ -x "$d/jq.exe" ] || continue
      m="$TMP/nonode/$(printf '%s' "$d" | tr -c 'A-Za-z0-9' '_')"
      mkdir -p "$m"
      for f in "$d"/*; do case ${f##*/} in node | node.exe) ;; *) ln -s "$f" "$m/" 2>/dev/null ;; esac; done
      d=$m
    fi
    out=${out:+$out:}$d
  done
  printf '%s\n' "$out"
}
NN_PATH=$(nonode_path)
NN_REPO="$TMP/nn-repo"; git init -q "$NN_REPO"
HOME_N="$TMP/nn-home"; mkdir -p "$HOME_N"
stores_home "$HOME_N" "$NN_REPO" proj local darkmem > /dev/null
nn_ctx() { # nn_ctx <source> — the additionalContext of one start of session s-nn
  MSYS_NO_PATHCONV=1 jq -n --arg cwd "$NN_REPO" --arg src "$1" \
    '{hook_event_name:"SessionStart",session_id:"s-nn",transcript_path:"",cwd:$cwd,source:$src}' \
    | HOME="$HOME_N" PATH="$NN_PATH" bash "$SCRIPT" 2>/dev/null | jq -r '.hookSpecificOutput.additionalContext // ""'
}
if PATH="$NN_PATH" command -v node >/dev/null 2>&1 || ! PATH="$NN_PATH" command -v git >/dev/null 2>&1 \
   || ! PATH="$NN_PATH" command -v jq >/dev/null 2>&1; then
  printf 'skip - no node at session start: node shares a PATH directory with git or jq here\n'
else
  check "no node: the first start warns once" "$(nn_ctx startup | grep -c 'node is required while darkmem stores are applied')" "1"
  check "no node: a later start of the same session does not repeat it" "$(nn_ctx resume | grep -c 'node is required while darkmem stores are applied')" "0"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
