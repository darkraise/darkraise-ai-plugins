#!/usr/bin/env bash
# Bisection script to find which test creates unwanted files/state
# Usage: ./find-polluter.sh <file_or_dir_to_check> <test_pattern> [test command]
#   The test command (default `npm test`) is split on spaces and run with
#   each test file as its last argument.
# Example: ./find-polluter.sh 'packages/core/.git' 'src/**/*.test.ts' 'npx vitest run'
# Exit: 0 no polluter among the runs (the last line says how many failed),
# 1 polluter found, 2 could not diagnose (usage
# error, pollution already present, no matching tests, a test command that
# cannot run, or every test run failing)

set -e

usage() {
  echo "Usage: $0 <file_to_check> <test_pattern> [test command]"
  echo "Example: $0 'packages/core/.git' 'src/**/*.test.ts' 'npx vitest run'"
  exit 2
}
[ $# -eq 2 ] || [ $# -eq 3 ] || usage

POLLUTION_CHECK="$1"
TEST_PATTERN="$2"
TEST_CMD="${3-npm test}"
read -r -a CMD <<< "$TEST_CMD"
[ ${#CMD[@]} -gt 0 ] || usage

if [ -e "$POLLUTION_CHECK" ] || [ -L "$POLLUTION_CHECK" ]; then
  echo "Pollution already exists; no diagnosis performed: $POLLUTION_CHECK"
  exit 2
fi

echo "🔍 Searching for test that creates: $POLLUTION_CHECK"
echo "Test pattern: $TEST_PATTERN"
echo "Test command: $TEST_CMD"
echo ""

# Get list of test files (find . emits ./-prefixed paths, so accept the
# pattern written with or without a leading ./)
TEST_PATTERN="${TEST_PATTERN#./}"
# find -path can't match '**/' against zero directory levels, so a pattern
# like src/**/*.test.ts would skip src/top.test.ts; also try the pattern
# with '**/' collapsed to cover files directly under the base directory.
# node_modules and .git are pruned: -path's * crosses /, so '**/*.test.ts'
# would otherwise reach dependencies' and hooks' files.
TEST_FILES=$(find . \( -name node_modules -o -name .git \) -prune -o \
  \( -path "./$TEST_PATTERN" -o -path "./${TEST_PATTERN//\*\*\//}" \) -print | sort -u)
if [ -z "$TEST_FILES" ]; then
  echo "No matching tests; no diagnosis performed. "
  exit 2
else
  TOTAL=$(printf '%s\n' "$TEST_FILES" | wc -l | tr -d ' ')
fi

echo "Found $TOTAL test files"
echo ""

COUNT=0
ANY_PASSED=no
FAILED=0
LAST_RC=0
# Read line by line so a path with a space stays one file; a here-string
# keeps the loop in this shell, so exit 1 below ends the script.
while IFS= read -r TEST_FILE; do
  COUNT=$((COUNT + 1))

  echo "[$COUNT/$TOTAL] Testing: $TEST_FILE"

  RC=0
  "${CMD[@]}" "$TEST_FILE" < /dev/null > /dev/null 2>&1 || RC=$?
  LAST_RC=$RC
  if [ "$RC" -eq 0 ]; then
    ANY_PASSED=yes
  else
    FAILED=$((FAILED + 1))
    echo "[$COUNT/$TOTAL] exit $RC"
  fi
  if [ "$RC" -eq 126 ] || [ "$RC" -eq 127 ]; then
    echo "Test command not runnable (exit $RC): $TEST_CMD; no diagnosis performed."
    exit 2
  fi

  # Check if pollution appeared
  if [ -e "$POLLUTION_CHECK" ] || [ -L "$POLLUTION_CHECK" ]; then
    echo ""
    echo "🎯 FOUND POLLUTER!"
    echo "   Test: $TEST_FILE"
    echo "   Created: $POLLUTION_CHECK"
    echo ""
    echo "Pollution details:"
    ls -la "$POLLUTION_CHECK"
    echo ""
    echo "To investigate:"
    echo "  $TEST_CMD '$TEST_FILE'    # Run just this test"
    echo "  cat '$TEST_FILE'         # Review test code"
    exit 1
  fi
done <<< "$TEST_FILES"

if [ "$ANY_PASSED" = no ]; then
  echo ""
  echo "Every test run failed (last exit $LAST_RC); no diagnosis performed. Check the test command: $TEST_CMD"
  exit 2
fi

echo ""
if [ "$FAILED" -gt 0 ]; then
  echo "No polluter found, but $FAILED of $TOTAL runs failed; no polluter among the ones that ran. A failed run may have stopped before its polluting code."
else
  echo "✅ No polluter found - all tests clean!"
fi
exit 0
