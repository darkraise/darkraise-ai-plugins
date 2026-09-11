# Plan and ledger parsing shared by next-step and repo-audit, so both count the
# same tasks. Sourced; defines functions only.

# plan_tasks FILE — one "N<TAB>title" line per Task heading outside code fences.
# Same heading rule as task-brief.
plan_tasks() {
  tr -d '\r' < "$1" | awk '
    /^```/ { infence = !infence }
    !infence && /^#+[ \t]+Task[ \t]+[0-9]+/ {
      line = $0
      sub(/^#+[ \t]+Task[ \t]+/, "", line)
      n = line; sub(/[^0-9].*$/, "", n)
      t = line; sub(/^[0-9]+[: \t.-]*/, "", t)
      print n "\t" t
    }
  '
}

# ledger_done FILE — the task numbers with a "Task N: complete" line, sorted,
# unique.
ledger_done() {
  tr -d '\r' < "$1" | sed -n 's/^Task \([0-9][0-9]*\): complete.*/\1/p' | sort -un
}
