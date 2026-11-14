# Sourced by the stub judge CLIs: logs what the child was given, then acts on its mode.
# Modes: ok (default), silent, fail, slow-fail, noverdict, slow, hang, hang-usage,
# leak, write, write-ignored, commit.
VERDICT=$'## Verdict\nruling: a noclobber lock file — it holds on uutils\n'

stub_log() { # stub_log <budget> <args…>
  budget=$1; shift
  upper=$(printf '%s' "$budget" | tr '[:lower:]' '[:upper:]')
  eval "mode=\${STUB_JUDGE_$upper:-ok}"
  if [ -n "${STUB_JUDGE_ARGS_LOG:-}" ]; then
    { printf 'budget %s\n' "$budget"; for arg in "$@"; do printf '%s\n' "$arg"; done; printf '%s\n' '--'; } >> "$STUB_JUDGE_ARGS_LOG"
  fi
  if [ -n "${STUB_JUDGE_STDIN_LOG:-}" ] && [ ! -t 0 ]; then cat >> "$STUB_JUDGE_STDIN_LOG"; fi
  if [ -n "${STUB_JUDGE_ENV_LOG:-}" ]; then
    { printf 'budget %s\n' "$budget"
      env | grep -E '^(DFORGE_[A-Z_]*|OPENAI_API_KEY|ANTHROPIC_API_KEY|ANTHROPIC_AUTH_TOKEN|ANTHROPIC_BASE_URL|CLAUDE_CODE_OAUTH_TOKEN|CLAUDE_CODE_USE_BEDROCK|CLAUDE_CODE_USE_VERTEX|OPENAI_BASE_URL)=' | while IFS='=' read -r name value; do
        printf '%s %s\n' "$name" "$(printf '%s' "$value" | sha256sum | cut -c1-16)"
      done
      printf 'CODEX_HOME %s\n' "${CODEX_HOME:-unset}"
      printf '%s\n' '--'; } >> "$STUB_JUDGE_ENV_LOG"
  fi
  if [ -n "${STUB_JUDGE_PID_FILE:-}" ]; then printf '%s\n' "$$" > "$STUB_JUDGE_PID_FILE"; fi
}

stub_run() {
  case "$mode" in
    ok | silent) reply "$VERDICT" ;;
    fail) printf 'stub judge: failed\n' >&2; exit 1 ;;
    slow-fail) sleep "${STUB_JUDGE_SLOW:-3}"; exit 1 ;;
    noverdict) reply "I would pick the first option." ;;
    slow) sleep "${STUB_JUDGE_SLOW:-3}"; reply "$VERDICT" ;;
    hang) exec sleep 300 ;;
    hang-usage) usage; exec sleep 300 ;;
    leak) reply "$VERDICT${STUB_JUDGE_LEAK:-}" ;;
    write) printf 'stray\n' > stray.txt; reply "$VERDICT" ;;
    write-ignored) mkdir -p .dforge; printf 'scratch\n' > .dforge/scratch.txt; reply "$VERDICT" ;;
    commit) git -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m stray; reply "$VERDICT" ;;
  esac
}
