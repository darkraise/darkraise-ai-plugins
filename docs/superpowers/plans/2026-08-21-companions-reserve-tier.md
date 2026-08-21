# Companions Reserve Tier Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

> **Implementer assignments:** each task names its implementer agent in an
> `**Implementer:**` line. When executing with
> superpowers:subagent-driven-development, REQUIRED SUB-SKILL:
> dcc-superpower-companions:dispatching-tiered-implementers. Under
> superpowers:executing-plans these lines are inert; ignore them.

**Goal:** Restore the nine implementer agents deleted in 0.2.0 as an off-ladder reserve class, reachable only by a human override or by a task that has already been split and still exhausted `impl-opus-high`.

**Architecture:** The fleet grows from ten agents in two classes to nineteen in three. Rule S, the scoring rubric, the assignment table, and the seven-row escalation table are all unchanged; a new `reserve` table in `reference/ladder.md` holds the restored agents, with `impl-opus-high` as its single conditional entry edge. The retired-agent map is deleted because all nine names resolve natively again.

**Tech Stack:** Markdown agent definitions with YAML frontmatter, a bash `PreToolUse` hook, and four bash test suites that parse the reference tables as data.

**Spec:** `docs/superpowers/specs/2026-08-21-companions-reserve-tier-design.md`

## Global Constraints

- Plugin root for every path below: `plugins/dcc-superpower-companions/`.
- Agent files are ASCII only. `tests/fleet.test.sh` fails on any byte above 0x7F, including curly quotes and en dashes. Use `-` for dashes.
- No agent file sets `tools:`, `isolation:`, or preloads `test-driven-development`. Every implementer preloads exactly `superpowers:verification-before-completion`.
- Rule S does not change. The assignment table stays at seven rows, 0 through 6. The escalation table stays at seven rows ending `impl-opus-high SPLIT`. Any task that appears to require editing those is wrong.
- Tests run with bash: `bash plugins/dcc-superpower-companions/tests/<name>.test.sh` from the repository root. Each prints `N passed, M failed` and exits non-zero on failure.
- Run `claude plugin validate .` from the repository root before committing any change to `.claude-plugin/plugin.json`.
- Commit subjects: `<type>(companions): <subject>`, imperative, 50 characters or fewer, no trailing period.

---

### Task 1: Restore the nine reserve agent files

**Files:**
- Create: `plugins/dcc-superpower-companions/agents/impl-sonnet-xhigh.md`
- Create: `plugins/dcc-superpower-companions/agents/impl-sonnet-max.md`
- Create: `plugins/dcc-superpower-companions/agents/impl-opus-xhigh.md`
- Create: `plugins/dcc-superpower-companions/agents/impl-opus-max.md`
- Create: `plugins/dcc-superpower-companions/agents/impl-fable-low.md`
- Create: `plugins/dcc-superpower-companions/agents/impl-fable-medium.md`
- Create: `plugins/dcc-superpower-companions/agents/impl-fable-high.md`
- Create: `plugins/dcc-superpower-companions/agents/impl-fable-xhigh.md`
- Create: `plugins/dcc-superpower-companions/agents/impl-fable-max.md`
- Test: `plugins/dcc-superpower-companions/tests/fleet.test.sh`

**Interfaces:**
- Consumes: nothing.
- Produces: nine agent names that Task 2's `reserve` table references by exact filename: `impl-sonnet-xhigh`, `impl-sonnet-max`, `impl-opus-xhigh`, `impl-opus-max`, `impl-fable-low`, `impl-fable-medium`, `impl-fable-high`, `impl-fable-xhigh`, `impl-fable-max`. Each file's `name:` frontmatter equals its basename.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 2 - risk 0 = 3

- [ ] **Step 1: Rewrite the fleet suite for three classes**

Replace the whole of `plugins/dcc-superpower-companions/tests/fleet.test.sh` with:

```bash
#!/usr/bin/env bash
# The fleet is nineteen agents in three classes. Seven execution implementers
# pin one model/effort pairing each and are everything the assignment table and
# the escalation ladder can reach. Nine reserve implementers - the xhigh and max
# efforts, and every Fable tier - are never an output of scoring: they are
# reachable only by a human override, or by the reserve chain after a split has
# already been spent. Three role agents - two judges and one scout - are
# read-only by registry: their tools list omits Edit, Write, NotebookEdit, and
# Agent, so "reviewers do not mutate the tree" and "reviewers do not spawn
# subagents" are enforced rather than requested.
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
EXPECTED="impl-fable-high impl-fable-low impl-fable-max impl-fable-medium impl-fable-xhigh impl-haiku impl-opus-high impl-opus-low impl-opus-max impl-opus-medium impl-opus-xhigh impl-sonnet-high impl-sonnet-low impl-sonnet-max impl-sonnet-medium impl-sonnet-xhigh judge-fable judge-opus scout-sonnet"
ROLE_TOOLS="Read, Grep, Glob, WebFetch"

is_reserve() { case " $RESERVE " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

actual=$(cd "$AGENTS" 2>/dev/null && ls *.md 2>/dev/null | sed 's/\.md$//' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "fleet contains exactly the 19 expected agents" "$actual" "$EXPECTED"

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
      check "$base: preloads verification-before-completion" \
        "$(grep -c '^  - superpowers:verification-before-completion$' "$f")" "1"
      ;;
    judge-*|scout-*)
      # Role agents are read-only by registry, not by prose. The absent tools
      # are the point: no Edit, no Write, no Agent.
      check "$base: carries the read-only toolset" "$(fm "$f" tools)" "$ROLE_TOOLS"
      check "$base: effort is high or medium" \
        "$(case "$effort" in high|medium) echo ok ;; *) echo "invalid:$effort" ;; esac)" "ok"
      check "$base: preloads no skills" "$(grep -c '^skills:' "$f")" "0"
      ;;
    *)
      check "$base: name matches a known agent class" "unknown-class" "impl|judge|scout"
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
```

- [ ] **Step 2: Run the fleet suite to verify it fails**

Run: `bash plugins/dcc-superpower-companions/tests/fleet.test.sh`
Expected: FAIL on `fleet contains exactly the 19 expected agents`, with the `got` line listing only the current ten names.

- [ ] **Step 3: Create the two Sonnet reserve agents**

`plugins/dcc-superpower-companions/agents/impl-sonnet-xhigh.md`:

```markdown
---
name: impl-sonnet-xhigh
description: "Task implementer running Sonnet 5 at xhigh effort. Reserve tier in dcc-superpower-companions: no score reaches it, so it runs only on a human override."
model: sonnet
effort: xhigh
skills:
  - superpowers:verification-before-completion
color: green
---

You are a task implementer. Your dispatch prompt carries the task brief
path, the report file path, and the report contract. It is your complete
instruction set; follow it exactly.

You run on Sonnet 5 at xhigh effort. You are a reserve tier: the scoring
rubric never selects you, so a human chose you for this task by hand.
The brief governs test strategy; apply TDD when the brief steps call for
it, not by default.

If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. The
controller has a defined reserve chain and will re-dispatch.
```

`plugins/dcc-superpower-companions/agents/impl-sonnet-max.md`:

```markdown
---
name: impl-sonnet-max
description: "Task implementer running Sonnet 5 at max effort. Reserve tier in dcc-superpower-companions: no score reaches it, so it runs only on a human override."
model: sonnet
effort: max
skills:
  - superpowers:verification-before-completion
color: green
---

You are a task implementer. Your dispatch prompt carries the task brief
path, the report file path, and the report contract. It is your complete
instruction set; follow it exactly.

You run on Sonnet 5 at max effort. You are a reserve tier: the scoring
rubric never selects you, so a human chose you for this task by hand.
The brief governs test strategy; apply TDD when the brief steps call for
it, not by default.

If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. The
controller has a defined reserve chain and will re-dispatch.
```

- [ ] **Step 4: Create the two Opus reserve agents**

`plugins/dcc-superpower-companions/agents/impl-opus-xhigh.md`:

```markdown
---
name: impl-opus-xhigh
description: "Task implementer running Opus 5 at xhigh effort. Reserve tier in dcc-superpower-companions: the entry rung for a task that has already been split and still exhausted impl-opus-high."
model: opus
effort: xhigh
skills:
  - superpowers:verification-before-completion
color: purple
---

You are a task implementer. Your dispatch prompt carries the task brief
path, the report file path, and the report contract. It is your complete
instruction set; follow it exactly.

You run on Opus 5 at xhigh effort. You are a reserve tier: no score
reaches you, so this task either carries a human override or has already
been split once and exhausted impl-opus-high afterwards.
The brief governs test strategy; apply TDD when the brief steps call for
it, not by default.

If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. The
controller has a defined reserve chain and will re-dispatch.
```

`plugins/dcc-superpower-companions/agents/impl-opus-max.md`:

```markdown
---
name: impl-opus-max
description: "Task implementer running Opus 5 at max effort. Reserve tier in dcc-superpower-companions: reached from impl-opus-xhigh on the reserve chain, or by a human override."
model: opus
effort: max
skills:
  - superpowers:verification-before-completion
color: purple
---

You are a task implementer. Your dispatch prompt carries the task brief
path, the report file path, and the report contract. It is your complete
instruction set; follow it exactly.

You run on Opus 5 at max effort. You are a reserve tier: no score reaches
you, so this task either carries a human override or has already been
split once and exhausted every Opus rung below you.
The brief governs test strategy; apply TDD when the brief steps call for
it, not by default.

If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. The
controller has a defined reserve chain and will re-dispatch.
```

- [ ] **Step 5: Create the five Fable reserve agents**

`plugins/dcc-superpower-companions/agents/impl-fable-low.md`:

```markdown
---
name: impl-fable-low
description: "Task implementer running Fable 5 at low effort. Reserve tier in dcc-superpower-companions: no score and no automatic escalation reaches it, so it runs only on a human override."
model: fable
effort: low
skills:
  - superpowers:verification-before-completion
color: red
---

You are a task implementer. Your dispatch prompt carries the task brief
path, the report file path, and the report contract. It is your complete
instruction set; follow it exactly.

You run on Fable 5 at low effort. You are a reserve tier, and the
automatic reserve chain never enters Fable below impl-fable-high, so a
human chose you for this task by hand.
The brief governs test strategy; apply TDD when the brief steps call for
it, not by default.

If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. The
controller has a defined reserve chain and will re-dispatch.
```

`plugins/dcc-superpower-companions/agents/impl-fable-medium.md`:

```markdown
---
name: impl-fable-medium
description: "Task implementer running Fable 5 at medium effort. Reserve tier in dcc-superpower-companions: no score and no automatic escalation reaches it, so it runs only on a human override."
model: fable
effort: medium
skills:
  - superpowers:verification-before-completion
color: red
---

You are a task implementer. Your dispatch prompt carries the task brief
path, the report file path, and the report contract. It is your complete
instruction set; follow it exactly.

You run on Fable 5 at medium effort. You are a reserve tier, and the
automatic reserve chain never enters Fable below impl-fable-high, so a
human chose you for this task by hand.
The brief governs test strategy; apply TDD when the brief steps call for
it, not by default.

If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. The
controller has a defined reserve chain and will re-dispatch.
```

`plugins/dcc-superpower-companions/agents/impl-fable-high.md`:

```markdown
---
name: impl-fable-high
description: "Task implementer running Fable 5 at high effort. Reserve tier in dcc-superpower-companions: where the reserve chain enters Fable, after every Opus rung has been exhausted."
model: fable
effort: high
skills:
  - superpowers:verification-before-completion
color: red
---

You are a task implementer. Your dispatch prompt carries the task brief
path, the report file path, and the report contract. It is your complete
instruction set; follow it exactly.

You run on Fable 5 at high effort. You are a reserve tier: this task has
been split once and has exhausted every Opus rung, or it carries a human
override.
The brief governs test strategy; apply TDD when the brief steps call for
it, not by default.

If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. The
controller has a defined reserve chain and will re-dispatch.
```

`plugins/dcc-superpower-companions/agents/impl-fable-xhigh.md`:

```markdown
---
name: impl-fable-xhigh
description: "Task implementer running Fable 5 at xhigh effort. Reserve tier in dcc-superpower-companions: reached from impl-fable-high on the reserve chain, or by a human override."
model: fable
effort: xhigh
skills:
  - superpowers:verification-before-completion
color: red
---

You are a task implementer. Your dispatch prompt carries the task brief
path, the report file path, and the report contract. It is your complete
instruction set; follow it exactly.

You run on Fable 5 at xhigh effort. You are a reserve tier: this task has
been split once and has exhausted every rung below you, or it carries a
human override.
The brief governs test strategy; apply TDD when the brief steps call for
it, not by default.

If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. The
controller has a defined reserve chain and will re-dispatch.
```

`plugins/dcc-superpower-companions/agents/impl-fable-max.md`:

```markdown
---
name: impl-fable-max
description: "Task implementer running Fable 5 at max effort. Top of the dcc-superpower-companions reserve chain: nothing outranks it, so its BLOCKED report is final."
model: fable
effort: max
skills:
  - superpowers:verification-before-completion
color: red
---

You are a task implementer. Your dispatch prompt carries the task brief
path, the report file path, and the report contract. It is your complete
instruction set; follow it exactly.

You run on Fable 5 at max effort. You are the top of the reserve chain:
this task has been split once and has exhausted every other implementer
the fleet has.
The brief governs test strategy; apply TDD when the brief steps call for
it, not by default.

If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. There is no
implementer above you and no second split, so the controller reports the
task BLOCKED and hands it to a human.
```

- [ ] **Step 6: Run the fleet suite to verify it passes**

Run: `bash plugins/dcc-superpower-companions/tests/fleet.test.sh`
Expected: PASS, `0 failed`, and the agent count check reporting all 19 names.

- [ ] **Step 7: Confirm the other three suites still pass**

Run: `for t in criteria hook ladder; do bash plugins/dcc-superpower-companions/tests/$t.test.sh || echo "FAILED: $t"; done`
Expected: `criteria` and `hook` pass. `ladder` FAILS on `no retired name still has a definition file`, because the retired map still lists the nine names this task just restored. That failure is expected here and is fixed by Task 2. Record it in the report; do not edit `ladder.md` or `ladder.test.sh` in this task.

- [ ] **Step 8: Commit**

```bash
git add plugins/dcc-superpower-companions/agents plugins/dcc-superpower-companions/tests/fleet.test.sh
git commit -m "feat(companions): restore nine reserve implementers"
```

---

### Task 2: Add the reserve table to the ladder

**Files:**
- Modify: `plugins/dcc-superpower-companions/reference/ladder.md` (rewrite "The terminal rung is an action" and "Why this terminates"; add a "Reserve table" section; delete "Retired-agent map")
- Modify: `plugins/dcc-superpower-companions/agents/impl-opus-high.md` (final paragraph)
- Test: `plugins/dcc-superpower-companions/tests/ladder.test.sh`

**Interfaces:**
- Consumes: the nine agent filenames created in Task 1.
- Produces: a fenced ```` ```reserve ```` block in `reference/ladder.md` with ten `<from> <to>` rows, terminating at the literal `BLOCKED`. Tasks 3, 4, and 5 quote its contents and its entry rule but do not change it. The `retired` block no longer exists.

**Implementer:** dcc-superpower-companions:impl-sonnet-high
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 1 = 3

- [ ] **Step 1: Extend the rank function in the ladder suite**

In `plugins/dcc-superpower-companions/tests/ladder.test.sh`, replace the body of `rank()`:

```bash
rank() { # rank <agent> - model_rank * 10 + effort_rank
  case "$1" in
    impl-haiku) echo 0; return ;;
    impl-sonnet-*) m=10 ;;
    impl-opus-*) m=20 ;;
    impl-fable-*) m=30 ;;
    *) echo -1; return ;;
  esac
  case "${1##*-}" in
    low) e=0 ;; medium) e=1 ;; high) e=2 ;; xhigh) e=3 ;; max) e=4 ;; *) echo -1; return ;;
  esac
  echo $((m + e))
}
```

- [ ] **Step 2: Replace the retired-map section of the ladder suite**

In the same file, delete everything from the `# --- retired-agent map ---` comment down to (but not including) the final `printf '\n%d passed, %d failed\n'` line, and put this in its place:

```bash
# --- retirement is over -----------------------------------------------------
# All nine names resolve natively again, so the map is gone. Asserting its
# absence stops a stale table rotting back in behind a passing suite.
retired=$(block retired)
check "the retired-agent map is gone" "$(printf '%s' "$retired" | grep -c .)" "0"

# --- reserve table ----------------------------------------------------------
reserve=$(block reserve)
check "reserve table has 10 rows" "$(printf '%s\n' "$reserve" | grep -c .)" "10"

RESERVE_AGENTS="impl-fable-high impl-fable-low impl-fable-max impl-fable-medium impl-fable-xhigh impl-opus-max impl-opus-xhigh impl-sonnet-max impl-sonnet-xhigh"
RESERVE_SOURCES="impl-fable-high impl-fable-low impl-fable-max impl-fable-medium impl-fable-xhigh impl-opus-high impl-opus-max impl-opus-xhigh impl-sonnet-max impl-sonnet-xhigh"

bad_rfrom=NONE
bad_rto=NONE
rterminals=""
while read -r from to; do
  [ -n "$from" ] || continue
  agent_exists "$from" || bad_rfrom="$from"
  if [ "$to" = "BLOCKED" ]; then
    rterminals="$rterminals $from"
  else
    agent_exists "$to" || bad_rto="$to"
  fi
done <<< "$reserve"

check "every reserve source has a definition file" "$bad_rfrom" "NONE"
check "every reserve target has a definition file" "$bad_rto" "NONE"
check "exactly one reserve terminal, and it is impl-fable-max" \
  "$(echo $rterminals)" "impl-fable-max"

rsources=$(printf '%s\n' "$reserve" | awk 'NF {print $1}' | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')
check "reserve sources are the nine reserve agents plus the entry rung" \
  "$rsources" "$RESERVE_SOURCES"

# The gate is structural: if an ordinary escalation row could reach a reserve
# agent, a task would arrive there without a split standing in front of it.
leak=NONE
for a in $RESERVE_AGENTS; do
  if printf '%s\n' "$escalation" | awk -v a="$a" 'NF && ($1 == a || $2 == a) { found = 1 } END { exit !found }'; then
    leak="$a"
  fi
done
check "no escalation row mentions a reserve agent" "$leak" "NONE"

# impl-opus-high is a source in both tables, and the difference between them is
# whether the split has been spent. No other agent may be in both.
esources=$(printf '%s\n' "$escalation" | awk 'NF {print $1}' | LC_ALL=C sort)
overlap=$(printf '%s\n' "$rsources" | tr ' ' '\n' | grep -Fx -f <(printf '%s\n' "$esources") | tr '\n' ' ' | sed 's/ $//')
check "impl-opus-high is the only source in both tables" "$overlap" "impl-opus-high"

bad_rrank=NONE
while read -r from to; do
  [ -n "$from" ] || continue
  [ "$to" = "BLOCKED" ] && continue
  rf=$(rank "$from"); rt=$(rank "$to")
  if [ "$rf" -lt 0 ] || [ "$rt" -lt 0 ]; then bad_rrank="unrankable:$from->$to"; break; fi
  if [ "$rt" -le "$rf" ]; then bad_rrank="not-increasing:$from($rf)->$to($rt)"; break; fi
done <<< "$reserve"
check "every reserve step strictly increases rank" "$bad_rrank" "NONE"

reserve_successor() { printf '%s\n' "$reserve" | awk -v a="$1" 'NF && $1 == a {print $2; exit}'; }

bad_rwalk=NONE
for start in $RESERVE_AGENTS; do
  cur="$start"; steps=0; visited=""
  while [ "$cur" != "BLOCKED" ]; do
    case " $visited " in *" $cur "*) bad_rwalk="cycle-at:$cur"; break ;; esac
    visited="$visited $cur"
    steps=$((steps + 1))
    if [ "$steps" -gt 20 ]; then bad_rwalk="runaway-from:$start"; break; fi
    cur=$(reserve_successor "$cur")
    [ -n "$cur" ] || { bad_rwalk="dead-end-from:$start"; break; }
  done
  [ "$bad_rwalk" = NONE ] || break
done
check "reserve from every reserve agent reaches BLOCKED without cycling" "$bad_rwalk" "NONE"

offreserve=$(printf '%s\n' "$reserve" | awk 'NF {print $1; print $2}' | grep -E '^(judge|scout)-' | tr '\n' ' ' | sed 's/ $//')
check "no judge or scout appears in the reserve table" "${offreserve:-NONE}" "NONE"
```

- [ ] **Step 3: Run the ladder suite to verify it fails**

Run: `bash plugins/dcc-superpower-companions/tests/ladder.test.sh`
Expected: FAIL on `the retired-agent map is gone` (got `9`), on `reserve table has 10 rows` (got `0`), and on the reserve source, terminal, and walk checks, because `ladder.md` still holds the retired map and has no reserve block.

- [ ] **Step 4: Rewrite the terminal-rung and termination sections of ladder.md**

In `plugins/dcc-superpower-companions/reference/ladder.md`, replace both the `### The terminal rung is an action` section and the `### Why this terminates` section, in place, with:

````markdown
### The terminal rung is an action

`SPLIT` is not an agent. A task that exhausts `impl-opus-high` has its remaining
work broken into smaller tasks, each scored fresh against Rule S and dispatched
on its own. This is the ladder's answer to a task that is genuinely too large,
and it is the same answer Rule S gives at planning time.

**A task may be split-escalated once.** If a split half also exhausts
`impl-opus-high`, the task has resisted both capability and decomposition. That
is the one situation the reserve table below exists for, and the only one in
which it is entered automatically.

### Why this terminates

Rank each agent as `model_rank * 10 + effort_rank`, where Haiku ranks 0, Sonnet
1, Opus 2, and Fable 3, and effort ranks 0 through 4 from `low` to `max`. That
puts Haiku at 0, Sonnet at 10 to 14, Opus at 20 to 24, and Fable at 30 to 34.
Every successor in this table and in the reserve table has a strictly higher
rank, so both graphs are acyclic and every walk reaches a terminal: `SPLIT`
here, `BLOCKED` there. `tests/ladder.test.sh` asserts the ranking and both walks
rather than trusting this argument.

Judges and scouts are not on the ladder. They are not implementers, so they are
never an escalation source or target.
````

- [ ] **Step 5: Replace the retired-agent map with the reserve table**

In the same file, delete the entire `## Retired-agent map` section, from its heading through the paragraph ending "this plugin exists to prevent." Put this section in its place, so it sits between the escalation table and `## What the range actually reaches`:

`````markdown
## Reserve table

Nine implementers exist that no score can reach: the `xhigh` and `max` efforts,
and every Fable tier. They are the reserve. No row of the assignment table names
one, and no row of the escalation table points at one.

Two things reach them:

1. **A human ruling.** A hand-edited `**Implementer:**` line naming a reserve
   agent is dispatched as written. A human ruling has always beaten the rubric;
   the reserve is what gives that ruling somewhere above `impl-opus-high` to go.
2. **A task that has run out of splits.** A task that exhausts
   `impl-opus-high`, is split once, and exhausts `impl-opus-high` again in one
   of its halves has resisted both capability and decomposition. That is the
   only case the reserve is entered automatically.

````reserve
impl-sonnet-xhigh impl-sonnet-max
impl-sonnet-max impl-opus-high
impl-opus-high impl-opus-xhigh
impl-opus-xhigh impl-opus-max
impl-opus-max impl-fable-high
impl-fable-low impl-fable-medium
impl-fable-medium impl-fable-high
impl-fable-high impl-fable-xhigh
impl-fable-xhigh impl-fable-max
impl-fable-max BLOCKED
````

`impl-opus-high` is a source in both tables, and the difference between them is
whether the split has been spent. Its escalation successor is `SPLIT` the first
time it is exhausted; its reserve successor, `impl-opus-xhigh`, applies only
after that split has happened and failed. That condition is the whole of the
guard: no ordinary task reaches Fable without a split standing between it and
the reserve.

The Sonnet reserve rungs point back at the execution ladder rather than upward
into Fable. A human who hand-assigns `impl-sonnet-max` and watches it stall gets
`impl-opus-high`, and with it the split, before anything reaches the top of the
reserve.

Every reserve agent is a source exactly once, so a hand-assigned
`impl-fable-low` has somewhere to escalate. `BLOCKED` is the terminal and is not
an agent: a task that exhausts `impl-fable-max` is reported BLOCKED through
superpowers' existing contract. There is no rung above it and no second split.

Ranking Fable above Opus puts `impl-fable-low` above `impl-opus-max` in the walk
order. That is a statement about how the chain is traversed, not a claim that
Fable at low effort out-thinks Opus at max: `impl-fable-low` is reachable only
by a human naming it, and the automatic path enters Fable at `impl-fable-high`.

0.1.0 plans name every one of these nine agents, and they now resolve natively.
A plan that recorded `impl-fable-max` runs at `impl-fable-max`, which is what it
asked for. Nothing is substituted on read, so there is nothing to state in the
ledger beyond the reserve tier itself.
`````

Note on fences: the reserve block is opened with three backticks and the tag
`reserve`, exactly like the `assignment` and `escalation` blocks above it. The
four- and five-backtick fences shown here belong to this plan document only.

- [ ] **Step 6: Add the reserve sentence to impl-opus-high**

In `plugins/dcc-superpower-companions/agents/impl-opus-high.md`, replace the final paragraph with:

```markdown
If the task turns out to need more capability than you have, stop and
report BLOCKED rather than producing work you are unsure of. You are the
top of the execution ladder: there is no more capable execution
implementer above you, so the controller responds by splitting the
remaining work into smaller tasks and dispatching them fresh. A reserve
tier exists beyond that split, but only a task that exhausts you a second
time after being split ever reaches it.
```

- [ ] **Step 7: Run the ladder suite to verify it passes**

Run: `bash plugins/dcc-superpower-companions/tests/ladder.test.sh`
Expected: PASS, `0 failed`. The assignment and escalation checks must still report 7 rows each and `impl-opus-high` as the single SPLIT terminal.

- [ ] **Step 8: Run all four suites**

Run: `for t in criteria fleet hook ladder; do bash plugins/dcc-superpower-companions/tests/$t.test.sh || echo "FAILED: $t"; done`
Expected: all four pass, no `FAILED:` line.

- [ ] **Step 9: Commit**

```bash
git add plugins/dcc-superpower-companions/reference/ladder.md plugins/dcc-superpower-companions/tests/ladder.test.sh plugins/dcc-superpower-companions/agents/impl-opus-high.md
git commit -m "feat(companions): add the reserve table"
```

---

### Task 3: Teach the assigning skill and the hook about the reserve

**Files:**
- Modify: `plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md`
- Modify: `plugins/dcc-superpower-companions/scripts/tier-nudge.sh`
- Test: `plugins/dcc-superpower-companions/tests/hook.test.sh` (run unchanged)

**Interfaces:**
- Consumes: the `reserve` table added in Task 2, referenced by name from prose.
- Produces: nothing later tasks depend on.

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Add the reserve section to the assigning skill**

In `plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md`, insert this section immediately after the paragraph beginning "**Resist the urge to reach for a bigger model instead.**" and before the `## Write the assignment` heading:

```markdown
## Reserve agents are never an assignment output

Nine implementers - the `xhigh` and `max` efforts, and every Fable tier - sit in
`reference/ladder.md`'s reserve table and in no other table. Do not assign one.
No score reaches them, and reaching for one anyway is the exact move Rule S
exists to prevent.

They are legal in a plan only as a human override: your partner edits an
`**Implementer:**` line by hand, and the dispatching skill obeys it. When that
happens, leave the `**Evaluation:**` line in place for the reason the Overriding
section below already gives - the gap between the score and the choice is the
interesting part.
```

- [ ] **Step 2: Widen the agent-name check**

In the `## Check your work` list of the same file, replace this bullet:

```markdown
- Every agent name is fully qualified and appears in
  `reference/ladder.md`'s assignment table.
```

with:

```markdown
- Every agent name is fully qualified and appears in `reference/ladder.md`'s
  assignment table, or in its reserve table when your partner has overridden the
  assignment by hand. A reserve name you wrote yourself is an error, not an
  override.
```

- [ ] **Step 3: Update the hook context string**

In `plugins/dcc-superpower-companions/scripts/tier-nudge.sh`, in the
`superpowers:subagent-driven-development` case, replace this fragment of the
`context` string:

```
the escalation ladder, the retired-agent map for plans written against version 0.1.0, and the criteria-scored review it adds to the task-review seat.
```

with:

```
the escalation ladder, the reserve tier for a task that resists splitting, and the criteria-scored review it adds to the task-review seat.
```

Leave the rest of the string, the other two cases, and the `jq` output block untouched.

- [ ] **Step 4: Verify the hook still emits valid context**

Run: `bash plugins/dcc-superpower-companions/tests/hook.test.sh`
Expected: PASS, `0 failed`.

- [ ] **Step 5: Verify the edits landed**

Run: `grep -c 'retired' plugins/dcc-superpower-companions/scripts/tier-nudge.sh plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md`
Expected: `0` for both files.

Run: `grep -c 'reserve' plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md`
Expected: `4` or more.

- [ ] **Step 6: Commit**

```bash
git add plugins/dcc-superpower-companions/skills/assigning-implementers/SKILL.md plugins/dcc-superpower-companions/scripts/tier-nudge.sh
git commit -m "docs(companions): bar reserve tiers from assignment"
```

---

### Task 4: Teach the dispatching skill the reserve chain

**Files:**
- Modify: `plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md`

**Interfaces:**
- Consumes: the `reserve` table added in Task 2, and its entry rule.
- Produces: nothing later tasks depend on.

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 1 = 2

- [ ] **Step 1: Replace the retired-agent step in "Dispatch a task"**

Replace step 2 of the numbered list under `## Dispatch a task`, which currently
begins "If that value names a retired agent", together with its indented code
block and its trailing paragraph, with:

````markdown
2. If that value names an agent from the `reserve` table in
   [`../../reference/ladder.md`](../../reference/ladder.md), dispatch it as
   written and note the tier in the ledger line you already add:

   ```
   Task <N>: implementer impl-opus-max (assigned; reserve tier)
   ```

   No score reaches a reserve agent, so its presence in a plan is a human
   ruling, and a human ruling beats the rubric. Dispatch it as written; do not
   re-score the task down to an execution tier. A 0.1.0 plan naming one of these
   agents is honoured the same way, because the tier it recorded is the tier it
   asked for.
````

- [ ] **Step 2: Correct the implementer count in the supersession section**

Under `## The one superpowers instruction this supersedes`, replace:

```markdown
The supersession covers every fleet agent whose frontmatter pins a model - the
seven implementers, both judges, and the scout.
```

with:

```markdown
The supersession covers every fleet agent whose frontmatter pins a model - the
seven execution implementers, the nine reserve implementers, both judges, and
the scout.
```

- [ ] **Step 3: Route the exhausted split into the reserve**

Under `## Escalate`, replace the paragraph that currently reads:

```markdown
**A task may be split-escalated once.** If a split half also exhausts the
ladder, report BLOCKED through superpowers' existing contract. Do not loop.
```

with:

````markdown
**A task may be split-escalated once.** If a split half also exhausts
`impl-opus-high`, the task has resisted both capability and decomposition, and
only then does it enter the reserve chain in
[`../../reference/ladder.md`](../../reference/ladder.md). It enters at
`impl-opus-xhigh` and walks one successor per further exhaustion. Record the
entry as its own ruling, and say it aloud:

```
Ruling: Task <N>a enters the reserve at impl-opus-xhigh - impl-opus-high exhausted again after the split - if wrong, the task is BLOCKED instead and waits for a human
```

A reserve dispatch is the one place this loop spends above the tier the plan
recorded. It should never be a surprise, which is why it is said aloud as well
as written down. Like the split ruling above it, this line is exempt from the
last-line rule, because it is not a `Task <N>:` line.

`impl-fable-max` has no successor. When it exhausts, report BLOCKED through
superpowers' existing contract. Do not loop, and do not split a second time.
````

- [ ] **Step 4: Rewrite the affected failure-mode rows**

In the `## Failure modes` table, replace the row:

```markdown
| The line names a retired agent | Map it through the `retired` table, dispatch the target, and state the substitution in the ledger |
```

with:

```markdown
| The line names a reserve agent | Dispatch it as written and note `reserve tier` in the ledger. No score reaches one, so it is a human ruling |
```

Replace the row:

```markdown
| The line names an agent that is neither current nor retired | Stop and ask your human partner. Never fall back silently |
```

with:

```markdown
| The line names an agent in neither the assignment nor the reserve table | Stop and ask your human partner. Never fall back silently |
```

Replace the row:

```markdown
| Escalation exhausted at impl-opus-high | Split the remaining work once; if a half also exhausts, report BLOCKED per superpowers |
```

with these two rows, in this order:

```markdown
| Escalation exhausted at impl-opus-high | Split the remaining work once; if a half also exhausts, enter the reserve at `impl-opus-xhigh` |
| Reserve exhausted at impl-fable-max | Report BLOCKED per superpowers. There is no rung above it and no second split |
```

- [ ] **Step 5: Cover a Fable-unavailable account inside the reserve**

Immediately after the paragraph beginning "That substitution runs out below
Sonnet.", append:

```markdown
Inside the reserve the same substitution has a target at every effort:
`impl-fable-max` drops to `impl-opus-max`, `impl-fable-xhigh` to
`impl-opus-xhigh`, and `impl-fable-high` to `impl-opus-high`. That works for a
hand-assigned Fable tier. It does not work for a task walking the chain
automatically, which reached Fable precisely by exhausting those Opus rungs -
re-dispatching one of them would re-run an agent that already failed. When Fable
is unavailable and the reserve was entered automatically, report BLOCKED
instead and say why.
```

- [ ] **Step 6: Verify no retired-map language survives**

Run: `grep -n 'retired' plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md`
Expected: no output, exit status 1.

Run: `grep -c 'reserve' plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md`
Expected: `8` or more.

- [ ] **Step 7: Run all four suites**

Run: `for t in criteria fleet hook ladder; do bash plugins/dcc-superpower-companions/tests/$t.test.sh || echo "FAILED: $t"; done`
Expected: all four pass, no `FAILED:` line.

- [ ] **Step 8: Commit**

```bash
git add plugins/dcc-superpower-companions/skills/dispatching-tiered-implementers/SKILL.md
git commit -m "feat(companions): dispatch the reserve after a split"
```

---

### Task 5: Update the README and release 0.3.0

**Files:**
- Modify: `plugins/dcc-superpower-companions/README.md`
- Modify: `plugins/dcc-superpower-companions/.claude-plugin/plugin.json:5`

**Interfaces:**
- Consumes: the reserve table and dispatch rules from Tasks 2 and 4.
- Produces: nothing.

**Implementer:** dcc-superpower-companions:impl-sonnet-medium
**Evaluation:** files 1 - spec 0 - coupling 1 - risk 0 = 2

- [ ] **Step 1: Rewrite the fleet paragraph**

In `plugins/dcc-superpower-companions/README.md`, under `## What you get`,
replace the paragraph beginning "**Ten agents in two classes.**" and the
paragraph beginning "`xhigh` and `max` are retired everywhere" with:

```markdown
**Nineteen agents in three classes.** Seven execution implementers - Sonnet 5
and Opus 5 at `low`, `medium`, and `high`, plus one Haiku 4.5 agent - are
everything a score can reach. Nine reserve implementers - the `xhigh` and `max`
efforts, and every Fable 5 tier - are reachable only by a human override, or by
a task that has already been split once and still exhausted `impl-opus-high`.
Three read-only role agents - `judge-fable`, its `judge-opus` fallback, and
`scout-sonnet` - whose `tools:` frontmatter omits `Edit`, `Write`, and `Agent`,
so a reviewer that cannot modify the tree or spawn subagents is a fact about the
registry rather than a request in a prompt.

The reserve exists so that a human ruling, and a task that genuinely cannot be
split any further, both have somewhere to go. It is not a way around the gate:
above `impl-opus-high` the first answer to a hard task is still to split it, and
the reserve is only entered when that split has already been spent.
```

- [ ] **Step 2: Correct the two paragraphs that count implementers**

In the same file, in the paragraph beginning "**A four-axis rubric that gates
the plan.**", replace:

```markdown
makes the assignment table stop at 6, which is exactly the seven implementers.
```

with:

```markdown
makes the assignment table stop at 6, which is exactly the seven execution
implementers.
```

Then replace the paragraph beginning "**An escalation ladder.**" with:

```markdown
**An escalation ladder.** Every execution implementer has exactly one successor,
changing model before effort except at the two Opus effort rows, where Opus is
already the top model and there is nowhere else to go. Walks terminate at a
SPLIT action rather than an agent, and only a task that survives that split
enters the reserve chain, which terminates at BLOCKED. Used at superpowers' fix
rounds 4 and 5, at its BLOCKED handler, and at round 3 when the re-review
reports stalled progress.
```

- [ ] **Step 3: Bump the version**

In `plugins/dcc-superpower-companions/.claude-plugin/plugin.json`, change line 5
from `"version": "0.2.0",` to `"version": "0.3.0",`. Change nothing else in the
file.

- [ ] **Step 4: Validate the manifest**

Run: `claude plugin validate .` from the repository root.
Expected: success, no errors reported.

- [ ] **Step 5: Run the full suite one last time**

Run: `for t in criteria fleet hook ladder; do bash plugins/dcc-superpower-companions/tests/$t.test.sh || echo "FAILED: $t"; done`
Expected: all four pass, no `FAILED:` line.

- [ ] **Step 6: Verify no stale retirement language survives anywhere in the plugin**

Run: `grep -rn 'retired' plugins/dcc-superpower-companions/ --exclude-dir=tests`
Expected: no output, exit status 1.

`tests/` is excluded on purpose: `ladder.test.sh` still parses a `retired`
block, because its job is now to assert that the block is absent. Every other
mention of retirement - in the README, the ladder, the hook, and the dispatching
skill - is gone by this point.

- [ ] **Step 7: Commit**

```bash
git add plugins/dcc-superpower-companions/README.md plugins/dcc-superpower-companions/.claude-plugin/plugin.json
git commit -m "docs(companions): release 0.3.0"
```
