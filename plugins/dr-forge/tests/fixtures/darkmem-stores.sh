# Sourced by shell suites: a HOME whose dr-forge config maps a repository to
# darkmem with each family applied as the suite asks.

# stores_home HOME REPO PROJECT DOCS PROGRESS — map REPO's primary checkout to
# PROJECT, record documents DOCS and progress PROGRESS (local or darkmem) as
# applied, create the mirror's directories, and print the mirror's path.
stores_home() {
  local home=$1 project=$3 common top dir
  common=$(git -C "$2" rev-parse --path-format=absolute --git-common-dir)
  top=$(git -C "$(dirname "$common")" rev-parse --show-toplevel)
  dir="$home/.dr-forge"
  mkdir -p "$dir/mirror/$project/forge" "$dir/mirror/$project/work/sdd" "$dir/mirror/$project/work/handoff"
  printf '{"darkmemEnabled":true,"darkmem":{"url":"http://127.0.0.1:9","repos":{"%s":{"project":"%s"}}}}\n' "$top" "$project" > "$dir/config.json"
  printf '{"%s":{"documents":"%s","progress":"%s"}}\n' "$top" "$4" "$5" > "$dir/stores.json"
  printf '%s\n' "$dir/mirror/$project"
}
