# git_without_z DIR — writes DIR/git, a git that refuses `worktree list -z`
# with exit 129 as git before 2.36 does, and runs the real git otherwise.
# Put DIR first on PATH.
git_without_z() {
  mkdir -p "$1"
  {
    printf '#!/usr/bin/env bash\n'
    printf 'real=%q\n' "$(command -v git)"
    cat <<'SHIM'
w=0 z=0
for a in "$@"; do case $a in worktree) w=1 ;; -z) z=1 ;; esac; done
if [ "$w" -eq 1 ] && [ "$z" -eq 1 ]; then
  printf "error: unknown switch \`z'\n" >&2
  exit 129
fi
exec "$real" "$@"
SHIM
  } > "$1/git"
  chmod +x "$1/git"
}
