#!/usr/bin/env bash
# The gates manifest is a format that adopting projects depend on. The template
# is its worked example, so it must satisfy the format.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL="$P/skills/running-gates/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

check "exists: skills/running-gates/SKILL.md" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

TPL="$P/skills/running-gates/references/gates-template.md"
check "exists: references/gates-template.md" \
  "$([ -f "$TPL" ] && echo yes || echo no)" "yes"

# The template is the worked example the format documents, so it must satisfy
# the format. Line classes are enumerated rather than rejected by exclusion:
# an H1, prose before the first gate, a gate heading, a blank line, a Field:
# line with one of the eleven names, a two-space continuation, or a fenced line.
awk_out=$(awk '
  BEGIN {
    split("Command Green Applies Evidence Repo Setup Teardown Known-flaky Why Tier Budget", f, " ")
    for (i in f) field[f[i]] = 1
    split("output exit image judgment", e, " ")
    for (i in e) ev[e[i]] = 1
    expect = 1; seen_gate = 0; fence = 0
  }
  /^(```|~~~)/ { fence = !fence; next }
  fence { next }
  /^# / { if (!seen_gate) next }
  /^## / {
    if ($0 !~ /^## [0-9]+\. .+/) { print "bad heading: " $0; next }
    n = $0; sub(/^## /, "", n); sub(/\..*$/, "", n)
    if (n + 0 != expect) print "non-contiguous: want " expect " got " n
    expect = n + 1
    if (seen_gate && !(cmd && grn)) print "gate " prev " missing Command or Green"
    prev = n; cmd = 0; grn = 0; seen_gate = 1
    next
  }
  /^$/ { next }
  /^  / { next }
  !seen_gate { next }
  /^[A-Za-z-]+:/ {
    name = $0; sub(/:.*$/, "", name)
    if (!(name in field)) { print "unknown field: " name; next }
    if (name == "Command") cmd = 1
    if (name == "Green") grn = 1
    if (name == "Evidence") {
      v = $0; sub(/^Evidence:[ \t]*/, "", v); gsub(/`/, "", v); sub(/[ \t]+$/, "", v)
      if (!(v in ev)) print "bad evidence: " v
    }
    if (name == "Tier") {
      v = $0; sub(/^Tier:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (v != "task" && v != "branch" && v != "sweep") print "bad tier: " v
    }
    if (name == "Budget") {
      v = $0; sub(/^Budget:[ \t]*/, "", v); sub(/[ \t]+$/, "", v)
      if (v !~ /^[0-9]+s$/) print "bad budget: " v
    }
    next
  }
  { print "stray line: " $0 }
  END { if (seen_gate && !(cmd && grn)) print "gate " prev " missing Command or Green" }
' <(tr -d '\r' < "$TPL") 2>&1)
check "template satisfies the documented format" "$awk_out" ""

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
