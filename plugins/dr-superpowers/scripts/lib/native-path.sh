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
