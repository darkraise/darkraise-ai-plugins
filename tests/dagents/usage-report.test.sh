#!/usr/bin/env bash
# The dagents usage-report wrapper reads dagents' own stores only: the
# primary checkout's .dagents markers, never a .dforge marker file beside them.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAP="$HERE/../../plugins/dagents/scripts/usage-report"
TMP=$(mktemp -d)
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export MSYS_NO_PATHCONV=1 GIT_CONFIG_NOSYSTEM=1 HOME="$TMP/home"
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# rows PLUGIN TASK — an open and a close row for TASK of the plan.
rows() {
  printf '2026-01-01T00:00:00Z\topen\t%s\t1.0.0\t/plugin\tdocs/dagents/plans/p.md\t%s\ts1\t\t\t\ttask-brief:%s\t\t\n' "$1" "$2" "$2"
  printf '2026-01-01T00:01:00Z\tclose\t%s\t1.0.0\t/plugin\tdocs/dagents/plans/p.md\t%s\ts1\t\t\t\ttask-close:%s\ta..b\t\n' "$1" "$2" "$2"
}

# --- wrapper_reads_own_stores ---
R="$TMP/repo"
git init -q "$R"
git -C "$R" config user.name Darkraise
git -C "$R" config user.email dark@example.invalid
mkdir -p "$R/docs/dagents/plans" "$R/.dagents/sdd" "$R/.dforge/sdd"
printf '# P\n\n### Task 1: one\n\nBody.\n\n### Task 2: two\n\nBody.\n' > "$R/docs/dagents/plans/p.md"
git -C "$R" add docs
git -C "$R" commit -q -m init
rows dagents 1 > "$R/.dagents/sdd/usage-markers.tsv"
rows dforge 2 > "$R/.dforge/sdd/usage-markers.tsv"
J=$(cd "$R" && bash "$WRAP" --format json 2>/dev/null)
check "wrapper_reads_own_stores: one plan" "$(jq -c '.plans | length' <<<"$J" 2>/dev/null | tr -d '\r')" "1"
check "wrapper_reads_own_stores: only the .dagents task" \
  "$(jq -c '[.plans[0].tasks[].tasks[]]' <<<"$J" 2>/dev/null | tr -d '\r')" "[1]"
J=$(cd "$R" && bash "$WRAP" --plan docs/dagents/plans/p.md --format json 2>/dev/null)
check "wrapper_reads_own_stores: --plan names the plan" "$(jq -c '[.plans[].completed]' <<<"$J" 2>/dev/null | tr -d '\r')" "[1]"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
