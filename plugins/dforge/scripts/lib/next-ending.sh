# shellcheck shell=bash
# ending_turn_record SID — the turn record next-step writes for SID
# (~/.claude/dforge/sessions/turns/<sid>.next, the id spelled as the turn
# stamp spells it): the Status and Next lines of the last block it printed,
# written or not. Prints nothing without a session id.
ending_turn_record() {
  [ -n "$1" ] || return 0
  printf '%s/.claude/dforge/sessions/turns/%s.next\n' "${HOME:-}" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
}

# ending_released_any MESSAGE STAMP SID [ROOT] — whether a stop message ends on
# a next-step block printed this turn, which releases a held turn. Status 0
# when SID's turn record is newer than STAMP and MESSAGE contains its Next line
# (verbatim); or when a handoff of any checkout or the mirror
# (dforge_handoff_files ROOT, default the working directory) is newer than
# STAMP and both its `**Status:**` and `**Next:**` lines appear in MESSAGE:
# next-step run without a session id (Codex) writes no record. Both lines,
# since final-phase Next lines read the same for every plan. Status 1
# otherwise, so a hand-typed block is held. Only grep, sed and awk run.
ending_released_any() {
  local message=$1 stamp=$2 record f status next
  record=$(ending_turn_record "$3")
  if [ -n "$record" ] && [ -f "$record" ] && [ "$record" -nt "$stamp" ]; then
    next=$(tr -d '\r' < "$record" | sed -n 's/^next=//p' | head -n 1)
    [ -n "$next" ] && grep -qF -- "$next" <<<"$message" && return 0
  fi
  while IFS= read -r f; do
    [ -n "$f" ] && [ -f "$f" ] && [ "$f" -nt "$stamp" ] || continue
    status=$(_ending_field '**Status:** ' "$f")
    next=$(_ending_field '**Next:** ' "$f")
    [ -n "$status" ] && [ -n "$next" ] || continue
    grep -qF -- "$status" <<<"$message" && grep -qF -- "$next" <<<"$message" && return 0
  done < <(dforge_handoff_files "${4:-$PWD}" 2>/dev/null)
  return 1
}

# _ending_field PREFIX FILE — the text after PREFIX on the first line of FILE's
# Next session section that starts with it.
_ending_field() {
  KEY=$1 awk '{ sub(/\r$/, "") } $0 == "## Next session" { in_block = 1; next } in_block && /^## / { exit } in_block && index($0, ENVIRON["KEY"]) == 1 { print substr($0, length(ENVIRON["KEY"]) + 1); exit }' "$2"
}
