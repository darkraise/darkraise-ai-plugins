# Convert a path to the form the platform's own process APIs accept.
# Sourced by the scripts that hand a working directory to a node client.
#
# Under Git Bash $PWD is a POSIX path such as /d/repo. Node's spawnSync takes
# cwd verbatim, and Windows cannot resolve that form: the spawn fails with
# ENOENT, which the codex plugin reports as {available:false, detail:"not
# found"} - indistinguishable from a missing binary. The roster then turns the
# whole lane off and names the wrong cause.
#
# -m, not -w: the result is interpolated into JSON, and a backslash path would
# produce invalid escapes. Off Windows there is no cygpath and no conversion to
# make, so the path is already native.
dr_native_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi
}

# dr_worktree_list GIT [ARG ...] — `GIT [ARG ...] worktree list --porcelain`
# as -z prints it: NUL-terminated fields, a record ended by an empty field.
# Git before 2.36 refuses -z, so its line form is converted there; a path
# holding a newline then splits, as it did before -z was read.
dr_worktree_list() {
  "$@" worktree list --porcelain -z 2>/dev/null && return 0
  "$@" worktree list --porcelain | tr -d '\r' | tr '\n' '\000'
}
