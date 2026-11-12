#!/usr/bin/env bash
# Acceptance tests for the wording-pin-deletion spec: the test-quality lens's
# path globs and the Test ratio must treat only real test directories and
# test files as tests.
set -uo pipefail
unset CLAUDE_CONFIG_DIR DFORGE_LENS_CAP
export DFORGE_NO_SETTINGS=1 DFORGE_LENS_MINOR_FROM=0

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$HERE/.."

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

new_repo() { # new_repo <dir>
  git init -q -b main "$1"
  git -C "$1" commit -q --allow-empty -m base
}
add_lines() { # add_lines <repo> <path>...  (one commit, one line per path)
  local repo=$1 path
  shift
  for path in "$@"; do
    mkdir -p "$repo/$(dirname "$path")"
    printf 'line\n' > "$repo/$path"
    git -C "$repo" add "$path"
  done
  git -C "$repo" commit -q -m "add files"
}

# A1: the Test ratio counts directory-named and test-named paths exactly.
R="$TMP/ratio"
new_repo "$R"
B=$(git -C "$R" rev-parse HEAD)
add_lines "$R" latest/a.txt contest/b.txt protests/c.txt src/latest_news.py \
  test/a.txt pkg/test/b.txt tests/c.txt pkg/tests/d.txt test_e.py pkg/test_f.py
H=$(git -C "$R" rev-parse HEAD)
out=$(cd "$R" && timeout 60 bash "$PLUGIN/scripts/review-record" ratio "$B" "$H"); rc=$?
check "A1: ratio over latest/ contest/ protests/ latest_news.py and six test paths: 6 test / 4 code" \
  "$rc:$(sed -E 's/\([0-9a-f]+\.\.[0-9a-f]+\)/(RANGE)/' <<<"$out")" \
  "0:Test ratio: 6 test / 4 code lines (RANGE)"

# A2: lens-route --final applies test-quality to pkg/test/ and not to latest/.
cat > "$TMP/plan.md" <<'PLAN'
# Acceptance Fixture Plan

## Task index

1. only

### Task 1: only

**Evaluation:** files 0 - spec 0 - coupling 0 - risk 0 = 0
PLAN
L="$TMP/lens"
new_repo "$L"
LB=$(git -C "$L" rev-parse HEAD)
add_lines "$L" latest/a.sh
LH1=$(git -C "$L" rev-parse HEAD)
git -C "$L" checkout -q -b only-test "$LB"
add_lines "$L" pkg/test/a.sh
LH3=$(git -C "$L" rev-parse HEAD)

out=$(cd "$L" && timeout 60 bash "$PLUGIN/scripts/lens-route" "$TMP/plan.md" --final "$LB" "$LH1"); rc=$?
check "A2: a change set whose only file is latest/a.sh: exit 0, no lens test-quality line" \
  "$rc:$(grep -c '^lens test-quality' <<<"$out")" "0:0"
out=$(cd "$L" && timeout 60 bash "$PLUGIN/scripts/lens-route" "$TMP/plan.md" --final "$LB" "$LH3"); rc=$?
check "A2: a change set whose only file is pkg/test/a.sh: exit 0, one lens test-quality line" \
  "$rc:$(grep -c '^lens test-quality' <<<"$out")" "0:1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
