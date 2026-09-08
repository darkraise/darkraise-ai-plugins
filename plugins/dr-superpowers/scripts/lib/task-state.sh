#!/usr/bin/env bash

dr_state_error() { printf 'task-state: %s\n' "$1" >&2; return 2; }
dr_canonical() { (cd -- "$1" && pwd -P); }

dr_snapshot() {
  local root output="$2" index files path hash mode kind temp
  root="$(dr_canonical "$1")" || return 2
  temp="$(mktemp "${output}.XXXXXX")" || return 2
  index="$(git -C "$root" ls-files --stage -z | base64 | tr -d '\r\n')" || { rm -f "$temp"; return 2; }
  files="$({ git -C "$root" ls-tree -r --name-only -z HEAD; git -C "$root" ls-files -c -o --exclude-standard -z; } | sort -zu | while IFS= read -r -d '' path; do
    if [ -L "$root/$path" ]; then
      kind=symlink; mode=120000
      hash="$(readlink -- "$root/$path" | git -C "$root" hash-object --stdin)" || exit 2
    elif [ -f "$root/$path" ]; then
      kind=file; mode=100644
      if [ "$(git -C "$root" config --bool core.filemode)" = true ] && [ -x "$root/$path" ]; then mode=100755; fi
      hash="$(git -C "$root" hash-object --no-filters -- "$path")" || exit 2
    elif [ ! -e "$root/$path" ]; then kind=deleted; mode=0; hash=''
    else exit 2
    fi
    jq -cn --arg path "$path" --arg hash "$hash" --arg mode "$mode" --arg kind "$kind" \
      '{path:$path,hash:$hash,mode:$mode,kind:$kind}' || exit 2
  done | jq -s 'sort_by(.path)')" || { rm -f "$temp"; return 2; }
  local head gitdir
  head="$(git -C "$root" rev-parse HEAD)" || { rm -f "$temp"; return 2; }
  gitdir="$(git -C "$root" rev-parse --absolute-git-dir)" || { rm -f "$temp"; return 2; }
  gitdir="$(dr_canonical "$gitdir")" || { rm -f "$temp"; return 2; }
  jq -n --arg root "$root" --arg gitdir "$gitdir" --arg head "$head" --arg index "$index" \
    --argjson files "$files" '{root:$root,gitdir:$gitdir,head:$head,index:$index,files:$files}' > "$temp" &&
    mv -f -- "$temp" "$output" || { rm -f "$temp"; return 2; }
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

dr_task_lock() {
  mkdir -- "$DR_TASK_ROOT/run.lock" 2>/dev/null || { dr_state_error 'worktree run lock exists; confirm prior writers stopped before reconciliation'; return 2; }
  DR_TASK_LOCK="$DR_TASK_ROOT/run.lock"
  printf '%s\n' "$$" > "$DR_TASK_LOCK/pid" || return 2
  awk '{print $22}' "/proc/$$/stat" > "$DR_TASK_LOCK/start" 2>/dev/null || { dr_task_unlock; return 2; }
}

dr_task_unlock() {
  [ -n "${DR_TASK_LOCK:-}" ] || return 0
  [ "$(cat "$DR_TASK_LOCK/pid" 2>/dev/null)" = "$$" ] || return 2
  rm -f -- "$DR_TASK_LOCK/pid" "$DR_TASK_LOCK/start"
  rmdir -- "$DR_TASK_LOCK" || return 2
  DR_TASK_LOCK=''
}

dr_task_scope_valid() {
  jq -e 'type == "array" and all(.[]; type == "string" and length > 0)' "$1" >/dev/null || return 2
  local path target
  while IFS= read -r -d '' path; do
    case "$path" in /*|[A-Za-z]:*|*\\*|..|../*|*/../*|*/..|.git|.git/*|.superpowers|.superpowers/*) return 2 ;; esac
    target="$(realpath -m -- "$DR_WORKTREE/$path")" || return 2
    case "$target" in "$DR_WORKTREE"/*) ;; *) return 2 ;; esac
  done < <(jq -j '.[] + "\u0000"' "$1")
}

dr_task_open() {
  local root="$1" task="$2" scope="${3:-}" gitdir common prefix key owner record
  [ -n "$task" ] || { dr_state_error 'task ID is required'; return 2; }
  DR_WORKTREE="$(dr_canonical "$root")" || return 2
  prefix="$(git -C "$DR_WORKTREE" rev-parse --show-prefix)" || return 2
  [ -z "$prefix" ] || { dr_state_error 'cwd must be the worktree root'; return 2; }
  gitdir="$(git -C "$DR_WORKTREE" rev-parse --absolute-git-dir)" || return 2
  gitdir="$(dr_canonical "$gitdir")" || return 2
  common="$(git -C "$DR_WORKTREE" rev-parse --path-format=absolute --git-common-dir)" || return 2
  common="$(dr_canonical "$common")" || return 2
  [ "$gitdir" != "$common" ] && [ -z "$(git -C "$DR_WORKTREE" rev-parse --show-superproject-working-tree)" ] || { dr_state_error 'an exclusively assigned linked worktree is required'; return 2; }
  DR_TASK_ROOT="$gitdir/dr-superpowers"
  key="$(printf '%s' "$task" | git -C "$DR_WORKTREE" hash-object --stdin)" || return 2
  DR_TASK_DIR="$DR_TASK_ROOT/tasks/$key"
  mkdir -p -- "$DR_TASK_ROOT" || return 2
  dr_task_lock || return 2
  owner="$DR_TASK_ROOT/owner.json"
  if [ -e "$owner" ] && ! jq -e --arg task "$task" --arg root "$DR_WORKTREE" \
    '.task_id == $task and .root == $root and .holder == "external"' "$owner" >/dev/null 2>&1; then
    dr_task_unlock; dr_state_error 'worktree is reserved by another task or handed back'; return 2
  fi
  if [ -e "$DR_TASK_DIR/state.json" ]; then
    if ! dr_task_schema_valid "$DR_TASK_DIR/state.json" || ! jq -e --arg task "$task" --arg root "$DR_WORKTREE" --arg gitdir "$gitdir" --arg repository "$common" \
      '.task_id == $task and .root == $root and .gitdir == $gitdir and .repository == $repository and .phase != "handed-back" and (.released // false) == false' "$DR_TASK_DIR/state.json" >/dev/null; then
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
    .head == $after.head and .root == $after.root and .gitdir == $after.gitdir and .index == $after.index and
    all(([$before.files[].path,$after.files[].path] | unique)[];
      . as $path | ([$before.files[] | select(.path == $path)] == [$after.files[] | select(.path == $path)]) or
      ($scope | index($path)) != null)' "$before" >/dev/null
  result=$?
  rm -f "$actual"
  return "$result"
}
