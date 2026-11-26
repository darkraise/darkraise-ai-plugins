# Sourced by suites that start an auto run. Stands in for the cockpit's echo
# of a session's run binding (syncBinding in
# plugins/dforge/hooks/cockpit/register.tsx), which start and resume wait for.

# cockpit_ack_start HOME_DIR — one background loop that copies each run
# binding under HOME_DIR whose content changed to its .seen name. It ends by
# itself once HOME_DIR is removed or the calling shell is gone, so a suite
# killed before its EXIT trap leaves no loop behind; no suite kills it.
cockpit_ack_start() {
  local home=$1 owner=$$
  mkdir -p "$home" || return
  # Forked twice, so the loop is no child of the suite and a bare wait in it
  # does not wait for the loop.
  ( (
    trap - EXIT
    dir="$home/.claude/dforge/sessions/run"
    declare -A last=()
    while [ -d "$home" ] && kill -0 "$owner" 2>/dev/null; do
      for f in "$dir"/*.json; do
        [ -f "$f" ] || continue
        text=""
        IFS= read -r -d '' text < "$f"
        [ "${last[$f]-}" != "$text" ] || continue
        printf '%s' "$text" > "${f%.json}.seen" && last[$f]=$text
      done
      sleep 0.05
    done
  ) >/dev/null 2>&1 </dev/null & )
}
