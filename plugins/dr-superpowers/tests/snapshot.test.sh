#!/usr/bin/env bash
# The compaction snapshot must carry what compaction summaries drop — the
# handoff's next step, ledger tails and rulings, files the session edited, the
# owner's last prompts, background agent ids — and stay under its cap by
# dropping the least important sections first.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/snapshot.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n' "$1" "$3"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

TMP="$(mktemp -d)"
# MSYS_NO_PATHCONV is exported below so jq --arg values stay opaque, which
# also stops Git Bash converting a POSIX TMP for native git; hand git a
# mixed-form path it understands on every host.
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
unset DR_SUPERPOWERS_JQ

REPO="$TMP/repo"
git init -q -b main "$REPO"
printf '.superpowers/\n' > "$REPO/.gitignore"
git -C "$REPO" add -A && git -C "$REPO" commit -qm init
WT="$TMP/wt"
git -C "$REPO" worktree add -q -b feat "$WT"
mkdir -p "$WT/.superpowers/sdd/plan"
{
  printf '# SDD ledger — plan: docs/plan.md\n'
  printf 'Ruling: translated old -> new — legacy plugin name — none\n'
  printf 'Task 1: complete (commits a..b, review clean)\n'
  printf 'Task 2: Ruling: kept the retry — spec 4.2 — a second fix round\n'
  printf 'Task 2: fix round 1/5 (1 addressed, 1 open — x)\n'
} > "$WT/.superpowers/sdd/plan/progress.md"
mkdir -p "$REPO/.superpowers/handoff"
printf '# Handoff\n\n## State\nstate\n\n## Next session\n\n**Next:** Resume at Task 2 (Two).\n\n## Do not\nKeep out of the snapshot.\n' \
  > "$REPO/.superpowers/handoff/latest.md"

prompt() { jq -cn --arg c "$1" '{type:"user",isSidechain:false,origin:{kind:"human"},message:{role:"user",content:$c}}'; }
tool() { # tool <name> <path> [isSidechain]
  jq -cn --arg n "$1" --arg p "$2" --argjson s "${3:-false}" \
    '{type:"assistant",isSidechain:$s,message:{model:"m",content:[{type:"tool_use",id:"t",name:$n,input:{file_path:$p}}]}}'
}
agent_use() { jq -cn '{type:"assistant",isSidechain:false,message:{model:"m",content:[{type:"tool_use",id:"toolu_1",name:"Agent",input:{description:"Fable review"}}]}}'; }
agent_result() { jq -cn '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",tool_use_id:"toolu_1",content:[{type:"text",text:"Async agent launched.\nagentId: abc123 (internal)"}]}]}}'; }
meta() { jq -cn '{type:"user",isSidechain:false,isMeta:true,message:{role:"user",content:"<command-name>/clear</command-name>"}}'; }
summary() { jq -cn '{type:"user",isSidechain:false,isCompactSummary:true,message:{role:"user",content:"This session is being continued"}}'; }

T="$TMP/t.jsonl"
{
  prompt 'please keep the API stable'
  meta
  summary
  tool Edit /repo/a.sh
  tool Write /repo/b.md
  tool Edit /repo/c.txt
  tool Read /repo/d.md
  tool Edit /repo/side.sh true
  tool Edit /repo/a.sh
  agent_use
  agent_result
  prompt 'second prompt'
  prompt 'third prompt'
  prompt 'fourth prompt'
} > "$T"

out=$(snapshot_build "$T" "$REPO")
check "heading first" "$(sed -n 1p <<<"$out")" "## Compaction snapshot"
has "handoff next step" "$out" "**Next:** Resume at Task 2 (Two)."
lacks "handoff stops at the next section" "$out" "Keep out of the snapshot."
has "ledger last line" "$out" "Task 2: fix round 1/5 (1 addressed, 1 open — x)"
has "rulings heading" "$out" "Rulings (most recent 10):"
has "ruling line" "$out" "Task 2: Ruling: kept the retry — spec 4.2 — a second fix round"
has "files heading" "$out" "### Files edited by this session (most recent first)"
check "files: most recent first, unique" \
  "$(grep -A3 '^### Files edited' <<<"$out" | tail -n 3 | tr '\n' '|')" \
  "- \`/repo/a.sh\`|- \`/repo/c.txt\`|- \`/repo/b.md\`|"
lacks "files: sidechain edits excluded" "$out" "/repo/side.sh"
lacks "files: reads excluded" "$out" "/repo/d.md"
has "prompts: the latest" "$out" "- fourth prompt"
lacks "prompts: only the last three" "$out" "please keep the API stable"
lacks "prompts: meta entries excluded" "$out" "<command-name>"
lacks "prompts: the summary excluded" "$out" "This session is being continued"
has "agents: id and description" "$out" "- abc123 — Fable review"

# --- no jq: transcript sections skipped, the rest kept ---
out=$(DR_SUPERPOWERS_JQ=no-such-jq snapshot_build "$T" "$REPO")
has "no jq: ledger kept" "$out" "Task 2: fix round 1/5"
lacks "no jq: no transcript sections" "$out" "### Files edited"

# --- cap: sections dropped from 6 up to 3 until the snapshot fits ---
LONG=$(printf '%0400d' 0)
T2="$TMP/t2.jsonl"
{ for i in $(seq 1 20); do tool Edit "/repo/$i-$LONG"; done; agent_use; agent_result; prompt 'x'; } > "$T2"
out=$(snapshot_build "$T2" "$REPO")
check "cap: at most 5500 characters" "$([ "${#out}" -le 5500 ] && echo yes || echo no)" "yes"
check "cap: heading kept" "$(sed -n 1p <<<"$out")" "## Compaction snapshot"
has "cap: handoff kept" "$out" "Resume at Task 2 (Two)."
has "cap: ledger kept" "$out" "Task 2: fix round 1/5"
lacks "cap: oversized files section dropped" "$out" "### Files edited"
lacks "cap: agents dropped" "$out" "### Background agents"

# --- an explicit cap, as the hook passes when the entry point leaves less room ---
out=$(snapshot_build "$T" "$REPO" 1500)
check "explicit cap: at most 1500 characters" "$([ "${#out}" -le 1500 ] && echo yes || echo no)" "yes"
has "explicit cap: ledger kept" "$out" "Task 2: fix round 1/5"

# --- an oversized Next session block: s1+s2 alone still fits under cap ---
LONG_NEXT=$(printf '%08000d' 0)
printf '# Handoff\n\n## State\nstate\n\n## Next session\n\n**Next:** %s\n\n## Do not\nKeep out.\n' "$LONG_NEXT" \
  > "$REPO/.superpowers/handoff/latest.md"
out=$(snapshot_build "$T" "$REPO")
check "oversized handoff: at most 5500 characters" "$([ "${#out}" -le 5500 ] && echo yes || echo no)" "yes"
check "oversized handoff: heading kept" "$(sed -n 1p <<<"$out")" "## Compaction snapshot"

git -C "$REPO" worktree remove --force "$WT" >/dev/null 2>&1

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
