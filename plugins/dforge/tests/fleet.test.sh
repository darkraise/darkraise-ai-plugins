#!/usr/bin/env bash
# The fleet is twenty-one agents in four classes. Seven execution implementers
# pin one model/effort pairing each and are everything the assignment table and
# the escalation ladder can reach. Nine reserve implementers - the xhigh and max
# efforts, and every Fable tier - are never an output of scoring: they are
# reachable only by a human override, or by the reserve chain after a split has
# already been spent. Four role agents - three judges and one scout - never
# carry Edit, NotebookEdit, Bash or Agent, so "reviewers do not spawn
# subagents" is enforced rather than requested. A judge carries Write for one
# file, the report its prompt names; task-step verdict checks that no tracked
# file changed during the review. The scout carries no Write at all.
# One drafter writes plan slices and may prototype, so it carries Bash, Write
# and Edit, but never Agent: drafters do not spawn subagents.
#
# Haiku 4.5 does not support reasoning effort at all, so impl-haiku must NOT
# carry an effort field. xhigh, max, and the Fable model are legal for reserve
# implementers and for nothing else.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS="$HERE/../agents"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

# fm <file> <key> - read one scalar key out of the YAML frontmatter block
fm() {
  awk -v k="$2" '
    NR == 1 && $0 == "---" { inb = 1; next }
    inb && $0 == "---" { exit }
    inb && index($0, k ":") == 1 { sub("^" k ":[ \t]*", ""); print; exit }
  ' "$1"
}

RESERVE="impl-fable-high impl-fable-low impl-fable-max impl-fable-medium impl-fable-xhigh impl-opus-max impl-opus-xhigh impl-sonnet-max impl-sonnet-xhigh"
EXPECTED="drafter-sonnet impl-fable-high impl-fable-low impl-fable-max impl-fable-medium impl-fable-xhigh impl-haiku impl-opus-high impl-opus-low impl-opus-max impl-opus-medium impl-opus-xhigh impl-sonnet-high impl-sonnet-low impl-sonnet-max impl-sonnet-medium impl-sonnet-xhigh judge-fable judge-opus judge-sonnet-high scout-sonnet"
JUDGE_TOOLS="Read, Grep, Glob, WebFetch, Write"
SCOUT_TOOLS="Read, Grep, Glob, WebFetch"
DRAFTER_TOOLS="Read, Grep, Glob, Bash, Write, Edit"
IMPL_DISALLOWED="Agent, Skill, Workflow, Artifact, ArtifactComments, ArtifactData, AskUserQuestion, EnterPlanMode, ExitPlanMode, EnterWorktree, ExitWorktree, CronCreate, CronDelete, CronList, RemoteTrigger, ScheduleWakeup, SendMessage, ListAgents, SendUserFile, PushNotification, DesignSync, ReportFindings, SendFeedback, ReadNotifications"

is_reserve() { case " $RESERVE " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

actual=$(cd "$AGENTS" 2>/dev/null && ls *.md 2>/dev/null | sed 's/\.md$//' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "fleet contains exactly the 21 expected agents" "$actual" "$EXPECTED"

for f in "$AGENTS"/*.md; do
  [ -e "$f" ] || continue
  base=$(basename "$f" .md)

  check "$base: frontmatter name matches filename" "$(fm "$f" name)" "$base"

  model=$(fm "$f" model)
  case "$model" in
    haiku|sonnet|opus|fable) got_model=ok ;;
    *) got_model="invalid:$model" ;;
  esac
  check "$base: model is a valid alias" "$got_model" "ok"

  effort=$(fm "$f" effort)

  case "$base" in
    impl-*)
      # An implementer's name is its contract: the second segment is the model
      # and the last is the effort. Checking both against the filename is what
      # keeps the ladder tables, which index by name, honest.
      check "$base: model matches the name segment" "$model" "$(printf '%s' "$base" | cut -d- -f2)"

      if is_reserve "$base"; then
        check "$base: effort matches the name suffix" "$effort" "${base##*-}"
        check "$base: reserve effort is an allowed level" \
          "$(case "$effort" in low|medium|high|xhigh|max) echo ok ;; *) echo "invalid:$effort" ;; esac)" "ok"
      else
        check "$base: execution implementer does not run on fable" \
          "$([ "$model" = fable ] && echo yes || echo no)" "no"
        if [ "$model" = "haiku" ]; then
          check "$base: haiku carries no effort field" "${effort:-ABSENT}" "ABSENT"
        else
          check "$base: effort matches the name suffix" "$effort" "${base##*-}"
          check "$base: execution effort is an allowed level" \
            "$(case "$effort" in low|medium|high) echo ok ;; *) echo "reserve-or-invalid:$effort" ;; esac)" "ok"
        fi
      fi

      check "$base: does not set tools" "$(grep -c '^tools:' "$f")" "0"
      check "$base: drops the session-only tools" "$(fm "$f" disallowedTools)" "$IMPL_DISALLOWED"
      check "$base: preloads verification-before-completion" \
        "$(grep -c '^  - dforge:verification-before-completion$' "$f")" "1"
      ;;
    judge-*|scout-*)
      # The absent tools are the point: no Edit, no Bash, no Agent. A judge's
      # one Write is its report file; the scout writes nothing.
      case "$base" in
        judge-*)
          check "$base: carries the judge toolset" "$(fm "$f" tools)" "$JUDGE_TOOLS"
          check "$base: writes only the report file" "$(grep -c 'write only the report file' "$f")" "1"
          check "$base: no longer says it cannot modify files" "$(grep -c 'You cannot modify files' "$f")" "0"
          check "$base: its reply is not its whole verdict" "$(grep -c 'Your verdict is the whole of your output' "$f")" "0"
          check "$base: the description does not call it read-only" "$(fm "$f" description | grep -c 'Read-only')" "0"
          ;;
        *)
          check "$base: carries the read-only toolset" "$(fm "$f" tools)" "$SCOUT_TOOLS"
          ;;
      esac
      check "$base: effort is high or medium" \
        "$(case "$effort" in high|medium) echo ok ;; *) echo "invalid:$effort" ;; esac)" "ok"
      check "$base: preloads no skills" "$(grep -c '^skills:' "$f")" "0"
      ;;
    drafter-*)
      check "$base: carries the drafter toolset" "$(fm "$f" tools)" "$DRAFTER_TOOLS"
      check "$base: runs on sonnet" "$model" "sonnet"
      check "$base: effort is high" "$effort" "high"
      check "$base: preloads no skills" "$(grep -c '^skills:' "$f")" "0"
      ;;
    *)
      check "$base: name matches a known agent class" "unknown-class" "impl|judge|scout|drafter"
      ;;
  esac

  check "$base: does not set isolation" \
    "$(grep -c '^isolation:' "$f")" "0"
  check "$base: does not preload test-driven-development" \
    "$(grep -c 'test-driven-development' "$f")" "0"
  # grep -P is unavailable here; awk with an octal byte range is portable.
  check "$base: content is ASCII only" \
    "$(LC_ALL=C awk '/[\200-\377]/{n++} END{print n+0}' "$f")" "0"
done

# Every implementer, reserve tiers included, carries the end-of-turn rule: the
# controller reads a final message as the report.
for f in "$HERE"/../agents/impl-*.md; do
  check "$(basename "$f" .md): carries the end-of-turn rule" \
    "$(grep -c '^Your final message ends your turn' "$f")" "1"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
