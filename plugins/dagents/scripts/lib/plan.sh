# Plan and ledger parsing shared by task-brief, plan-lint, plan-amend, next-step
# and repo-audit, so every reader agrees on what a task, the header and an
# amendment are. Sourced; defines functions only.

. "$(dirname "${BASH_SOURCE[0]}")/roots.sh"

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
  if (line !~ /^#+[ \t]+Task[ \t]+[0-9]+([ \t:.-]|$)/) return -1
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

# plan_lettered FILE — the task headings outside fences numbered with a letter
# (`### Task A1: …`), which plan_tasks does not read, so a caller can say why a
# plan has no tasks instead of passing over it.
plan_lettered() {
  tr -d '\r' < "$1" | awk "$_PLAN_AWK"'
    in_fence($0) { next }
    /^#+[ \t]+Task[ \t]+[A-Za-z]+[0-9]+/ { print }
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
# A checkout whose git directory is the common one (a standard, separate-git-dir
# or submodule checkout) is its own primary. A linked worktree's primary is the
# common directory's core.worktree when set (a submodule's), else its parent.
# A linked worktree of a --separate-git-dir repository without core.worktree
# still returns 1: git records no primary path for it.
plan_primary_root() {
  local dir=${1:-.} gitdir common
  common=$(git -C "$dir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) || return 1
  gitdir=$(git -C "$dir" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  if [ "$gitdir" -ef "$common" ]; then
    git -C "$dir" rev-parse --show-toplevel 2>/dev/null
  else
    git -C "$common" rev-parse --show-toplevel 2>/dev/null \
      || git -C "$(dirname "$common")" rev-parse --show-toplevel 2>/dev/null
  fi
}

# ladder_block TAG — the lines of reference/ladder.md's ```TAG fenced block,
# blank lines dropped.
# DAGENTS_LADDER is a test seam: a suite that needs a fixture executor's blocks
# points it at the shipped ladder plus its own. Unset in production.
ladder_block() {
  tr -d '\r' < "${DAGENTS_LADDER:-$_PLAN_LIB_DIR/../../reference/ladder.md}" \
    | awk -v tag="$1" 'stop { next } $0 == "```" tag { f = 1; next } f && /^```/ { stop = 1; next } f && NF { print }'
}

# ledger_blocked FILE — the task numbers whose terminal ledger line is
# "Task N: BLOCKED", sorted, unique. BLOCKED is terminal: a resumed session must
# not start the task. The Recovery rule both execution skills define reads the
# last "Task N:" line in file order, stepping over the kinds that are not
# terminal (a waiting line is a question asked, not a state), so a BLOCKED
# the owner resolved and the task re-ran is not blocked any more — a flat
# grep would keep reporting it forever.
ledger_blocked() {
  tr -d '\r' < "$1" | awk '
    !/^Task [0-9]+:/ { next }
    /^Task [0-9]+: (minor \(deferred\)|parked|Ruling:|waiting[[:space:]]+(—|–|-)[[:space:]])/ { next }
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
# line outside a fenced block. One row per task: a split task takes the first
# line among its parts, and a line above its first part routes nothing, as
# plan_eval_lines ignores a stale Evaluation line there. Exit 0 whether or not
# any task carries a line: ordinary absence is not a failure.
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
      /^#### Part [A-Z]:/ { parts = 1; next }
      /^\*\*Executor:\*\*/ {
        sub(/^\*\*Executor:\*\*[ \t]*/, "")
        if (parts) { if (part == "") part = $1 } else if (pre == "") pre = $1
      }
      END { id = parts ? part : pre; if (id != "") print id }')
    # An `if`, not `[ -n "$id" ] && printf`: the last iteration's status becomes
    # the function's, so a final task with no Executor line would return 1 and
    # abort plan_delegated's `execs=` assignment under errexit, emitting no rows
    # at all - and an empty delegated set reads as "nothing is delegated".
    if [ -n "$id" ]; then printf '%s\t%s\n' "$n" "$id"; fi
  done < <(plan_tasks "$1")
}

# plan_heavy FILE — the heavy task numbers: a highest total of 5 or more, or a
# highest risk of 3, which task-brief lists on the **Heavy:** header line. One
# per line, ascending.
plan_heavy() {
  plan_scores "$1" | awk -F'\t' '$2 != "-" && $2 != "?" && ($2 + 0 >= 5 || $3 + 0 == 3) { print $1 }'
}

# plan_delegated FILE — the tasks an inline plan delegates, one "N<TAB>executor"
# line each, ascending: the scored tasks an Executor line marks for an external
# executor. A heavy task is never delegated: the session implements it.
plan_delegated() {
  local execs
  execs=$(plan_executors "$1" | cut -f1 | tr '\n' ' ')
  plan_scores "$1" | awk -F'\t' -v execs=" $execs" '
    $2 == "-" || $2 == "?" { next }
    index(execs, " " $1 " ") > 0 { print $1 "\texecutor" }
  '
}

# plan_parallelism FILE — the plan's execution strategy: `sequential` when the
# header has no **Parallelism:** line or names sequential, `waves` for a waves
# line, `bad` for anything else. See reference/parallel-waves.md.
plan_parallelism() {
  local line
  line=$(plan_header_line "$1" Parallelism)
  if [ -z "$line" ] || [[ "$line" =~ ^\*\*Parallelism:\*\*[[:space:]]+sequential([[:space:]]|$) ]]; then
    echo sequential
  elif [[ "$line" =~ ^\*\*Parallelism:\*\*[[:space:]]+waves( — | – | - | -- ) ]]; then
    echo waves
  else
    echo bad
  fi
}

# plan_waves FILE — one "K<TAB>FIRST<TAB>LAST" line per wave of a waves plan,
# in the order the **Parallelism:** line lists them; nothing for a sequential
# plan. Exit 4, printing nothing, when a range does not parse. Whether the
# ranges are contiguous and cover the plan is plan-lint's check, not this one's.
plan_waves() {
  local line body k=0 r a b out=""
  [ "$(plan_parallelism "$1")" = waves ] || return 0
  line=$(plan_header_line "$1" Parallelism)
  body=$(sed -E 's/^\*\*Parallelism:\*\*[[:space:]]+waves( — | – | - | -- )//; s/[[:space:]]+$//' <<<"$line")
  IFS='|' read -r -a ranges <<<"$body"
  for r in "${ranges[@]}"; do
    r=$(tr -d ' \t' <<<"$r")
    if [[ "$r" =~ ^([0-9]+)$ ]]; then a=${BASH_REMATCH[1]} b=$a
    elif [[ "$r" =~ ^([0-9]+)-([0-9]+)$ ]]; then a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]}
    else return 4
    fi
    [ "$a" -le "$b" ] || return 4
    k=$((k + 1))
    out="$out$k"$'\t'"$((10#$a))"$'\t'"$((10#$b))"$'\n'
  done
  [ "$k" -gt 0 ] || return 4
  printf '%s' "$out"
}

# plan_task_paths — the repository paths the task text on stdin names in its
# `- Create:`, `- Modify:`, `- Test:` and `- Delete:` lines outside fences, in
# every part, one per line, unique. A `:123-145` or `:12,30-40` line
# range is dropped.
plan_task_paths() {
  awk "$_PLAN_AWK"'
    in_fence($0) { next }
    /^[ \t]*- (Create|Modify|Test|Delete):[ \t]*`[^`]+`/ {
      p = $0; sub(/^[^`]*`/, "", p); sub(/`.*$/, "", p)
      sub(/:[0-9]+(-[0-9]+)?(,[0-9]+(-[0-9]+)?)*$/, "", p)
      sub(/^\.\//, "", p)
      if (p != "" && !seen[p]++) print p
    }
  '
}

# plan_task_depends — the task numbers the first **Depends on:** line of the
# task text on stdin names, one per line; `none` prints nothing. Exit 3 when
# the text has no Depends on line.
plan_task_depends() {
  local line
  line=$(awk "$_PLAN_AWK"'
    stop { next }
    in_fence($0) { next }
    /^\*\*Depends on:\*\*/ { print; stop = 1 }')
  [ -n "$line" ] || return 3
  line=${line#"**Depends on:**"}
  grep -oE '[0-9]+' <<<"$line" || true
}

# _plan_ctx PLAN — the directory whose checkout a plan belongs to: its own
# directory inside a git repository, else the working directory.
_plan_ctx() {
  local dir here
  # Native forms: callers hand the result to git -C, which under
  # MSYS_NO_PATHCONV=1 cannot open Git Bash's /tmp/... spelling of $PWD.
  dir=$(dr_native_path "$(dirname "$1")")
  here=$(dr_native_path "$PWD")
  if git -C "$dir" rev-parse --show-toplevel >/dev/null 2>&1; then printf '%s\n' "$dir"; else printf '%s\n' "$here"; fi
}

# plan_locate PLAN — PLAN when it exists, else the file its name resolves to
# under the docs root (an older docs prefix included), else PLAN unchanged.
plan_locate() {
  local found name ctx
  ctx=$(_plan_ctx "$1")
  dagents_stores_init "$ctx"
  name=$(dagents_name "$1" "$ctx")
  found=$(dagents_resolve "$name" "$ctx")
  if [ -f "$1" ]; then printf '%s\n' "$1"
  elif [ -f "$found" ]; then printf '%s\n' "$found"
  else printf '%s\n' "$1"; fi
}

# plan_ledger PLAN — the plan's ledger file when it exists and its identity line
# names PLAN; nothing otherwise. A stale ledger under the same slug is ignored.
# Plan and identity are compared as name keys, so either docs prefix matches.
# plan_ledger_any ROOT PLAN — "<ledger>\t<checkout>" for the first progress.md
# whose identity line names PLAN: this checkout's ledger directory first, then
# every worktree's (dagents_ledger_files). Status 1, nothing printed, when none.
plan_ledger_any() {
  local root=$1 want slug file wt
  dagents_stores_init "$root"
  want=$(dagents_name_key "$(dagents_name "$2" "$root")")
  slug=$(basename "$2" .md)
  file="$(dagents_ledger_dir "$slug" "$root")/progress.md"
  if _plan_ledger_names "$file" "$root" "$want"; then printf '%s\t%s\n' "$file" "$root"; return 0; fi
  while IFS=$'\t' read -r file wt; do
    [ -n "$file" ] || continue
    _plan_ledger_names "$file" "$wt" "$want" || continue
    printf '%s\t%s\n' "$file" "$wt"
    return 0
  done < <(dagents_ledger_files "$root")
  return 1
}

# _plan_ledger_names LEDGER CHECKOUT KEY — true when LEDGER's identity line
# names the plan whose name key is KEY. An absolute path in another checkout is
# named from that checkout's top by prefix: naming it through the store roots
# would re-key them to that checkout for the rest of the caller.
_plan_ledger_names() {
  local named
  [ -f "$1" ] || return 1
  named=$(ledger_plan "$1")
  [ -n "$named" ] || return 1
  if command -v cygpath >/dev/null 2>&1; then
    named=$(cygpath -m "$named" 2>/dev/null || printf '%s' "$named")
  fi
  if [ "$2" != "$_DAGENTS_TOP" ]; then
    case $named in "$2"/*) named=${named#"$2"/} ;; esac
  fi
  [ "$(dagents_name_key "$(dagents_name "$named")")" = "$3" ]
}

plan_ledger() {
  local ctx want file named
  ctx=$(_plan_ctx "$1")
  # In this shell, so the roots it caches serve the calls below.
  dagents_stores_init "$ctx"
  want=$(dagents_name_key "$(dagents_name "$1" "$ctx")")
  file="$(dagents_ledger_dir "$(basename "$1" .md)" "$ctx")/progress.md"
  [ -f "$file" ] || return 0
  named=$(ledger_plan "$file")
  [ -n "$named" ] || return 0
  if command -v cygpath >/dev/null 2>&1; then
    named=$(cygpath -m "$named" 2>/dev/null || printf '%s' "$named")
  fi
  [ "$(dagents_name_key "$(dagents_name "$named" "$ctx")")" != "$want" ] || printf '%s\n' "$file"
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
# applied in file order; the plan unchanged when AMEND is missing or empty,
# with the read's own status. Exit 1, naming the entry on stderr, when an entry
# does not apply: its Old lines must match a contiguous run of whole lines of
# its target exactly once.
plan_apply_amendments() {
  if [ ! -s "${2:-}" ]; then tr -d '\r' < "$1"; return; fi
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

# plan_amendments_file PLAN — <ledger dir>/amendments.md, beside the ledger
# (dagents_ledger_dir), when
# PLAN belongs to a git checkout and that file is non-empty; otherwise
# nothing, which readers take as no amendments. Computed, not created: readers
# never bring the ledger directory into being. plan-amend computes the same
# path to write it.
plan_amendments_file() {
  local ctx file
  ctx=$(_plan_ctx "$1")
  git -C "$ctx" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
  file="$(dagents_ledger_dir "$(basename "$1" .md)" "$ctx")/amendments.md"
  [ -s "$file" ] && printf '%s\n' "$file"
  return 0
}

# plan_amendments_ready PLAN — run in the caller's own shell, never inside
# $(…): it exits the caller. Amendments used to live in the workspace, which
# is not where the ledger is. When the ledger directory has no amendments file and the workspace
# has one, it is moved there (copied to a temporary name, renamed, then
# removed from the workspace) and the move is logged in the ledger, once.
# Then a ledger line citing `Ruling: amendment A<k>` whose `## A<k> ` heading
# the file lacks exits 2, naming it: the task text would be read without an
# amendment the run already applied.
plan_amendments_ready() {
  local me ctx slug ldir ws file old ledger tmp k seen=" " bad=0
  local moved='Ruling: amendments moved beside the ledger — none'
  # Parameter expansion, not basename: plan-lint runs this with only the tools
  # its own checks need on PATH.
  me=${0##*/}
  ctx=$(_plan_ctx "$1")
  git -C "$ctx" rev-parse --show-toplevel >/dev/null 2>&1 || return 0
  dagents_stores_init "$ctx"
  slug=${1##*/} slug=${slug%.md}
  ldir=$(dagents_ledger_dir "$slug" "$ctx")
  ws=$(dagents_workspace "$slug" "$ctx")
  file="$ldir/amendments.md" old="$ws/amendments.md" ledger="$ldir/progress.md"
  if [ ! -s "$file" ] && [ -s "$old" ] && [ "$ldir" != "$ws" ] && ! [ "$ldir" -ef "$ws" ]; then
    tmp="$file.tmp.$$"
    if ! { mkdir -p "$ldir" && cp -- "$old" "$tmp" && mv -f -- "$tmp" "$file"; }; then
      rm -f -- "$tmp"
      printf '%s: could not move %s beside the ledger, to %s\n' "$me" "$old" "$file" >&2
      exit 2
    fi
    rm -f -- "$old" \
      || printf '%s: moved %s beside the ledger but could not remove it\n' "$me" "$old" >&2
    if [ -f "$ledger" ] && ! grep -qxF -- "$moved" "$ledger"; then
      printf '%s\n' "$moved" >> "$ledger"
    fi
  fi
  [ -f "$ledger" ] || return 0
  for k in $(tr -d '\r' < "$ledger" | grep -oE 'Ruling: amendment A[0-9]+' | sed 's/.*A//'); do
    case $seen in *" $k "*) continue ;; esac
    seen="$seen$k "
    [ -f "$file" ] && grep -q "^## A$k " < <(tr -d '\r' < "$file") && continue
    printf '%s: the ledger cites amendment A%s, which %s lacks\n' "$me" "$k" "$file" >&2
    bad=1
  done
  [ "$bad" -eq 0 ] || exit 2
}

# plan_require_same_project FILE — return when FILE belongs to the working
# directory's checkout: inside its top level. Otherwise name both on stderr
# and exit 2. Scripts find the repository from the working directory, but the
# plan functions resolve from the plan's location, so a plan in another
# checkout would split one plan's state across two. A linked worktree and its
# primary checkout have different top levels, so a worktree session given the
# primary checkout's plan path is refused as well.
plan_require_same_project() {
  local me cwd_top plan_top
  me=$(basename "$0")
  cwd_top=$(git rev-parse --show-toplevel 2>/dev/null) \
    || { printf '%s: not inside a git repository\n' "$me" >&2; exit 2; }
  plan_top=$(git -C "$(dirname "$1")" rev-parse --show-toplevel 2>/dev/null) || plan_top=""
  [ "$plan_top" != "$cwd_top" ] || return 0
  printf "%s: %s is in %s, but the working directory is in %s; run from inside the plan's worktree\n" \
    "$me" "$1" "${plan_top:-no git repository}" "$cwd_top" >&2
  exit 2
}

# plan_final_review_state LEDGER [DIR] — whether the ledger's last
# `Final review: clean (commits <base>..<head>)` line still covers HEAD in DIR
# (default the working directory): `none` (no clean line); `current` (HEAD is
# <head>, or only docs-root paths changed since); `stale <from>` (a later
# commit touches code); `rewritten <head>` (<head> is no commit, or no
# ancestor of HEAD). <from> is <head>, or, when <head> reached HEAD through a
# merge, off its first-parent chain, that merge: only what came after it is
# unreviewed. A clean line with no commits clause, or a DIR where HEAD does not
# resolve, reads `current`: git cannot judge it. A failed walk of the history
# after <head> reads `stale <head>`. The ledger records no branch, so the
# first-parent chain is the only base-branch test.
plan_final_review_state() {
  local dir line head full now top docs path changed from desc
  dir=$(dr_native_path "${2:-$PWD}")
  line=$(tr -d '\r' < "$1" 2>/dev/null | grep '^Final review: clean' | tail -n 1)
  if [ -z "$line" ]; then echo none; return 0; fi
  head=$(sed -n 's/^Final review: clean (commits [^ .]*\.\.\([0-9A-Za-z]*\)[,)].*/\1/p' <<<"$line")
  if [ -z "$head" ]; then echo current; return 0; fi
  now=$(git -C "$dir" rev-parse --verify -q HEAD 2>/dev/null | tr -d '\r')
  if [ -z "$now" ]; then echo current; return 0; fi
  full=$(git -C "$dir" rev-parse --verify -q "$head^{commit}" 2>/dev/null | tr -d '\r')
  if [ -z "$full" ]; then echo "rewritten $head"; return 0; fi
  if [ "$full" = "$now" ]; then echo current; return 0; fi
  if ! git -C "$dir" merge-base --is-ancestor "$full" "$now" 2>/dev/null; then echo "rewritten $head"; return 0; fi
  # A git call that fails proves nothing, so it reads as stale: the scoped
  # re-review is the safe route, finishing is not.
  local chain
  chain=$(git -C "$dir" rev-list --first-parent "$now" 2>/dev/null) || { echo "stale $head"; return 0; }
  chain=$(tr -d '\r' <<<"$chain")
  from=$full
  if ! grep -qxF -- "$full" <<<"$chain"; then
    # The oldest first-parent commit that descends from <head> is the merge
    # that brought it in.
    desc=$(git -C "$dir" rev-list --ancestry-path "$full..$now" 2>/dev/null) || { echo "stale $head"; return 0; }
    from=$(printf '%s\n--\n%s\n' "$desc" "$chain" | tr -d '\r' |
      awk '$0 == "--" { past = 1; next } !past { s[$0] = 1; next } $0 in s { m = $0 } END { print m }')
    [ -n "$from" ] || { echo "stale $head"; return 0; }
    head=$(git -C "$dir" rev-parse --short "$from" 2>/dev/null | tr -d '\r')
    [ -n "$head" ] || head=$from
  fi
  changed=$(git -C "$dir" log --format= --name-only "$from..$now" 2>/dev/null) || { echo "stale $head"; return 0; }
  changed=$(tr -d '\r' <<<"$changed" | sed '/^$/d')
  if [ -z "$changed" ]; then echo current; return 0; fi
  top=$(dr_native_path "$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')")
  docs=$(dr_native_path "$(dagents_docs_root "$dir")")
  while IFS= read -r path; do
    case "$top/$path" in "${docs%/}"/*) ;; *) echo "stale $head"; return 0 ;; esac
  done <<<"$changed"
  echo current
}
