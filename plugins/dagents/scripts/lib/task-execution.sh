#!/usr/bin/env bash

dr_task_block() {
  local reason="$1" snapshot="$DAGENTS_TASK_DIR/blocked-snapshot.json"
  dr_snapshot "$DAGENTS_WORKTREE" "$snapshot" || return 2
  dr_task_update '.prior_phase = .phase | .phase = "blocked" | .pending = $snapshot[0] | .error = $reason' \
    --slurpfile snapshot "$snapshot" --arg reason "$reason"
}

dr_task_complete() {
  local head snapshot="$DAGENTS_TASK_DIR/completed-snapshot.json"
  head="$(git -C "$DAGENTS_WORKTREE" rev-parse HEAD)" || return 2
  [ -z "$(git -C "$DAGENTS_WORKTREE" status --porcelain=v1 --untracked-files=all)" ] || return 2
  dr_snapshot "$DAGENTS_WORKTREE" "$snapshot" || return 2
  dr_task_update '.expected_head = $head | .phase = "complete" | .prior_phase = null | .pending = null | .processes = [] | .baseline = $snapshot[0] | del(.error)' \
    --arg head "$head" --slurpfile snapshot "$snapshot"
}

dr_task_commit() {
  local tree parent subject head actual_tree
  tree="$(jq -er .candidate.tree "$DAGENTS_TASK_DIR/state.json")" || return 2
  parent="$(jq -er .candidate.parent "$DAGENTS_TASK_DIR/state.json")" || return 2
  subject="$(jq -er .candidate.subject "$DAGENTS_TASK_DIR/state.json")" || return 2
  head="$(git -C "$DAGENTS_WORKTREE" rev-parse HEAD)" || return 2
  if [ "$head" != "$parent" ]; then
    [ "$(git -C "$DAGENTS_WORKTREE" show -s --format=%P HEAD)" = "$parent" ] &&
    [ "$(git -C "$DAGENTS_WORKTREE" show -s --format=%T HEAD)" = "$tree" ] &&
    [ "$(git -C "$DAGENTS_WORKTREE" show -s --format=%s HEAD)" = "$subject" ] || return 2
    dr_task_complete
    return
  fi
  actual_tree="$(git -C "$DAGENTS_WORKTREE" write-tree)" || return 2
  [ "$actual_tree" = "$tree" ] || return 2
  dr_task_update '.phase = "committing"' || return 2
  timeout 60s git -C "$DAGENTS_WORKTREE" commit -q -m "$subject" || { dr_task_block 'commit failed'; return 2; }
  [ "$(git -C "$DAGENTS_WORKTREE" show -s --format=%T HEAD)" = "$tree" ] &&
    [ "$(git -C "$DAGENTS_WORKTREE" show -s --format=%P HEAD)" = "$parent" ] &&
    [ "$(git -C "$DAGENTS_WORKTREE" show -s --format=%s HEAD)" = "$subject" ] || { dr_task_block 'commit hooks changed the candidate'; return 2; }
  # A tree left dirty after a real commit is blocked, never parked in
  # "committing", where recover-commit would retry the same check forever.
  dr_task_complete || { dr_task_block 'worktree not clean after commit'; return 2; }
}

dr_task_stage() {
  local before="$1" subject="$2" after="$DAGENTS_TASK_DIR/verified-snapshot.json" path kind mode hash tree parent
  local expected_index="$DAGENTS_TASK_DIR/expected.index" paths=()
  dr_task_validate_scope "$before" || { dr_task_block 'worktree/index/HEAD changed outside task scope'; return 2; }
  jq .write_set "$DAGENTS_TASK_DIR/state.json" > "$DAGENTS_TASK_DIR/scope.json" && dr_task_scope_valid "$DAGENTS_TASK_DIR/scope.json" || { dr_task_block 'write-set path escapes worktree'; return 2; }
  dr_snapshot "$DAGENTS_WORKTREE" "$after" || return 2
  parent="$(jq -r .expected_head "$DAGENTS_TASK_DIR/state.json")" || return 2
  # The commit covers every change since the last commit, not only this
  # attempt's: a resumed task starts from a pending snapshot that still holds
  # an earlier attempt's uncommitted, already scope-checked work.
  while IFS= read -r -d '' path; do paths+=("$path"); done < <({
    jq -j --slurpfile after "$after" 'INDEX(.files[]; .path) as $b | INDEX($after[0].files[]; .path) as $a |
      ($b + $a | keys_unsorted[]) | select($b[.] != $a[.]) | . + "\u0000"' "$before"
    git -C "$DAGENTS_WORKTREE" diff --no-renames --name-only -z "$parent" --
    git -C "$DAGENTS_WORKTREE" ls-files -o --exclude-standard -z
  } | sort -zu)
  if [ "${#paths[@]}" -eq 0 ]; then dr_task_complete; return; fi
  [[ "$subject" =~ ^(feat|fix|docs|style|refactor|test|chore|perf)(\([^\)]+\))?:\ .+ ]] &&
    [ "${#subject}" -le 50 ] && [[ "$subject" != *$'\n'* && "$subject" != *. ]] || { dr_task_block 'invalid commit subject'; return 2; }
  rm -f -- "$expected_index"
  GIT_INDEX_FILE="$expected_index" git -C "$DAGENTS_WORKTREE" read-tree "$parent" || return 2
  for path in "${paths[@]}"; do
    kind="$(jq -r --arg path "$path" '.files[] | select(.path == $path) | .kind' "$after")"
    if [ -z "$kind" ] || [ "$kind" = deleted ]; then
      GIT_INDEX_FILE="$expected_index" git -C "$DAGENTS_WORKTREE" update-index --force-remove -- "$path" || return 2
    else
      mode="$(jq -r --arg path "$path" '.files[] | select(.path == $path) | .mode' "$after")"
      if [ "$kind" = gitlink ]; then
        hash="$(jq -r --arg path "$path" '.files[] | select(.path == $path) | .hash' "$after")"
        [[ "$hash" =~ ^[0-9a-f]+$ ]] || { dr_task_block "submodule $path is not initialized"; return 2; }
        _dr_is_gitlink "$DAGENTS_WORKTREE" "$path" "$parent" &&
          git -C "$DAGENTS_WORKTREE" config --blob "$parent:.gitmodules" --get-regexp '^submodule\..*\.path$' 2>/dev/null |
            awk -v p="$path" '{ sub(/^[^ ]+ /, "") } $0 == p { found = 1 } END { exit !found }' ||
          { dr_task_block "submodule $path is not registered in the parent commit"; return 2; }
      elif [ "$kind" = symlink ]; then hash="$(readlink -n -- "$DAGENTS_WORKTREE/$path" | git -C "$DAGENTS_WORKTREE" hash-object -w --stdin)"
      else hash="$(git -C "$DAGENTS_WORKTREE" hash-object -w --path="$path" -- "$path")"; fi
      [ -n "$hash" ] && GIT_INDEX_FILE="$expected_index" git -C "$DAGENTS_WORKTREE" update-index --add --cacheinfo "$mode" "$hash" "$path" || return 2
    fi
  done
  tree="$(GIT_INDEX_FILE="$expected_index" git -C "$DAGENTS_WORKTREE" write-tree)" || return 2
  dr_task_assert_snapshot "$after" || { dr_task_block 'files changed during tree preparation'; return 2; }
  dr_task_update '.candidate = {tree:$tree,parent:$parent,subject:$subject} | .pending = $snapshot[0] | .prior_phase = .phase | .phase = "committing"' \
    --arg tree "$tree" --arg parent "$parent" --arg subject "$subject" --slurpfile snapshot "$after" || return 2
  git --literal-pathspecs -C "$DAGENTS_WORKTREE" add -A -- "${paths[@]}" || { dr_task_block 'staging failed'; return 2; }
  [ "$(git -C "$DAGENTS_WORKTREE" write-tree)" = "$tree" ] || { dr_task_block 'staged tree differs from verified task tree'; return 2; }
  dr_snapshot "$DAGENTS_WORKTREE" "$DAGENTS_TASK_DIR/staged-snapshot.json" || return 2
  jq -e --slurpfile staged "$DAGENTS_TASK_DIR/staged-snapshot.json" '.files == $staged[0].files and .head == $staged[0].head' "$after" >/dev/null || { dr_task_block 'files changed during staging'; return 2; }
  dr_task_update '.pending = $snapshot[0]' --slurpfile snapshot "$DAGENTS_TASK_DIR/staged-snapshot.json" || return 2
  dr_task_commit
}

dr_task_control() {
  local operation="$1" value="${2:-}" approval="${3:-}" record="$DAGENTS_TASK_DIR/state.json" snapshot="$DAGENTS_TASK_DIR/control-snapshot.json"
  jq -e '.processes | length == 0' "$record" >/dev/null || { dr_state_error 'process termination must be reconciled first'; return 2; }
  case "$operation" in
    recover-commit)
      jq -e '.candidate != null and (.phase == "blocked" or .phase == "committing")' "$record" >/dev/null || return 2
      if [ "$(git -C "$DAGENTS_WORKTREE" rev-parse HEAD)" = "$(jq -r .candidate.parent "$record")" ]; then
        jq .pending "$record" > "$snapshot" && dr_task_assert_snapshot "$snapshot" || return 2
        local actual_tree candidate_tree parent path
        actual_tree="$(git -C "$DAGENTS_WORKTREE" write-tree)" || return 2
        candidate_tree="$(jq -r .candidate.tree "$record")"
        parent="$(jq -r .candidate.parent "$record")"
        while IFS= read -r -d '' path; do
          [ "$(git --literal-pathspecs -C "$DAGENTS_WORKTREE" ls-tree "$actual_tree" -- "$path")" = \
            "$(git --literal-pathspecs -C "$DAGENTS_WORKTREE" ls-tree "$candidate_tree" -- "$path")" ] || return 2
        done < <(git -C "$DAGENTS_WORKTREE" diff-tree -r --no-commit-id --no-renames --name-only -z "$parent" "$actual_tree")
        git -C "$DAGENTS_WORKTREE" read-tree "$candidate_tree" || return 2
      fi
      dr_task_commit ;;
    handback|release)
      if [ "$operation" = release ] && jq -e '.phase == "handed-back"' "$record" >/dev/null; then
        # Claude finishes a handed-back task with its own commits, which move
        # HEAD past every recorded snapshot, so only a clean worktree is checked.
        [ -z "$(git -C "$DAGENTS_WORKTREE" status --porcelain)" ] || return 2
        dr_task_update '.released = true' && rm -f -- "$DAGENTS_TASK_ROOT/owner.json"
        return
      fi
      jq -e '.phase == "complete" or .phase == "pending"' "$record" >/dev/null || return 2
      jq '.pending // .baseline' "$record" > "$snapshot" && dr_task_assert_snapshot "$snapshot" || return 2
      if [ "$operation" = release ]; then
        [ "$(jq -r .phase "$record")" = complete ] && [ -z "$(git -C "$DAGENTS_WORKTREE" status --porcelain)" ] || return 2
        dr_task_update '.released = true' && rm -f -- "$DAGENTS_TASK_ROOT/owner.json"
      else
        dr_task_update '.phase = "handed-back" | .history += [{operation:"handback",holder:"claude"}]' || return 2
        jq '.holder = "claude"' "$DAGENTS_TASK_ROOT/owner.json" > "$DAGENTS_TASK_ROOT/owner.next.json" && mv -f -- "$DAGENTS_TASK_ROOT/owner.next.json" "$DAGENTS_TASK_ROOT/owner.json"
      fi ;;
    amend-write-set|accept-baseline)
      [ -f "$value" ] && [ -f "$approval" ] || return 2
      local hash
      hash="$(git -C "$DAGENTS_WORKTREE" hash-object --no-filters -- "$value")" || return 2
      jq -e --arg task "$(jq -r .task_id "$record")" --arg operation "$operation" --arg hash "$hash" \
        '.task_id == $task and .operation == $operation and .file_hash == $hash and (.approval_reference | type == "string" and length > 0)' "$approval" >/dev/null || return 2
      if [ "$operation" = amend-write-set ]; then
        jq '.pending // .baseline' "$record" > "$snapshot" && dr_task_assert_snapshot "$snapshot" && dr_task_scope_valid "$value" || return 2
        dr_task_update '.write_set = $scope[0] | .history += [$approval[0]]' --slurpfile scope "$value" --slurpfile approval "$approval"
      else
        dr_task_assert_snapshot "$value" || return 2
        git -C "$DAGENTS_WORKTREE" diff --cached --quiet || return 2
        dr_task_update '.expected_head = $snapshot[0].head | .baseline = $snapshot[0] | .pending = $snapshot[0] | .phase = "pending" | .candidate = null | .history += [$approval[0]]' \
          --slurpfile snapshot "$value" --slurpfile approval "$approval"
      fi ;;
    *) return 2 ;;
  esac
}
