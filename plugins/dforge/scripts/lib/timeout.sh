# shellcheck shell=bash
# dforge_timeout — sets DFORGE_TIMEOUT to GNU timeout under either of its names;
# returns 1 when neither is on PATH. macOS ships none, and Homebrew's coreutils
# installs it as gtimeout. A variable, not a function, because some callers hand
# it to exec or setsid, which look the name up on PATH.
dforge_timeout() {
  if command -v timeout >/dev/null 2>&1; then DFORGE_TIMEOUT=timeout
  elif command -v gtimeout >/dev/null 2>&1; then DFORGE_TIMEOUT=gtimeout
  else DFORGE_TIMEOUT=""; return 1
  fi
}
