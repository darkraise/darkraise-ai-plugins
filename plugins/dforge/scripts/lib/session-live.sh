# Sourced. Whether a Claude Code session is still live: its cockpit's
# heartbeat, or, for a session with no cockpit, its transcript's last write.
# Defines functions and the two thresholds only.

AR_STALE_MINUTES=60
AR_BEAT_SECONDS=180

# A native jq.exe ends its lines CRLF.
_session_jq() { "${DFORGE_JQ:-jq}" "$@" | tr -d '\r'; }

_session_safe() { printf '%s' "$1" | tr -c 'A-Za-z0-9' '-'; }

# session_age_text SECONDS — 45s, 12m, 3h or 2d.
session_age_text() {
  local s=$1
  if [ "$s" -lt 60 ]; then printf '%ss\n' "$s"
  elif [ "$s" -lt 3600 ]; then printf '%sm\n' $((s / 60))
  elif [ "$s" -lt 86400 ]; then printf '%sh\n' $((s / 3600))
  else printf '%sd\n' $((s / 86400)); fi
}

# session_transcript SESSION — the session's transcript: its by-id record's
# path, else the projects tree's <SESSION>.jsonl. Records hold native paths,
# so a Windows path is converted as scripts/lib/context.sh does.
session_transcript() {
  local rec tp
  rec="$HOME/.claude/dforge/sessions/by-id/$(_session_safe "$1").json"
  if [ -f "$rec" ]; then
    tp=$(_session_jq -r '.transcript_path // empty' < "$rec" 2>/dev/null | tr -d '\r')
    if [ -n "$tp" ] && command -v cygpath >/dev/null 2>&1; then tp=$(cygpath -u "$tp"); fi
    if [ -n "$tp" ] && [ -f "$tp" ]; then printf '%s\n' "$tp"; return 0; fi
  fi
  tp=$(ls -t "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/projects/*/"$1".jsonl 2>/dev/null | head -n 1)
  [ -n "$tp" ] || return 1
  printf '%s\n' "$tp"
}

# session_beat_file SESSION — where the session's cockpit writes its
# heartbeat: the epoch seconds of its last beat.
session_beat_file() {
  printf '%s/.claude/dforge/sessions/cockpit/%s\n' "${HOME:-}" "$(_session_safe "$1")"
}

# session_beat_age SESSION — seconds since the session's cockpit last beat;
# fails when the file is missing or holds no number. A beat up to
# AR_BEAT_SECONDS ahead of this clock is clock skew and reads as age 0; one
# further ahead fails, so session_gone reads it as gone.
session_beat_age() {
  local file beat age
  file=$(session_beat_file "$1")
  [ -f "$file" ] || return 1
  beat=$(head -n 1 "$file" | tr -dc '0-9')
  [ -n "$beat" ] || return 1
  age=$(( $(date +%s) - beat ))
  [ "$age" -ge $(( -AR_BEAT_SECONDS )) ] || return 1
  [ "$age" -ge 0 ] || age=0
  echo "$age"
}

# session_gone SESSION — status 0 when the session is gone: its cockpit beat
# is older than AR_BEAT_SECONDS, or, with no beat file, its transcript was not
# written within AR_STALE_MINUTES or it has none; status 1 when it is live.
# SESSION_GONE_REASON says why it is gone.
session_gone() {
  local sid=$1 tp age mtime
  SESSION_GONE_REASON=""
  if [ -z "$sid" ]; then SESSION_GONE_REASON="no session"; return 0; fi
  if [ -f "$(session_beat_file "$sid")" ]; then
    if ! age=$(session_beat_age "$sid"); then SESSION_GONE_REASON="beat unreadable"; return 0; fi
    [ "$age" -gt "$AR_BEAT_SECONDS" ] || return 1
    SESSION_GONE_REASON="beat $(session_age_text "$age") old"
    return 0
  fi
  if ! tp=$(session_transcript "$sid"); then SESSION_GONE_REASON="no beat, no transcript"; return 0; fi
  [ -n "$(find "$tp" -mmin +"$AR_STALE_MINUTES" 2>/dev/null)" ] || return 1
  mtime=$(stat -c %Y "$tp" 2>/dev/null || stat -f %m "$tp" 2>/dev/null) || mtime=""
  if [ -n "$mtime" ]; then age=$(session_age_text $(( $(date +%s) - mtime )))
  else age="over ${AR_STALE_MINUTES}m"; fi
  SESSION_GONE_REASON="no beat, transcript idle $age"
  return 0
}
