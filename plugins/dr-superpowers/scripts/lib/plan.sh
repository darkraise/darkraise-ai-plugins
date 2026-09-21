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
      t = line; sub(/^[0-9]+[ \t]*[:.-]?[ \t]*/, "", t)
      print n "\t" t
    }
  '
}

# ledger_done FILE — the task numbers with a "Task N: complete" line, sorted,
# unique.
ledger_done() {
  tr -d '\r' < "$1" | sed -n 's/^Task \([0-9][0-9]*\): complete.*/\1/p' | sort -un
}

# ledger_plan FILE — the plan path the ledger's identity line names, or nothing.
ledger_plan() {
  head -n 1 "$1" | tr -d '\r' | sed -n 's/^# SDD ledger — plan: //p'
}

# plan_primary_root [DIR] — the primary checkout's top level for the worktree
# containing DIR (default: the current directory); nothing outside a repository.
plan_primary_root() {
  local common
  common=$(git -C "${1:-.}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null
}

# ladder_block TAG — the lines of reference/ladder.md's ```TAG fenced block,
# blank lines dropped.
# DR_LADDER is a test seam: a suite that needs a fixture executor's blocks
# points it at the shipped ladder plus its own. Unset in production.
ladder_block() {
  tr -d '\r' < "${DR_LADDER:-$_PLAN_LIB_DIR/../../reference/ladder.md}" \
    | awk -v tag="$1" 'stop { next } $0 == "```" tag { f = 1; next } f && /^```/ { stop = 1; next } f && NF { print }'
}

# ledger_blocked FILE — the task numbers whose terminal ledger line is
# "Task N: BLOCKED", sorted, unique. BLOCKED is terminal: a resumed session must
# not start the task. The Recovery rule both execution skills define reads the
# last "Task N:" line in file order, stepping over the kinds that are not
# terminal, so a BLOCKED the owner resolved and the task re-ran is not blocked
# any more — a flat grep would keep reporting it forever.
ledger_blocked() {
  tr -d '\r' < "$1" | awk '
    !/^Task [0-9]+:/ { next }
    /^Task [0-9]+: (minor \(deferred\)|parked|Ruling:)/ { next }
    { n = $2; sub(/:$/, "", n); blocked[n] = ($0 ~ /^Task [0-9]+: BLOCKED/) }
    END { for (n in blocked) if (blocked[n]) print n }
  ' | sort -un
}

# plan_header_line FILE LABEL — the first line outside fences that begins
# "**LABEL:**", or nothing.
# awk stops at a flag rather than exit: exiting leaves tr writing into a closed
# pipe, and under pipefail that SIGPIPE becomes the caller's exit status on any
# plan larger than the pipe buffer.
plan_header_line() {
  tr -d '\r' < "$1" | awk -v p="**$2:**" "$_PLAN_AWK"'
    stop { next }
    in_fence($0) { next }
    index($0, p) == 1 { print; stop = 1 }
  '
}

# plan_header FILE — every line before the first task heading.
plan_header() {
  tr -d '\r' < "$1" | awk "$_PLAN_AWK"'
    stop { next }
    { f = in_fence($0) }
    !f && is_task($0) >= 0 { stop = 1; next }
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

# plan_lines LABEL — the `**LABEL:**` lines of the task text on stdin that lie
# outside every fenced block, in order. A plan that shows a line inside a fence
# is documenting the format, not annotating a task.
plan_lines() {
  awk -v lab="$1" "$_PLAN_AWK"'
    in_fence($0) { next }
    index($0, "**" lab ":**") == 1 { print }
  '
}

# plan_task_parts — the part letters of the task text on stdin, in order, one
# per line. A `#### Part <L>:` heading inside a fence is an example, not a part.
plan_task_parts() {
  awk "$_PLAN_AWK"'
    in_fence($0) { next }
    /^#### Part [A-Z]:/ { print substr($3, 1, 1) }
  '
}

# plan_part_text PART — the text of one part of the task text on stdin, from its
# heading to the next part heading. A fenced line belongs to the part that
# opened the fence, so a fenced part heading neither opens nor closes a part.
plan_part_text() {
  awk -v p="$1" "$_PLAN_AWK"'
    in_fence($0) { if (on) print; next }
    /^#### Part [A-Z]:/ { on = (substr($3, 1, 1) == p) }
    on { print }
  '
}

# plan_eval_lines — the **Evaluation:** lines that score the task text on stdin.
# Fenced lines never score. When the text holds any part heading, only the lines
# at or after the first one score: a line left above `#### Part A` scores the
# task as it stood before the split, which is the score that forced the split.
plan_eval_lines() {
  awk "$_PLAN_AWK"'
    in_fence($0) { next }
    /^#### Part [A-Z]:/ { parts = 1; next }
    /^\*\*Evaluation:\*\*/ { if (parts) print; else pre[++k] = $0 }
    END { if (!parts) for (i = 1; i <= k; i++) print pre[i] }
  '
}

# plan_scores FILE — one "N<TAB>total<TAB>risk" line per task: the highest total
# and the highest risk among the task's Claude-host **Evaluation:** lines, as
# plan_eval_lines selects them. "N<TAB>-<TAB>-" when the task has no
# Evaluation line, "N<TAB>?<TAB>?" when one does not parse.
plan_scores() {
  local sep='( — | – | - | -- )' n _title evs ev tot risk bad
  while IFS=$'\t' read -r n _title; do
    [ -n "$n" ] || continue
    evs=$(plan_task_text "$1" "$n" | plan_eval_lines)
    if [ -z "$evs" ]; then printf '%s\t-\t-\n' "$n"; continue; fi
    tot=-1 risk=-1 bad=0
    while IFS= read -r ev; do
      if [[ "$ev" =~ ^\*\*Evaluation:\*\*\ files\ [0-9]+$sep"spec "[0-9]+$sep"coupling "[0-9]+$sep"risk "([0-9]+)\ =\ ([0-9]+) ]]; then
        [ "${BASH_REMATCH[4]}" -le "$risk" ] || risk=${BASH_REMATCH[4]}
        [ "${BASH_REMATCH[5]}" -le "$tot" ] || tot=${BASH_REMATCH[5]}
      else
        bad=1
      fi
    done <<<"$evs"
    if [ "$bad" -eq 1 ]; then printf '%s\t?\t?\n' "$n"; else printf '%s\t%s\t%s\n' "$n" "$tot" "$risk"; fi
  done < <(plan_tasks "$1")
}

# plan_executors FILE — `<task>\t<id>` for every task carrying an Executor
# line outside a fenced block, in any part. One row per task: a split task
# whose parts each name one takes the first. Exit 0 whether or not any task
# carries a line: ordinary absence is not a failure.
#
# The Executor line is the decision the plan already made. Nothing here
# re-evaluates a gate, because execution time must not second-guess planning.
plan_executors() {
  local n _title id
  while IFS=$'\t' read -r n _title; do
    [ -n "$n" ] || continue
    # No `exit`: scripts/lib/plan.sh:92-94 records that an early exit leaves
    # the upstream writer on a closed pipe, and under `pipefail` that SIGPIPE
    # becomes the caller's status - and task-brief runs `set -euo pipefail`.
    id=$(plan_task_text "$1" "$n" | awk "$_PLAN_AWK"'
      in_fence($0) { next }
      !found && /^\*\*Executor:\*\*/ { sub(/^\*\*Executor:\*\*[ \t]*/, ""); id = $1; found = 1 }
      END { if (found) print id }')
    # An `if`, not `[ -n "$id" ] && printf`: the last iteration's status becomes
    # the function's, so a final task with no Executor line would return 1 and
    # abort plan_delegated's `execs=` assignment under errexit, emitting no rows
    # at all - and an empty delegated set reads as "nothing is delegated".
    if [ -n "$id" ]; then printf '%s\t%s\n' "$n" "$id"; fi
  done < <(plan_tasks "$1")
}

# plan_heavy FILE — the task numbers mixed mode delegates: a highest total of 5
# or more, or a highest risk of 3. One per line, ascending.
plan_heavy() {
  plan_scores "$1" | awk -F'\t' '$2 != "-" && $2 != "?" && ($2 + 0 >= 5 || $3 + 0 == 3) { print $1 }'
}

# plan_delegated FILE — the tasks an inline plan delegates, one "N<TAB>heavy",
# "N<TAB>executor" or "N<TAB>total 4" line each, ascending. Heavy tasks always,
# then the tasks an Executor line marks for an external executor. Tasks whose
# highest total is exactly 4 only while they are a third of the plan or fewer:
# past that, one Opus session costs less than a seat for each of them.
plan_delegated() {
  local tasks execs
  tasks=$(plan_tasks "$1" | grep -c . || true)
  execs=$(plan_executors "$1" | cut -f1 | tr '\n' ' ')
  plan_scores "$1" | awk -F'\t' -v n="$tasks" -v execs=" $execs" '
    $2 == "-" || $2 == "?" { next }
    # Heavy first: a heavy task is delegated whatever else it is, and the
    # (heavy) label is what the preflight ruling keys on.
    $2 + 0 >= 5 || $3 + 0 == 3 { row[++k] = $1 "\theavy"; next }
    # A total-4 task counts toward the four-band population whether or not it
    # is offloaded. Removing it from the numerator could flip the threshold
    # and newly delegate other four-band tasks nobody marked.
    $2 + 0 == 4 { four++ }
    index(execs, " " $1 " ") > 0 { row[++k] = $1 "\texecutor"; next }
    $2 + 0 == 4 { row[++k] = $1 "\ttotal 4" }
    END {
      for (i = 1; i <= k; i++)
        if (row[i] !~ /\ttotal 4$/ || 3 * four <= n + 0) print row[i]
    }
  '
}

# Git reports the top level in one form (C:/… under Git Bash) whichever way the
# path was spelled, so comparing <top level>/<prefix><name> is stable where pwd
# output is not: /tmp and /c/Users/…/Temp name the same directory.
plan_repo_canon() {
  local dir top prefix
  dir=$(dirname "$1")
  top=$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null) || return 1
  prefix=$(git -C "$dir" rev-parse --show-prefix 2>/dev/null) || return 1
  printf '%s/%s%s\n' "$top" "$prefix" "$(basename "$1")"
}

# plan_ledger PLAN — the plan's ledger file when it exists and its identity line
# names PLAN; nothing otherwise. A stale ledger under the same slug is ignored.
plan_ledger() {
  local want top file named got
  want=$(plan_repo_canon "$1") || return 0
  top=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null) || return 0
  file="$top/.superpowers/sdd/$(basename "$1" .md)/progress.md"
  [ -f "$file" ] || return 0
  named=$(ledger_plan "$file")
  [ -n "$named" ] || return 0
  if command -v cygpath >/dev/null 2>&1; then
    named=$(cygpath -u "$named" 2>/dev/null || printf '%s' "$named")
  fi
  case $named in /*) ;; *) named="$top/$named" ;; esac
  got=$(plan_repo_canon "$named") || return 0
  [ "$got" != "$want" ] || printf '%s\n' "$file"
  return 0
}

# ledger_left_inline LEDGER — the task number where the plan left inline mode:
# the last "escalated inline -> subagent" line with no later inline assignment.
# Nothing when the plan is in inline mode. The marker is a whole ledger line,
# never a substring of another line.
ledger_left_inline() {
  tr -d '\r' < "$1" | awk '
    /^Task [0-9]+: escalated inline -> subagent[ \t]*(—|-|$)/ { n = $2; sub(/:$/, "", n); esc = n; next }
    /^Task [0-9]+: implementer inline \(assigned/ { esc = "" }
    END { if (esc != "") print esc }
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
# git repository and that file is non-empty; otherwise nothing. Computed, not
# created: readers never bring the workspace into being.
plan_amendments_file() {
  local root slug
  root=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null) || return 0
  slug=$(basename "$1" .md)
  [ -s "$root/.superpowers/sdd/$slug/amendments.md" ] \
    && printf '%s\n' "$root/.superpowers/sdd/$slug/amendments.md"
  return 0
}

# plan_require_same_repo FILE — return when FILE's directory and the working
# directory share a top level; otherwise name both on stderr and exit 2.
# Scripts find the repository from the working directory, but
# plan_amendments_file and plan_ledger resolve from the plan's directory, so a
# plan in another checkout would split one plan's state across two. A linked
# worktree and its primary checkout have different top levels, so a worktree
# session given the primary checkout's plan path is refused as well.
plan_require_same_repo() {
  local me cwd_top plan_top
  me=$(basename "$0")
  cwd_top=$(git rev-parse --show-toplevel 2>/dev/null) \
    || { printf '%s: not inside a git repository\n' "$me" >&2; exit 2; }
  plan_top=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null) \
    || plan_top="no git repository"
  [ "$plan_top" != "$cwd_top" ] || return 0
  printf "%s: %s is in %s, but the working directory is in %s; run from inside the plan's worktree\n" \
    "$me" "$1" "$plan_top" "$cwd_top" >&2
  exit 2
}
