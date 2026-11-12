#!/usr/bin/env bash
# lib/roots.sh: each family's root follows its applied store, from the primary
# checkout and from a linked worktree, and names round-trip in all four
# combinations, including a checkout and a project both named superpowers.
set -uo pipefail
unset CLAUDE_CONFIG_DIR DFORGE_DOCUMENT_STORE DFORGE_PROGRESS_SOURCE CLAUDE_PROJECT_DIR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/roots.sh"
. "$HERE/fixtures/darkmem-stores.sh"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
REPO="$TMP/superpowers"
git init -q -b main "$REPO"
git -C "$REPO" commit -q --allow-empty -m init
TOP=$(git -C "$REPO" rev-parse --show-toplevel)
git -C "$REPO" worktree add -q -b wt "$TMP/wt"
WT=$(git -C "$TMP/wt" rev-parse --show-toplevel)

# --- no config: both families local ---
check "no config: docs root" "$(cd "$REPO" && dforge_docs_root)" "$TOP/docs/dforge"
check "no config: stores" "$(cd "$REPO" && dforge_docs_store) $(cd "$REPO" && dforge_progress_store)" "local local"
check "no config: a DIR argument" "$(dforge_docs_root "$WT")" "$WT/docs/dforge"
check "outside git: local under the directory" "$(cd "$TMP" && dforge_docs_root)" "$TMP/docs/dforge"

# --- the four applied combinations, from the primary checkout and a worktree ---
for docs in local darkmem; do
  for progress in local darkmem; do
    MIRROR=$(stores_home "$HOME" "$REPO" superpowers "$docs" "$progress")
    for where in "$TOP" "$WT"; do
      label="$docs/$progress from $(basename "$where")"
      if [ "$docs" = darkmem ]; then want_docs="$MIRROR/dforge"; else want_docs="$where/docs/dforge"; fi
      check "$label: stores" "$(cd "$where" && dforge_docs_store) $(cd "$where" && dforge_progress_store)" "$docs $progress"
      check "$label: docs root" "$(cd "$where" && dforge_docs_root)" "$want_docs"
      check "$label: a document name" "$(cd "$where" && dforge_resolve docs/dforge/plans/p1.md)" "$want_docs/plans/p1.md"
      check "$label: a pre-2.0 document name" "$(cd "$where" && dforge_resolve docs/superpowers/plans/p1.md)" "$want_docs/plans/p1.md"
      check "$label: a working name" "$(cd "$where" && dforge_resolve .dforge/sdd/p1/brief.md)" "$where/.dforge/sdd/p1/brief.md"
      check "$label: an absolute path stays" "$(cd "$where" && dforge_resolve /x/y.md)" "/x/y.md"
      check "$label: a document round-trips" "$(cd "$where" && dforge_name "$(dforge_resolve docs/dforge/plans/p1.md)")" "docs/dforge/plans/p1.md"
      check "$label: a working file round-trips" "$(cd "$where" && dforge_name "$where/.dforge/x.md")" ".dforge/x.md"
      check "$label: a name stays a name" "$(cd "$where" && dforge_name ./docs/dforge/specs/s.md)" "docs/dforge/specs/s.md"
      check "$label: an outside path stays" "$(cd "$where" && dforge_name /elsewhere/superpowers/a.md)" "/elsewhere/superpowers/a.md"
    done
  done
done

# --- a relative file spelled from a subdirectory is named from the checkout ---
stores_home "$HOME" "$REPO" superpowers local local > /dev/null
mkdir -p "$WT/docs/dforge/plans"
printf 'p\n' > "$WT/docs/dforge/plans/p.md"
check "subdirectory: a relative file" "$(cd "$WT/docs/dforge/plans" && dforge_name p.md)" "docs/dforge/plans/p.md"
check "subdirectory: a name that is no file here stays" "$(cd "$WT/docs/dforge/plans" && dforge_name docs/superpowers/plans/p.md)" "docs/superpowers/plans/p.md"
check "a historical citation resolves to the file" "$(cd "$WT" && cat "$(dforge_resolve docs/superpowers/plans/p.md)")" "p"
check "a 3.x citation resolves to the file" "$(cd "$WT" && cat "$(dforge_resolve docs/forge/plans/p.md)")" "p"
check "a bare 3.x docs directory resolves to the docs root" "$(cd "$WT" && dforge_resolve docs/forge)" "$WT/docs/dforge"
check "DIR: a relative file is a path from the working directory" \
  "$(cd "$WT/docs/dforge" && dforge_name plans/p.md plans)" "docs/dforge/plans/p.md"

# --- the mapped project, from roots.sh and from dforge-path ---
FP="$HERE/../scripts/dforge-path"
stores_home "$HOME" "$REPO" superpowers local local > /dev/null
check "project: mapped, from a worktree" "$(cd "$WT" && dforge_project)" "superpowers"
check "project: dforge-path" "$(cd "$WT" && bash "$FP" project)" "superpowers"
OTHER="$TMP/other"
git init -q -b main "$OTHER"
git -C "$OTHER" commit -q --allow-empty -m init
(cd "$OTHER" && dforge_project > "$TMP/project-out")
check "project: unmapped is status 1" "$?" "1"
check "project: unmapped prints nothing" "$(cat "$TMP/project-out")" ""
(cd "$OTHER" && bash "$FP" project > "$TMP/project-out")
check "project: dforge-path unmapped exits 1" "$?" "1"
check "project: dforge-path unmapped prints nothing" "$(cat "$TMP/project-out")" ""
(cd "$TMP" && dforge_project > /dev/null)
check "project: outside git is status 1" "$?" "1"
(cd "$WT" && bash "$FP" project extra > /dev/null 2>&1)
check "project: dforge-path takes no argument" "$?" "2"
NB="$TMP/nonode-bin"
mkdir -p "$NB"
for c in git dirname; do ln -s "$(type -P "$c")" "$NB/$c"; done
(cd "$WT" && PATH="$NB" dforge_project > "$TMP/project-out")
check "project: without node is status 1" "$?" "1"
check "project: without node prints nothing" "$(cat "$TMP/project-out")" ""

# --- a --mode run that prints nothing stops the script ---
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/fakebin/node"
chmod +x "$TMP/fakebin/node"
(cd "$REPO" && PATH="$TMP/fakebin:$PATH" dforge_docs_root > /dev/null 2> "$TMP/err-empty")
check "empty --mode: exit 2" "$?" "2"
check "empty --mode: the message" "$(grep -c 'printed no roots' "$TMP/err-empty")" "1"

# --- a ConfigError stops the script ---
printf '{"darkmem":{"url":"http://127.0.0.1:9","repos":{"%s":{"project":"superpowers","documentStore":"cloud"}}}}\n' "$TOP" > "$HOME/.dforge/config.json"
(cd "$REPO" && dforge_docs_root > /dev/null 2> "$TMP/err")
check "config error: exit 2" "$?" "2"
check "config error: the message" "$(grep -c 'use local or darkmem' "$TMP/err")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
