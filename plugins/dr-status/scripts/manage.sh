#!/usr/bin/env bash
set -uo pipefail
scripts="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
action="${1:-status}"
[ "$#" -eq 0 ] || shift
case "$action" in
  preview) exec bash "$scripts/preview.sh" "$@" ;;
  install|uninstall|doctor|status) exec bash "$scripts/install.sh" "$action" "$@" ;;
  *) printf 'usage: manage.sh {install|uninstall|status|doctor|preview} [arguments]\n' >&2; exit 2 ;;
esac
