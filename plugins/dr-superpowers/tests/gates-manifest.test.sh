#!/usr/bin/env bash
# The gates manifest is a format that adopting projects depend on, and the
# skill is the only specification of it. These checks pin the parts two
# sessions could otherwise read differently: the field set, the evidence
# values, the default, and the retry rule.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
SKILL="$P/skills/running-gates/SKILL.md"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <file> <needle>
  if grep -qF -- "$3" "$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}

check "exists: skills/running-gates/SKILL.md" \
  "$([ -f "$SKILL" ] && echo yes || echo no)" "yes"

present "gates names the manifest path" "$SKILL" 'docs/superpowers/gates.md'

# Two required fields and seven optional ones.
for f in Command Green; do
  present "required field $f" "$SKILL" "**\`$f\`**"
done
for f in Applies Evidence Repo Setup Teardown Known-flaky Why; do
  present "optional field $f" "$SKILL" "**\`$f\`**"
done
present "gates says seven optional fields" "$SKILL" 'Optional, seven of them'

# The four evidence values and the default. Defaulting to exit would make every
# Green line decorative in a manifest that omits the field.
for v in output exit image judgment; do
  present "evidence value $v" "$SKILL" "\`$v\`"
done
present "evidence default is output" "$SKILL" 'default is `output`'
present "output evidence needs the Green text" "$SKILL" 'The declared `Green` text appears in this run'
present "every gate also requires exit 0" "$SKILL" 'requires its command to exit 0'

# Branch-level only. A pointer from verification-before-completion would reach
# all sixteen implementer agents.
present "gates are branch level" "$SKILL" 'branch level'

# The rules that stop a rotted or flaky manifest passing silently.
present "stop at the first red" "$SKILL" 'first red'
present "known-flaky retries only its own failure" "$SKILL" 'matches the `Known-flaky`'
present "a non-launching gate is a manifest defect" "$SKILL" 'manifest defect'
present "gates computes its own base" "$SKILL" 'merge-base'
present "gates states a skip" "$SKILL" 'silent skip'

TPL="$P/skills/running-gates/references/gates-template.md"
check "exists: references/gates-template.md" \
  "$([ -f "$TPL" ] && echo yes || echo no)" "yes"

# The template is the worked example the format documents, so it must satisfy
# the format. Line classes are enumerated rather than rejected by exclusion:
# an H1, prose before the first gate, a gate heading, a blank line, a Field:
# line with one of the nine names, a two-space continuation, or a fenced line.
awk_out=$(awk '
  BEGIN {
    split("Command Green Applies Evidence Repo Setup Teardown Known-flaky Why", f, " ")
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
    next
  }
  { print "stray line: " $0 }
  END { if (seen_gate && !(cmd && grn)) print "gate " prev " missing Command or Green" }
' <(tr -d '\r' < "$TPL") 2>&1)
check "template satisfies the documented format" "$awk_out" ""

present "template shows the fenced Setup form" "$TPL" 'Setup:'
present "template shows an image gate" "$TPL" 'Evidence: image'
present "template carries a blank skeleton" "$TPL" 'Copy the block below for a new gate'

FIN="$P/skills/finishing-a-development-branch/SKILL.md"
VBC="$P/skills/verification-before-completion/SKILL.md"

present "finishing prefers the gates manifest" "$FIN" 'dr-superpowers:running-gates'
present "finishing verifies the merged result with gates" "$FIN" 'gates when the project declares a manifest'
present "finishing writes the completed index" "$FIN" 'docs/superpowers/plans/completed.md'
present "index write is bound to the outcome" "$FIN" 'not to Step 6'
present "option 2 records via PR" "$FIN" 'via PR'
present "a discard records nothing" "$FIN" 'write nothing'

# All sixteen implementer agents preload verification-before-completion. A
# gates pointer there would tell every task implementer to run a branch-level
# manifest.
absent "verification-before-completion never names running-gates" "$VBC" 'running-gates'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
