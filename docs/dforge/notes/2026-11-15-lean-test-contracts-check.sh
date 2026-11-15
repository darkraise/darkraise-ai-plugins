#!/usr/bin/env bash
# m2-check.sh <n> <base> <commit> <tests: space-separated repo paths> <suite: space-separated test scripts>
# Runs M2 checks (a), (b), (c) in clone $M2_SCRATCH/m2-<n>, the seat's test files
# taken from $M2_WORK/<n>/; prints one result line per check.
set -u
n=$1 base=$2 commit=$3 tests=$4 suite=$5
S=${M2_SCRATCH:?set M2_SCRATCH to the directory holding the m2-<n> clones}
W=${M2_WORK:?set M2_WORK to the directory holding the seat outputs as <n>/}/$n
C=$S/m2-$n
LOG=$S/m2-$n.log
cd "$C" || exit 1
: > "$LOG"

git checkout -q -f "$base" && git clean -qfd
for t in $tests; do mkdir -p "$(dirname "$t")"; cp "$W/$(basename "$t")" "$t.contract.keep" || exit 1; done

put() { # put contract|plan
  for t in $tests; do
    mkdir -p "$(dirname "$t")"
    if [ "$1" = contract ]; then cp "$t.contract.keep" "$t"
    elif git cat-file -e "$commit:$t" 2>/dev/null; then git show "$commit:$t" > "$t"
    else rm -f "$t"; fi
    [ -f "$t" ] && chmod +x "$t" 2>/dev/null
  done
}
suite_rc() { # runs the Step 2 command; prints 0 when every suite exits 0
  local rc=0 s
  for s in $suite; do
    printf -- '--- %s (%s)\n' "$s" "$label" >> "$LOG"
    timeout -k 10 600 bash "$s" >> "$LOG" 2>&1 || rc=1
  done
  echo $rc
}
is_test() { local t; for t in $tests; do [ "$t" = "$1" ] && return 0; done; return 1; }
nontest=()
while IFS= read -r f; do is_test "$f" || nontest+=("$f"); done < <(git diff --name-only "$base" "$commit")

# (a) base, contract version: must fail. Control: plan version.
label="a contract"; put contract; a_c=$(suite_rc)
label="a plan"; put plan; a_p=$(suite_rc)
echo "run $n (a) base: contract rc=$a_c plan rc=$a_p -> $([ "$a_c" = 1 ] && echo PASS || echo FAIL)"

# (b) the commit's non-test files, contract version: must pass. Control: plan version.
git checkout -q "$commit" -- "${nontest[@]}"
label="b contract"; put contract; b_c=$(suite_rc)
label="b plan"; put plan; b_p=$(suite_rc)
echo "run $n (b) commit non-test files: contract rc=$b_c plan rc=$b_p -> $([ "$b_c" = 0 ] && echo PASS || echo FAIL)"

# (c) each non-test file reverted alone: whenever the plan version fails, the contract version fails too.
cfail=0
for f in "${nontest[@]}"; do
  if git cat-file -e "$base:$f" 2>/dev/null; then git checkout -q "$base" -- "$f"; else rm -f "$f"; fi
  label="c $f plan"; put plan; p=$(suite_rc)
  label="c $f contract"; put contract; c=$(suite_rc)
  if [ "$p" = 1 ] && [ "$c" = 0 ]; then v=FAIL; cfail=1; else v=ok; fi
  echo "run $n (c) $f reverted: plan rc=$p contract rc=$c -> $v"
  git checkout -q "$commit" -- "$f"
done
echo "run $n (c) -> $([ "$cfail" = 0 ] && echo PASS || echo FAIL)"
put contract
