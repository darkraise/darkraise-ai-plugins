#!/usr/bin/env bash
# Acceptance tests for the reviewer-only externals spec
# (docs/dforge/specs/2026-11-12-reviewer-only-externals-design.md), statements
# A1-A11 and A15-A18. Written from the statements' text and run through the
# public surface: the panel and the agy runner as commands, the gates, the
# review routing, task-step, plan-lint, dforge-config and the release script. Real gates and real runners run against the stub agy
# (fixtures/stub-agy) and a copy of the stub Codex plugin; the host's own agy
# is kept out of PATH, so nothing here makes a billed call.
# Usage:
#   bash reviewer-only-externals.acceptance.test.sh            run every test
#   bash reviewer-only-externals.acceptance.test.sh A5 A9      run the named tests only
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN/../.." && pwd)"
S="$PLUGIN/scripts"
PANEL="$S/run-review-panel"
AGYRUN="$S/run-agy-review.sh"
ROUTE="$S/review-route"
STEP="$S/task-step"
BRIEF="$S/task-brief"
LINT="$S/plan-lint"
CONFIG="$S/dforge-config"
FIXTURE_AGY="$HERE/fixtures/stub-agy/agy"

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%.700s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
absent() { # absent <name> <haystack> <ERE>
  if grep -qE -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected match: [%s]\n       in: [%.700s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
skip() { printf 'skip - %s\n' "$1"; }

WANT=("$@")
want() { # want <A-id> - true when no filter was given or the id is listed
  local w
  [ ${#WANT[@]} -eq 0 ] && return 0
  for w in "${WANT[@]}"; do [ "$w" = "$1" ] && return 0; done
  return 1
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi

# --- environment: a private home, config dir, session dirs and policy copy ---
unset CLAUDE_CONFIG_DIR CODEX_HOME AR_SESSION DFORGE_BUDGET DR_SUPERPOWERS_BUDGET GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
export HOME="$TMP/home" GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME/.dforge"
export CLAUDE_CONFIG_DIR="$TMP/config" CLAUDE_PROJECT_DIR=
export DR_CODEX_SESSION_DIR="$TMP/codex-sessions" DR_AGY_SESSION_DIR="$TMP/agy-sessions" CLAUDE_CODE_SESSION_ID=reviewer-only-externals-qa
export STUB_EVENT_LOG="$TMP/codex.events" STUB_AGY_ARGS_LOG="$TMP/agy.args" STUB_CALL_FILE="$TMP/codex.calls"
export STUB_FINAL_MESSAGE='{"spec":18,"scope":18,"verification":18,"quality":18,"spec_verdict":"compliant","task_quality":"approved","findings":[],"cannot_verify":[]}'
export STUB_AGY_MODE=review

# A trusted copy of the shipped agy policy; the shipped file is never edited.
TRUSTED="$TMP/agy-policy-trusted.json"
jq '.trust.review = "pass"' "$PLUGIN/reference/agy-policy.json" > "$TRUSTED"
export DR_AGY_POLICY="$TRUSTED"
UNTRUSTED="$TMP/agy-policy-untrusted.json"
jq '.trust.review = "pending"' "$PLUGIN/reference/agy-policy.json" > "$UNTRUSTED"

# A PATH holding every tool the scripts use and no agy: this host has a real
# agy, which must never be reached. The stub agy goes in front of this PATH.
SEAL="$TMP/seal"
mkdir -p "$SEAL"
while IFS= read -r dir; do
  for tool in "$dir"/*; do
    name=${tool##*/}
    case "$name" in agy|agy.exe) continue ;; esac
    [ -e "$SEAL/$name" ] || ln -s "$tool" "$SEAL/$name" 2>/dev/null
  done
done < <(for tool in bash node jq git cat date sleep timeout setsid; do dirname "$(type -P "$tool")"; done | sort -u)

# The agy on PATH is a thin wrapper over the stub: for a print call it can log
# start and end times and wait, so a test can see two reviewers overlap.
AGYBIN="$TMP/agybin"
mkdir -p "$AGYBIN"
cat > "$AGYBIN/agy" <<EOF
#!/usr/bin/env bash
ms() { local n; n=\$(date +%s%N); echo \$((n / 1000000)); }
case " \$* " in
  *" -p "*)
    if [ -n "\${TS_LOG:-}" ]; then
      printf 'agy start %s\n' "\$(ms)" >> "\$TS_LOG"
      sleep "\${AGY_DELAY:-0}"
      "$FIXTURE_AGY" "\$@"; rc=\$?
      printf 'agy end %s\n' "\$(ms)" >> "\$TS_LOG"
      exit \$rc
    fi ;;
esac
exec "$FIXTURE_AGY" "\$@"
EOF
chmod +x "$AGYBIN/agy"
export PATH="$AGYBIN:$SEAL"
NOAGY_PATH="$SEAL"

# Node cannot run a bash-script stub on Windows, which the agy gate's sign-in
# probe needs.
SPAWNABLE=$(node -e 'const r = require("child_process").spawnSync(process.argv[1], ["--version"], { encoding: "utf8" }); console.log(r.status === 0 ? "yes" : "no")' "$AGYBIN/agy" 2>/dev/null | tr -d '\r')
needs_spawn() { # needs_spawn <A-id>
  [ "$SPAWNABLE" = yes ] && return 0
  skip "$1: Node cannot start the stub agy on this host"
  return 1
}

# A copy of the stub Codex plugin whose app-server client answers the gate's
# login and quota reads (STUB_GATE_MODE), and whose turns can wait
# (TURN_DELAY_MS) and log their start time (TS_LOG).
PLUG="$TMP/codex-plugin"
cp -r "$HERE/fixtures/stub-codex-plugin" "$PLUG"
mkdir -p "$PLUG/.claude-plugin"
printf '{"name":"codex","version":"1.0.3"}\n' > "$PLUG/.claude-plugin/plugin.json"
cat > "$PLUG/scripts/lib/app-server.mjs" <<'EOF'
import fs from "node:fs";
const log = (line) => process.env.STUB_EVENT_LOG && fs.appendFileSync(process.env.STUB_EVENT_LOG, `${line}\n`);
export class CodexAppServerClient {
  static async connect() { return new CodexAppServerClient(); }
  async request(method) {
    log(`request ${method}`);
    const mode = process.env.STUB_GATE_MODE || "ok";
    if (method === "account/read") {
      if (mode === "logged-out") return { account: null, requiresOpenaiAuth: true };
      return { account: { type: "chatgpt", email: "a@b.c" }, requiresOpenaiAuth: true };
    }
    if (mode === "quota") return { ordinaryUsageAllowed: false, rateLimits: { primary: { usedPercent: 100, resetsAt: 1789898607 } } };
    return { ordinaryUsageAllowed: true, rateLimits: { primary: { usedPercent: 12, resetsAt: 1789898607 } } };
  }
  async close() {}
}
EOF
cat > "$TMP/inject.txt" <<'EOF'
  if (process.env.TS_LOG) {
    fs.appendFileSync(process.env.TS_LOG, `codex start ${Date.now()}\n`);
    await new Promise((resolve) => setTimeout(resolve, Number(process.env.TURN_DELAY_MS || 0)));
  }
EOF
awk -v inj="$TMP/inject.txt" '{ print } /^async function turn\(cwd, options, label\) \{$/ { while ((getline line < inj) > 0) print line }' \
  "$HERE/fixtures/stub-codex-plugin/scripts/lib/codex.mjs" > "$PLUG/scripts/lib/codex.mjs"
mkdir -p "$CLAUDE_CONFIG_DIR/plugins"
printf '{"enabledPlugins":{"codex@openai-codex":true}}\n' > "$CLAUDE_CONFIG_DIR/settings.json"
jq -nc --arg p "$PLUG" '{version:2,plugins:{"codex@openai-codex":[{scope:"user",installPath:$p,version:"1.0.3"}]}}' \
  > "$CLAUDE_CONFIG_DIR/plugins/installed_plugins.json"

# The repository the reviewers are pointed at.
WORK="$TMP/work"
mkdir -p "$WORK"
git -C "$WORK" init -q -b main
git -C "$WORK" config user.name Darkraise
git -C "$WORK" config user.email quangtc94@gmail.com
printf 'original\n' > "$WORK/tracked.txt"
git -C "$WORK" add -A
git -C "$WORK" commit -q -m base
printf '# review the change\n' > "$TMP/prompt.md"
OUT="$TMP/out"

settings() { # settings <codexReview> <agyReview>; "-" leaves a key unset
  jq -nc --arg c "$1" --arg a "$2" '({} | if $c != "-" then .codexReview = ($c == "true") else . end | if $a != "-" then .agyReview = ($a == "true") else . end)' > "$HOME/.dforge/config.json"
}
fresh() { # fresh - clean sessions, logs and the work repository
  rm -rf "$DR_CODEX_SESSION_DIR" "$DR_AGY_SESSION_DIR" "$OUT" "$STUB_EVENT_LOG" "$STUB_AGY_ARGS_LOG" "$STUB_CALL_FILE" "$TMP/ts.log"
  git -C "$WORK" reset -q --hard; git -C "$WORK" clean -qfd; git -C "$WORK" stash clear
  git -C "$WORK" checkout -q main
}
panel() { # panel <tier> [extra args]; sets out and rc. Other STUB_* variables ride in the environment.
  local tier=$1; shift
  rm -rf "$OUT"
  out=$(cd "$WORK" && timeout 300 bash "$PANEL" --kind task --tier "$tier" --cwd "$WORK" --out-dir "$OUT" --prompt "$TMP/prompt.md" "$@" 2>"$TMP/err"); rc=$?
  out=${out//$'\r'/}
}
sline() { grep -m1 "^$1-judge " <<<"$out"; } # sline <id>: that family's status line
sval() { sed -n "s/.* $2=\\([^ ]*\\).*/\\1/p" <<<"$1"; } # sval <line> <key>
model_of() { awk '{ print $2 }' <<<"$1"; }
gate_line() { (cd "$WORK" && timeout 120 bash "$S/$1-gate" 2>/dev/null | tr -d '\r'); }
turns() { grep '^runAppServerTurn ' "$STUB_EVENT_LOG" 2>/dev/null | awk '{ print $2 }' | tr '\n' ' '; }
agy_models() { grep -A1 -x -e '--model' "$STUB_AGY_ARGS_LOG" 2>/dev/null | grep -v -e '^--' | tr '\n' ' '; }
agy_prints() { if [ -f "$STUB_AGY_ARGS_LOG" ]; then grep -c -x -e '-p' "$STUB_AGY_ARGS_LOG" || true; else echo 0; fi; }

# --- A1 ---
t_A1() {
  needs_spawn A1 || return
  fresh; settings true true
  TS_LOG="$TMP/ts.log" AGY_DELAY=3 TURN_DELAY_MS=3000 panel heavy
  check "A1: the panel prints the Codex gpt-6-astra line once" "$(grep -c '^codex-judge gpt-6-astra/xhigh status=OK ' <<<"$out")" "1"
  check "A1: the panel prints the agy claude-opus-5-5 line once" "$(grep -c '^agy-judge claude-opus-5-5/high status=OK ' <<<"$out")" "1"
  check "A1: the panel prints one status line per reviewer and the summary" "$(grep -c '' <<<"$out")" "3"
  check "A1: the summary is panel tier=heavy lists=2" "$(tail -1 <<<"$out")" "panel tier=heavy lists=2"
  check "A1: the panel exits 0" "$rc" "0"
  check "A1: Codex ran gpt-6-astra" "$(turns)" "gpt-6-astra/xhigh "
  check "A1: agy ran claude-opus-5-5" "$(agy_models)" "claude-opus-5-5 "
  local cs as ae
  cs=$(awk '$1 == "codex" && $2 == "start" { print $3 }' "$TMP/ts.log" | head -1)
  as=$(awk '$1 == "agy" && $2 == "start" { print $3 }' "$TMP/ts.log" | head -1)
  ae=$(awk '$1 == "agy" && $2 == "end" { print $3 }' "$TMP/ts.log" | head -1)
  check "A1: the two runners were running at the same time" \
    "$([ -n "$cs" ] && [ -n "$as" ] && [ -n "$ae" ] && [ "$as" -lt $((cs + 3000)) ] && [ "$cs" -lt "$ae" ] && echo overlap || echo "serial cs=$cs as=$as ae=$ae")" "overlap"

  fresh; settings true true
  STUB_REFUSE_ONCE=1 STUB_AGY_REFUSE_MODEL=claude-opus-5-5 panel heavy
  check "A1: a Codex runner that ends FALLBACK" "$(sval "$(sline codex)" status)" "FALLBACK"
  check "A1: an agy runner that ends FALLBACK" "$(sval "$(sline agy)" status)" "FALLBACK"
  check "A1: FALLBACK runners count as lists" "$(tail -1 <<<"$out")" "panel tier=heavy lists=2"
}

# --- A2 ---
t_A2() {
  needs_spawn A2 || return
  fresh; settings true true
  panel heavy
  check "A2: Codex runs gpt-6-astra" "$(model_of "$(sline codex)")" "gpt-6-astra/xhigh"
  check "A2: agy runs claude-opus-5-5" "$(model_of "$(sline agy)")" "claude-opus-5-5/high"
  check "A2: both heavy runners answer OK and count as lists" "$(tail -1 <<<"$out")" "panel tier=heavy lists=2"
  check "A2: Codex sent the Astra request" "$(turns)" "gpt-6-astra/xhigh "
  check "A2: agy was asked for Opus" "$(agy_models)" "claude-opus-5-5 "

  fresh; settings true true
  STUB_REFUSE_ONCE=1 STUB_AGY_REFUSE_MODEL=claude-opus-5-5 panel heavy
  check "A2: a refused Astra falls back to gpt-6.1-sol" "$(model_of "$(sline codex)") $(sval "$(sline codex)" status)" "gpt-6.1-sol/xhigh FALLBACK"
  check "A2: Codex tried Astra, then Sol, and nothing else" "$(turns)" "gpt-6-astra/xhigh gpt-6.1-sol/xhigh "
  check "A2: a refused Opus falls back to gemini-4-argon high" "$(model_of "$(sline agy)") $(sval "$(sline agy)" status)" "gemini-4-argon/high FALLBACK"
  check "A2: agy was asked for Opus, then Argon, and nothing else" "$(agy_models)" "claude-opus-5-5 gemini-4-argon "
  check "A2: agy ran exactly two print calls" "$(agy_prints)" "2"

  fresh; settings true true
  STUB_MODE=refusal panel heavy
  check "A2: Codex falls back once only: two refused rows end FAILED" "$(sval "$(sline codex)" status)" "FAILED"
  check "A2: Codex made exactly two attempts" "$(turns)" "gpt-6-astra/xhigh gpt-6.1-sol/xhigh "
}

# --- A3 ---
skipped_check() { # skipped_check <label> <id> <reason|-> - the family's line says SKIPPED with that reason
  local line; line=$(sline "$2")
  check "A3: $1: $2 is SKIPPED" "$(sval "$line" status)" "SKIPPED"
  [ "$3" = - ] || check "A3: $1: $2 carries the gate's reason" "$(sval "$line" reason)" "$3"
}
t_A3() {
  needs_spawn A3 || return
  local gr

  fresh; settings false false
  panel heavy
  skipped_check "both settings off" agy setting
  skipped_check "both settings off" codex setting
  check "A3: with both skipped the panel prints lists=0" "$(tail -1 <<<"$out")" "panel tier=heavy lists=0"
  check "A3: with both skipped the panel exits 0" "$rc" "0"
  check "A3: no Codex turn started" "$(turns)" ""
  check "A3: agy never ran a print call" "$(agy_prints)" "0"

  fresh; settings true false
  panel heavy
  skipped_check "agy setting off" agy setting
  check "A3: agy setting off: Codex still runs" "$(sval "$(sline codex)" status)" "OK"
  check "A3: agy setting off: the panel counts one list" "$(tail -1 <<<"$out")" "panel tier=heavy lists=1"
  check "A3: agy setting off: agy never ran a print call" "$(agy_prints)" "0"

  fresh; settings false true
  panel heavy
  skipped_check "codex setting off" codex setting
  check "A3: codex setting off: agy still runs" "$(sval "$(sline agy)" status)" "OK"
  check "A3: codex setting off: no Codex turn started" "$(turns)" ""

  fresh; settings true true
  PATH="$NOAGY_PATH" panel heavy
  gr=$(PATH="$NOAGY_PATH" gate_line agy | sed -n 's/.* reason=\([^ ]*\).*/\1/p')
  skipped_check "agy not installed" agy "$gr"
  absent "A3: agy not installed: the reason is the gate's, never ok" "reason=$gr" '^reason=(ok)?$'
  check "A3: agy not installed: Codex still runs" "$(sval "$(sline codex)" status)" "OK"

  fresh; settings true true
  STUB_AGY_AUTH=logged-out panel heavy
  gr=$(STUB_AGY_AUTH=logged-out gate_line agy | sed -n 's/.* reason=\([^ ]*\).*/\1/p')
  skipped_check "agy signed out" agy "$gr"
  absent "A3: agy signed out: the reason is the gate's, never ok" "reason=$gr" '^reason=(ok)?$'
  check "A3: agy signed out: agy never ran a print call" "$(agy_prints)" "0"

  fresh; settings true true
  STUB_GATE_MODE=logged-out panel heavy
  gr=$(STUB_GATE_MODE=logged-out gate_line codex | sed -n 's/.* reason=\([^ ]*\).*/\1/p')
  skipped_check "codex signed out" codex "$gr"
  absent "A3: codex signed out: the reason is the gate's, never ok" "reason=$gr" '^reason=(ok)?$'
  check "A3: codex signed out: no Codex turn started" "$(turns)" ""
  check "A3: codex signed out: agy still runs" "$(sval "$(sline agy)" status)" "OK"

  fresh; settings true true
  STUB_GATE_MODE=quota panel heavy
  skipped_check "codex quota" codex quota
  check "A3: codex quota: no Codex turn started" "$(turns)" ""

  fresh; settings true true
  # The first run's quota error lands on the Claude row; with Claude off, the
  # second lands on the Gemini row and marks the family.
  STUB_AGY_MODE=error STUB_AGY_ERROR='RESOURCE_EXHAUSTED quota for gemini-4-argon. Resets in 2h' panel heavy
  STUB_AGY_MODE=error STUB_AGY_ERROR='RESOURCE_EXHAUSTED quota for gemini-4-argon. Resets in 2h' panel heavy
  : > "$STUB_AGY_ARGS_LOG"
  panel heavy
  skipped_check "agy quota marked by an earlier run" agy quota
  check "A3: agy quota: agy never ran a print call" "$(agy_prints)" "0"

  fresh; settings true true
  STUB_GATE_MODE=quota STUB_AGY_AUTH=logged-out panel heavy
  skipped_check "both gates closed for different reasons" agy -
  skipped_check "both gates closed for different reasons" codex quota
  check "A3: both closed: lists=0" "$(tail -1 <<<"$out")" "panel tier=heavy lists=0"
  check "A3: both closed: the panel exits 0" "$rc" "0"
  check "A3: both closed: nothing started" "$(turns)|$(agy_prints)" "|0"
}

# --- routing fixtures: one repository holding plans ---
PLANREPO="$TMP/planrepo"
mkdir -p "$PLANREPO/docs"
git -C "$PLANREPO" init -q -b main
git -C "$PLANREPO" config user.name Darkraise
git -C "$PLANREPO" config user.email quangtc94@gmail.com
printf '# Spec\n' > "$PLANREPO/docs/spec.md"
cat > "$PLANREPO/route.md" <<'EOF'
# Route Plan

**Goal:** Fixture.

## Task index

1. risk zero
2. risk one
3. risk two total five
4. risk two total six
5. risk three total six
6. risk three total four

### Task 1: risk zero

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

### Task 2: risk one

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 1 = 4

### Task 3: risk two total five

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 2 = 5

### Task 4: risk two total six

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 2 - coupling 1 - risk 2 = 6

### Task 5: risk three total six

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 1 - spec 1 - coupling 1 - risk 3 = 6

### Task 6: risk three total four

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 3 = 4
EOF
git -C "$PLANREPO" add -A
git -C "$PLANREPO" commit -q -m plans

open_gates() { # open_gates <codexReview> <agyReview>; runs both gates so the session files hold their answers
  fresh; settings "$1" "$2"
  gate_line codex >/dev/null; gate_line agy >/dev/null
}
route() { # route <args...>; sets rline
  rline=$(cd "$PLANREPO" && timeout 60 bash "$ROUTE" route.md "$@" 2>"$TMP/err" | tr -d '\r')
}

# --- A4 ---
t_A4() {
  needs_spawn A4 || return
  local mode
  for mode in "true true" "true false" "false true"; do
    open_gates $mode
    local tag="codex=${mode% *} agy=${mode#* }"
    for t in 1 2 3 4; do
      route --task "$t"
      check "A4: $tag: risk 0-2 task $t gets no per-task route" "$rline" ""
    done
    route --task 5
    check "A4: $tag: risk 3 (total 6) routes to the heavy panel then Opus" "$(sval "$rline" primary)" "panel:heavy+judge-opus"
    route --task 6
    check "A4: $tag: risk 3 (total 4) routes to the heavy panel then Opus" "$(sval "$rline" primary)" "panel:heavy+judge-opus"
  done

  open_gates false false
  route --task 5
  check "A4: neither open: risk 3 is the Opus seat" "$(sval "$rline" primary)" "dforge:judge-opus"
  check "A4: neither open: risk 3 says reviewers-off" "$(sval "$rline" reason)" "reviewers-off"
  route --task 6
  check "A4: neither open: risk 3 at total 4 is the Opus seat" "$(sval "$rline" primary)" "dforge:judge-opus"
  absent "A4: neither open: no route names a panel" "$rline" 'panel:'

  # An untrusted agy surface with Codex off is neither open.
  fresh; settings false true
  DR_AGY_POLICY="$UNTRUSTED" gate_line agy >/dev/null; gate_line codex >/dev/null
  route --task 5
  check "A4: an untrusted agy surface does not count as open" "$(sval "$rline" reason)" "reviewers-off"
}

# --- A5 ---
t_A5() {
  needs_spawn A5 || return
  local mode
  for mode in "true true" "true false" "false true"; do
    open_gates $mode
    route --plan-round 1
    check "A5: codex=${mode% *} agy=${mode#* }: round 1 is panel:plan" "$(sval "$rline" primary)" "panel:plan"
  done
  open_gates false false
  route --plan-round 1
  absent "A5: neither open: round 1 is not the panel" "$rline" 'panel:plan'
  check "A5: neither open: round 1 names the Claude seat with reviewers-off" "$(sval "$rline" reason)" "reviewers-off"
}

# --- A6 ---
agyrun() { # agyrun <kind> [tier]; direct run of the agy runner, sets out and rc
  local kind=$1 tier=${2-} extra=()
  case $kind in
    final) extra=(--base main); out_file="$OUT/out.md" ;;
    *) extra=(--prompt "$TMP/prompt.md"); out_file="$OUT/out.json" ;;
  esac
  [ -z "$tier" ] || extra+=(--tier "$tier")
  rm -rf "$OUT"; mkdir -p "$OUT"
  out=$(cd "$WORK" && AGY_REVIEW_GRACE=5 timeout 300 bash "$AGYRUN" --kind "$kind" --cwd "$WORK" --out "$out_file" "${extra[@]}" 2>"$TMP/err"); rc=$?
  out=${out//$'\r'/}
}
named_in_output() { # named_in_output <word> - the word appears in the status output, stderr or a file next to the list
  { printf '%s\n' "$out"; cat "$TMP/err"; cat "$OUT"/* 2>/dev/null; } | tr -d '\r' | grep -qF -- "$1" && echo named || echo unnamed
}
t_A6() {
  needs_spawn A6 || return
  local kind mode
  for kind in "task heavy" "plan" "final"; do
    fresh; settings false true
    case ${kind%% *} in plan) mode=plan-review ;; final) mode=final-review ;; *) mode=review ;; esac
    STUB_AGY_MODE=$mode agyrun $kind
    check "A6: a clean $kind run is OK" "$(sval "$out" status)" "OK"
    check "A6: a clean $kind run records no write" "$(sval "$out" evidence)" "none"
    check "A6: the $kind run ran agy" "$(agy_prints)" "1"
    check "A6: the $kind run never skips permissions" "$(grep -c -x -e '--dangerously-skip-permissions' "$STUB_AGY_ARGS_LOG")" "0"
  done

  fresh; settings false true
  STUB_AGY_SIDE=write STUB_AGY_WRITE=tracked.txt agyrun task heavy
  check "A6: a changed tracked file ends FAILED" "$(sval "$out" status)" "FAILED"
  check "A6: a changed tracked file is evidence=wrote" "$(sval "$out" evidence)" "wrote"
  check "A6: a changed tracked file is named" "$(named_in_output tracked.txt)" "named"

  fresh; settings false true
  STUB_AGY_SIDE=write STUB_AGY_WRITE=brand-new.txt agyrun task heavy
  check "A6: a new untracked file ends FAILED" "$(sval "$out" status)" "FAILED"
  check "A6: a new untracked file is evidence=wrote" "$(sval "$out" evidence)" "wrote"
  check "A6: a new untracked file is named" "$(named_in_output brand-new.txt)" "named"

  fresh; settings false true
  STUB_AGY_SIDE=commit STUB_AGY_WRITE=committed.txt agyrun task heavy
  check "A6: a run that moves HEAD ends FAILED" "$(sval "$out" status)" "FAILED"
  check "A6: a run that moves HEAD is evidence=wrote" "$(sval "$out" evidence)" "wrote"
  check "A6: a run that moves HEAD names HEAD" "$(named_in_output HEAD)" "named"

  fresh; settings false true
  STUB_AGY_SIDE=stash STUB_AGY_WRITE=stashed.txt agyrun task heavy
  check "A6: a run that changes the stash list ends FAILED" "$(sval "$out" status)" "FAILED"
  check "A6: a run that changes the stash list is evidence=wrote" "$(sval "$out" evidence)" "wrote"
  check "A6: a run that changes the stash list names the stash" "$(named_in_output stash)" "named"

  fresh; settings false true
  STUB_AGY_SIDE=write STUB_AGY_WRITE=tracked.txt agyrun task heavy
  check "A6: a heavy run that writes also ends FAILED evidence=wrote" "$(sval "$out" status)/$(sval "$out" evidence)" "FAILED/wrote"
  fresh; settings false true
  STUB_AGY_MODE=plan-review STUB_AGY_SIDE=write STUB_AGY_WRITE=tracked.txt agyrun plan
  check "A6: a plan run that writes ends FAILED evidence=wrote" "$(sval "$out" status)/$(sval "$out" evidence)" "FAILED/wrote"
  fresh; settings false true
  STUB_AGY_MODE=final-review STUB_AGY_SIDE=write STUB_AGY_WRITE=tracked.txt agyrun final
  check "A6: a final run that writes ends FAILED evidence=wrote" "$(sval "$out" status)/$(sval "$out" evidence)" "FAILED/wrote"
}

# --- A7 ---
t_A7() {
  needs_spawn A7 || return
  fresh; settings true true
  STUB_AGY_MODE=error STUB_AGY_ERROR='RESOURCE_EXHAUSTED quota for claude. Resets in 2h' panel heavy
  check "A7: the Opus run ends FAILED" "$(model_of "$(sline agy)") $(sval "$(sline agy)" status)" "claude-opus-5-5/high FAILED"
  check "A7: Codex is not affected by the Claude quota" "$(sval "$(sline codex)" status)" "OK"
  local g; g=$(gate_line agy)
  check "A7: agy stays usable with its review surface open" "$(sval "$g" usable)/$(sval "$g" review)" "true/true"
  check "A7: only the Claude row is marked off" "$(sval "$g" claude)" "off"

  : > "$STUB_AGY_ARGS_LOG"; rm -f "$STUB_EVENT_LOG" "$STUB_CALL_FILE"
  panel heavy
  check "A7: the next heavy panel runs agy on gemini-4-argon high" "$(model_of "$(sline agy)")" "gemini-4-argon/high"
  check "A7: the next heavy agy run is not a failure" "$(sval "$(sline agy)" status)" "OK"
  check "A7: agy was asked for Argon only" "$(agy_models)" "gemini-4-argon "
  check "A7: agy was given the high effort" "$(grep -A1 -x -e '--effort' "$STUB_AGY_ARGS_LOG" | grep -v -e '^--' | tr '\n' ' ')" "high "
  check "A7: the next heavy panel still runs Astra" "$(model_of "$(sline codex)")" "gpt-6-astra/xhigh"
  check "A7: the next heavy panel counts both lists" "$(tail -1 <<<"$out")" "panel tier=heavy lists=2"
}

# --- A8 ---
t_A8() {
  fresh; settings true -
  local g
  g=$(gate_line agy)
  check "A8: agy-gate with agyReview unset answers review=false reason=setting" "$(sval "$g" review) $(sval "$g" reason)" "false setting"
  check "A8: agy-gate ran no agy" "$([ -s "$STUB_AGY_ARGS_LOG" ] && echo ran || echo none)" "none"
  fresh; settings true false
  g=$(gate_line agy)
  check "A8: agy-gate with agyReview false answers reason=setting" "$(sval "$g" reason)" "setting"
  check "A8: agy-gate with agyReview false ran no agy" "$([ -s "$STUB_AGY_ARGS_LOG" ] && echo ran || echo none)" "none"

  fresh; settings true true
  g=$(gate_line codex)
  check "A8: codex-gate (on) answers" "$(sval "$g" usable)/$(sval "$g" review)" "true/true"
  absent "A8: codex-gate's line carries no lane= field" "$g" '(^| )lane='
  fresh; settings false true
  g=$(gate_line codex)
  check "A8: codex-gate (off) answers reason=setting" "$(sval "$g" reason)" "setting"
  absent "A8: codex-gate's off line carries no lane= field" "$g" '(^| )lane='
}

# --- A9 ---
t_A9() {
  local plan body
  body=$(cat <<'EOF'
# Demo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: the skill the **Execution:** line names.

**Goal:** Demo.

**Spec:** `docs/spec.md`

**Execution:** inline — `claude --model sonnet --effort high` — Task 2 scores 4

**Task check:** `bash quick.sh` — gate 1 has Tier: task

**Integration check:** `bash test.sh`

**CI:** none

**Plan review:** 2026-09-12 — dforge:judge-fable — executability 18 / coherence 18 / coverage 18 / assumptions 18 (round 1)

## Global Constraints

- Bash only.

## Contracts

None

## Assumptions (evidence)

- None.

## Task index

1. First thing
2. Second thing

### Task 1: First thing

**Files:**
- Create: `a.txt`

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1

- [ ] **Step 1: Write the failing test**

```bash
echo hi
```

### Task 2: Second thing

**Files:**
- Modify: `a.txt`

**Implementer:** dforge:impl-sonnet-high
**Evaluation:** files 0 - spec 1 - coupling 1 - risk 2 = 4
**Approach:** inline - skip 2: follows the pattern

- [ ] **Step 1: Do it**
EOF
)
  local R="$TMP/nine"
  mkdir -p "$R/docs"
  git -C "$R" init -q -b main
  git -C "$R" config user.name Darkraise
  git -C "$R" config user.email quangtc94@gmail.com
  printf '# Spec\n' > "$R/docs/spec.md"
  printf '%s\n' "$body" > "$R/plan-plain.md"
  printf '%s\n' "$body" | awk '/^### Task 2:/ { t = 1 } { print } t && /^\*\*Implementer:\*\*/ { print "**Executor:** codex gpt-6.1-sol / high"; t = 0 }' > "$R/plan-exec.md"
  git -C "$R" add -A
  git -C "$R" commit -q -m plans

  local lint lrc
  lint=$(cd "$R" && timeout 60 bash "$LINT" plan-exec.md 2>&1); lrc=$?
  lint=${lint//$'\r'/}
  check "A9: plan-lint on an Executor: codex plan exits 0" "$lrc" "0"
  present "A9: plan-lint reports no errors" "$lint" 'plan-lint: 0 errors'
  absent "A9: plan-lint prints no ERROR" "$lint" '^ERROR'
  local plain
  plain=$(cd "$R" && timeout 60 bash "$LINT" plan-plain.md 2>&1)
  check "A9: the plan without the line has no Executor WARN" "$(grep -c 'Executor' <<<"$plain")" "0"

  norm() { sed -e "s#$R/##g" -e 's#plan-exec#PLAN#g' -e 's#plan-plain#PLAN#g' | tr -d '\r'; }
  local b_exec b_plain
  b_exec=$(cd "$R" && timeout 60 bash "$BRIEF" plan-exec.md 2 2>&1; echo "rc=$?")
  b_plain=$(cd "$R" && timeout 60 bash "$BRIEF" plan-plain.md 2 2>&1; echo "rc=$?")
  check "A9: task-brief exits 0 on the Executor task" "$(tail -1 <<<"$b_exec")" "rc=0"
  check "A9: task-brief's brief is the ordinary brief plus the plan's own line" \
    "$(diff <(grep -v '^\*\*Executor:' "$R/.dforge/sdd/plan-exec/task-2-brief.md" | sed 's#plan-exec#plan-plain#g') "$R/.dforge/sdd/plan-plain/task-2-brief.md" >/dev/null && echo same || echo differs)" "same"
  absent "A9: task-brief names no dispatch to an executor" "$(norm <<<"$b_exec")" '[Dd]ispatch|[Ll]ane'

  local s_exec s_plain
  (cd "$R" && timeout 60 bash "$BRIEF" --open plan-exec.md 2 >/dev/null 2>&1 && timeout 60 bash "$BRIEF" --open plan-plain.md 2 >/dev/null 2>&1)
  s_exec=$(cd "$R" && timeout 60 bash "$STEP" review plan-exec.md 2 2>&1; echo "rc=$?")
  s_plain=$(cd "$R" && timeout 60 bash "$STEP" review plan-plain.md 2 2>&1; echo "rc=$?")
  check "A9: task-step review treats the Executor task as the ordinary task" \
    "$(norm <<<"$s_exec" | grep -v '^gate: ' | sed 's/ t0 [0-9]*$//')" "$(norm <<<"$s_plain" | grep -v '^gate: ' | sed 's/ t0 [0-9]*$//')"
  check "A9: task-step review exits 0" "$(tail -1 <<<"$s_exec")" "rc=0"
  absent "A9: task-step review names no executor" "$(norm <<<"$s_exec" | grep -v '^gate: ')" '[Cc]odex|[Ee]xecutor|agy'
  check "A9: the same files are written for both plans" \
    "$(cd "$R/.dforge/sdd/plan-exec" && ls | tr '\n' ' ')" "$(cd "$R/.dforge/sdd/plan-plain" && ls | tr '\n' ' ')"
}

# --- A10 ---
t_A10() {
  local files
  files=$(cd "$PLUGIN" && grep -rIlE 'run-codex-task\.sh|run-agy-task\.sh|lane-breaker|plan-revise|codexLane|agyLane|executor-lane\.md' \
    scripts reference skills hooks config .claude-plugin .codex-plugin 2>/dev/null | sort)
  check "A10: no shipped file names a retired lane name" "$files" ""
  local vr vrc
  vr=$(cd "$REPO_ROOT" && timeout 300 node scripts/validate-repository.mjs 2>&1); vrc=$?
  check "A10: validate-repository.mjs exits 0" "$vrc" "0"
  present "A10: validate-repository.mjs says the repository is valid" "$vr" 'valid'
}

# --- A11 ---
t_A11() {
  local keys list label def
  printf '{}\n' > "$HOME/.dforge/config.json"
  list=$(cd "$WORK" && timeout 60 bash "$CONFIG" get --json 2>"$TMP/err" | jq -r 'keys_unsorted | join(",")')
  absent "A11: dforge-config get --json lists neither lane switch" "$list" 'codexLane|agyLane'
  check "A11: agyReview follows codexReview in the settings list" \
    "$(tr ',' '\n' <<<"$list" | grep -x -A1 codexReview | tail -1)" "agyReview"
  check "A11: agyReview defaults to false" "$(cd "$WORK" && timeout 60 bash "$CONFIG" get agyReview 2>&1 | tr -d '\r')" "false"
  check "A11: codexLane is an unknown setting" "$(cd "$WORK" && timeout 60 bash "$CONFIG" get codexLane >/dev/null 2>&1; echo $?)" "2"
  check "A11: agyLane is an unknown setting" "$(cd "$WORK" && timeout 60 bash "$CONFIG" get agyLane >/dev/null 2>&1; echo $?)" "2"

  local schema_info
  schema_info=$(timeout 60 node --input-type=module -e '
    import { pathToFileURL } from "node:url";
    const schema = (await import(pathToFileURL(process.argv[1]).href)).default;
    const keys = Object.keys(schema);
    const i = keys.indexOf("codexReview");
    console.log([keys[i + 1], schema.agyReview?.default, schema.agyReview?.label, "codexLane" in schema, "agyLane" in schema].join("|"));
  ' "$PLUGIN/config/schema.mjs" 2>&1 | tr -d '\r')
  check "A11: the schema lists agyReview right after codexReview, default false, labelled Agy reviews, with neither lane key" \
    "$schema_info" "agyReview|false|Agy reviews|false|false"

  printf '{"codexLane":false,"agyLane":true,"codexReview":true}\n' > "$HOME/.dforge/config.json"
  local json jrc
  json=$(cd "$WORK" && timeout 60 bash "$CONFIG" get --json 2>"$TMP/err"); jrc=$?
  check "A11: a settings file holding codexLane: false resolves with exit 0" "$jrc" "0"
  check "A11: resolving a stale codexLane writes nothing to stderr" "$(tr -d '\r' < "$TMP/err")" ""
  check "A11: the stale lane keys are not in the resolved settings" "$(jq -r 'has("codexLane") or has("agyLane")' <<<"$json")" "false"
  check "A11: other settings in that file still resolve" "$(jq -r '.codexReview' <<<"$json")" "true"
  check "A11: the stale file still resolves the agyReview default" "$(jq -r '.agyReview' <<<"$json")" "false"
  printf '{}\n' > "$HOME/.dforge/config.json"
}

# --- A15 ---
t_A15() {
  needs_spawn A15 || return
  fresh; settings true true
  out=$(cd "$WORK" && STUB_FINAL_MESSAGE='No findings.' STUB_AGY_MODE=final-review timeout 300 bash "$PANEL" --kind final --cwd "$WORK" --out-dir "$OUT" --base main 2>"$TMP/err"); rc=$?
  out=${out//$'\r'/}
  check "A15: the final panel contributes one list per reviewer" "$(tail -1 <<<"$out")" "panel tier=heavy lists=2"
  check "A15: the final panel writes the Codex list" "$([ -s "$OUT/codex.md" ] && echo yes || echo no)" "yes"
  check "A15: the final panel writes the agy list" "$([ -s "$OUT/agy.md" ] && echo yes || echo no)" "yes"
}

# --- A16 ---
t_A16() {
  needs_spawn A16 || return
  local trust
  trust=$(jq -r '.trust.review' "$PLUGIN/reference/agy-policy.json" | tr -d '\r')
  present "A16: agy-policy.json ships trust.review as pass or pending" "$trust" '^(pass|pending)$'
  fresh; settings true true
  DR_AGY_POLICY="$PLUGIN/reference/agy-policy.json" panel heavy
  if [ "$trust" = pending ]; then
    local g; g=$(DR_AGY_POLICY="$PLUGIN/reference/agy-policy.json" gate_line agy)
    check "A16: pending: the shipped policy keeps agy review off whatever the setting" "$(sval "$g" usable)/$(sval "$g" review)" "true/false"
    check "A16: pending: the panel skips agy as untrusted" "$(sval "$(sline agy)" status)/$(sval "$(sline agy)" reason)" "SKIPPED/untrusted"
    check "A16: pending: agy never ran a print call" "$(agy_prints)" "0"
  else
    check "A16: pass: the shipped policy opens the agy review surface" "$(sval "$(sline agy)" status)" "OK"
    skip "A16: whether both billed runs returned a schema-valid list without writing cannot be checked without a billed run"
  fi
}

# --- A17 ---
auth_probes() { if [ -f "$STUB_EVENT_LOG" ]; then grep -c '^getCodexAuthStatus ' "$STUB_EVENT_LOG" || true; else echo 0; fi; }
t_A17() {
  needs_spawn A17 || return
  local order
  fresh; settings true true
  panel heavy
  check "A17: a panel run makes no Codex auth probe of its own" "$(auth_probes)" "0"
  check "A17: the panel run did run Codex" "$(sval "$(sline codex)" status)" "OK"
  order=$(grep -E '^(getCodexAuthStatus|runAppServerTurn) ' "$STUB_EVENT_LOG" | awk '{ print $1 }' | tr '\n' ' ')
  check "A17: the panel run goes straight to the Codex turn" "$order" "runAppServerTurn "
  fresh; settings true true
  STUB_REFUSE_ONCE=1 panel heavy
  check "A17: a heavy run with a Codex fallback still makes no auth probe" "$(auth_probes)" "0"
  check "A17: that run made both Codex attempts" "$(turns)" "gpt-6-astra/xhigh gpt-6.1-sol/xhigh "
  fresh; settings false true
  panel heavy
  check "A17: a panel run with Codex skipped makes no Codex auth probe" "$(auth_probes)" "0"
}

# --- A18 ---
t_A18() {
  local before after rel
  before=$(git -C "$REPO_ROOT" status --porcelain)
  rel=$(cd "$REPO_ROOT" && timeout 120 node scripts/release.mjs --dry-run 2>/dev/null | tr -d '\r')
  after=$(git -C "$REPO_ROOT" status --porcelain)
  check "A18: the release dry run changes no file" "$after" "$before"
  check "A18: no marketplace file holds a dforge version" \
    "$(jq -r '[.plugins[] | select(.name == "dforge") | has("version")] | any' "$REPO_ROOT/.claude-plugin/marketplace.json" "$REPO_ROOT/.agents/plugins/marketplace.json" 2>&1 | tr '\n' ' ')" "false false "
}

for id in A1 A2 A3 A4 A5 A6 A7 A8 A9 A10 A11 A15 A16 A17 A18; do
  want "$id" && "t_$id"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
