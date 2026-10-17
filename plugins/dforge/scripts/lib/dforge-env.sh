# Sourced. Reads dforge settings for the shell scripts.

_DFORGE_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# dforge_setting KEY DEFAULT - the setting in force (scripts/dforge-config), or
# DEFAULT when the command cannot answer: no Node, an unknown key, or a settings
# file that cannot be read. A setting must never be what fails its caller, and
# reading one never creates the settings file (DFORGE_NO_IMPORT).
# DFORGE_NO_SETTINGS answers DEFAULT outright, for a test suite that runs
# against the real home directory.
dforge_setting() {
  local value=""
  if [ -z "${DFORGE_NO_SETTINGS:-}" ]; then
    value=$(DFORGE_NO_IMPORT=1 bash "$_DFORGE_ENV_DIR/../dforge-config" get "$1" 2>/dev/null | tr -d '\r') || value=""
  fi
  [ -n "$value" ] || value=$2
  printf '%s' "$value"
}
