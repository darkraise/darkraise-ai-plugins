# Sourced; functions only. The marker scripts/ask leaves beside the turn stamp:
# a question asked this turn, after the last recorded work, releases the Stop
# hooks' hold for that turn and no other.

ask_marker_path() { # ask_marker_path SESSION_ID
  printf '%s/.claude/dagents/sessions/turns/%s.asked\n' "${HOME:-}" "$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
}

# Work recorded after the question (a ledger, completed.md or the roadmap
# written later) means the turn went on past it, so the hold stands.
ask_marker_released() { # ask_marker_released STAMP LEDGER_ROOT DOCS_DIR
  local marker="$1.asked" newer
  [ -e "$marker" ] && [ "$marker" -nt "$1" ] || return 1
  if [ -n "$2" ] && [ -d "$2" ]; then
    newer=$(find "$2" -mindepth 2 -maxdepth 2 -name progress.md -newer "$marker" 2>/dev/null | head -n 1)
    [ -z "$newer" ] || return 1
  fi
  if [ -n "$3" ]; then
    [ "$3/plans/completed.md" -nt "$marker" ] && return 1
    [ "$3/roadmap.md" -nt "$marker" ] && return 1
  fi
  return 0
}
