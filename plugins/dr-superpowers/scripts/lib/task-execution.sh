#!/usr/bin/env bash

dr_task_block() {
  local reason="$1" snapshot="$DR_TASK_DIR/blocked-snapshot.json"
  dr_snapshot "$DR_WORKTREE" "$snapshot" || return 2
  dr_task_update '.prior_phase = .phase | .phase = "blocked" | .pending = $snapshot[0] | .error = $reason' \
    --slurpfile snapshot "$snapshot" --arg reason "$reason"
}

dr_task_complete() {
  local head snapshot="$DR_TASK_DIR/completed-snapshot.json"
  head="$(git -C "$DR_WORKTREE" rev-parse HEAD)" || return 2
  [ -z "$(git -C "$DR_WORKTREE" status --porcelain=v1 --untracked-files=all)" ] || return 2
  dr_snapshot "$DR_WORKTREE" "$snapshot" || return 2
  dr_task_update '.expected_head = $head | .phase = "complete" | .prior_phase = null | .pending = null | .processes = [] | .baseline = $snapshot[0] | del(.error)' \
    --arg head "$head" --slurpfile snapshot "$snapshot"
}

dr_task_commit() {
  local tree parent subject head actual_tree
  tree="$(jq -er .candidate.tree "$DR_TASK_DIR/state.json")" || return 2
  parent="$(jq -er .candidate.parent "$DR_TASK_DIR/state.json")" || return 2
  subject="$(jq -er .candidate.subject "$DR_TASK_DIR/state.json")" || return 2
  head="$(git -C "$DR_WORKTREE" rev-parse HEAD)" || return 2
  if [ "$head" != "$parent" ]; then
    [ "$(git -C "$DR_WORKTREE" show -s --format=%P HEAD)" = "$parent" ] &&
    [ "$(git -C "$DR_WORKTREE" show -s --format=%T HEAD)" = "$tree" ] &&
    [ "$(git -C "$DR_WORKTREE" show -s --format=%s HEAD)" = "$subject" ] || return 2
    dr_task_complete
    return
  fi
  actual_tree="$(git -C "$DR_WORKTREE" write-tree)" || return 2
  [ "$actual_tree" = "$tree" ] || return 2
  dr_task_update '.phase = "committing"' || return 2
  timeout 60s git -C "$DR_WORKTREE" commit -q -m "$subject" || { dr_task_block 'commit failed'; return 2; }
  [ "$(git -C "$DR_WORKTREE" show -s --format=%T HEAD)" = "$tree" ] &&
    [ "$(git -C "$DR_WORKTREE" show -s --format=%P HEAD)" = "$parent" ] &&
    [ "$(git -C "$DR_WORKTREE" show -s --format=%s HEAD)" = "$subject" ] || { dr_task_block 'commit hooks changed the candidate'; return 2; }
  dr_task_complete
}

dr_task_stage() {
  local before="$1" subject="$2" after="$DR_TASK_DIR/verified-snapshot.json" path kind mode hash tree parent
  local expected_index="$DR_TASK_DIR/expected.index" paths=()
  dr_task_validate_scope "$before" || { dr_task_block 'worktree/index/HEAD changed outside task scope'; return 2; }
  jq .write_set "$DR_TASK_DIR/state.json" > "$DR_TASK_DIR/scope.json" && dr_task_scope_valid "$DR_TASK_DIR/scope.json" || { dr_task_block 'write-set path escapes worktree'; return 2; }
  dr_snapshot "$DR_WORKTREE" "$after" || return 2
  while IFS= read -r -d '' path; do paths+=("$path"); done < <(
    jq -j --slurpfile after "$after" '. as $before | $after[0] as $after |
      ([$before.files[].path,$after.files[].path] | unique)[] | . as $path |
      select([$before.files[] | select(.path == $path)] != [$after.files[] | select(.path == $path)]) | . + "\u0000"' "$before")
  if [ "${#paths[@]}" -eq 0 ]; then dr_task_complete; return; fi
  [[ "$subject" =~ ^(feat|fix|docs|style|refactor|test|chore|perf)(\([^\)]+\))?:\ .+ ]] &&
    [ "${#subject}" -le 50 ] && [[ "$subject" != *$'\n'* && "$subject" != *. ]] || { dr_task_block 'invalid commit subject'; return 2; }
  parent="$(jq -r .expected_head "$DR_TASK_DIR/state.json")" || return 2
  rm -f -- "$expected_index"
  GIT_INDEX_FILE="$expected_index" git -C "$DR_WORKTREE" read-tree "$parent" || return 2
  for path in "${paths[@]}"; do
    kind="$(jq -r --arg path "$path" '.files[] | select(.path == $path) | .kind' "$after")"
    if [ -z "$kind" ] || [ "$kind" = deleted ]; then
      GIT_INDEX_FILE="$expected_index" git -C "$DR_WORKTREE" update-index --force-remove -- "$path" || return 2
    else
      mode="$(jq -r --arg path "$path" '.files[] | select(.path == $path) | .mode' "$after")"
      if [ "$kind" = symlink ]; then hash="$(readlink -n -- "$DR_WORKTREE/$path" | git -C "$DR_WORKTREE" hash-object -w --stdin)"
      else hash="$(git -C "$DR_WORKTREE" hash-object -w --path="$path" -- "$path")"; fi
      [ -n "$hash" ] && GIT_INDEX_FILE="$expected_index" git -C "$DR_WORKTREE" update-index --add --cacheinfo "$mode" "$hash" "$path" || return 2
    fi
  done
  tree="$(GIT_INDEX_FILE="$expected_index" git -C "$DR_WORKTREE" write-tree)" || return 2
  dr_task_assert_snapshot "$after" || { dr_task_block 'files changed during tree preparation'; return 2; }
  dr_task_update '.candidate = {tree:$tree,parent:$parent,subject:$subject} | .pending = $snapshot[0] | .prior_phase = .phase | .phase = "committing"' \
    --arg tree "$tree" --arg parent "$parent" --arg subject "$subject" --slurpfile snapshot "$after" || return 2
  git --literal-pathspecs -C "$DR_WORKTREE" add -A -- "${paths[@]}" || { dr_task_block 'staging failed'; return 2; }
  [ "$(git -C "$DR_WORKTREE" write-tree)" = "$tree" ] || { dr_task_block 'staged tree differs from verified task tree'; return 2; }
  dr_snapshot "$DR_WORKTREE" "$DR_TASK_DIR/staged-snapshot.json" || return 2
  jq -e --slurpfile staged "$DR_TASK_DIR/staged-snapshot.json" '.files == $staged[0].files and .head == $staged[0].head' "$after" >/dev/null || { dr_task_block 'files changed during staging'; return 2; }
  dr_task_update '.pending = $snapshot[0]' --slurpfile snapshot "$DR_TASK_DIR/staged-snapshot.json" || return 2
  dr_task_commit
}

dr_task_control() {
  local operation="$1" value="${2:-}" approval="${3:-}" record="$DR_TASK_DIR/state.json" snapshot="$DR_TASK_DIR/control-snapshot.json"
  jq -e '.processes | length == 0' "$record" >/dev/null || { dr_state_error 'process termination must be reconciled first'; return 2; }
  case "$operation" in
    recover-commit)
      jq -e '.candidate != null and (.phase == "blocked" or .phase == "committing")' "$record" >/dev/null || return 2
      if [ "$(git -C "$DR_WORKTREE" rev-parse HEAD)" = "$(jq -r .candidate.parent "$record")" ]; then
        jq .pending "$record" > "$snapshot" && dr_task_assert_snapshot "$snapshot" || return 2
        local actual_tree candidate_tree parent path
        actual_tree="$(git -C "$DR_WORKTREE" write-tree)" || return 2
        candidate_tree="$(jq -r .candidate.tree "$record")"
        parent="$(jq -r .candidate.parent "$record")"
        while IFS= read -r -d '' path; do
          [ "$(git --literal-pathspecs -C "$DR_WORKTREE" ls-tree "$actual_tree" -- "$path")" = \
            "$(git --literal-pathspecs -C "$DR_WORKTREE" ls-tree "$candidate_tree" -- "$path")" ] || return 2
        done < <(git -C "$DR_WORKTREE" diff-tree -r --no-commit-id --no-renames --name-only -z "$parent" "$actual_tree")
        git -C "$DR_WORKTREE" read-tree "$candidate_tree" || return 2
      fi
      dr_task_commit ;;
    handback|release)
      jq -e '.phase == "complete" or .phase == "pending"' "$record" >/dev/null || return 2
      jq '.pending // .baseline' "$record" > "$snapshot" && dr_task_assert_snapshot "$snapshot" || return 2
      if [ "$operation" = release ]; then
        [ "$(jq -r .phase "$record")" = complete ] && [ -z "$(git -C "$DR_WORKTREE" status --porcelain)" ] || return 2
        dr_task_update '.released = true' && rm -f -- "$DR_TASK_ROOT/owner.json"
      else
        dr_task_update '.phase = "handed-back" | .history += [{operation:"handback",holder:"claude"}]' || return 2
        jq '.holder = "claude"' "$DR_TASK_ROOT/owner.json" > "$DR_TASK_ROOT/owner.next.json" && mv -f -- "$DR_TASK_ROOT/owner.next.json" "$DR_TASK_ROOT/owner.json"
      fi ;;
    amend-write-set|accept-baseline)
      [ -f "$value" ] && [ -f "$approval" ] || return 2
      local hash
      hash="$(git -C "$DR_WORKTREE" hash-object --no-filters -- "$value")" || return 2
      jq -e --arg task "$(jq -r .task_id "$record")" --arg operation "$operation" --arg hash "$hash" \
        '.task_id == $task and .operation == $operation and .file_hash == $hash and (.approval_reference | type == "string" and length > 0)' "$approval" >/dev/null || return 2
      if [ "$operation" = amend-write-set ]; then
        jq '.pending // .baseline' "$record" > "$snapshot" && dr_task_assert_snapshot "$snapshot" && dr_task_scope_valid "$value" || return 2
        dr_task_update '.write_set = $scope[0] | .history += [$approval[0]]' --slurpfile scope "$value" --slurpfile approval "$approval"
      else
        dr_task_assert_snapshot "$value" || return 2
        git -C "$DR_WORKTREE" diff --cached --quiet || return 2
        dr_task_update '.expected_head = $snapshot[0].head | .baseline = $snapshot[0] | .pending = $snapshot[0] | .phase = "pending" | .candidate = null | .history += [$approval[0]]' \
          --slurpfile snapshot "$value" --slurpfile approval "$approval"
      fi ;;
    *) return 2 ;;
  esac
}
