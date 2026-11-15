#!/usr/bin/env bash
# The fleet is four agents in two classes. impl-sonnet-high runs the Acceptance
# QA pass; it never carries Agent, Skill or the other session-only tools. Three
# judges never carry Edit, NotebookEdit, Bash or Agent, so "reviewers do not
# spawn subagents" is enforced rather than requested. A judge carries Write for
# one file, the report its prompt names; task-step verdict checks that no
# tracked file changed during the review.
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

EXPECTED="impl-sonnet-high judge-fable judge-opus judge-sonnet-high"
JUDGE_TOOLS="Read, Grep, Glob, Write"
IMPL_DISALLOWED="Agent, Skill, Workflow, Artifact, ArtifactComments, ArtifactData, AskUserQuestion, EnterPlanMode, ExitPlanMode, EnterWorktree, ExitWorktree, CronCreate, CronDelete, CronList, RemoteTrigger, ScheduleWakeup, SendMessage, ListAgents, SendUserFile, PushNotification, DesignSync, ReportFindings, SendFeedback, ReadNotifications"

actual=$(cd "$AGENTS" 2>/dev/null && ls *.md 2>/dev/null | sed 's/\.md$//' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "fleet contains exactly the 4 expected agents" "$actual" "$EXPECTED"

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
      check "$base: model matches the name segment" "$model" "$(printf '%s' "$base" | cut -d- -f2)"
      check "$base: effort matches the name suffix" "$effort" "${base##*-}"
      check "$base: does not set tools" "$(grep -c '^tools:' "$f")" "0"
      check "$base: drops the session-only tools" "$(fm "$f" disallowedTools)" "$IMPL_DISALLOWED"
      check "$base: preloads verification-before-completion" \
        "$(grep -c '^  - dforge:verification-before-completion$' "$f")" "1"
      ;;
    judge-*)
      # The absent tools are the point: no Edit, no Bash, no Agent. A judge's
      # one Write is its report file.
      check "$base: carries the judge toolset" "$(fm "$f" tools)" "$JUDGE_TOOLS"
      check "$base: effort is high or medium" \
        "$(case "$effort" in high|medium) echo ok ;; *) echo "invalid:$effort" ;; esac)" "ok"
      check "$base: preloads no skills" "$(grep -c '^skills:' "$f")" "0"
      ;;
    *)
      check "$base: name matches a known agent class" "unknown-class" "impl|judge"
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
