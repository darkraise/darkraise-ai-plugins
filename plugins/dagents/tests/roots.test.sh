#!/usr/bin/env bash
# lib/roots.sh: each family's root follows its applied store, from the primary
# checkout and from a linked worktree, and names round-trip in all four
# combinations, including a checkout and a project both named superpowers.
set -uo pipefail
unset CLAUDE_CONFIG_DIR DAGENTS_DOCUMENT_STORE DAGENTS_PROGRESS_SOURCE CLAUDE_PROJECT_DIR

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
check "no config: docs root" "$(cd "$REPO" && dagents_docs_root)" "$TOP/docs/dagents"
check "no config: stores" "$(cd "$REPO" && dagents_docs_store) $(cd "$REPO" && dagents_progress_store)" "local local"
check "no config: a worktree's ledger dir" "$(cd "$WT" && dagents_ledger_dir p1)" "$WT/.dagents/sdd/p1"
check "no config: latest.md from a worktree" "$(cd "$WT" && dagents_latest_file)" "$TOP/.dagents/handoff/latest.md"
check "no config: a DIR argument" "$(dagents_docs_root "$WT")" "$WT/docs/dagents"
check "outside git: local under the directory" "$(cd "$TMP" && dagents_docs_root)" "$TMP/docs/dagents"

# --- the four applied combinations, from the primary checkout and a worktree ---
for docs in local darkmem; do
  for progress in local darkmem; do
    MIRROR=$(stores_home "$HOME" "$REPO" superpowers "$docs" "$progress")
    for where in "$TOP" "$WT"; do
      label="$docs/$progress from $(basename "$where")"
      if [ "$docs" = darkmem ]; then want_docs="$MIRROR/dagents"; else want_docs="$where/docs/dagents"; fi
      if [ "$progress" = darkmem ]; then
        want_ledger="$MIRROR/work/sdd/p1" want_latest="$MIRROR/work/handoff/latest.md"
      else
        want_ledger="$where/.dagents/sdd/p1" want_latest="$TOP/.dagents/handoff/latest.md"
      fi
      check "$label: stores" "$(cd "$where" && dagents_docs_store) $(cd "$where" && dagents_progress_store)" "$docs $progress"
      check "$label: docs root" "$(cd "$where" && dagents_docs_root)" "$want_docs"
      check "$label: ledger dir" "$(cd "$where" && dagents_ledger_dir p1)" "$want_ledger"
      check "$label: latest.md" "$(cd "$where" && dagents_latest_file)" "$want_latest"
      check "$label: the workspace stays local" "$(cd "$where" && dagents_workspace p1)" "$where/.dagents/sdd/p1"
      check "$label: a document name" "$(cd "$where" && dagents_resolve docs/dagents/plans/p1.md)" "$want_docs/plans/p1.md"
      check "$label: a pre-2.0 document name" "$(cd "$where" && dagents_resolve docs/superpowers/plans/p1.md)" "$want_docs/plans/p1.md"
      check "$label: a working name" "$(cd "$where" && dagents_resolve .dagents/sdd/p1/brief.md)" "$where/.dagents/sdd/p1/brief.md"
      check "$label: an absolute path stays" "$(cd "$where" && dagents_resolve /x/y.md)" "/x/y.md"
      check "$label: a document round-trips" "$(cd "$where" && dagents_name "$(dagents_resolve docs/dagents/plans/p1.md)")" "docs/dagents/plans/p1.md"
      check "$label: a working file round-trips" "$(cd "$where" && dagents_name "$where/.dagents/x.md")" ".dagents/x.md"
      check "$label: a name stays a name" "$(cd "$where" && dagents_name ./docs/dagents/specs/s.md)" "docs/dagents/specs/s.md"
      check "$label: an outside path stays" "$(cd "$where" && dagents_name /elsewhere/superpowers/a.md)" "/elsewhere/superpowers/a.md"
    done
  done
done

# --- ledger listings: every worktree's when local, the mirror's once when darkmem ---
mkdir -p "$REPO/.dagents/sdd/a" "$WT/.dagents/sdd/b"
printf 'x\n' > "$REPO/.dagents/sdd/a/progress.md"
printf 'x\n' > "$WT/.dagents/sdd/b/progress.md"
stores_home "$HOME" "$REPO" superpowers local local > /dev/null
check "ledger files: local lists each worktree's" "$(cd "$WT" && dagents_ledger_files | sort)" \
  "$(printf '%s\t%s\n%s\t%s' "$TOP/.dagents/sdd/a/progress.md" "$TOP" "$WT/.dagents/sdd/b/progress.md" "$WT" | sort)"
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local darkmem)
mkdir -p "$MIRROR/work/sdd/c"
printf 'x\n' > "$MIRROR/work/sdd/c/progress.md"
check "ledger files: darkmem lists the mirror's once" "$(cd "$WT" && dagents_ledger_files)" "$(printf '%s\tmirror' "$MIRROR/work/sdd/c/progress.md")"

# --- a relative file spelled from a subdirectory is named from the checkout ---
stores_home "$HOME" "$REPO" superpowers local local > /dev/null
mkdir -p "$WT/docs/dagents/plans"
printf 'p\n' > "$WT/docs/dagents/plans/p.md"
check "subdirectory: a relative file" "$(cd "$WT/docs/dagents/plans" && dagents_name p.md)" "docs/dagents/plans/p.md"
check "subdirectory: a name that is no file here stays" "$(cd "$WT/docs/dagents/plans" && dagents_name docs/superpowers/plans/p.md)" "docs/superpowers/plans/p.md"
check "a historical citation resolves to the file" "$(cd "$WT" && cat "$(dagents_resolve docs/superpowers/plans/p.md)")" "p"
check "a 3.x citation resolves to the file" "$(cd "$WT" && cat "$(dagents_resolve docs/forge/plans/p.md)")" "p"
check "a bare 3.x docs directory resolves to the docs root" "$(cd "$WT" && dagents_resolve docs/forge)" "$WT/docs/dagents"
check "DIR: a relative file is a path from the working directory" \
  "$(cd "$WT/docs/dagents" && dagents_name plans/p.md plans)" "docs/dagents/plans/p.md"

# --- one name under either docs prefix (spec §7.1) ---
check "name key: the pre-2.0 prefix" "$(dagents_name_key docs/superpowers/plans/p.md)" "docs/dagents/plans/p.md"
check "name key: the 3.x prefix" "$(dagents_name_key docs/forge/plans/p.md)" "docs/dagents/plans/p.md"
check "name key: a bare docs/forge" "$(dagents_name_key docs/forge)" "docs/dagents"
check "name key: docs/forgex is another name" "$(dagents_name_key docs/forgex/a.md)" "docs/forgex/a.md"
check "name key: the dagents prefix" "$(dagents_name_key docs/dagents/plans/p.md)" "docs/dagents/plans/p.md"
check "name key: a bare docs/superpowers" "$(dagents_name_key docs/superpowers)" "docs/dagents"
check "name key: a trailing slash" "$(dagents_name_key docs/superpowers/)" "docs/dagents"
check "name key: a trailing slash after a name" "$(dagents_name_key docs/forge/plans/)" "docs/dagents/plans"
check "name key: a leading ./" "$(dagents_name_key ./docs/superpowers/specs/s.md)" "docs/dagents/specs/s.md"
check "name key: docs/superpowersx is another name" "$(dagents_name_key docs/superpowersx/a.md)" "docs/superpowersx/a.md"
check "name key: a name outside the docs directory" "$(dagents_name_key .dagents/sdd/p/progress.md)" ".dagents/sdd/p/progress.md"
check "name key: an absolute path stays" "$(dagents_name_key /x/docs/superpowers/a.md)" "/x/docs/superpowers/a.md"
check "name spellings: a document name" \
  "$(dagents_name_spellings docs/superpowers/plans/p.md | tr '\n' '|')" "docs/dagents/plans/p.md|docs/forge/plans/p.md|docs/superpowers/plans/p.md|"
check "name spellings: the docs directory itself" \
  "$(dagents_name_spellings ./docs/dagents | tr '\n' '|')" "docs/dagents|docs/forge|docs/superpowers|"
check "name spellings: a trailing slash" \
  "$(dagents_name_spellings docs/forge/ | tr '\n' '|')" "docs/dagents|docs/forge|docs/superpowers|"
check "name spellings: any other name" "$(dagents_name_spellings .dagents/x.md | tr '\n' '|')" ".dagents/x.md|"

# --- the mapped project, from roots.sh and from dagents-path ---
FP="$HERE/../scripts/dagents-path"
stores_home "$HOME" "$REPO" superpowers local local > /dev/null
check "project: mapped, from a worktree" "$(cd "$WT" && dagents_project)" "superpowers"
check "project: dagents-path" "$(cd "$WT" && bash "$FP" project)" "superpowers"
OTHER="$TMP/other"
git init -q -b main "$OTHER"
git -C "$OTHER" commit -q --allow-empty -m init
(cd "$OTHER" && dagents_project > "$TMP/project-out")
check "project: unmapped is status 1" "$?" "1"
check "project: unmapped prints nothing" "$(cat "$TMP/project-out")" ""
(cd "$OTHER" && bash "$FP" project > "$TMP/project-out")
check "project: dagents-path unmapped exits 1" "$?" "1"
check "project: dagents-path unmapped prints nothing" "$(cat "$TMP/project-out")" ""
(cd "$TMP" && dagents_project > /dev/null)
check "project: outside git is status 1" "$?" "1"
(cd "$WT" && bash "$FP" project extra > /dev/null 2>&1)
check "project: dagents-path takes no argument" "$?" "2"
NB="$TMP/nonode-bin"
mkdir -p "$NB"
for c in git dirname; do ln -s "$(type -P "$c")" "$NB/$c"; done
(cd "$WT" && PATH="$NB" dagents_project > "$TMP/project-out")
check "project: without node is status 1" "$?" "1"
check "project: without node prints nothing" "$(cat "$TMP/project-out")" ""

# --- a --mode run that prints nothing stops the script ---
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/fakebin/node"
chmod +x "$TMP/fakebin/node"
(cd "$REPO" && PATH="$TMP/fakebin:$PATH" dagents_docs_root > /dev/null 2> "$TMP/err-empty")
check "empty --mode: exit 2" "$?" "2"
check "empty --mode: the message" "$(grep -c 'printed no roots' "$TMP/err-empty")" "1"

# --- a ConfigError stops the script ---
printf '{"darkmem":{"url":"http://127.0.0.1:9","repos":{"%s":{"project":"superpowers","documentStore":"cloud"}}}}\n' "$TOP" > "$HOME/.dagents/config.json"
(cd "$REPO" && dagents_docs_root > /dev/null 2> "$TMP/err")
check "config error: exit 2" "$?" "2"
check "config error: the message" "$(grep -c 'use local or darkmem' "$TMP/err")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
