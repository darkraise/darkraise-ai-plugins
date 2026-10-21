#!/usr/bin/env bash

dr_state_error() { printf 'task-state: %s\n' "$1" >&2; return 2; }
dr_canonical() { (cd -- "$1" && pwd -P); }

dr_snapshot() {
  local root output="$2" index files temp indexfile filesfile filemode
  root="$(dr_canonical "$1")" || return 2
  temp="$(mktemp "${output}.XXXXXX")" || return 2
  index="$(git -C "$root" ls-files --stage -z | base64 | tr -d '\r\n')" || { rm -f "$temp"; return 2; }
  filemode=$(git -C "$root" config --bool core.filemode) || filemode=false
  files="$({ git -C "$root" ls-tree -r --name-only -z HEAD; git -C "$root" ls-files -c -o --exclude-standard -z; } | sort -zu |
    _dr_snapshot_entries "$root" "$filemode" | jq -Rs 'split("\u0000") | . as $f |
    [range(0; length - 1; 4) as $i |
      {path:$f[$i], hash:$f[$i+1], mode:$f[$i+2], kind:$f[$i+3]}] |
    sort_by(.path)')" || { rm -f "$temp"; return 2; }
  local head gitdir
  head="$(git -C "$root" rev-parse HEAD)" || { rm -f "$temp"; return 2; }
  gitdir="$(git -C "$root" rev-parse --absolute-git-dir)" || { rm -f "$temp"; return 2; }
  gitdir="$(dr_canonical "$gitdir")" || { rm -f "$temp"; return 2; }
  # The index and the manifest both scale with the repository, and a command
  # line is bounded - 32767 bytes on Windows. Passing them as arguments made
  # the snapshot fail outright past a few hundred files, so both reach jq as
  # files. --rawfile takes the index verbatim and --slurpfile parses the
  # manifest, which keeps the output byte-identical to the argument form.
  indexfile="$(mktemp "${output}.idx.XXXXXX")" || { rm -f "$temp"; return 2; }
  filesfile="$(mktemp "${output}.fls.XXXXXX")" || { rm -f "$temp" "$indexfile"; return 2; }
  printf '%s' "$index" > "$indexfile" || { rm -f "$temp" "$indexfile" "$filesfile"; return 2; }
  printf '%s' "$files" > "$filesfile" || { rm -f "$temp" "$indexfile" "$filesfile"; return 2; }
  jq -n --arg root "$root" --arg gitdir "$gitdir" --arg head "$head" \
    --rawfile index "$indexfile" --slurpfile files "$filesfile" \
    '{root:$root,gitdir:$gitdir,head:$head,index:$index,files:$files[0]}' > "$temp" &&
    mv -f -- "$temp" "$output" || { rm -f "$temp" "$indexfile" "$filesfile"; return 2; }
  rm -f "$indexfile" "$filesfile"
}

# _dr_snapshot_entries ROOT FILEMODE: NUL-separated paths on stdin become
# path, hash, mode, kind records. Regular files are hashed in one
# `hash-object --stdin-paths` call: a process per file made a snapshot of a
# 2,000-file repository take seconds, and a task takes several snapshots.
# Symlinks, and names --stdin-paths cannot carry verbatim (a newline or
# carriage return, or a leading quote, which it unquotes C-style), are still
# hashed one at a time.
_dr_snapshot_entries() {
  local root="$1" filemode="$2" path hash mode n=0 i=0
  local paths=() hashes=() modes=() kinds=() batch=()
  while IFS= read -r -d '' path; do
    paths+=("$path")
    if [ -L "$root/$path" ]; then
      hash="$(readlink -- "$root/$path" | git -C "$root" hash-object --stdin)" || return 2
      hashes+=("$hash"); modes+=(120000); kinds+=(symlink)
    elif [ -f "$root/$path" ]; then
      mode=100644
      if [ "$filemode" = true ] && [ -x "$root/$path" ]; then mode=100755; fi
      case "$path" in
        *$'\n'*|*$'\r'*|\"*) hash="$(git -C "$root" hash-object --no-filters -- "$path")" || return 2 ;;
        *) hash=''; batch+=("$n") ;;
      esac
      hashes+=("$hash"); modes+=("$mode"); kinds+=(file)
    elif [ ! -e "$root/$path" ]; then hashes+=(''); modes+=(0); kinds+=(deleted)
    else return 2
    fi
    n=$((n + 1))
  done
  if [ "${#batch[@]}" -gt 0 ]; then
    while IFS= read -r hash; do
      hashes[${batch[i]}]="${hash%$'\r'}"; i=$((i + 1))
    done < <(for n in "${batch[@]}"; do printf '%s\n' "${paths[n]}"; done |
      git -C "$root" hash-object --no-filters --stdin-paths)
    # The process substitution hides git's status, so a short answer is the
    # failure signal.
    [ "$i" -eq "${#batch[@]}" ] || return 2
  fi
  # NUL delimiters preserve tabs/newlines and other JSON-special filename
  # characters. Serialize once for the whole tree, not once per file.
  for ((i = 0; i < ${#paths[@]}; i++)); do
    printf '%s\0%s\0%s\0%s\0' "${paths[i]}" "${hashes[i]}" "${modes[i]}" "${kinds[i]}" || return 2
  done
}

dr_task_assert_snapshot() {
  local expected="$1" actual root
  root="$(jq -er .root "$expected")" || return 2
  actual="$(mktemp)" || return 2
  dr_snapshot "$root" "$actual" || { rm -f "$actual"; return 2; }
  jq -e --slurpfile actual "$actual" '. == $actual[0]' "$expected" >/dev/null
  local result=$?
  rm -f "$actual"
  return "$result"
}

dr_task_schema_valid() {
  jq -e 'type == "object" and .version == 1 and (. as $s | (["ready","running","pending","committing","complete","handed-back","blocked"] | index($s.phase)) != null and
    all([$s.task_id,$s.root,$s.gitdir,$s.repository,$s.initial_base,$s.expected_head][]; type == "string" and length > 0) and
    ($s.write_set | type == "array" and all(.[]; type == "string" and length > 0) and (unique | length) == length) and
    ($s.attempts | type == "array") and
    ($s.processes | type == "array") and ($s.history | type == "array") and
    ($s.artifacts | type == "object") and ($s | has("candidate") and has("pending") and has("prior_phase") and has("thread") and has("model") and has("effort")) and
    ($s.review_rounds | type == "number" and . >= 0 and floor == .))' "$1" >/dev/null 2>&1
}

dr_task_write() {
  dr_task_schema_valid "$1" || return 2
  local tmp
  tmp="$(mktemp "$DR_TASK_DIR/state.json.XXXXXX")" || return 2
  cat -- "$1" > "$tmp" && mv -f -- "$tmp" "$DR_TASK_DIR/state.json" || { rm -f "$tmp"; return 2; }
}

dr_task_update() {
  local expression="$1" tmp
  shift
  tmp="$(mktemp "$DR_TASK_DIR/update.XXXXXX")" || return 2
  jq "$@" "$expression" "$DR_TASK_DIR/state.json" > "$tmp" && dr_task_write "$tmp"
  local result=$?
  rm -f "$tmp"
  return "$result"
}

# _dr_proc_start PID — when PID's process started, so a reused PID reads as a
# different process; empty where neither /proc nor `ps -o lstart` exists.
_dr_proc_start() {
  if [ -r "/proc/$1/stat" ]; then
    # The command name in field 2 may hold spaces, so count from its ")".
    sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $20}'
  else
    ps -o lstart= -p "$1" 2>/dev/null
  fi
}

# _dr_task_reclaim LOCK — remove LOCK when its recorded owner provably exited:
# same host, and its PID is gone or names a process started at another time.
# A lock missing any of those records is uncertain and stays. Reclaims are
# serialized so one cannot remove a lock another reclaimer just took.
_dr_task_reclaim() {
  local lock="$1" guard="$1.reclaim" pid host start now stale=1
  mkdir -- "$guard" 2>/dev/null || return 1
  pid="$(cat "$lock/pid" 2>/dev/null)"
  host="$(cat "$lock/host" 2>/dev/null)"
  start="$(cat "$lock/start" 2>/dev/null)"
  if [[ "$pid" =~ ^[0-9]+$ ]] && [ -n "$host" ] && [ "$host" = "$(uname -n)" ]; then
    if ! kill -0 "$pid" 2>/dev/null; then
      stale=0
    else
      now="$(_dr_proc_start "$pid")"
      [ -n "$start" ] && [ -n "$now" ] && [ "$now" != "$start" ] && stale=0
    fi
  fi
  if [ "$stale" -eq 0 ]; then
    rm -f -- "$lock/pid" "$lock/start" "$lock/host"
    rmdir -- "$lock" 2>/dev/null || stale=1
  fi
  rmdir -- "$guard"
  return "$stale"
}

dr_task_lock() {
  local lock="$DR_TASK_ROOT/run.lock"
  if ! mkdir -- "$lock" 2>/dev/null; then
    _dr_task_reclaim "$lock" && mkdir -- "$lock" 2>/dev/null ||
      { dr_state_error 'worktree run lock exists; confirm prior writers stopped before reconciliation'; return 2; }
  fi
  # The pid is written last: a lock whose pid is missing is never reclaimed.
  # An unknown start time only narrows reclaiming to a PID that is gone.
  _dr_proc_start "$$" > "$lock/start" || true
  if ! { uname -n > "$lock/host" && printf '%s\n' "$$" > "$lock/pid"; }; then
    rm -f -- "$lock/start" "$lock/host" "$lock/pid"; rmdir -- "$lock" 2>/dev/null
    dr_state_error 'cannot record the run lock owner'; return 2
  fi
  DR_TASK_LOCK="$lock"
}

dr_task_unlock() {
  [ -n "${DR_TASK_LOCK:-}" ] || return 0
  [ "$(cat "$DR_TASK_LOCK/pid" 2>/dev/null)" = "$$" ] || return 2
  rm -f -- "$DR_TASK_LOCK/pid" "$DR_TASK_LOCK/start" "$DR_TASK_LOCK/host"
  rmdir -- "$DR_TASK_LOCK" || return 2
  DR_TASK_LOCK=''
}

dr_task_scope_valid() {
  jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' "$1" >/dev/null || return 2
  local path target
  while IFS= read -r -d '' path; do
    case "$path" in /*|[A-Za-z]:*|*\\*|..|../*|*/../*|*/..|.git|.git/*|.dforge|.dforge/*) return 2 ;; esac
    target="$(realpath -m -- "$DR_WORKTREE/$path")" || return 2
    case "$target" in "$DR_WORKTREE"/*) ;; *) return 2 ;; esac
  done < <(jq -j '.[] + "\u0000"' "$1")
}

dr_task_open() {
  local root="$1" task="$2" scope="${3:-}" accept="${4:-}" gitdir common prefix key owner record
  [ -n "$task" ] || { dr_state_error 'task ID is required'; return 2; }
  DR_WORKTREE="$(dr_canonical "$root")" || return 2
  prefix="$(git -C "$DR_WORKTREE" rev-parse --show-prefix)" || return 2
  [ -z "$prefix" ] || { dr_state_error 'cwd must be the worktree root'; return 2; }
  gitdir="$(git -C "$DR_WORKTREE" rev-parse --absolute-git-dir)" || return 2
  gitdir="$(dr_canonical "$gitdir")" || return 2
  common="$(git -C "$DR_WORKTREE" rev-parse --path-format=absolute --git-common-dir)" || return 2
  common="$(dr_canonical "$common")" || return 2
  [ "$gitdir" != "$common" ] && [ -z "$(git -C "$DR_WORKTREE" rev-parse --show-superproject-working-tree)" ] || { dr_state_error 'an exclusively assigned linked worktree is required'; return 2; }
  DR_TASK_ROOT="$gitdir/dforge"
  key="$(printf '%s' "$task" | git -C "$DR_WORKTREE" hash-object --stdin)" || return 2
  DR_TASK_DIR="$DR_TASK_ROOT/tasks/$key"
  mkdir -p -- "$DR_TASK_ROOT" || return 2
  dr_task_lock || return 2
  owner="$DR_TASK_ROOT/owner.json"
  if [ -e "$owner" ] && ! jq -e --arg task "$task" --arg root "$DR_WORKTREE" --arg accept "$accept" \
    '.task_id == $task and .root == $root and (.holder == "external" or ($accept == "handed-back" and .holder == "claude"))' "$owner" >/dev/null 2>&1; then
    dr_task_unlock; dr_state_error 'worktree is reserved by another task or handed back'; return 2
  fi
  if [ -e "$DR_TASK_DIR/state.json" ]; then
    if ! dr_task_schema_valid "$DR_TASK_DIR/state.json" || ! jq -e --arg task "$task" --arg root "$DR_WORKTREE" --arg gitdir "$gitdir" --arg repository "$common" --arg accept "$accept" \
      '.task_id == $task and .root == $root and .gitdir == $gitdir and .repository == $repository and (.phase != "handed-back" or $accept == "handed-back") and (.released // false) == false' "$DR_TASK_DIR/state.json" >/dev/null; then
      dr_task_unlock; dr_state_error 'invalid task state or identity'; return 2
    fi
    if [ -n "$scope" ] && ! jq -e --slurpfile scope "$scope" '.write_set == $scope[0]' "$DR_TASK_DIR/state.json" >/dev/null; then
      dr_task_unlock; dr_state_error 'write set changed without an amendment'; return 2
    fi
    if ! jq .write_set "$DR_TASK_DIR/state.json" > "$DR_TASK_DIR/scope.json" || ! dr_task_scope_valid "$DR_TASK_DIR/scope.json"; then
      dr_task_unlock; dr_state_error 'recorded write set is invalid or escapes worktree'; return 2
    fi
  else
    if [ -e "$owner" ] || [ -z "$scope" ] || ! dr_task_scope_valid "$scope" || [ -n "$(git -C "$DR_WORKTREE" status --porcelain=v1 --untracked-files=all)" ]; then
      dr_task_unlock; dr_state_error 'initial execution requires a write set and clean index/worktree'; return 2
    fi
    mkdir -p -- "$DR_TASK_DIR" || { dr_task_unlock; return 2; }
    local head
    head="$(git -C "$DR_WORKTREE" rev-parse HEAD)" || { dr_task_unlock; return 2; }
    record="$DR_TASK_DIR/initial.json"
    jq -n --arg task "$task" --arg root "$DR_WORKTREE" --arg gitdir "$gitdir" --arg repo "$common" --arg head "$head" --slurpfile scope "$scope" \
      '{version:1,task_id:$task,root:$root,gitdir:$gitdir,repository:$repo,initial_base:$head,expected_head:$head,
        write_set:$scope[0],model:null,effort:null,thread:null,attempts:[],review_rounds:0,processes:[],
        phase:"ready",prior_phase:null,history:[],pending:null,candidate:null,artifacts:{}}' > "$record" && dr_task_write "$record" || { dr_task_unlock; return 2; }
    rm -f "$record"
  fi
  # A handed-back task belongs to Claude; reopening it must not hand the
  # worktree back to the external executor.
  [ -e "$DR_TASK_DIR/state.json" ] && jq -e '.phase == "handed-back"' "$DR_TASK_DIR/state.json" >/dev/null && return 0
  local owner_tmp
  owner_tmp="$(mktemp "$owner.XXXXXX")" || { dr_task_unlock; return 2; }
  jq -n --arg task "$task" --arg root "$DR_WORKTREE" --arg gitdir "$gitdir" \
    '{task_id:$task,root:$root,gitdir:$gitdir,holder:"external"}' > "$owner_tmp" && mv -f -- "$owner_tmp" "$owner" || { rm -f "$owner_tmp"; dr_task_unlock; return 2; }
}

dr_task_validate_scope() {
  local before="$1" actual scope result
  actual="$(mktemp "$DR_TASK_DIR/snapshot.XXXXXX")" || return 2
  dr_snapshot "$DR_WORKTREE" "$actual" || { rm -f "$actual"; return 2; }
  scope="$(jq -c .write_set "$DR_TASK_DIR/state.json")" || { rm -f "$actual"; return 2; }
  jq -e --slurpfile after "$actual" --argjson scope "$scope" '
    . as $before | $after[0] as $after |
    # Keyed lookups: nested selects made this quadratic in the file count.
    # Bound before the test: jq 1.8 parses `x and E as $v | ...` differently.
    INDEX($before.files[]; .path) as $b | INDEX($after.files[]; .path) as $a | INDEX($scope[]; .) as $s |
    .head == $after.head and .root == $after.root and .gitdir == $after.gitdir and .index == $after.index and
    all(($b + $a | keys_unsorted[]); . as $path | $b[$path] == $a[$path] or $s[$path] != null)' "$before" >/dev/null
  result=$?
  rm -f "$actual"
  return "$result"
}
