# Build the compaction snapshot: what a compaction summary drops that the next
# turn needs — the handoff's next step, ledger tails and rulings, files the
# session edited, the owner's last prompts, background agent ids. Sourced by
# scripts/session-start.sh on the compact source; defines functions only.
#
# Capped because hook output over 10,000 characters is replaced by a file
# reference, and the injected entry point already takes about 3,400.

SNAPSHOT_CAP=5500

snapshot_latest() { # CWD — the Next session block of the primary checkout's latest.md
  local common primary latest
  common=$(git -C "$1" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 0
  primary=$(git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null) || return 0
  latest="$primary/.superpowers/handoff/latest.md"
  [ -f "$latest" ] || return 0
  echo "### From \`$latest\`"
  tr -d '\r' < "$latest" | awk '/^## Next session/ { f = 1; next } f && /^## / { exit } f'
}

snapshot_ledgers() { # CWD — every worktree's ledgers: last 8 lines, last 10 rulings
  local wt ledger plan_rel rulings
  git -C "$1" worktree list --porcelain 2>/dev/null | tr -d '\r' | sed -n 's/^worktree //p' |
  while IFS= read -r wt; do
    for ledger in "$wt"/.superpowers/sdd/*/progress.md; do
      [ -f "$ledger" ] || continue
      plan_rel=$(head -n 1 "$ledger" | tr -d '\r' | sed -n 's/^# SDD ledger — plan: //p')
      echo "### Ledger \`$ledger\` (plan \`${plan_rel:-unknown}\`)"
      echo "Last lines:"
      tr -d '\r' < "$ledger" | grep -v '^[[:space:]]*$' | tail -n 8 | sed 's/^/    /'
      rulings=$(tr -d '\r' < "$ledger" | grep 'Ruling:' | tail -n 10)
      if [ -n "$rulings" ]; then
        echo "Rulings (most recent 10):"
        printf '%s\n' "$rulings" | sed 's/^/    /'
      fi
    done
  done
}

# FILE — sections 4-6 from the transcript's last 3000 lines, separated by
# @@4 / @@5 / @@6 marker lines.
snapshot_transcript_sections() {
  tail -n 3000 "$1" | tr -d '\r' | "${DR_SUPERPOWERS_JQ:-jq}" -R -r -n '
    [inputs | select(length > 0) | (try fromjson catch null) | objects
     | select((.isSidechain // false) == false)] as $e
    | ([$e[] | select(.type == "assistant") | .message.content[]?
        | select(type == "object" and .type == "tool_use"
                 and (.name == "Write" or .name == "Edit" or .name == "NotebookEdit"))
        | (.input.file_path // .input.notebook_path // empty)]
       | reverse | reduce .[] as $f ([]; if any(.[]; . == $f) then . else . + [$f] end)
       | .[:20]) as $files
    | ([$e[] | select(.type == "user" and ((.isCompactSummary // false) | not)
                      and ((.isMeta // false) | not)
                      and ((.message.content | type) == "string")
                      and ((.origin.kind // "") == "human"
                           or (.origin == null and (.message.content | startswith("<") | not))))
        | .message.content | gsub("\\s+"; " ") | .[:300]] | .[-3:]) as $prompts
    | ([$e[] | select(.type == "assistant") | .message.content[]?
        | select(type == "object" and .type == "tool_use" and .name == "Agent")
        | {key: .id, value: (.input.description // "")}] | from_entries) as $desc
    | ([$e[] | select(.type == "user") | .message.content | arrays | .[]
        | select(type == "object" and .type == "tool_result" and ($desc[.tool_use_id] != null))
        | . as $r
        | ([.content] | flatten | map(if type == "object" then (.text // "") else tostring end) | join(" "))
        | capture("agentId: (?<id>[A-Za-z0-9]+)")?
        | "\(.id) — \($desc[$r.tool_use_id])"] | .[-5:]) as $agents
    | "@@4",
      (if ($files | length) > 0
       then "### Files edited by this session (most recent first)", ($files[] | "- `\(.)`")
       else empty end),
      "@@5",
      (if ($prompts | length) > 0
       then "### The owner'"'"'s last prompts (verbatim, truncated)", ($prompts[] | "- \(.)")
       else empty end),
      "@@6",
      (if ($agents | length) > 0
       then "### Background agents (resume by id while still running)", ($agents[] | "- \(.)")
       else empty end)
  ' 2>/dev/null
}

# snapshot_build TRANSCRIPT CWD [CAP] — the markdown snapshot, at most CAP
# characters (default SNAPSHOT_CAP). Sections 6, 5, 4, 3 are dropped whole, in
# that order, until it fits; sections 1-2 are never dropped.
snapshot_build() {
  local tp=${1:-} cwd=${2:-$PWD} cap=${3:-$SNAPSHOT_CAP} s1 s2 s3 s4="" s5="" s6="" raw out part i
  s1='## Compaction snapshot

This session was just compacted. Trust this snapshot, the ledger and `git log`
over the summary above. If anything is unclear, run `scripts/repo-audit` from the
dr-superpowers plugin root; if the next budget line says `handoff`, run the
dr-superpowers handoff skill.'
  s2=$(snapshot_latest "$cwd")
  s3=$(snapshot_ledgers "$cwd")
  if [ -n "$tp" ] && command -v "${DR_SUPERPOWERS_JQ:-jq}" >/dev/null 2>&1; then
    if command -v cygpath >/dev/null 2>&1; then tp=$(cygpath -u "$tp"); fi
    if [ -f "$tp" ]; then
      raw=$(snapshot_transcript_sections "$tp")
      s4=$(printf '%s\n' "$raw" | awk '/^@@4$/ { f = 1; next } /^@@5$/ { f = 0 } f')
      s5=$(printf '%s\n' "$raw" | awk '/^@@5$/ { f = 1; next } /^@@6$/ { f = 0 } f')
      s6=$(printf '%s\n' "$raw" | awk '/^@@6$/ { f = 1; next } f')
    fi
  fi
  for i in 6 5 4 3 0; do
    out=""
    for part in "$s1" "$s2" "$s3" "$s4" "$s5" "$s6"; do
      [ -n "$part" ] && out+="$part"$'\n\n'
    done
    [ "${#out}" -le "$cap" ] && break
    case $i in 6) s6="" ;; 5) s5="" ;; 4) s4="" ;; 3) s3="" ;; esac
  done
  # Sections 1-2 are never dropped, but s2 (the Next session block, copied
  # verbatim from latest.md) is unbounded — truncate it as a last resort so
  # the "at most CAP characters" contract holds even for an oversized handoff.
  if [ "${#out}" -gt "$cap" ]; then
    local room=$((cap - ${#s1} - 4))
    [ "$room" -lt 0 ] && room=0
    s2="${s2:0:room}"
    out="$s1"$'\n\n'
    [ -n "$s2" ] && out+="$s2"$'\n\n'
  fi
  printf '%s\n' "${out%$'\n\n'}"
}
