#!/usr/bin/env bash
# lib/roots.sh: every root is in the checkout, from the primary checkout and
# from a linked worktree, and names round-trip, including a checkout named
# superpowers.
set -uo pipefail
unset CLAUDE_CONFIG_DIR DAGENTS_DOCUMENT_STORE DAGENTS_PROGRESS_SOURCE CLAUDE_PROJECT_DIR

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../scripts/lib/roots.sh"

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

# --- no config ---
check "no config: docs root" "$(cd "$REPO" && dagents_docs_root)" "$TOP/docs/dagents"
check "no config: a worktree's ledger dir" "$(cd "$WT" && dagents_ledger_dir p1)" "$WT/.dagents/sdd/p1"
check "no config: latest.md from a worktree" "$(cd "$WT" && dagents_latest_file)" "$TOP/.dagents/handoff/latest.md"
check "no config: a DIR argument" "$(dagents_docs_root "$WT")" "$WT/docs/dagents"
check "outside git: local under the directory" "$(cd "$TMP" && dagents_docs_root)" "$TMP/docs/dagents"

# --- settings, a leftover darkmem key or stores.json start no node ---
mkdir -p "$TMP/marknode" "$HOME/.dagents"
printf '#!/bin/sh\n: > "%s"\nexit 1\n' "$TMP/node-ran" > "$TMP/marknode/node"
chmod +x "$TMP/marknode/node"
printf '{"handoffTokens": 300000, "darkmemEnabled": true, "darkmem": {"repos": {"%s": {"project": "p"}}}}\n' "$TOP" > "$HOME/.dagents/config.json"
printf '{"%s":{"documents":"darkmem","progress":"darkmem"}}\n' "$TOP" > "$HOME/.dagents/stores.json"
check "leftover keys: docs root" "$(cd "$REPO" && PATH="$TMP/marknode:$PATH" dagents_docs_root)" "$TOP/docs/dagents"
check "leftover keys: ledger dir" "$(cd "$REPO" && PATH="$TMP/marknode:$PATH" dagents_ledger_dir p1)" "$TOP/.dagents/sdd/p1"
check "leftover keys: latest.md from a worktree" "$(cd "$WT" && PATH="$TMP/marknode:$PATH" dagents_latest_file)" "$TOP/.dagents/handoff/latest.md"
check "leftover keys: node is not started" "$([ -e "$TMP/node-ran" ] && echo ran || echo skipped)" "skipped"
rm -rf "$TMP/node-ran" "$HOME/.dagents"

# --- the roots from the primary checkout and a worktree ---
for where in "$TOP" "$WT"; do
  label="from $(basename "$where")"
  want_docs="$where/docs/dagents"
  want_ledger="$where/.dagents/sdd/p1" want_latest="$TOP/.dagents/handoff/latest.md"
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

# --- ledger listings: every worktree's ---
mkdir -p "$REPO/.dagents/sdd/a" "$WT/.dagents/sdd/b"
printf 'x\n' > "$REPO/.dagents/sdd/a/progress.md"
printf 'x\n' > "$WT/.dagents/sdd/b/progress.md"
check "ledger files: lists each worktree's" "$(cd "$WT" && dagents_ledger_files | sort)" \
  "$(printf '%s\t%s\n%s\t%s' "$TOP/.dagents/sdd/a/progress.md" "$TOP" "$WT/.dagents/sdd/b/progress.md" "$WT" | sort)"

# --- a relative file spelled from a subdirectory is named from the checkout ---
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
  "$(dagents_name_spellings docs/superpowers/plans/p.md | tr '\n' '|')" "docs/dagents/plans/p.md|docs/dforge/plans/p.md|docs/forge/plans/p.md|docs/superpowers/plans/p.md|"
check "name spellings: the docs directory itself" \
  "$(dagents_name_spellings ./docs/dagents | tr '\n' '|')" "docs/dagents|docs/dforge|docs/forge|docs/superpowers|"
check "name spellings: a trailing slash" \
  "$(dagents_name_spellings docs/forge/ | tr '\n' '|')" "docs/dagents|docs/dforge|docs/forge|docs/superpowers|"
check "name spellings: any other name" "$(dagents_name_spellings .dagents/x.md | tr '\n' '|')" ".dagents/x.md|"

# --- dforge 4.x citations read as an older spelling ---
check "dforge key" "$(dagents_name_key docs/dforge/plans/x.md)" "docs/dagents/plans/x.md"
check "dforge root key" "$(dagents_name_key docs/dforge)" "docs/dagents"
check "spellings: key, then dforge first" "$(dagents_name_spellings docs/dagents/plans/x.md | tr '\n' '|')" "docs/dagents/plans/x.md|docs/dforge/plans/x.md|docs/forge/plans/x.md|docs/superpowers/plans/x.md|"
check "dforge citation resolves" "$(cd "$TOP" && dagents_resolve docs/dforge/plans/x.md)" "$(cd "$TOP" && dagents_docs_root)/plans/x.md"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
