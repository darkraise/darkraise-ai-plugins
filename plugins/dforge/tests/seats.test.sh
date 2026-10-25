#!/usr/bin/env bash
# Every dforge seat is typed. A general-purpose prescription must name its
# model, or it inherits the session's, usually the most expensive. A
# prescription is a `Subagent (general-purpose):` template line, which needs a
# `model:` line before its block's closing fence, or a table row whose second
# cell (a Seats table's Agent column) is `general-purpose`, which needs a
# backticked model alias in the same row.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
names() { # names <label> <file> <text>
  check "$1" "$(grep -qF -- "$3" "$2" 2>/dev/null && echo yes || echo no)" "yes"
}

# unmodelled FILE... - one "file:line" per general-purpose prescription with no model
unmodelled() {
  awk '
    FNR == 1 { if (open) print where; open = 0 }
    open && /^[ \t]+model:/ { open = 0 }
    open && /^```/ { print where; open = 0 }
    /Subagent \(general-purpose\):/ { open = 1; where = FILENAME ":" FNR; next }
    /^\|/ {
      n = split($0, cell, "|")
      agent = cell[3]; gsub(/^[ \t]+/, "", agent); gsub(/[ \t]+$/, "", agent)
      if (agent == "general-purpose" && $0 !~ /`(sonnet|opus|haiku|fable)`/) print FILENAME ":" FNR
    }
    END { if (open) print where }
  ' "$@"
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

files=$(find "$P/skills" "$P/reference" -name '*.md' | LC_ALL=C sort)
# shellcheck disable=SC2086
check "no dforge prescription leaves a general-purpose seat unmodelled" "$(unmodelled $files)" ""

cat > "$TMP/bad-block.md" <<'EOF'
```
Subagent (general-purpose):
  description: "Review"
  prompt: |
    Review it.
```
EOF
check "a template block with no model is caught" "$(unmodelled "$TMP/bad-block.md")" "$TMP/bad-block.md:2"

cat > "$TMP/bad-row.md" <<'EOF'
| Seat | Agent | Model argument |
|---|---|---|
| Verifier | general-purpose | None |
EOF
check "a Seats row with no model is caught" "$(unmodelled "$TMP/bad-row.md")" "$TMP/bad-row.md:3"

cat > "$TMP/good.md" <<'EOF'
```
Subagent (general-purpose):
  description: "Re-review"
  model: [MODEL]
  prompt: |
    Re-review it.
```

| Seat | Agent | Model argument |
|---|---|---|
| Scoped re-review | general-purpose | `sonnet` |
EOF
check "a modelled block and row pass" "$(unmodelled "$TMP/good.md")" ""

RCR="$P/skills/requesting-code-review/SKILL.md"
CR="$P/skills/requesting-code-review/references/code-reviewer.md"
UD="$P/skills/using-dforge/SKILL.md"
names "requesting review: the judge seat" "$RCR" 'Dispatch `dforge:judge-opus` as `subagent_type`'
names "requesting review: the diff file comes first" "$RCR" 'git diff -U10 "$BASE_SHA..$HEAD_SHA"'
check "requesting review: no general-purpose seat" "$(grep -c 'general-purpose' "$RCR")" "0"
names "code reviewer: the judge seat" "$CR" 'Subagent (dforge:judge-opus):'
check "code reviewer: no git fallback" "$(grep -c 'derive it yourself' "$CR")" "0"
names "code reviewer: the diff file is required" "$CR" '`[DIFF_FILE]` — REQUIRED'
names "entry point: the Seats section" "$UD" '## Seats'
names "entry point: general-purpose takes a model" "$UD" '`general-purpose` takes an explicit `model`'
names "entry point: read-only checks on a judge" "$UD" 'Read-only checks (register rows, findings, a claim) go to `dforge:judge-sonnet-high`'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
