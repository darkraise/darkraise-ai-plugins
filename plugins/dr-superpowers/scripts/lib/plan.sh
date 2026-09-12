# Plan and ledger parsing shared by task-brief, plan-lint, plan-amend, next-step
# and repo-audit, so every reader agrees on what a task, the header and an
# amendment are. Sourced; defines functions only.

_PLAN_LIB_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# CommonMark fence rule, the one scripts/validate-repository.mjs uses: a fence
# closes only at a bare marker of the same character at least as long as the
# opener, so a 4-backtick block may hold 3-backtick fences. in_fence(line)
# returns 1 for fence markers and fenced lines. is_task(line) returns the task
# number of a task heading, or -1.
_PLAN_AWK='
function close_marker(t, open) {
  sub(/^ ? ? ?/, "", t); sub(/[ \t]+$/, "", t)
  return t ~ /^(`+|~+)$/ && substr(t, 1, 1) == substr(open, 1, 1) && length(t) >= length(open)
}
function in_fence(line,   mk) {
  if (FENCE != "") {
    if (close_marker(line, FENCE)) FENCE = ""
    return 1
  }
  if (match(line, /^ ? ? ?(`+|~+)/)) {
    mk = substr(line, RSTART, RLENGTH); sub(/^ +/, "", mk)
    if (length(mk) >= 3) { FENCE = mk; return 1 }
  }
  return 0
}
function is_task(line,   n) {
  if (line !~ /^#+[ \t]+Task[ \t]+[0-9]+/) return -1
  n = line; sub(/^#+[ \t]+Task[ \t]+/, "", n); sub(/[^0-9].*$/, "", n)
  return n + 0
}
'

# plan_tasks FILE — one "N<TAB>title" line per task heading outside fences.
plan_tasks() {
  tr -d '\r' < "$1" | awk "$_PLAN_AWK"'
    in_fence($0) { next }
    is_task($0) >= 0 {
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

# plan_header_line FILE LABEL — the first line outside fences that begins
# "**LABEL:**", or nothing.
plan_header_line() {
  tr -d '\r' < "$1" | awk -v p="**$2:**" "$_PLAN_AWK"'
    in_fence($0) { next }
    index($0, p) == 1 { print; exit }
  '
}

# plan_header FILE — every line before the first task heading.
plan_header() {
  tr -d '\r' < "$1" | awk "$_PLAN_AWK"'
    { f = in_fence($0) }
    !f && is_task($0) >= 0 { exit }
    { print }
  '
}

# plan_task_text FILE N — task N from its heading to the line before the next
# task heading. Exit 3 when there is no such task.
plan_task_text() {
  tr -d '\r' < "$1" | awk -v want="$2" "$_PLAN_AWK"'
    { f = in_fence($0); k = f ? -1 : is_task($0) }
    k >= 0 { intask = (k == want + 0); if (intask) found = 1 }
    intask { print }
    END { exit found ? 0 : 3 }
  '
}

# plan_apply_amendments PLAN AMEND — the plan with every amendments.md entry
# applied in file order; the plan unchanged when AMEND is missing or empty.
# Exit 1, naming the entry on stderr, when an entry does not apply: its Old
# lines must match a contiguous run of whole lines of its target exactly once.
plan_apply_amendments() {
  if [ ! -s "${2:-}" ]; then tr -d '\r' < "$1"; return 0; fi
  awk "$_PLAN_AWK"'
    function bounds(ent,   i, k) {
      FENCE = ""; S = 0; E = 0
      for (i = 1; i <= n; i++) {
        k = in_fence(L[i]) ? -1 : is_task(L[i])
        if (TGT[ent] == "H") { if (k >= 0) { S = 1; E = i - 1; return } }
        else if (S == 0 && k == TGT[ent] + 0) S = i
        else if (S > 0 && k >= 0) { E = i - 1; return }
      }
      if (TGT[ent] == "H") { S = 1; E = n } else if (S > 0) E = n
    }
    FNR == NR {
      sub(/\r$/, "")
      if (mode != "" ) {
        if (close_marker($0, open)) { mode = ""; next }
        if (mode == "old") OLD[m, ++OC[m]] = $0; else NEW[m, ++NC[m]] = $0
        next
      }
      if ($0 ~ /^## A[0-9]+ (—|-) (Task [0-9]+|Header)[ \t]*$/) {
        m++; ID[m] = $2
        t = $0; sub(/^## A[0-9]+ (—|-) /, "", t); sub(/[ \t]+$/, "", t)
        if (t == "Header") TGT[m] = "H"; else { sub(/^Task /, "", t); TGT[m] = t }
        sect = ""; next
      }
      if ($0 ~ /^### Old[ \t]*$/) { sect = "old"; next }
      if ($0 ~ /^### New[ \t]*$/) { sect = "new"; next }
      if (sect != "" && match($0, /^(````+|~~~~+)/)) {
        open = substr($0, RSTART, RLENGTH); mode = sect; sect = ""; next
      }
      next
    }
    { sub(/\r$/, ""); L[++n] = $0 }
    END {
      for (e = 1; e <= m; e++) {
        bounds(e)
        k = OC[e] + 0; hits = 0
        if (S > 0 && k > 0)
          for (i = S; i + k - 1 <= E; i++) {
            ok = 1
            for (j = 1; j <= k; j++) if (L[i + j - 1] != OLD[e, j]) { ok = 0; break }
            if (ok) { hits++; at = i }
          }
        if (hits != 1) { print "amendment " ID[e] " does not apply" > "/dev/stderr"; exit 1 }
        c = 0
        for (i = 1; i < at; i++) N2[++c] = L[i]
        for (j = 1; j <= NC[e] + 0; j++) N2[++c] = NEW[e, j]
        for (i = at + k; i <= n; i++) N2[++c] = L[i]
        delete L; n = c
        for (i = 1; i <= n; i++) L[i] = N2[i]
        delete N2
      }
      for (i = 1; i <= n; i++) print L[i]
    }
  ' "$2" "$1"
}

# plan_amendments_file PLAN — <workspace>/amendments.md when PLAN is inside a
# git repository and that file is non-empty; otherwise nothing.
plan_amendments_file() {
  local dir
  dir=$(cd "$(dirname "$1")" 2>/dev/null \
    && git rev-parse --show-toplevel >/dev/null 2>&1 \
    && "$_PLAN_LIB_DIR/../sdd-workspace" "$(basename "$1")" 2>/dev/null) || return 0
  [ -s "$dir/amendments.md" ] && printf '%s\n' "$dir/amendments.md"
  return 0
}
