#!/usr/bin/env bash
# Acceptance tests for docs/dforge/specs/2026-11-16-dagents-split-design.md
# (the dagents-specific statements), run through dagents' scripts and hooks.
set -uo pipefail
unset CLAUDE_CONFIG_DIR CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA
for name in $(compgen -e | grep -E '^(DFORGE_|DAGENTS_|DR_(CODEX|LOCK|EXECUTORS|AGY)|WORKFLOW_GUARD_)'); do unset "$name"; done

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then pass=$((pass + 1)); printf 'ok   - %s\n' "$1"
  else printf 'FAIL - %s\n       got:  [%s]\n       want: [%s]\n' "$1" "$2" "$3"; fail=$((fail + 1)); fi
}
exists() { [ -e "$1" ] && echo yes || echo no; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 2; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com

# A world is a temporary home, an empty guard input set and a repository with
# one plan, so no case reads the machine's own plugins or settings.
PLAN_REL=docs/dagents/plans/2026-01-01-demo.md
write_plan() { # write_plan FILE
  mkdir -p "$(dirname "$1")"
  cat > "$1" <<'EOF'
# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** `docs/spec.md`

**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 scores 4

**Task check:** `bash quick.sh` — gate 1 has Tier: task

**Integration check:** `bash test.sh`

**CI:** none

## Global Constraints

- Bash only.

## Contracts

None

## Task index

1. First thing
2. Second thing

### Task 1: First thing

**Files:**
- Create: `a.txt`

**Implementer:** dagents:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

### Task 2: Second thing

**Files:**
- Modify: `a.txt`

**Implementer:** dagents:impl-sonnet-medium
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4

- [ ] **Step 1: Do it**
EOF
}
mkworld() { # mkworld NAME — a world with a project holding the demo plan
  local w="$TMP/$1"
  mkdir -p "$w/home" "$w/guard" "$w/data" "$w/proj/docs"
  git -C "$w/proj" init -q
  printf '# Spec\n' > "$w/proj/docs/spec.md"
  write_plan "$w/proj/$PLAN_REL"
  git -C "$w/proj" add -A && git -C "$w/proj" commit -q -m plan
}
event() { # event W NAME — a hook's stdin
  printf '{"session_id":"acc-s1","cwd":"%s","source":"startup","hook_event_name":"%s","transcript_path":"%s/t.jsonl","stop_hook_active":false,"prompt":"go"}' "$1/proj" "$2" "$1"
}
# in_world W CMD… — run CMD in W's project with W's home and guard inputs.
in_world() {
  local w=$1; shift
  ( cd "$w/proj" && export HOME="$w/home" CLAUDE_PLUGIN_ROOT="$PLUGIN" CLAUDE_PLUGIN_DATA="$w/data" \
      WORKFLOW_GUARD_CLAUDE_DIR="$w/guard" WORKFLOW_GUARD_MANAGED_DIR="$w/guard" WORKFLOW_GUARD_PROJECT_DIR="$w/guard" && "$@" )
}
# cycle W — session start, task brief, next step, turn start and turn end.
cycle() {
  local w=$1 o="$1/out"
  mkdir -p "$o"
  event "$w" SessionStart | in_world "$w" bash "$PLUGIN/scripts/session-start.sh" > "$o/ss.out" 2> "$o/ss.err"
  in_world "$w" bash "$PLUGIN/scripts/task-brief" "$PLAN_REL" 1 > "$o/tb.out" 2>&1
  in_world "$w" bash "$PLUGIN/scripts/next-step" "$PLAN_REL" > "$o/ns.out" 2>&1
  event "$w" UserPromptSubmit | in_world "$w" bash "$PLUGIN/scripts/turn-start.sh" > "$o/ts.out" 2>&1
  event "$w" Stop | in_world "$w" bash "$PLUGIN/scripts/turn-end.sh" > "$o/te.out" 2>&1
}
# Outputs with the world's path made neutral, and the session context as text.
normalized() { # normalized W FILE
  local w=$1 f=$2
  if [ "$f" = ss ]; then jq -r '.hookSpecificOutput.additionalContext // .systemMessage // empty' "$w/out/ss.out" 2>/dev/null | sed "s#$w#@W#g"
  else sed "s#$w#@W#g" "$w/out/$f.out"; fi
}
named() { # named DIR — every path under DIR with dforge in its name
  find "$1" -iname '*dforge*' 2>/dev/null | sed "s#^$1#@#" | sort
}
sums() { # sums DIR — a checksum per file under DIR
  ( cd "$1" && find . -type f -not -path './.git/*' | sort | while IFS= read -r f; do printf '%s %s\n' "$(sed "s#$TMP/[a-z]*#@W#g; s#at=[0-9]*#at=N#" "$f" | cksum)" "$f"; done )
}

# --- A7: dagents reads and writes none of dforge's names ---------------------
mkworld base
cycle "$TMP/base"
check "A7: the cycle's session start injects dagents' entry skill" "$( [ "$(normalized "$TMP/base" ss | grep -c 'dagents')" -gt 0 ] && echo yes)" "yes"
check "A7: the cycle's next-step names the plan's first task" "$(grep -c 'Start at Task 1' "$TMP/base/out/ns.out")" "1"
check "A7: the cycle wrote dagents' state" "$(exists "$TMP/base/proj/.dagents/sdd/2026-01-01-demo/task-1-brief.md")" "yes"
check "A7: nothing named dforge appears in the project, its git directory or the home" "$(named "$TMP/base")" ""

# A second identical world with dforge's variables set: nothing changes.
mkworld envset
( export DFORGE_BUDGET=1234 DR_CODEX_SESSION_DIR="$TMP/envset/codex-sessions" DR_EXECUTORS_DIR="$TMP/envset/none" DFORGE_FAST=on; cycle "$TMP/envset" )
for f in ss tb ns ts te; do
  check "A7: DFORGE_BUDGET and DR_CODEX_SESSION_DIR change no $f output" "$(normalized "$TMP/envset" $f | sed 's#envset#base#g')" "$(normalized "$TMP/base" $f)"
done
check "A7: the set variables created nothing named dforge" "$(named "$TMP/envset")" ""
check "A7: the set variables changed no file" "$(sums "$TMP/envset/proj")" "$(sums "$TMP/base/proj")"
check "A7: DR_CODEX_SESSION_DIR was not used as a session directory" "$(exists "$TMP/envset/codex-sessions")" "no"

# A world holding a dforge home config and .dforge state.
mkworld seeded
S="$TMP/seeded"
top=$(git -C "$S/proj" rev-parse --show-toplevel)
mkdir -p "$S/home/.dforge" "$S/proj/.dforge/sdd/2026-01-01-demo" "$S/proj/.dforge/handoff"
printf '{"handoffTokens":77777,"handoffMode":"relaxed","worktree":"never","notifyAfter":5,"darkmemEnabled":true,"darkmem":{"url":"http://127.0.0.1:9","repos":{"%s":{"project":"seeded-project"}}}}\n' "$top" > "$S/home/.dforge/config.json"
printf '{}\n' > "$S/home/.dforge/stores.json"
printf '# Ledger\n\n- Task 1: complete\n- Task 2: complete\n' > "$S/proj/.dforge/sdd/2026-01-01-demo/progress.md"
printf '## Next session\n\n**Next:** dforge says final review.\n' > "$S/proj/.dforge/handoff/latest.md"
seed_before=$( { sums "$S/home/.dforge"; sums "$S/proj/.dforge"; } )
cycle "$S"
for f in tb ns ts te; do
  check "A7: a dforge home config and .dforge state change no $f output" "$(normalized "$S" $f | sed 's#seeded#base#g')" "$(normalized "$TMP/base" $f)"
done
check "A7: session start differs only by the dforge 4.x layout line" "$(normalized "$S" ss | sed 's#seeded#base#g' | grep -v 'dforge 4.x layout found')" "$(normalized "$TMP/base" ss)"
check "A7: the dforge files were not changed" "$( { sums "$S/home/.dforge"; sums "$S/proj/.dforge"; } )" "$seed_before"
check "A7: no new path named dforge appeared" "$(named "$S")" "$(printf '%s\n' '@/home/.dforge' '@/proj/.dforge' | sort)"
check "A7: dagents' budget ignores ~/.dforge/config.json" "$(tail -n 1 "$S/out/tb.out" | grep -c '78k')" "0"


# --- A9 and A10: migrating a dforge 4.x project ------------------------------
MIGRATE="$PLUGIN/scripts/dagents-migrate"
PIDS=()
trap 'kill "${PIDS[@]}" 2>/dev/null; rm -rf "$TMP"' EXIT
ACTIVE_PLAN='# Active plan

**Execution:** subagent — `claude --model sonnet --effort high` — Task 1 scores 1

> **For agentic workers:** REQUIRED SUB-SKILL: dforge:subagent-driven-development

## Task index

1. Only thing

### Task 1: Only thing

**Implementer:** dforge:impl-sonnet-low
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

- [ ] **Step 1: Do it**
'
FINISHED_PLAN='# Finished plan

**Implementer:** dforge:impl-sonnet-low (a finished plan keeps its text)
'
mk4x() { # mk4x NAME — a dforge 4.x project with a linked worktree and a home
  local w="$TMP/$1" p="$TMP/$1/proj" top
  mkdir -p "$w/home" "$w/guard" "$w/data" "$p"
  git -C "$p" init -q -b main
  mkdir -p "$p/docs/dforge/specs" "$p/docs/dforge/plans"
  printf '# Spec\n\nSee dforge:brainstorming.\n' > "$p/docs/dforge/specs/2026-01-01-demo-design.md"
  printf '%s' "$ACTIVE_PLAN" > "$p/docs/dforge/plans/2026-01-01-active.md"
  printf '%s' "$FINISHED_PLAN" > "$p/docs/dforge/plans/2026-01-01-finished.md"
  printf '# Completed\n\n- `docs/dforge/plans/2026-01-01-finished.md`\n' > "$p/docs/dforge/plans/completed.md"
  printf '.dforge/\n' > "$p/.gitignore"
  printf 'docs/dforge/** linguist-generated\n' > "$p/.gitattributes"
  printf '# Project\n\nPlans live in docs/dforge/plans.\n' > "$p/CLAUDE.md"
  git -C "$p" add -A && git -C "$p" commit -q -m "a dforge 4.x project"
  git -C "$p" worktree add -q -b feature "$w/wt"
  top=$(git -C "$p" rev-parse --show-toplevel)
  for c in "$p" "$w/wt"; do
    mkdir -p "$c/.dforge/handoff" "$c/.dforge/sdd/2026-01-01-active"
    printf '## Next session\n\nContinue with dforge:subagent-driven-development.\n' > "$c/.dforge/handoff/latest.md"
    printf '# Ledger\n' > "$c/.dforge/sdd/2026-01-01-active/progress.md"
  done
  mkdir -p "$p/.git/dforge/locks" "$p/.git/worktrees/wt/dforge"
  printf 'x\n' > "$p/.git/worktrees/wt/dforge/note"
  printf 'x\n' > "$p/.git/dforge/keep"
  printf '.dforge\n' >> "$p/.git/info/exclude"
  mkdir -p "$w/home/.dforge" "$w/home/.dagents"
  printf '{"handoffTokens":77777,"worktree":"never","notifyAfter":5,"agyReview":true,"darkmemEnabled":false}\n' > "$w/home/.dforge/config.json"
  printf '{"worktree":"always"}\n' > "$w/home/.dagents/config.json"
  : "$top"
}
migrate() { # migrate W [ARGS…] — run dagents-migrate in W's project; sets out and rc
  local w=$1; shift
  out=$(in_world "$w" bash "$MIGRATE" "$@" 2>&1); rc=$?
  out=$(printf '%s\n' "$out" | sed "s#$w#@W#g")
}
snapshot() { # snapshot W — every path and file content under W, apart from git's index and objects
  ( cd "$1" && find . -not -path '*/.git/objects/*' -not -path '*/.git/index' -not -path '*/.git/logs/*' \( -type f -o -type d \) | sort | while IFS= read -r f; do
      if [ -f "$f" ]; then printf '%s %s\n' "$(cksum < "$f")" "$f"; else printf 'dir %s\n' "$f"; fi
    done; git -C proj status --porcelain=v1 --untracked-files=all; git -C wt status --porcelain=v1 --untracked-files=all )
}

mk4x m1
W="$TMP/m1"; P="$W/proj"; T="$W/wt"
before=$(snapshot "$W")
migrate "$W" --dry-run
check "A10: the dry run exits 0 and lists the moves" "$rc:$(printf '%s\n' "$out" | grep -c '^would ')" "0:$(printf '%s\n' "$out" | grep -c '^would ')"
check "A10: the dry run lists a move" "$( [ "$(printf '%s\n' "$out" | grep -c '^would ')" -gt 3 ] && echo yes)" "yes"
check "A10: the dry run writes nothing (checkouts, git directory, home)" "$(snapshot "$W")" "$before"

migrate "$W"
check "A9: the move exits 0" "$rc" "0"
check "A9: docs/dforge is staged as renames to docs/dagents in the checkout" "$(git -C "$P" diff --cached --name-status -M | awk '$1 ~ /^R/ && $2 ~ /^docs\/dforge\// && $3 ~ /^docs\/dagents\//' | wc -l | tr -d ' ')" "4"
check "A9: docs/dforge is staged as renames in the worktree too" "$(git -C "$T" diff --cached --name-status -M | awk '$1 ~ /^R/ && $2 ~ /^docs\/dforge\// && $3 ~ /^docs\/dagents\//' | wc -l | tr -d ' ')" "4"
check "A9: no docs/dforge is left in either checkout" "$(exists "$P/docs/dforge")$(exists "$T/docs/dforge")" "nono"
check "A9: .dforge moved to .dagents in each checkout, state kept" "$(exists "$P/.dforge")$(exists "$T/.dforge")$(exists "$P/.dagents/sdd/2026-01-01-active/progress.md")$(exists "$T/.dagents/sdd/2026-01-01-active/progress.md")" "nonoyesyes"
check "A9: <git dir>/dforge moved to dagents, in the checkout and in the worktree's git directory" "$(exists "$P/.git/dforge")$(exists "$P/.git/worktrees/wt/dforge")$(exists "$P/.git/dagents/keep")$(exists "$P/.git/worktrees/wt/dagents/note")" "nonoyesyes"
check "A9: the active plan's dforge: prefixes are rewritten" "$(grep -c 'dforge:' "$P/docs/dagents/plans/2026-01-01-active.md")/$(grep -c 'dagents:impl-sonnet-low' "$P/docs/dagents/plans/2026-01-01-active.md")/$(grep -c 'dagents:subagent-driven-development' "$P/docs/dagents/plans/2026-01-01-active.md")" "0/1/1"
check "A9: the worktree's active plan is rewritten" "$(grep -c 'dforge:' "$T/docs/dagents/plans/2026-01-01-active.md")" "0"
check "A9: the handoff note's prefixes are rewritten in each checkout" "$(grep -c 'dforge:' "$P/.dagents/handoff/latest.md" "$T/.dagents/handoff/latest.md" | tr '\n' ' ')" "$P/.dagents/handoff/latest.md:0 $T/.dagents/handoff/latest.md:0 "
check "A9: a finished plan and a spec keep their text" "$(grep -c 'dforge:' "$P/docs/dagents/plans/2026-01-01-finished.md" "$P/docs/dagents/specs/2026-01-01-demo-design.md" | tr '\n' ' ')" "$P/docs/dagents/plans/2026-01-01-finished.md:1 $P/docs/dagents/specs/2026-01-01-demo-design.md:1 "
check "A9: a project CLAUDE.md that names docs/dforge is reported and left" "$(printf '%s\n' "$out" | grep -c '^report: .*CLAUDE.md'):$(grep -c 'docs/dforge' "$P/CLAUDE.md")" "1:1"
check "A9: .gitignore keeps the dforge line and gains the dagents twin" "$(grep -c '^\.dforge/$' "$P/.gitignore")$(grep -c '^\.dagents/$' "$P/.gitignore")" "11"
check "A9: .gitattributes keeps its dforge line and gains the dagents twin" "$(grep -c 'docs/dforge/\*\*' "$P/.gitattributes")$(grep -c 'docs/dagents/\*\*' "$P/.gitattributes")" "11"
check "A9: info/exclude keeps its dforge line and gains the dagents twin" "$(grep -c '^\.dforge$' "$P/.git/info/exclude")$(grep -c '^\.dagents$' "$P/.git/info/exclude")" "11"
check "A9: dagents' settings gain the schema keys dforge's home held" "$(in_world "$W" bash "$PLUGIN/scripts/dagents-config" get handoffTokens)/$(in_world "$W" bash "$PLUGIN/scripts/dagents-config" get notifyAfter)" "77777/5"
check "A9: a value dagents already had is not overwritten" "$(in_world "$W" bash "$PLUGIN/scripts/dagents-config" get worktree)" "always"
check "A9: a key outside dagents' schema is not copied" "$(jq 'has("agyReview")' "$W/home/.dagents/config.json")" "false"
check "A9: dforge's own home config stays where it is" "$(jq -c '.handoffTokens' "$W/home/.dforge/config.json")" "77777"
migrate "$W"
check "A10: a second run has nothing left to do and exits 0" "$rc" "0"

# The same project once its home holds a record for it: the settings copy.
mk4x m1b
W="$TMP/m1b"; P="$W/proj"
top=$(git -C "$P" rev-parse --show-toplevel)
printf '{"%s":{"documents":"local","progress":"local","project":"acc-project"}}\n' "$top" > "$W/home/.dforge/stores.json"
migrate "$W"
check "A9: with a home record for the project, the move exits 0" "$rc" "0"
check "A9: dagents' settings gain the schema keys dforge's home held (record present)" "$(in_world "$W" bash "$PLUGIN/scripts/dagents-config" get handoffTokens)/$(in_world "$W" bash "$PLUGIN/scripts/dagents-config" get notifyAfter)" "77777/5"
check "A9: a value dagents already had is not overwritten (record present)" "$(in_world "$W" bash "$PLUGIN/scripts/dagents-config" get worktree)" "always"
check "A9: a key outside dagents' schema is not copied (record present)" "$(jq 'has("agyReview")' "$W/home/.dagents/config.json")" "false"
check "A9: the project's record stays in dforge's stores.json, and dagents keeps none" "$(exists "$W/home/.dagents/stores.json")/$(jq -r --arg k "$top" 'has($k)' "$W/home/.dforge/stores.json")" "no/true"
check "A9: dforge's config.json stays where it is (record present)" "$(jq -c '.handoffTokens' "$W/home/.dforge/config.json")" "77777"
check "A9: no darkmem setting is copied (record present)" "$(jq -c 'has("darkmemEnabled") or has("darkmem")' "$W/home/.dagents/config.json")" "false"

# The same project once its home keeps its progress in darkmem: refused
# before anything moves, saying to bring it home in dforge first.
mk4x m1c
W="$TMP/m1c"; P="$W/proj"
top=$(git -C "$P" rev-parse --show-toplevel)
printf '{"%s":{"documents":"local","progress":"darkmem","project":"acc-project"}}\n' "$top" > "$W/home/.dforge/stores.json"
migrate "$W"
check "A9: progress kept in darkmem refuses the move" "$rc" "1"
check "A9: the refusal says to set progressSource local in dforge first" "$(printf '%s\n' "$out" | grep -c "progress in darkmem.*set progressSource to local in dforge first")" "1"
check "A9: nothing moved while progress is in darkmem" "$(exists "$P/docs/dforge")$(exists "$P/.dforge")$(exists "$P/docs/dagents")$(exists "$P/.dagents")" "yesyesnono"

# A10: refusals, one case each, each in its own project
case_refused() { # case_refused NAME PREPARE-FUNCTION WHAT — prepares a project, migrates, and returns with out/rc set
  mk4x "$1"; "$2" "$TMP/$1"; migrate "$TMP/$1"
}
prep_differs() { printf 'old\n' > "$1/proj/.dforge/note.txt"; mkdir -p "$1/proj/.dagents"; printf 'new\n' > "$1/proj/.dagents/note.txt"; }
case_refused m2 prep_differs
W="$TMP/m2"
check "A10: a differing same-path file refuses" "$rc" "1"
check "A10: ... and both copies are left as they were" "$(cat "$W/proj/.dforge/note.txt")/$(cat "$W/proj/.dagents/note.txt")" "old/new"
migrate_status_after_fix() { rm -f "$W/proj/.dforge/note.txt"; migrate "$W"; }
check "A10: a refusal keeps the rest of the job: docs moved in the first run" "$(exists "$W/proj/docs/dagents/plans/2026-01-01-active.md")" "yes"
migrate_status_after_fix
check "A10: a second run after the partial migration finishes the job and exits 0" "$rc:$(exists "$W/proj/.dforge/sdd"):$(exists "$W/proj/.dagents/sdd/2026-01-01-active/progress.md")" "0:no:yes"

prep_two_trees() { mkdir -p "$1/proj/docs/dagents"; printf 'x\n' > "$1/proj/docs/dagents/a.md"; git -C "$1/proj" add -A; git -C "$1/proj" commit -q -m "two trees"; }
case_refused m3 prep_two_trees
W="$TMP/m3"
check "A10: two tracked docs trees refuse" "$rc" "1"
check "A10: ... and neither tree moved" "$(exists "$W/proj/docs/dforge/plans/2026-01-01-active.md")$(exists "$W/proj/docs/dagents/a.md")" "yesyes"
check "A10: ... and nothing was staged for them" "$(git -C "$W/proj" diff --cached --name-only -- docs | wc -l | tr -d ' ')" "0"

prep_dirty() { printf 'edited\n' >> "$1/proj/docs/dforge/specs/2026-01-01-demo-design.md"; }
case_refused m4 prep_dirty
W="$TMP/m4"
check "A10: a dirty file among the moved paths refuses" "$rc" "1"
check "A10: ... and docs/dforge is left in place, edit intact" "$(exists "$W/proj/docs/dforge/specs/2026-01-01-demo-design.md"):$(grep -c edited "$W/proj/docs/dforge/specs/2026-01-01-demo-design.md"):$(exists "$W/proj/docs/dagents")" "yes:1:no"

prep_lock() {
  sleep 300 & PIDS+=("$!")
  mkdir -p "$1/proj/.git/dforge/locks/run"
  printf '%s\n' "$!" > "$1/proj/.git/dforge/locks/run/pid"
  printf '%s\n' "$(uname -n)" > "$1/proj/.git/dforge/locks/run/host"
}
case_refused m5 prep_lock
W="$TMP/m5"
check "A10: a lock a live process holds refuses" "$rc" "1"
check "A10: ... and nothing moved at all" "$(exists "$W/proj/docs/dforge")$(exists "$W/proj/.dforge")$(exists "$W/proj/docs/dagents")$(exists "$W/proj/.dagents")$(exists "$W/home/.dagents/config.json.bak")" "yesyesnonono"
check "A10: ... and no home setting was copied" "$(in_world "$W" bash "$PLUGIN/scripts/dagents-config" get handoffTokens)" "0"

prep_auto() {
  printf '{"active":true,"session":"live-sess"}\n' > "$1/proj/.dforge/sdd/auto-run.json"
  mkdir -p "$1/home/.claude/dforge/sessions/cockpit"
  date +%s > "$1/home/.claude/dforge/sessions/cockpit/live-sess"
}
case_refused m6 prep_auto
W="$TMP/m6"
check "A10: an auto run bound to a live session refuses, and nothing moved" "$rc:$(exists "$W/proj/docs/dforge"):$(exists "$W/proj/.dforge/sdd/auto-run.json")" "1:yes:yes"

# A version 5 project: an active plan whose task has no Implementer line
V5_PLAN='# Version 5 plan

## Task index

1. Only thing

### Task 1: Only thing

**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

- [ ] **Step 1: Do it**
'
prep_v5() { printf '%s' "$V5_PLAN" > "$1/proj/docs/dforge/plans/2026-01-02-five.md"; git -C "$1/proj" add -A; git -C "$1/proj" commit -q -m "a version 5 plan"; }
case_refused m7 prep_v5
W="$TMP/m7"
check "A10: a project with a version-5 marker is refused" "$rc" "1"
check "A10: ... as not migratable, with nothing moved" "$(printf '%s\n' "$out" | grep -c 'dforge 5 layout: not migratable'):$(exists "$W/proj/docs/dforge"):$(exists "$W/proj/docs/dagents"):$(exists "$W/proj/.dforge")" "1:yes:no:yes"
git clone -q "$W/proj" "$W/clone" 2>/dev/null
out=$(in_world "$W" bash "$MIGRATE" "$W/clone" 2>&1); rc=$?
check "A10: a fresh clone of a version-5 project is refused too" "$rc:$(printf '%s\n' "$out" | grep -c 'not migratable'):$(exists "$W/clone/docs/dagents")" "1:1:no"

# A 4.x project opened once under dforge 5 still migrates.
mk4x m8
W="$TMP/m8"; P="$W/proj"
dforge_event() { printf '{"session_id":"five-s1","cwd":"%s","source":"startup","hook_event_name":"%s","transcript_path":"%s/t.jsonl","stop_hook_active":false,"prompt":"go"}' "$P" "$1" "$W"; }
for hook in "session-start.sh:SessionStart" "turn-start.sh:UserPromptSubmit" "turn-end.sh:Stop"; do
  dforge_event "${hook#*:}" | ( cd "$P" && HOME="$W/home" CLAUDE_PLUGIN_ROOT="$PLUGIN/../dforge" CLAUDE_PLUGIN_DATA="$W/data5" WORKFLOW_GUARD_CLAUDE_DIR="$W/guard" WORKFLOW_GUARD_MANAGED_DIR="$W/guard" WORKFLOW_GUARD_PROJECT_DIR="$W/guard" bash "$PLUGIN/../dforge/scripts/${hook%%:*}" >/dev/null 2>&1 )
done
migrate "$W"
check "A10: a 4.x project opened once under dforge 5 still migrates" "$rc:$(exists "$P/docs/dagents/plans/2026-01-01-active.md"):$(exists "$P/docs/dforge")" "0:yes:no"


# --- A20: dforge 5 in another project keeps its darkmem mapping and stores ----
DFORGE="$PLUGIN/../dforge"
in_world_at() { # in_world_at W DIR PLUGIN-ROOT CMD… — like in_world, from DIR with another plugin's root
  local w=$1 dir=$2 root=$3; shift 3
  ( cd "$dir" && export HOME="$w/home" CLAUDE_PLUGIN_ROOT="$root" CLAUDE_PLUGIN_DATA="$w/data" \
      WORKFLOW_GUARD_CLAUDE_DIR="$w/guard" WORKFLOW_GUARD_MANAGED_DIR="$w/guard" WORKFLOW_GUARD_PROJECT_DIR="$w/guard" && "$@" )
}
W="$TMP/a20"
mkdir -p "$W/home/.dforge" "$W/guard" "$W/data"
for n in a b; do
  mkdir -p "$W/$n/docs/dforge/plans"; git -C "$W/$n" init -q -b main
  printf 'x\n' > "$W/$n/docs/dforge/plans/p.md"; git -C "$W/$n" add -A; git -C "$W/$n" commit -q -m init
done
A=$(git -C "$W/a" rev-parse --show-toplevel); B=$(git -C "$W/b" rev-parse --show-toplevel)
mkdir -p "$W/home/.dforge/mirror/proj-b/dforge" "$W/home/.dforge/mirror/proj-b/work/sdd" "$W/home/.dforge/mirror/proj-b/work/handoff"
printf '{"darkmemEnabled":true,"handoffTokens":5555,"darkmem":{"url":"http://127.0.0.1:9","repos":{"%s":{"project":"proj-b"}}}}\n' "$B" > "$W/home/.dforge/config.json"
printf '{"%s":{"documents":"local","progress":"local","project":"proj-a"},"%s":{"documents":"darkmem","progress":"local"}}\n' "$A" "$B" > "$W/home/.dforge/stores.json"
five_view() { # what dforge 5 resolves for project B
  in_world_at "$W" "$W/b" "$DFORGE" bash "$DFORGE/scripts/darkmem-sync" status 2>&1 | sed "s#$W#@W#g"
  in_world_at "$W" "$W/b" "$DFORGE" bash "$DFORGE/scripts/dforge-config" get handoffTokens 2>&1
}
five_view > /dev/null
b_before=$(five_view); b_record=$(jq -S --arg k "$B" '.[$k]' "$W/home/.dforge/stores.json"); b_config=$(sed "s#$W#@W#g" "$W/home/.dforge/config.json" | cksum)
out=$(in_world_at "$W" "$W/a" "$PLUGIN" bash "$MIGRATE" 2>&1); rc=$?
check "A20: project A migrates" "$rc" "0"
check "A20: dforge 5 in project B resolves the same mapping and applied stores" "$(five_view)" "$b_before"
check "A20: B's applied stores record in ~/.dforge/stores.json is unchanged" "$(jq -S --arg k "$B" '.[$k]' "$W/home/.dforge/stores.json")" "$b_record"
check "A20: ~/.dforge/config.json is unchanged" "$(sed "s#$W#@W#g" "$W/home/.dforge/config.json" | cksum)" "$b_config"
check "A20: B's mirror is untouched" "$(exists "$W/home/.dforge/mirror/proj-b/dforge")$(exists "$W/home/.dagents/mirror/proj-b")" "yesno"
check "A20: the status names B's darkmem project" "$(printf '%s\n' "$b_before" | grep -c 'project proj-b')" "1"

# --- A21: a migrated plan and ledger that cite docs/dforge keep their meaning ---
W="$TMP/a21"; P="$W/proj"
mkdir -p "$W/home" "$W/guard" "$W/data" "$P/docs/dforge/plans" "$P/.dforge/sdd/2026-01-02-unfinished" "$P/.dforge/sdd/2026-01-01-finished"
git -C "$P" init -q -b main
plan3() {
  printf '# Demo Implementation Plan\n\n> **For agentic workers:** REQUIRED SUB-SKILL: dforge:subagent-driven-development\n\n**Goal:** Demo.\n\n**Execution:** subagent — `claude --model sonnet --effort high` — Task 2 scores 4\n\n## Task index\n\n1. First thing\n2. Second thing\n3. Third thing\n'
  for n in 1 2 3; do printf '\n### Task %s: Thing %s\n\n**Implementer:** dforge:impl-sonnet-low\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\n- [ ] **Step 1: Do it**\n' "$n" "$n"; done
}
plan3 > "$P/docs/dforge/plans/2026-01-01-finished.md"; plan3 > "$P/docs/dforge/plans/2026-01-02-unfinished.md"
printf '# Completed\n\n- `docs/dforge/plans/2026-01-01-finished.md`\n' > "$P/docs/dforge/plans/completed.md"
printf '# SDD ledger — plan: docs/dforge/plans/2026-01-02-unfinished.md\nTask 1: complete (commits a..b, review clean)\nTask 2: complete (commits b..c, review clean)\n' > "$P/.dforge/sdd/2026-01-02-unfinished/progress.md"
printf '# SDD ledger — plan: docs/dforge/plans/2026-01-01-finished.md\nTask 1: complete (x)\nTask 2: complete (x)\nTask 3: complete (x)\n' > "$P/.dforge/sdd/2026-01-01-finished/progress.md"
printf '.dforge/\n' > "$P/.gitignore"
git -C "$P" add -A; git -C "$P" commit -q -m init
migrate "$W"
check "A21: the fixture migrates" "$rc" "0"
check "A21: the ledger and completed.md keep citing docs/dforge" "$(grep -c 'docs/dforge' "$P/.dagents/sdd/2026-01-02-unfinished/progress.md" "$P/docs/dagents/plans/completed.md" | tr '\n' ' ')" "$P/.dagents/sdd/2026-01-02-unfinished/progress.md:1 $P/docs/dagents/plans/completed.md:1 "
fin=$(in_world "$W" bash "$PLUGIN/scripts/next-step" --print docs/dagents/plans/2026-01-01-finished.md 2>&1)
check "A21: next-step treats the finished plan as finished" "$(printf '%s\n' "$fin" | grep -cE 'Start at Task|Resume at Task')/$(printf '%s\n' "$fin" | grep -ci 'complete')" "0/1"
unf=$(in_world "$W" bash "$PLUGIN/scripts/next-step" --print docs/dagents/plans/2026-01-02-unfinished.md 2>&1)
check "A21: next-step resumes the unfinished plan at its next task" "$(printf '%s\n' "$unf" | grep -c '\*\*Next:\*\* Resume at Task 3 ')" "1"
check "A21: ... counting the ledger's two completed tasks" "$(printf '%s\n' "$unf" | grep -c '2 of 3 tasks complete')" "1"

printf '%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
