# shellcheck shell=bash
# dagents_timeout — sets DAGENTS_TIMEOUT to GNU timeout under either of its names;
# returns 1 when neither is on PATH. macOS ships none, and Homebrew's coreutils
# installs it as gtimeout. A variable, not a function, because some callers hand
# it to exec or setsid, which look the name up on PATH.
dagents_timeout() {
  if command -v timeout >/dev/null 2>&1; then DAGENTS_TIMEOUT=timeout
  elif command -v gtimeout >/dev/null 2>&1; then DAGENTS_TIMEOUT=gtimeout
  else DAGENTS_TIMEOUT=""; return 1
  fi
}
