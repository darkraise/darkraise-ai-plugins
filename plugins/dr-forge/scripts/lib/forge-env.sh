# Sourced. The pre-2.0 DR_SUPERPOWERS_* names still apply wherever the
# DR_FORGE_* name is unset or empty; the plugin itself sets only the new names.
: "${DR_FORGE_BUDGET:=${DR_SUPERPOWERS_BUDGET:-}}"
: "${DR_FORGE_JQ:=${DR_SUPERPOWERS_JQ:-}}"
: "${DR_FORGE_BUDGET_CALLER:=${DR_SUPERPOWERS_BUDGET_CALLER:-}}"

_FORGE_ENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# forge_setting KEY DEFAULT - the setting in force (scripts/forge-config), or
# DEFAULT when the command cannot answer: no Node, an unknown key, or a settings
# file that cannot be read. A setting must never be what fails its caller, and
# reading one never creates the settings file (DR_FORGE_NO_IMPORT).
# DR_FORGE_NO_SETTINGS answers DEFAULT outright, for a test suite that runs
# against the real home directory.
forge_setting() {
  local value=""
  if [ -z "${DR_FORGE_NO_SETTINGS:-}" ]; then
    value=$(DR_FORGE_NO_IMPORT=1 bash "$_FORGE_ENV_DIR/../forge-config" get "$1" 2>/dev/null | tr -d '\r') || value=""
  fi
  [ -n "$value" ] || value=$2
  printf '%s' "$value"
}
