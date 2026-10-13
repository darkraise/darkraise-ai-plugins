#!/usr/bin/env bash
# lib/roots.sh: each family's root follows its applied store, from the primary
# checkout and from a linked worktree, and names round-trip in all four
# combinations, including a checkout and a project both named superpowers.
set -uo pipefail
unset CLAUDE_CONFIG_DIR DR_FORGE_DOCUMENT_STORE DR_FORGE_PROGRESS_SOURCE

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
check "no config: docs root" "$(cd "$REPO" && forge_docs_root)" "$TOP/docs/forge"
check "no config: stores" "$(cd "$REPO" && forge_docs_store) $(cd "$REPO" && forge_progress_store)" "local local"
check "no config: a worktree's ledger dir" "$(cd "$WT" && forge_ledger_dir p1)" "$WT/.forge/sdd/p1"
check "no config: latest.md from a worktree" "$(cd "$WT" && forge_latest_file)" "$TOP/.forge/handoff/latest.md"
check "no config: a DIR argument" "$(forge_docs_root "$WT")" "$WT/docs/forge"
check "outside git: local under the directory" "$(cd "$TMP" && forge_docs_root)" "$TMP/docs/forge"

# --- the four applied combinations, from the primary checkout and a worktree ---
for docs in local darkmem; do
  for progress in local darkmem; do
    MIRROR=$(stores_home "$HOME" "$REPO" superpowers "$docs" "$progress")
    for where in "$TOP" "$WT"; do
      label="$docs/$progress from $(basename "$where")"
      if [ "$docs" = darkmem ]; then want_docs="$MIRROR/superpowers"; else want_docs="$where/docs/forge"; fi
      if [ "$progress" = darkmem ]; then
        want_ledger="$MIRROR/work/sdd/p1" want_latest="$MIRROR/work/handoff/latest.md"
      else
        want_ledger="$where/.forge/sdd/p1" want_latest="$TOP/.forge/handoff/latest.md"
      fi
      check "$label: stores" "$(cd "$where" && forge_docs_store) $(cd "$where" && forge_progress_store)" "$docs $progress"
      check "$label: docs root" "$(cd "$where" && forge_docs_root)" "$want_docs"
      check "$label: ledger dir" "$(cd "$where" && forge_ledger_dir p1)" "$want_ledger"
      check "$label: latest.md" "$(cd "$where" && forge_latest_file)" "$want_latest"
      check "$label: the workspace stays local" "$(cd "$where" && forge_workspace p1)" "$where/.forge/sdd/p1"
      check "$label: a document name" "$(cd "$where" && forge_resolve docs/forge/plans/p1.md)" "$want_docs/plans/p1.md"
      check "$label: a pre-2.0 document name" "$(cd "$where" && forge_resolve docs/superpowers/plans/p1.md)" "$want_docs/plans/p1.md"
      check "$label: a working name" "$(cd "$where" && forge_resolve .forge/sdd/p1/brief.md)" "$where/.forge/sdd/p1/brief.md"
      check "$label: an absolute path stays" "$(cd "$where" && forge_resolve /x/y.md)" "/x/y.md"
      check "$label: a document round-trips" "$(cd "$where" && forge_name "$(forge_resolve docs/forge/plans/p1.md)")" "docs/forge/plans/p1.md"
      check "$label: a working file round-trips" "$(cd "$where" && forge_name "$where/.forge/x.md")" ".forge/x.md"
      check "$label: a name stays a name" "$(cd "$where" && forge_name ./docs/forge/specs/s.md)" "docs/forge/specs/s.md"
      check "$label: an outside path stays" "$(cd "$where" && forge_name /elsewhere/superpowers/a.md)" "/elsewhere/superpowers/a.md"
    done
  done
done

# --- ledger listings: every worktree's when local, the mirror's once when darkmem ---
mkdir -p "$REPO/.forge/sdd/a" "$WT/.forge/sdd/b"
printf 'x\n' > "$REPO/.forge/sdd/a/progress.md"
printf 'x\n' > "$WT/.forge/sdd/b/progress.md"
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local local)
check "ledger files: local lists each worktree's" "$(cd "$WT" && forge_ledger_files | sort)" \
  "$(printf '%s\t%s\n%s\t%s' "$TOP/.forge/sdd/a/progress.md" "$TOP" "$WT/.forge/sdd/b/progress.md" "$WT" | sort)"
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local darkmem)
mkdir -p "$MIRROR/work/sdd/c"
printf 'x\n' > "$MIRROR/work/sdd/c/progress.md"
check "ledger files: darkmem lists the mirror's once" "$(cd "$WT" && forge_ledger_files)" "$(printf '%s\tmirror' "$MIRROR/work/sdd/c/progress.md")"

# --- a pre-2.0 checkout keeps its names ---
MIRROR=$(stores_home "$HOME" "$REPO" superpowers local local)
mkdir -p "$WT/docs/superpowers/plans"
check "pre-2.0: the docs root" "$(cd "$WT" && forge_docs_root)" "$WT/docs/superpowers"
check "pre-2.0: the name" "$(cd "$WT" && forge_name "$WT/docs/superpowers/plans/p.md")" "docs/superpowers/plans/p.md"

# --- a relative file spelled from a subdirectory is named from the checkout ---
printf 'p\n' > "$WT/docs/superpowers/plans/p.md"
check "subdirectory: a relative file" "$(cd "$WT/docs/superpowers/plans" && forge_name p.md)" "docs/superpowers/plans/p.md"
check "subdirectory: a name that is no file here stays" "$(cd "$WT/docs/superpowers/plans" && forge_name docs/superpowers/plans/p.md)" "docs/superpowers/plans/p.md"

# --- a --mode run that prints nothing stops the script ---
mkdir -p "$TMP/fakebin"
printf '#!/bin/sh\nexit 0\n' > "$TMP/fakebin/node"
chmod +x "$TMP/fakebin/node"
(cd "$REPO" && PATH="$TMP/fakebin:$PATH" forge_docs_root > /dev/null 2> "$TMP/err-empty")
check "empty --mode: exit 2" "$?" "2"
check "empty --mode: the message" "$(grep -c 'printed no roots' "$TMP/err-empty")" "1"

# --- a ConfigError stops the script ---
printf '{"darkmem":{"url":"http://127.0.0.1:9","repos":{"%s":{"project":"superpowers","documentStore":"cloud"}}}}\n' "$TOP" > "$HOME/.dr-forge/config.json"
(cd "$REPO" && forge_docs_root > /dev/null 2> "$TMP/err")
check "config error: exit 2" "$?" "2"
check "config error: the message" "$(grep -c 'use local or darkmem' "$TMP/err")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
