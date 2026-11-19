#!/usr/bin/env bash
# lib/roots.sh: each family's root follows its applied store, from the primary
# checkout and from a linked worktree, and names round-trip in all four
# combinations, including a checkout and a project both named superpowers.
set -uo pipefail
unset CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../plugins/dforge/scripts/lib/roots.sh"
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
check "no config: a worktree's ledger dir" "$(cd "$WT" && dforge_ledger_dir p1)" "$WT/.dforge/sdd/p1"
check "no config: latest.md from a worktree" "$(cd "$WT" && dforge_latest_file)" "$WT/.dforge/handoff/latest.md"
check "no config: latest.md from the primary" "$(cd "$REPO" && dforge_latest_file)" "$TOP/.dforge/handoff/latest.md"
check "no config: a DIR argument" "$(dforge_docs_root "$WT")" "$WT/docs/dforge"
check "outside git: local under the directory" "$(cd "$TMP" && dforge_docs_root)" "$TMP/docs/dforge"

# --- a home with no darkmem section and no applied family starts no node ---
mkdir -p "$TMP/marknode" "$HOME/.dforge"
printf '#!/bin/sh\n: > "%s"\nexit 1\n' "$TMP/node-ran" > "$TMP/marknode/node"
chmod +x "$TMP/marknode/node"
printf '{"handoffTokens": 300000, "darkmemEnabled": true}\n' > "$HOME/.dforge/config.json"
check "settings only: docs root" "$(cd "$REPO" && PATH="$TMP/marknode:$PATH" dforge_docs_root)" "$TOP/docs/dforge"
check "settings only: latest.md from a worktree" "$(cd "$WT" && PATH="$TMP/marknode:$PATH" dforge_latest_file)" "$WT/.dforge/handoff/latest.md"
check "settings only: node is not started" "$([ -e "$TMP/node-ran" ] && echo ran || echo skipped)" "skipped"
printf '{"darkmem": {}}\n' > "$HOME/.dforge/config.json"
(cd "$REPO" && PATH="$TMP/marknode:$PATH" dforge_docs_root > /dev/null 2>&1)
check "a darkmem section: node decides" "$([ -e "$TMP/node-ran" ] && echo ran || echo skipped)" "ran"
rm -f "$TMP/node-ran" "$HOME/.dforge/config.json"
printf '{}\n' > "$HOME/.dforge/stores.json"
(cd "$REPO" && PATH="$TMP/marknode:$PATH" dforge_docs_root > /dev/null 2>&1)
check "a stores record: node decides" "$([ -e "$TMP/node-ran" ] && echo ran || echo skipped)" "ran"
rm -rf "$TMP/node-ran" "$HOME/.dforge"

# --- the four applied combinations, from the primary checkout and a worktree ---
for docs in local darkmem; do
  for progress in local darkmem; do
    MIRROR=$(stores_home "$HOME" "$REPO" superpowers "$docs" "$progress")
    for where in "$TOP" "$WT"; do
      label="$docs/$progress from $(basename "$where")"
      if [ "$docs" = darkmem ]; then want_docs="$MIRROR/dforge"; else want_docs="$where/docs/dforge"; fi
      if [ "$progress" = darkmem ]; then
        want_ledger="$MIRROR/work/sdd/p1"
      else
        want_ledger="$where/.dforge/sdd/p1"
      fi
      if [ "$progress" = darkmem ] && [ "$where" = "$TOP" ]; then want_latest="$MIRROR/work/handoff/latest.md"
      else want_latest="$where/.dforge/handoff/latest.md"; fi
      check "$label: stores" "$(cd "$where" && dforge_docs_store) $(cd "$where" && dforge_progress_store)" "$docs $progress"
      check "$label: docs root" "$(cd "$where" && dforge_docs_root)" "$want_docs"
      check "$label: ledger dir" "$(cd "$where" && dforge_ledger_dir p1)" "$want_ledger"
      check "$label: latest.md" "$(cd "$where" && dforge_latest_file)" "$want_latest"
      check "$label: the workspace stays local" "$(cd "$where" && dforge_workspace p1)" "$where/.dforge/sdd/p1"
      check "$label: a document name" "$(cd "$where" && dforge_resolve docs/dforge/plans/p1.md)" "$want_docs/plans/p1.md"
      check "$label: a pre-2.0 document name" "$(cd "$where" && dforge_resolve docs/superpowers/plans/p1.md)" "$want_docs/plans/p1.md"
      check "$label: a working name" "$(cd "$where" && dforge_resolve .dforge/sdd/p1/brief.md)" "$where/.dforge/sdd/p1/brief.md"
      check "$label: an absolute path stays" "$(cd "$where" && dforge_resolve /x/y.md)" "/x/y.md"
      check "$label: a document round-trips" "$(cd "$where" && dforge_name "$(dforge_resolve docs/dforge/plans/p1.md)")" "docs/dforge/plans/p1.md"
      check "$label: a working file round-trips" "$(cd "$where" && dforge_name "$where/.dforge/x.md")" ".dforge/x.md"
      check "$label: a name stays a name" "$(cd "$where" && dforge_name ./docs/dforge/specs/s.md)" "docs/dforge/specs/s.md"
      check "$label: an outside path stays" "$(cd "$where" && dforge_name /elsewhere/superpowers/a.md)" "/elsewhere/superpowers/a.md"
      check "$label: every checkout's handoff" "$(cd "$where" && dforge_latest_files | tr '\n' ' ')" \
        "$( [ "$progress" = darkmem ] && printf '%s ' "$MIRROR/work/handoff/latest.md" || printf '%s ' "$TOP/.dforge/handoff/latest.md")$WT/.dforge/handoff/latest.md "
    done
  done
done

# --- ledger listings: every worktree's when local, the mirror's once when darkmem ---
mkdir -p "$REPO/.dforge/sdd/a" "$WT/.dforge/sdd/b"
printf 'x\n' > "$REPO/.dforge/sdd/a/progress.md"
printf 'x\n' > "$WT/.dforge/sdd/b/progress.md"
stores_home "$HOME" "$REPO" superpowers local local > /dev/null
check "ledger files: local lists each worktree's" "$(cd "$WT" && dforge_ledger_files | sort)" \
  "$(printf '%s\t%s\n%s\t%s' "$TOP/.dforge/sdd/a/progress.md" "$TOP" "$WT/.dforge/sdd/b/progress.md" "$WT" | sort)"
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local darkmem)
mkdir -p "$MIRROR/work/sdd/c"
printf 'x\n' > "$MIRROR/work/sdd/c/progress.md"
check "ledger files: darkmem lists the mirror's once" "$(cd "$WT" && dforge_ledger_files)" "$(printf '%s\tmirror' "$MIRROR/work/sdd/c/progress.md")"

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

# --- one name under either docs prefix (spec §7.1) ---
check "name key: the pre-2.0 prefix" "$(dforge_name_key docs/superpowers/plans/p.md)" "docs/dforge/plans/p.md"
check "name key: the 3.x prefix" "$(dforge_name_key docs/forge/plans/p.md)" "docs/dforge/plans/p.md"
check "name key: a bare docs/forge" "$(dforge_name_key docs/forge)" "docs/dforge"
check "name key: docs/forgex is another name" "$(dforge_name_key docs/forgex/a.md)" "docs/forgex/a.md"
check "name key: the dforge prefix" "$(dforge_name_key docs/dforge/plans/p.md)" "docs/dforge/plans/p.md"
check "name key: a bare docs/superpowers" "$(dforge_name_key docs/superpowers)" "docs/dforge"
check "name key: a trailing slash" "$(dforge_name_key docs/superpowers/)" "docs/dforge"
check "name key: a trailing slash after a name" "$(dforge_name_key docs/forge/plans/)" "docs/dforge/plans"
check "name key: a leading ./" "$(dforge_name_key ./docs/superpowers/specs/s.md)" "docs/dforge/specs/s.md"
check "name key: docs/superpowersx is another name" "$(dforge_name_key docs/superpowersx/a.md)" "docs/superpowersx/a.md"
check "name key: a name outside the docs directory" "$(dforge_name_key .dforge/sdd/p/progress.md)" ".dforge/sdd/p/progress.md"
check "name key: an absolute path stays" "$(dforge_name_key /x/docs/superpowers/a.md)" "/x/docs/superpowers/a.md"
check "name spellings: a document name" \
  "$(dforge_name_spellings docs/superpowers/plans/p.md | tr '\n' '|')" "docs/dforge/plans/p.md|docs/forge/plans/p.md|docs/superpowers/plans/p.md|"
check "name spellings: the docs directory itself" \
  "$(dforge_name_spellings ./docs/dforge | tr '\n' '|')" "docs/dforge|docs/forge|docs/superpowers|"
check "name spellings: a trailing slash" \
  "$(dforge_name_spellings docs/forge/ | tr '\n' '|')" "docs/dforge|docs/forge|docs/superpowers|"
check "name spellings: any other name" "$(dforge_name_spellings .dforge/x.md | tr '\n' '|')" ".dforge/x.md|"

# --- the mapped project, from roots.sh and from dforge-path ---
FP="$HERE/../../plugins/dforge/scripts/dforge-path"
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

# --- no node while darkmem is applied: exit 2, never local (row 15) ---
nonode_path() { # PATH with no node: a directory holding node is dropped, or, when it holds git or jq too, stood in for by links to its other programs
  local d f m out='' IFS=:
  for d in $PATH; do
    if [ -x "$d/node" ] || [ -x "$d/node.exe" ]; then
      [ -x "$d/git" ] || [ -x "$d/git.exe" ] || [ -x "$d/jq" ] || [ -x "$d/jq.exe" ] || continue
      m="$TMP/nonode/$(printf '%s' "$d" | tr -c 'A-Za-z0-9' '_')"
      mkdir -p "$m"
      for f in "$d"/*; do case ${f##*/} in node | node.exe) ;; *) ln -s "$f" "$m/" 2>/dev/null ;; esac; done
      d=$m
    fi
    out=${out:+$out:}$d
  done
  printf '%s\n' "$out"
}
NONODE_PATH=$(nonode_path)
if PATH="$NONODE_PATH" command -v node >/dev/null 2>&1 || ! PATH="$NONODE_PATH" command -v git >/dev/null 2>&1 \
   || ! PATH="$NONODE_PATH" command -v jq >/dev/null 2>&1; then
  printf 'skip - no node: node shares a PATH directory with git or jq here\n'
else
  stores_home "$HOME" "$REPO" superpowers local darkmem > /dev/null
  out=$(cd "$REPO" && _DFORGE_KEY= PATH="$NONODE_PATH" dforge_ledger_dir p1 2>&1); rc=$?
  check "no node, progress applied darkmem: exit 2" "$rc" "2"
  check "the message names node" "$(grep -c 'roots.sh: node is required while darkmem stores are applied' <<<"$out")" "1"
  printf '{"broken": \n' > "$HOME/.dforge/stores.json"
  out=$(cd "$REPO" && _DFORGE_KEY= PATH="$NONODE_PATH" dforge_ledger_dir p1 2>&1); rc=$?
  check "no node, a stores.json that does not parse: exit 2, never local" "$rc:$(grep -c 'does not parse' <<<"$out")" "2:1"
  printf '{"/elsewhere":{"documents":"darkmem","progress":"darkmem"}}\n' > "$HOME/.dforge/stores.json"
  check "no node, darkmem applied only for another checkout: still local" "$(cd "$REPO" && _DFORGE_KEY= PATH="$NONODE_PATH" dforge_ledger_dir p1 2>&1)" "$TOP/.dforge/sdd/p1"
  rm -f "$HOME/.dforge/stores.json"
  check "no node, nothing applied: still local" "$(cd "$REPO" && _DFORGE_KEY= PATH="$NONODE_PATH" dforge_ledger_dir p1)" "$TOP/.dforge/sdd/p1"
fi

# --- dforge_latest_files skips a worktree whose directory is gone ---
git -C "$REPO" worktree add -q -b gone "$TMP/gone"
rm -rf "$TMP/gone"
check "latest files: a missing worktree is skipped" "$(cd "$REPO" && dforge_latest_files | grep -c gone)" "0"
git -C "$REPO" worktree prune

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
