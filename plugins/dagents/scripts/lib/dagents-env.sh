# Sourced. Reads dagents settings for the shell scripts.

_DAGENTS_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# dagents_setting KEY DEFAULT - the setting in force (scripts/dagents-config), or
# DEFAULT when the command cannot answer: no Node, an unknown key, or a settings
# file that cannot be read. A setting must never be what fails its caller, and
# reading one never creates the settings file (DAGENTS_NO_IMPORT).
# DAGENTS_NO_SETTINGS answers DEFAULT outright, for a test suite that runs
# against the real home directory.
dagents_setting() {
  local value=""
  if [ -z "${DAGENTS_NO_SETTINGS:-}" ]; then
    value=$(DAGENTS_NO_IMPORT=1 bash "$_DAGENTS_ENV_DIR/../dagents-config" get "$1" 2>/dev/null) || value=""
    value=${value//$'\r'/}
  fi
  [ -n "$value" ] || value=$2
  printf '%s' "$value"
}
