#!/usr/bin/env bash
# lib/session-live.sh: a session is live while its cockpit beats, or, with no
# cockpit, while its transcript is written; gone otherwise, with a reason.
set -uo pipefail
unset CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CLAUDE_CODE_SESSION_ID

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../plugins/dforge/scripts/lib/session-live.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/dforge/sessions/cockpit" "$HOME/.claude/dforge/sessions/by-id" "$HOME/.claude/projects/p"

# ago SECONDS: that long ago as touch -t reads it, from GNU or BSD date.
ago() { local t=$(( $(date +%s) - $1 )); date -d "@$t" +%Y%m%d%H%M.%S 2>/dev/null || date -r "$t" +%Y%m%d%H%M.%S; }
beat() { printf '%s\n' "$2" > "$HOME/.claude/dforge/sessions/cockpit/$1"; } # beat <session> <epoch>
transcript() { # transcript <session> [seconds ago]
  local tp="$HOME/.claude/projects/p/$1.jsonl"
  printf '{}\n' > "$tp"
  printf '{"transcript_path":"%s"}\n' "$tp" > "$HOME/.claude/dforge/sessions/by-id/$1.json"
  [ -z "${2:-}" ] || touch -t "$(ago "$2")" "$tp"
}
gone() { session_gone "$1"; printf '%s|%s' "$?" "$SESSION_GONE_REASON"; } # gone <session>: status|reason

# beat_fresh_is_live
beat s-fresh "$(date +%s)"
check "beat_fresh_is_live" "$(gone s-fresh)" "1|"

# beat_old_is_gone
beat s-old $(( $(date +%s) - AR_BEAT_SECONDS - 60 ))
out=$(gone s-old)
check "beat_old_is_gone: status" "${out%%|*}" "0"
check "beat_old_is_gone: reason" "$(case ${out#*|} in 'beat '*' old') echo beat ;; *) echo "${out#*|}" ;; esac)" "beat"
check "beat_old_is_gone: the age" "${out#*|}" "beat 4m old"

# no_beat_idle_transcript_is_gone
transcript s-idle $(( (AR_STALE_MINUTES + 1) * 60 ))
out=$(gone s-idle)
check "no_beat_idle_transcript_is_gone: status" "${out%%|*}" "0"
check "no_beat_idle_transcript_is_gone: reason" "${out#*|}" "no beat, transcript idle 1h"
transcript s-busy
check "no_beat_idle_transcript_is_gone: a fresh transcript is live" "$(gone s-busy)" "1|"

# no_beat_missing_transcript_is_gone
out=$(gone s-none)
check "no_beat_missing_transcript_is_gone: status" "${out%%|*}" "0"
check "no session is gone" "$(gone '' | cut -d'|' -f1)" "0"

# a beat file outranks the transcript: a fresh transcript with an old beat is gone
transcript s-old
check "an old beat outranks a fresh transcript" "$(gone s-old | cut -d'|' -f1)" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
