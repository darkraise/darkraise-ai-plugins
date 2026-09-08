#!/usr/bin/env bash
# SessionStart hook. Re-copies the script tree when the plugin version differs
# from the installed copy, because ${CLAUDE_PLUGIN_ROOT} moves on every update
# while the path in settings.json must not.
#
# It deliberately does nothing when the destination does not exist: a user who
# never ran the install command should not get files created behind their back.
set -uo pipefail

# Without CLAUDE_PLUGIN_ROOT the source path would read "/scripts", which is a
# real absolute path -- on the wrong machine it could exist and be copied from.
[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || exit 0

source "$(dirname "${BASH_SOURCE[0]}")/install.sh"
DCC_SRC_DIR="$CLAUDE_PLUGIN_ROOT/scripts"
[ -d "$DCC_SRC_DIR" ] || exit 0
dcc_installation_read >/dev/null || exit 1
dcc_installation_lock || exit 1
trap 'dcc_installation_unlock' EXIT
targets="$(dcc_targets --all)" || exit 1
active="$(dcc_targets)" || exit 1
targets="$(printf '%s\n%s\n' "$targets" "$active" | sort -u)"
result=0
while IFS= read -r account; do
  [ -n "$account" ] || continue
  dcc_installation_owns "$account" || continue
  [ -d "$DCC_DEST" ] || continue
  cmp -s "$DCC_SRC_DIR/VERSION" "$DCC_DEST/VERSION" && continue
  dcc_copy_scripts "$DCC_DEST" || result=1
done <<< "$targets"
exit "$result"
