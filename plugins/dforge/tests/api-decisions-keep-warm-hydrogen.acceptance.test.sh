#!/usr/bin/env bash
# Acceptance tests for docs/dforge/specs/2026-11-14-api-decisions-keep-warm-hydrogen-design.md,
# the statements that reach scripts, config and reference files (A1-A18, A25, A27, A28, A31).
# The cockpit statements (A21-A24) are in api-decisions-keep-warm-hydrogen.acceptance.test.ts.
#
# Usage: api-decisions-keep-warm-hydrogen.acceptance.test.sh [A<n>]...   (no argument runs every statement)
#
# The scripts are driven only through their command lines, a local stub endpoint
# (DFORGE_DECISIONS_URL) and stub judge CLIs. Keys are sentinel values; HOME and
# every state directory live in a temporary directory.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
for v in $(compgen -e | grep -E '^(DFORGE_|API_JUDGE_|STUB_|QA_|AR_|CLAUDE_CODE_|GIT_)' || true); do unset "$v"; done
unset CLAUDE_CONFIG_DIR CLAUDE_PROJECT_DIR CODEX_HOME OPENAI_API_KEY ANTHROPIC_API_KEY XDG_CONFIG_HOME AR_SESSION

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { case "$2" in *"$3"*) check "$1" yes yes ;; *) check "$1" "[$2]" "contains [$3]" ;; esac; }
lacks() { case "$2" in *"$3"*) check "$1" "[$2]" "lacks [$3]" ;; *) check "$1" yes yes ;; esac; }

TMP=$(mktemp -d); stub=""
cleanup() {
  [ -n "$stub" ] && kill "$stub" 2>/dev/null
  if [ -s "$TMP/stub.pid" ]; then kill "$(cat "$TMP/stub.pid")" 2>/dev/null; fi
  rm -rf "$TMP"
}
trap cleanup EXIT
export HOME="$TMP/home" CLAUDE_CODE_SESSION_ID=s1
KEY_A=sk-test-anthropic-SENTINEL KEY_O=sk-test-openai-SENTINEL KEY_R=sk-test-agentrouter-SENTINEL
export DFORGE_ANTHROPIC_API_KEY=$KEY_A DFORGE_OPENAI_API_KEY=$KEY_O DFORGE_AGENTROUTER_API_KEY=$KEY_R
WORK="$TMP/work"; REPORT="$TMP/report.md"; REQ="$TMP/requests.jsonl"; CFG="$TMP/stub-config.json"
DECIDE="$P/scripts/decide"; RUN="$P/scripts/run-api-judge"; SPEND="$P/scripts/api-spend"
FIX="$P/tests/fixtures/stub-api-judge"
ARGS="$TMP/args.log" ENVLOG="$TMP/env.log"
export STUB_JUDGE_ARGS_LOG="$ARGS" STUB_JUDGE_PID_FILE="$TMP/stub.pid"

# --- stub Decisions endpoint: answers by position, so the test needs no option-value naming ---
cat > "$TMP/stub-decisions.mjs" <<'JS'
import { createServer } from 'node:http'
import { appendFileSync, readFileSync, writeFileSync } from 'node:fs'
const [portFile, cfgFile, logFile] = process.argv.slice(2)
createServer((req, res) => {
  let text = ''
  req.on('data', chunk => { text += chunk })
  req.on('end', () => {
    const cfg = JSON.parse(readFileSync(cfgFile, 'utf8'))
    const body = JSON.parse(text)
    const authorized = req.headers.authorization === `Bearer ${process.env.STUB_KEY}`
    appendFileSync(logFile, `${JSON.stringify({ method: req.method, url: req.url, authorized, body })}\n`)
    const choice = (name, pick, confidence) => {
      const q = (body.questions ?? []).find(one => one.name === name)
      const values = (q?.choices ?? []).map(one => one.value)
      const at = cfg.options.indexOf(pick)
      const index = pick === 'other' ? values.length - 1 : name === 'ruling_reversed' ? cfg.options.length - 1 - at : at
      return { type: 'choice', name, choice: values[index], probabilities: [], confidence }
    }
    const one = (name, pick, confidence) => (cfg.refuse === name ? { type: 'refusal', name } : choice(name, pick, confidence))
    const answer = cfg.raw ?? {
      answers: [
        one('ruling', cfg.a, cfg.ca),
        one('ruling_reversed', cfg.b, cfg.cb),
        { type: 'predicate', name: 'needs_more', probability: cfg.nm },
        { type: 'predicate', name: 'guarded', probability: cfg.g },
      ],
      usage: { input_tokens: cfg.tokens ?? 1000 },
    }
    setTimeout(() => {
      res.writeHead(cfg.status ?? 200, { 'content-type': 'application/json' })
      res.end(JSON.stringify(answer))
    }, cfg.delayMs ?? 0)
  })
}).listen(0, '127.0.0.1', function () { writeFileSync(portFile, String(this.address().port)) })
JS
: > "$REQ"
reply() { # reply <pick> <confidence> <reversed pick> <reversed confidence> <needs_more> <guarded> [input tokens] [delay ms]
  jq -n --arg a "$1" --argjson ca "$2" --arg b "$3" --argjson cb "$4" --argjson nm "$5" --argjson g "$6" --argjson t "${7:-1000}" --argjson d "${8:-0}" \
    '{options: ["alpha", "beta"], a: $a, ca: $ca, b: $b, cb: $cb, nm: $nm, g: $g, tokens: $t, delayMs: $d}' > "$CFG"
}
refusing() { # refusing <question name> — that question's answer is a refusal, the others confident
  jq -n --arg r "$1" '{options: ["alpha", "beta"], a: "alpha", ca: 0.95, b: "alpha", cb: 0.95, nm: 0.05, g: 0.02, refuse: $r}' > "$CFG"
}
rawreply() { # rawreply <status> <json body> [delay ms]
  jq -n --argjson s "$1" --argjson r "$2" --argjson d "${3:-0}" '{options: ["alpha", "beta"], status: $s, raw: $r, delayMs: $d}' > "$CFG"
}
reply alpha 0.9 alpha 0.9 0.05 0.02
STUB_KEY=$KEY_O node "$TMP/stub-decisions.mjs" "$TMP/port" "$CFG" "$REQ" & stub=$!
for _ in $(seq 1 100); do [ -s "$TMP/port" ] && break; sleep 0.1; done
export DFORGE_DECISIONS_URL="http://127.0.0.1:$(cat "$TMP/port")/v1/decisions"

# --- stub judge CLIs: the repository's fixtures behind wrappers that record the child's environment ---
BIN="$TMP/bin"; mkdir -p "$BIN"
cat > "$BIN/common.sh" <<'SH'
log_env() { # log_env <budget>
  [ -n "${QA_ENV_LOG:-}" ] || return 0
  while IFS= read -r line; do
    name=${line%%=*}; value=${line#*=}
    case "$value" in
      *sk-test-anthropic-SENTINEL*) label=key-anthropic ;;
      *sk-test-openai-SENTINEL*) label=key-openai ;;
      *sk-test-agentrouter-SENTINEL*) label=key-agentrouter ;;
      vendor-*) label=$value ;;
      *) continue ;;
    esac
    printf '%s %s %s\n' "$1" "$name" "$label" >> "$QA_ENV_LOG"
  done < <(env)
  printf '%s CODEX_HOME=%s\n' "$1" "${CODEX_HOME:-unset}" >> "$QA_ENV_LOG"
}
mutate() {
  case "${QA_MUTATE:-}" in
    tracked) printf 'x\n' >> docs/s.md ;;
    untracked) printf 'x\n' > stray.txt ;;
    delete) rm -f docs/s.md ;;
    index) printf 'x\n' >> docs/s.md; git add docs/s.md; git show HEAD:docs/s.md > docs/s.md ;;
    head) git -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m stray ;;
    ignored) mkdir -p .dforge; printf 'scratch\n' > .dforge/scratch.txt ;;
  esac
}
SH
for cli in claude codex; do
  budget=anthropic; [ "$cli" = codex ] && budget=openai
  cat > "$BIN/$cli" <<SH
#!/usr/bin/env bash
. "$BIN/common.sh"
b=$budget
for a in "\$@"; do case "\$a" in *agentrouter.org*) b=agentrouter ;; esac; done
log_env "\$b"
mutate
exec bash "$FIX/$cli" "\$@"
SH
  chmod +x "$BIN/$cli"
done
export PATH="$BIN:$PATH" API_JUDGE_CLAUDE="$BIN/claude" API_JUDGE_CODEX="$BIN/codex" QA_ENV_LOG="$ENVLOG"

printf '%s\n' '{"checked":"2026-11-14","models":{"gpt-6-luna":{"source":"https://example.invalid/pricing","input":0.1},"gpt-6-astra":{"source":"https://example.invalid/pricing","input":2,"cached_input":0.5,"output":8}}}' > "$TMP/prices.json"
export DFORGE_API_PRICES="$TMP/prices.json"
ladder() { # ladder <seconds> [<budget>...] — the api-judge block, rows in the order given
  local secs=$1; shift
  [ $# -gt 0 ] || set -- anthropic openai agentrouter
  { printf '%s\n' '# fixture' '' '```api-judge'
    for b in "$@"; do
      case $b in anthropic) printf 'anthropic claude-opus-5-5 medium %s\n' "$secs" ;; *) printf '%s gpt-6-astra xhigh %s\n' "$b" "$secs" ;; esac
    done
    printf '%s\n' '```'; } > "$TMP/ladder.md"
}
ladder 30
export API_JUDGE_LADDER="$TMP/ladder.md"

# --- a fresh working repository with an auto run bound to session s1 ---
reset() {
  rm -rf "$HOME" "$WORK" "$TMP/ws" "$TMP/mirror" "$TMP/outside.txt" "$ARGS" "$ENVLOG" "$TMP/stub.pid" "$REPORT"
  mkdir -p "$HOME/.dforge" "$HOME/.claude/dforge/sessions/cockpit" "$WORK/docs" "$TMP/ws" "$TMP/mirror"
  git -C "$WORK" init -q
  printf '.dforge/\nsecret.env\n' > "$WORK/.gitignore"
  printf '# Spec\nThe lock must hold on uutils.\n' > "$WORK/docs/s.md"
  printf 'TOKEN=abc\n' > "$WORK/secret.env"
  git -C "$WORK" add -A
  git -C "$WORK" -c user.name=t -c user.email=t@example.invalid -c commit.gpgsign=false commit -qm init
  date +%s > "$HOME/.claude/dforge/sessions/cockpit/s1"
  (cd "$WORK" && bash "$P/scripts/auto-run" --session s1 start --spec docs/s.md >/dev/null 2>&1)
  STATE=$(cd "$WORK" && bash "$P/scripts/dforge-path" state | tr -d '\r')
  mkdir -p "$STATE"
  : > "$REQ"
  reply alpha 0.9 alpha 0.9 0.05 0.02
  printf 'Rule on the lock.\n' > "$TMP/prompt.md"
}
settings() { printf '%s\n' "$1" > "$HOME/.dforge/config.json"; }
caps() { printf '{"apiBudgetAnthropic":%s,"apiBudgetOpenai":%s,"apiBudgetAgentRouter":%s}\n' "$1" "$2" "$3" > "$HOME/.dforge/config.json"; }
j() { jq -r "$1" | tr -d '\r'; }

ask() { out=$(cd "$WORK" && bash "$DECIDE" ask "$@" </dev/null 2>>"$TMP/err"); rc=$?; out=${out//$'\r'/}; printf '%s\n' "$out" >> "$TMP/all.out"; }
sent() { wc -l < "$REQ" | tr -d ' '; }
logged() { if [ -f "$STATE/decisions.jsonl" ]; then wc -l < "$STATE/decisions.jsonl" | tr -d ' '; else echo 0; fi; }
Q=(--id q1 --question "Which lock should the spend file use?" --options "alpha | beta")
rulings() { printf '%s\n' "$out" | grep -c '^ruling:' || true; }

jrun() { # jrun [env arguments…] — one ruling through run-api-judge; sets out, rc
  rm -f "$ARGS" "$ENVLOG" "$TMP/stub.pid"
  out=$(cd "$WORK" && env "$@" bash "$RUN" --prompt "$TMP/prompt.md" --report "$REPORT" --cwd "$WORK" --add-dir "$TMP/ws" --add-dir "$TMP/mirror" 2>>"$TMP/err"); rc=$?
  out=${out//$'\r'/}; printf '%s\n' "$out" >> "$TMP/all.out"
}
status_lines() { printf '%s\n' "$out" | grep ' status=' || true; }
tried() { status_lines | sed 's/^api-judge \([a-z]*\)[: ].* status=\([A-Z]*\) .* reason=\([a-z-]*\)$/\1 \2 \3/' | tr '\n' ' '; }
started() { if [ -f "$ARGS" ]; then grep -c '^budget ' "$ARGS"; else echo 0; fi; }
report_state() { if [ -e "$REPORT" ]; then echo present; else echo absent; fi; }
spent() { bash "$SPEND" status | tr -d '\r' | sed -n "s/^api-budget $1 .*spent=\([0-9.]*\) .*/\1/p"; }
money() { awk -v n="$1" 'BEGIN { printf "%.4f", n }'; }
unspend() { rm -f "$HOME/.dforge/api-spend.json"; }

# ---------------------------------------------------------------------------
a1() {
  reset; settings '{"decisionApi":"on","apiBudgetOpenai":10}'
  reply beta 0.93 beta 0.91 0.05 0.02
  ask "${Q[@]}" --evidence docs/s.md
  check "A1: both orders name the same option confidently: ruling at the lower confidence, exit 0" "$rc:$out" "0:ruling: beta — Decisions API (confidence 0.91)"
  check "A1: one request was sent" "$(sent)" "1"
  reply alpha 0.88 alpha 0.97 0.05 0.02
  ask "${Q[@]}" --evidence docs/s.md
  check "A1: the lower confidence is printed when it is the first order's" "$rc:$out" "0:ruling: alpha — Decisions API (confidence 0.88)"
  reply beta 0.85 beta 0.85 0.15 0.10
  ask "${Q[@]}" --evidence docs/s.md
  check "A1: a confidence at the setting, needs_more at 0.15 and guarded at 0.10 still rule" "$rc:$out" "0:ruling: beta — Decisions API (confidence 0.85)"
}

a2() {
  reset; settings '{"decisionApi":"on","apiBudgetOpenai":10}'
  while IFS='|' read -r name a ca b cb nm g token; do
    reply "$a" "$ca" "$b" "$cb" "$nm" "$g"
    ask "${Q[@]}"
    check "A2: $name" "$rc:$out" "3:no ruling reason=$token"
    check "A2: $name: no ruling line" "$(rulings)" "0"
  done <<'ROWS'
the orders disagree|alpha|0.95|beta|0.95|0.05|0.02|disagree
the first order answers other|other|0.95|alpha|0.95|0.05|0.02|needs-more
the reversed order answers other|alpha|0.95|other|0.95|0.05|0.02|needs-more
the first confidence is below the setting|alpha|0.84|alpha|0.95|0.05|0.02|low-confidence
the reversed confidence is below the setting|alpha|0.95|alpha|0.84|0.05|0.02|low-confidence
needs_more is above 0.15|alpha|0.95|alpha|0.95|0.16|0.02|needs-more
guarded is above 0.10|alpha|0.95|alpha|0.95|0.05|0.11|guarded
ROWS
  settings '{"decisionApi":"on","apiBudgetOpenai":10,"decisionConfidence":95}'
  reply alpha 0.93 alpha 0.94 0.05 0.02
  ask "${Q[@]}"
  check "A2: a confidence under a raised decisionConfidence" "$rc:$out" "3:no ruling reason=low-confidence"
  settings '{"decisionApi":"on","apiBudgetOpenai":10}'
  refusing ruling
  ask "${Q[@]}"
  check "A2: the first answer is a refusal" "$rc:$out" "3:no ruling reason=refusal"
  refusing ruling_reversed
  ask "${Q[@]}"
  check "A2: the reversed answer is a refusal" "$rc:$out" "3:no ruling reason=refusal"
  rawreply 500 '{"error":{"message":"boom"}}'
  ask "${Q[@]}"
  check "A2: a failed request (HTTP 500)" "$rc:$out" "3:no ruling reason=error"
  DFORGE_DECISIONS_URL="http://127.0.0.1:1/v1/decisions" ask "${Q[@]}"
  check "A2: an endpoint that cannot be reached" "$rc:$out" "3:no ruling reason=error"
  reply alpha 0.95 alpha 0.95 0.05 0.02 1000 4000
  local before; before=$(date +%s)
  DFORGE_DECISIONS_TIMEOUT=1 ask "${Q[@]}"
  check "A2: no answer inside the shortened timeout" "$rc:$out" "3:no ruling reason=error"
  check "A2: the shortened timeout bounds the wait" "$([ $(( $(date +%s) - before )) -lt 4 ] && echo yes || echo no)" "yes"
  reply alpha 0.95 alpha 0.95 0.05 0.02 1000 33000
  before=$(date +%s)
  out=$(cd "$WORK" && timeout 60 bash "$DECIDE" ask "${Q[@]}" </dev/null 2>>"$TMP/err"); rc=$?; out=${out//$'\r'/}
  check "A2: an answer that arrives after 30 seconds is no ruling" "$rc:$out" "3:no ruling reason=error"
  check "A2: the default wait ends near 30 seconds, before the late answer" "$([ $(( $(date +%s) - before )) -le 32 ] && echo yes || echo no)" "yes"
}

a3() {
  reset; reply alpha 0.95 alpha 0.95 0.05 0.02
  settings '{"decisionApi":"off","apiBudgetOpenai":10}'
  ask "${Q[@]}"
  check "A3: off sends no request and exits 3" "$rc:$out:$(sent)" "3:no ruling reason=off:0"
  settings '{"decisionApi":"on","apiBudgetOpenai":10}'
  CLAUDE_CODE_SESSION_ID=other ask "${Q[@]}"
  check "A3: no run bound to the session: no request, exit 3" "$rc:$out:$(sent)" "3:no ruling reason=no-run:0"
  settings '{"decisionApi":"on","apiBudgetOpenai":0}'
  ask "${Q[@]}"
  check "A3: the openai budget closed: no request, exit 3" "$rc:$out:$(sent)" "3:no ruling reason=closed:0"
  settings '{"decisionApi":"shadow","apiBudgetOpenai":10}'
  ask "${Q[@]}"
  check "A3: shadow sends the request, prints no ruling reason=shadow and exits 3" "$rc:$out:$(sent):$(rulings)" "3:no ruling reason=shadow:1:0"
  settings '{"decisionApi":"on","apiBudgetOpenai":10}'
  ask "${Q[@]}"
  check "A3: control: the same ask rules once the mode is on" "$rc:$(sent)" "0:2"
}

a4() {
  reset; settings '{"decisionApi":"on","apiBudgetOpenai":10}'
  reply alpha 0.95 alpha 0.95 0.05 0.02
  printf 'outside\n' > "$TMP/outside.txt"
  head -c 400001 /dev/zero | tr '\0' 'a' > "$WORK/docs/big.txt"
  head -c 250000 /dev/zero | tr '\0' 'b' > "$WORK/docs/half1.txt"
  head -c 250000 /dev/zero | tr '\0' 'c' > "$WORK/docs/half2.txt"
  head -c 400000 /dev/zero | tr '\0' 'd' > "$WORK/docs/exact.txt"
  while IFS='|' read -r name files; do
    local -a ev=(); local f; for f in $files; do ev+=(--evidence "$f"); done
    ask "${Q[@]}" "${ev[@]}"
    check "A4: $name" "$rc:$out:$(sent)" "3:no ruling reason=evidence:0"
  done <<ROWS
a file outside the working tree and both dforge roots|$TMP/outside.txt
a file inside the working tree that git ignores|secret.env
a file over 400000 bytes|docs/big.txt
two files over 400000 bytes in total|docs/half1.txt docs/half2.txt
ROWS
  ask "${Q[@]}" --evidence docs/exact.txt
  check "A4: control: exactly 400000 bytes of evidence is sent" "$rc:$(sent)" "0:1"
}

a5() {
  reset; settings '{"decisionApi":"on","apiBudgetOpenai":10}'
  reply alpha 0.95 alpha 0.95 0.05 0.02
  printf 'state note text\n' > "$STATE/note.md"
  check "fixture: git ignores the state root's file" "$(git -C "$WORK" check-ignore -q -- "$STATE/note.md" && echo ignored || echo tracked-or-new)" "ignored"
  ask "${Q[@]}" --evidence docs/s.md --evidence "$STATE/note.md"
  check "A5: a file under the state root that git ignores is accepted" "$rc:$(sent)" "0:1"
  has "A5: the state file's text reaches the request input" "$(tail -1 "$REQ" | j '.body.input')" "state note text"
  # The documents root in the darkmem mirror lies outside the working tree.
  . "$HERE/fixtures/darkmem-stores.sh"
  stores_home "$HOME" "$WORK" proj darkmem local > /dev/null
  jq '. + {decisionApi: "on", apiBudgetOpenai: 10}' < "$HOME/.dforge/config.json" > "$TMP/config.json" && mv "$TMP/config.json" "$HOME/.dforge/config.json"
  local docs; docs=$(cd "$WORK" && bash "$P/scripts/dforge-path" docs | tr -d '\r')
  mkdir -p "$docs/specs"; printf 'mirror spec text\n' > "$docs/specs/s.md"
  check "fixture: the documents root is outside the working tree" "$(case "$docs" in "$WORK"/*) echo inside ;; *) echo outside ;; esac)" "outside"
  ask "${Q[@]}" --evidence "$docs/specs/s.md"
  check "A5: a spec under the documents root outside the working tree is accepted" "$rc:$(sent)" "0:2"
  has "A5: the spec's text reaches the request input" "$(tail -1 "$REQ" | j '.body.input')" "mirror spec text"
}

# Whether the JSON log line <n> holds a scalar equal to <value>, whatever its key.
line_has() { sed -n "${1}p" "$STATE/decisions.jsonl" | jq -r '[.. | scalars | tostring] | .[]' | tr -d '\r' | grep -qxF -- "$2" && echo yes || echo no; }

a6() {
  reset; reply beta 0.93 beta 0.91 0.05 0.02
  settings '{"decisionApi":"on","apiBudgetOpenai":10}'
  local n0 n; n0=$(logged)
  ask --id q6 --question "Which lock should the spend file use?" --options "alpha | beta"
  n=$(logged)
  check "A6: an ask in on mode appends exactly one line" "$(( n - n0 ))" "1"
  check "A6: the line is one JSON object" "$(sed -n "${n}p" "$STATE/decisions.jsonl" | jq -e 'type == "object"' >/dev/null 2>&1 && echo yes || echo no)" "yes"
  local v
  for v in q6 alpha beta on 0.93 0.91 0.05 0.02; do
    check "A6: the answered ask's line holds '$v'" "$(line_has "$n" "$v")" "yes"
  done
  check "A6: the answered ask's line holds the choice twice (both orders)" "$(sed -n "${n}p" "$STATE/decisions.jsonl" | jq -r '[.. | scalars | tostring | select(. == "beta")] | length' | tr -d '\r')" "3"
  settings '{"decisionApi":"shadow","apiBudgetOpenai":10}'
  reply alpha 0.9 beta 0.8 0.07 0.03
  n0=$(logged)
  ask --id q6s --question "Which lock should the spend file use?" --options "alpha | beta"
  n=$(logged)
  check "A6: an ask in shadow mode appends exactly one line" "$(( n - n0 ))" "1"
  for v in q6s shadow 0.9 0.8 0.07 0.03; do
    check "A6: the shadow ask's line holds '$v'" "$(line_has "$n" "$v")" "yes"
  done
  settings '{"decisionApi":"on","apiBudgetOpenai":0}'
  n0=$(logged)
  ask --id q6c --question "Which lock should the spend file use?" --options "alpha | beta"
  n=$(logged)
  check "A6: an ask refused before any request is logged too" "$(( n - n0 )):$(line_has "$n" q6c):$(line_has "$n" closed):$(line_has "$n" on)" "1:yes:yes:yes"
  settings '{"decisionApi":"on","apiBudgetOpenai":10}'
  n0=$(logged)
  ask --id q6e --question "Which?" --options "alpha | beta" --evidence "$TMP/none.txt"
  n=$(logged)
  check "A6: an ask refused for its evidence is logged with that token" "$(( n - n0 )):$(line_has "$n" q6e):$(line_has "$n" evidence)" "1:yes:yes"
  rawreply 500 '{"error":{"message":"boom"}}'
  n0=$(logged)
  ask --id q6x --question "Which?" --options "alpha | beta"
  n=$(logged)
  check "A6: a failed request is logged with the error token" "$(( n - n0 )):$(line_has "$n" q6x):$(line_has "$n" error)" "1:yes:yes"
}

a7() {
  reset; settings '{"decisionApi":"on","apiBudgetOpenai":1000}'
  rec() { (cd "$WORK" && bash "$DECIDE" record "$@" 2>>"$TMP/err"); }
  report() { (cd "$WORK" && bash "$DECIDE" report 2>>"$TMP/err") | tr -d '\r'; }
  # An item below the confidence setting, so the usage checks stay out of the promotion counts.
  reply alpha 0.5 alpha 0.5 0.05 0.02
  ask --id u1 --question "Which?" --options "alpha | beta"
  local n0; n0=$(logged)
  rec --id u1 --ruling beta; check "A7: record takes a listed option: exit 0" "$?" "0"
  check "A7: the record is appended with its id and ruling" "$(( $(logged) - n0 )):$(line_has "$(logged)" u1):$(line_has "$(logged)" beta)" "1:yes:yes"
  rec --id u1 --ruling other; check "A7: record takes other: exit 0" "$?" "0"
  n0=$(logged)
  rec --id u1 --ruling "a third way"; check "A7: record refuses any other text: exit 2" "$?" "2"
  check "A7: a refused record appends nothing" "$(( $(logged) - n0 ))" "0"
  # Items at confidence 0.96 (the lower of 0.97 and 0.96), and items under the setting.
  local i
  for i in $(seq 1 19); do
    reply alpha 0.97 alpha 0.96 0.05 0.02
    ask --id "c$i" --question "Which?" --options "alpha | beta"; rec --id "c$i" --ruling alpha
  done
  for i in 1 2 3 4 5; do
    reply alpha 0.7 alpha 0.72 0.05 0.02
    ask --id "l$i" --question "Which?" --options "alpha | beta"; rec --id "l$i" --ruling alpha
  done
  reply alpha 0.99 alpha 0.99 0.05 0.02
  ask --id unrecorded --question "Which?" --options "alpha | beta"
  local r; r=$(report)
  check "A7: report ends with promote: no at 19 confident items, however many lower ones match" "$(printf '%s\n' "$r" | tail -1 | cut -c1-11)" "promote: no"
  check "A7: report prints more than the verdict line (counts per band)" "$([ "$(printf '%s\n' "$r" | wc -l | tr -d ' ')" -gt 1 ] && echo yes || echo no)" "yes"
  reply alpha 0.97 alpha 0.96 0.05 0.02
  ask --id c20 --question "Which?" --options "alpha | beta"; rec --id c20 --ruling beta
  check "A7: 20 confident items, 19 matching (95%): promote: yes" "$(report | tail -1)" "promote: yes"
  ask --id c21 --question "Which?" --options "alpha | beta"; rec --id c21 --ruling other
  check "A7: 21 confident items, 19 matching (90%): promote: no" "$(report | tail -1 | cut -c1-11)" "promote: no"
  check "A7: report exits 0" "$(cd "$WORK" && bash "$DECIDE" report >/dev/null 2>&1; echo $?)" "0"
}

a8() {
  reset; caps 1000 1000 1000
  settings '{"decisionApi":"on","apiBudgetOpenai":1000,"apiBudgetAnthropic":1000,"apiBudgetAgentRouter":1000}'
  reply beta 0.93 beta 0.91 0.05 0.02
  ask "${Q[@]}" --evidence docs/s.md
  ask --id q8b --question "Which?" --options "alpha | beta" --evidence secret.env
  rawreply 500 '{"error":{"message":"boom"}}'
  ask --id q8c --question "Which?" --options "alpha | beta"
  bash "$SPEND" status >> "$TMP/all.out" 2>>"$TMP/err"
  bash "$SPEND" add openai 0.5 >> "$TMP/all.out" 2>>"$TMP/err"
  jrun
  jrun STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=fail
  (cd "$WORK" && bash "$RUN" --prompt "$TMP/prompt.md" --report "$REPORT" --cwd "$WORK" --dry-run >> "$TMP/all.out" 2>>"$TMP/err")
  jrun STUB_JUDGE_ANTHROPIC=leak "STUB_JUDGE_LEAK=$KEY_O"
  check "A8: a reply holding a key value is FAILED key-in-reply and the next budget is tried" "$rc $(tried)" "0 anthropic FAILED key-in-reply openai OK none "
  lacks "A8: the report written by the next budget holds no key" "$(cat "$REPORT")" "SENTINEL"
  rm -f "$REPORT"
  jrun STUB_JUDGE_ANTHROPIC=leak "STUB_JUDGE_LEAK=$KEY_A"
  check "A8: the Anthropic key in a reply is FAILED key-in-reply" "$rc $(tried)" "0 anthropic FAILED key-in-reply openai OK none "
  rm -f "$REPORT"
  jrun STUB_JUDGE_ANTHROPIC=leak STUB_JUDGE_OPENAI=leak STUB_JUDGE_AGENTROUTER=leak "STUB_JUDGE_LEAK=$KEY_R"
  check "A8: every reply holds a key: all FAILED key-in-reply, exit 3" "$rc $(tried)" "3 anthropic FAILED key-in-reply openai FAILED key-in-reply agentrouter FAILED key-in-reply "
  check "A8: a reply holding a key is not written to --report" "$(report_state)" "absent"
  local seen
  seen="$(cat "$TMP/all.out" "$TMP/err" 2>/dev/null; cat "$STATE/decisions.jsonl" "$STATE/api-judge.log" "$HOME/.dforge/api-spend.json" 2>/dev/null; grep -rh SENTINEL "$STATE" "$HOME/.dforge" 2>/dev/null; cat "$REPORT" 2>/dev/null)"
  lacks "A8: no sentinel in stdout, stderr, decisions.jsonl, api-judge.log, api-spend.json, the state directory or the report" "$seen" "SENTINEL"
  check "fixture: the log files the check reads exist" "$([ -s "$STATE/decisions.jsonl" ] && [ -s "$STATE/api-judge.log" ] && [ -s "$HOME/.dforge/api-spend.json" ] && echo yes || echo no)" "yes"
}

a9() {
  reset; caps 1000 1000 1000
  local home
  for mode in with-codex-home without; do
    if [ "$mode" = with-codex-home ]; then
      jrun OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic "CODEX_HOME=$TMP/user-codex" STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=fail
    else
      jrun OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=fail
    fi
    check "fixture ($mode): all three judge children ran" "$(started)" "3"
    check "A9 ($mode): no child holds a DFORGE_*_API_KEY variable" "$(grep -cE ' DFORGE_[A-Z_]*_API_KEY ' "$ENVLOG" || true)" "0"
    local b
    for b in anthropic openai agentrouter; do
      check "A9 ($mode): the $b child holds exactly one key variable, its own, and no vendor value" "$(grep "^$b " "$ENVLOG" | grep -v CODEX_HOME | awk '{print $3}' | tr '\n' ' ')" "key-$b "
    done
    check "A9 ($mode): the Anthropic child's key variable is ANTHROPIC_API_KEY" "$(grep '^anthropic ' "$ENVLOG" | grep -v CODEX_HOME | awk '{print $2}')" "ANTHROPIC_API_KEY"
    check "A9 ($mode): no child but the Anthropic one holds ANTHROPIC_API_KEY, and the Anthropic child holds no OPENAI_API_KEY" "$(grep -E '^(openai|agentrouter) ANTHROPIC_API_KEY ' "$ENVLOG" | wc -l | tr -d ' '):$(grep -E '^anthropic OPENAI_API_KEY ' "$ENVLOG" | wc -l | tr -d ' ')" "0:0"
    for b in openai agentrouter; do
      home=$(sed -n "s/^$b CODEX_HOME=//p" "$ENVLOG")
      check "A9 ($mode): the $b Codex child's CODEX_HOME is set and is not the user's" "$(case "$home" in unset | "" | "$TMP/user-codex" | "$HOME/.codex") echo "shared:$home" ;; *) echo own ;; esac)" "own"
    done
  done
}

a10() {
  reset; caps 1000 1000 1000
  settings '{"decisionApi":"on","apiBudgetOpenai":1000,"apiBudgetAnthropic":1000,"apiBudgetAgentRouter":1000}'
  local st
  st=$(env -u DFORGE_ANTHROPIC_API_KEY -u DFORGE_OPENAI_API_KEY -u DFORGE_AGENTROUTER_API_KEY OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic bash "$SPEND" status | tr -d '\r')
  check "A10: every budget is closed with reason=no-key" "$(printf '%s\n' "$st" | grep -cE '^api-budget (anthropic|openai|agentrouter) open=false spent=[0-9.]+ cap=1000\.0+ reason=no-key$')" "3"
  jrun -u DFORGE_ANTHROPIC_API_KEY -u DFORGE_OPENAI_API_KEY -u DFORGE_AGENTROUTER_API_KEY OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic
  check "A10: run-api-judge starts no CLI: every budget SKIPPED no-key, exit 3" "$rc $(tried)$(started)" "3 anthropic SKIPPED no-key openai SKIPPED no-key agentrouter SKIPPED no-key 0"
  reply alpha 0.95 alpha 0.95 0.05 0.02
  out=$(cd "$WORK" && env -u DFORGE_ANTHROPIC_API_KEY -u DFORGE_OPENAI_API_KEY -u DFORGE_AGENTROUTER_API_KEY OPENAI_API_KEY=vendor-openai ANTHROPIC_API_KEY=vendor-anthropic bash "$DECIDE" ask "${Q[@]}" </dev/null 2>>"$TMP/err"); rc=$?
  check "A10: decide sends no request: exit 3" "$rc:$(sent)" "3:0"
  check "A10: control: with the DFORGE_ keys back, the first budget opens" "$(bash "$SPEND" status | tr -d '\r' | grep -c 'open=true')" "3"
}

a11() {
  reset; caps 1000 1000 1000
  jrun -u API_JUDGE_LADDER STUB_JUDGE_ANTHROPIC=fail
  check "A11: the repository's api-judge block is tried in order; the first to return a verdict ends the chain" "$rc $(tried)" "0 anthropic FAILED error openai OK none "
  check "A11: the CLIs ran in the block's order" "$(grep '^budget ' "$ARGS" | tr '\n' ' ')" "budget anthropic budget openai "
  check "A11: the first verdict is written to --report" "$(head -1 "$REPORT" | tr -d '\r')" "## Verdict"
  has "A11: the report holds the judge's ruling" "$(cat "$REPORT")" "ruling: a noclobber lock file"
  check "A11: one status line per budget tried is printed" "$(status_lines | wc -l | tr -d ' ')" "2"
  check "A11: the status lines printed are the status lines logged" "$(status_lines)" "$(grep ' status=' "$STATE/api-judge.log" | tr -d '\r')"
  has "A11: the status line names the budget, model, effort, report path and spend" "$out" "api-judge openai:gpt-6-astra/xhigh status=OK exit=0 out=$REPORT "
  rm -f "$STATE/api-judge.log" "$REPORT"; unspend
  ladder 30 agentrouter anthropic openai
  jrun STUB_JUDGE_AGENTROUTER=fail
  check "A11: a reordered block changes the order tried" "$rc $(tried)" "0 agentrouter FAILED error anthropic OK none "
  check "A11: the first row's CLI ran first" "$(grep '^budget ' "$ARGS" | tr '\n' ' ')" "budget agentrouter budget anthropic "
  check "A11: reordered: two lines printed and logged" "$(status_lines | wc -l | tr -d ' '):$(grep -c ' status=' "$STATE/api-judge.log")" "2:2"
  ladder 30
}

a12() {
  reset; caps 1000 1000 1000; ladder 60
  rm -f "$ARGS" "$TMP/live.out"
  (cd "$WORK" && env API_JUDGE_BEAT=1 STUB_JUDGE_ANTHROPIC=slow STUB_JUDGE_SLOW=5 bash "$RUN" --prompt "$TMP/prompt.md" --report "$REPORT" --cwd "$WORK" > "$TMP/live.out" 2>>"$TMP/err") & local pid=$!
  sleep 2.5
  check "A12: while the row still runs, its started line has been printed" "$(kill -0 "$pid" 2>/dev/null && echo running):$(grep -c '^api-judge anthropic:claude-opus-5-5/medium started$' "$TMP/live.out" | tr -d ' ')" "running:1"
  check "A12: and a running line has reached the output" "$([ "$(grep -c '^api-judge anthropic running [0-9]*s$' "$TMP/live.out")" -ge 1 ] && echo yes || echo no)" "yes"
  wait "$pid"
  check "A12: a running line at least every beat over a five-second run" "$([ "$(grep -c '^api-judge anthropic running [0-9]*s$' "$TMP/live.out")" -ge 3 ] && echo yes || echo no)" "yes"
  check "A12: the run still ruled" "$(head -1 "$REPORT" | tr -d '\r')" "## Verdict"
  ladder 30
}

a13() {
  reset; caps 1000 1000 1000
  jrun STUB_JUDGE_ANTHROPIC=fail
  check "A13: a failed run is FAILED and the next budget is tried" "$rc $(tried)" "0 anthropic FAILED error openai OK none "
  jrun STUB_JUDGE_ANTHROPIC=noverdict STUB_JUDGE_OPENAI=noverdict
  check "A13: text not opening with ## Verdict is FAILED and the next budget is tried" "$rc $(tried)" "0 anthropic FAILED no-verdict openai FAILED no-verdict agentrouter OK none "
  rm -f "$REPORT"
  jrun STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=fail STUB_JUDGE_AGENTROUTER=noverdict
  check "A13: no report produced: exit 3" "$rc $(tried)" "3 anthropic FAILED error openai FAILED error agentrouter FAILED no-verdict "
  check "A13: and no report file exists" "$(report_state)" "absent"
  ladder 2
  local before; before=$(date +%s)
  jrun STUB_JUDGE_ANTHROPIC=hang
  check "A13: a run past its seconds is TIMEOUT and no further budget is tried, exit 3" "$rc $(tried)$(started)" "3 anthropic TIMEOUT timeout 1"
  check "A13: the timed-out run's CLI is stopped" "$(kill -0 "$(cat "$TMP/stub.pid")" 2>/dev/null && echo running || echo stopped)" "stopped"
  check "A13: the row's seconds bound the wait" "$([ $(( $(date +%s) - before )) -lt 20 ] && echo yes || echo no)" "yes"
  check "A13: after TIMEOUT no report file exists" "$(report_state)" "absent"
  ladder 30
  before=$(date +%s)
  jrun API_JUDGE_CHAIN=2 STUB_JUDGE_ANTHROPIC=hang
  check "A13: the chain's seconds end a row that has more of its own: TIMEOUT, no further budget" "$rc $(tried)$(started)$([ $(( $(date +%s) - before )) -lt 20 ] && echo bounded)" "3 anthropic TIMEOUT timeout 1bounded"
  before=$(date +%s)
  jrun API_JUDGE_CHAIN=5 STUB_JUDGE_ANTHROPIC=slow-fail STUB_JUDGE_SLOW=3 STUB_JUDGE_OPENAI=hang
  check "A13: a later row gets only what is left of the chain: TIMEOUT, agentrouter never tried" "$rc $(tried)$(started)$([ $(( $(date +%s) - before )) -lt 20 ] && echo bounded)" "3 anthropic FAILED error openai TIMEOUT timeout 2bounded"
  check "A13: the second timed-out CLI is stopped" "$(kill -0 "$(cat "$TMP/stub.pid")" 2>/dev/null && echo running || echo stopped)" "stopped"
  rm -f "$REPORT"
  jrun QA_MUTATE=untracked
  check "A13: a FAILED reason=wrote ends the chain: exit 3, one CLI" "$rc $(tried)$(started)" "3 anthropic FAILED wrote 1"
}

a14() {
  reset
  # skipped <budget> <reason> — the budget's status line is SKIPPED with the reason and its CLI never started
  skipped() {
    check "A14: $3: SKIPPED $2" "$(status_lines | grep "^api-judge $1:" | sed 's/.* status=\([A-Z]*\) .* reason=\([a-z-]*\)$/\1 \2/')" "SKIPPED $2"
    check "A14: $3: its CLI never started" "$(if [ -f "$ARGS" ]; then grep -c "^budget $1\$" "$ARGS" || true; else echo 0; fi)" "0"
  }
  caps 0 1000 1000
  jrun
  skipped anthropic off "a cap of 0"
  check "A14: a cap of 0: the next budget still runs" "$rc $(tried)" "0 anthropic SKIPPED off openai OK none "
  caps 1000 1000 1000
  jrun -u DFORGE_OPENAI_API_KEY STUB_JUDGE_ANTHROPIC=fail
  skipped openai no-key "no key"
  caps 20 1000 1000; bash "$SPEND" add anthropic 19
  jrun
  skipped anthropic spent "recorded spend at 95% of the cap"
  unspend; caps 20 1000 1000; bash "$SPEND" add anthropic 18.9
  jrun
  check "A14: control: spend under 95% of the cap still runs" "$(tried)" "anthropic OK none "
  unspend; caps 1000 1000 1000
  printf '%s\n' '{"checked":"2026-11-14","models":{}}' > "$TMP/noprices.json"
  jrun "DFORGE_API_PRICES=$TMP/noprices.json" STUB_JUDGE_ANTHROPIC=fail
  skipped openai no-price "no price row (openai)"
  skipped agentrouter no-price "no price row (agentrouter)"
  check "A14: no price row never skips anthropic" "$(tried)" "anthropic FAILED error openai SKIPPED no-price agentrouter SKIPPED no-price "
  caps 0 0 0
  jrun
  check "A14: every cap 0: no CLI starts, exit 3" "$rc $(tried)$(started)" "3 anthropic SKIPPED off openai SKIPPED off agentrouter SKIPPED off 0"
}

a15() {
  reset; caps 1000 1000 1000
  local mode
  for mode in tracked untracked delete index head; do
    git -C "$WORK" reset -q --hard HEAD; git -C "$WORK" clean -qfd; rm -f "$REPORT"
    jrun "QA_MUTATE=$mode"
    check "A15: a run that changed the worktree ($mode) is FAILED wrote and ends the chain" "$rc $(tried)$(started)" "3 anthropic FAILED wrote 1"
    check "A15: after $mode the text is not written to --report" "$(report_state)" "absent"
    git -C "$WORK" reset -q --hard "$(git -C "$WORK" rev-list --max-parents=0 HEAD)"
  done
  git -C "$WORK" reset -q --hard HEAD; git -C "$WORK" clean -qfd
  jrun QA_MUTATE=ignored
  check "A15: control: a change git ignores is no write" "$rc $(tried)" "0 anthropic OK none "
  rm -f "$REPORT"
  jrun
  check "A15: control: an untouched worktree rules" "$rc $(tried)$(report_state)" "0 anthropic OK none present"
}

a16() {
  reset; caps 1000 1000 1000
  unspend; jrun STUB_JUDGE_COST=0.37
  check "A16: the Anthropic run is charged the cost its CLI reports" "$(spent anthropic):$(spent openai)" "0.3700:0.0000"
  jrun STUB_JUDGE_COST=0.37
  check "A16: a second call adds to the spend" "$(spent anthropic)" "0.7400"
  unspend; jrun STUB_JUDGE_ANTHROPIC=fail
  check "A16: a run that reported neither cost nor tokens adds 1.00; a Codex run is priced from its last token total" "$(spent anthropic):$(spent openai)" "1.0000:2.5000"
  unspend; jrun STUB_JUDGE_ANTHROPIC=noverdict STUB_JUDGE_OPENAI=noverdict
  check "A16: a failed run is charged what it reported, agentrouter from the same table" "$(spent anthropic):$(spent openai):$(spent agentrouter)" "0.2500:2.5000:2.5000"
  unspend; ladder 2; jrun STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=hang-usage
  check "A16: a timed-out run is charged its last token total" "$(tried)$(spent openai)" "anthropic FAILED error openai TIMEOUT timeout 2.5000"
  unspend; jrun STUB_JUDGE_ANTHROPIC=fail STUB_JUDGE_OPENAI=hang
  check "A16: a timed-out run that reported nothing adds 1.00" "$(spent openai)" "1.0000"
  ladder 30
  unspend; jrun STUB_JUDGE_ANTHROPIC=silent
  check "A16: a verdict with no cost reported adds 1.00" "$rc:$(spent anthropic)" "0:1.0000"
  # A Decisions request is charged to openai from its input tokens at the price row.
  unspend; settings '{"decisionApi":"on","apiBudgetOpenai":1000}'
  reply beta 0.95 beta 0.95 0.05 0.02 2000000
  ask "${Q[@]}"
  check "A16: a Decisions request of 2,000,000 input tokens at 0.10 per million is charged to openai" "$(spent openai):$(spent anthropic):$(spent agentrouter)" "0.2000:0.0000:0.0000"
  check "fixture: the request was answered" "$rc" "0"
}

a17() {
  reset; caps 1000 1000 1000
  jrun CLAUDE_CODE_SESSION_ID=other
  check "A17: no run bound: exit 3 with reason=no-run" "$rc:$(printf '%s\n' "$out" | grep -c 'reason=no-run')" "3:1"
  check "A17: no CLI starts" "$(started)" "0"
  check "A17: no report file exists" "$(report_state)" "absent"
}

a18() {
  reset; caps 1000 1000 1000
  jrun
  local following
  following=$(awk -v b="budget anthropic" '$0 == b { f = 1; next } f && $0 == "--" { exit } f { if (p == "--add-dir") print; p = $0 }' "$ARGS" | tr '\n' ' ')
  check "A18: each --add-dir directory reaches the Anthropic CLI as an --add-dir argument" "$following" "$TMP/ws $TMP/mirror "
}

a25() {
  local s; s=$(node -e "import('$P/config/schema.mjs').then(m => console.log(JSON.stringify(m.default)))" | tr -d '\r')
  field() { printf '%s' "$s" | jq -c "$1"; }
  check "A25: decisionApi is off by default and takes off, shadow, on" "$(field '.decisionApi | [.default, .values]')" '["off",["off","shadow","on"]]'
  check "A25: decisionConfidence defaults to 85, range 50 to 99" "$(field '.decisionConfidence | [.default, .min, .max]')" "[85,50,99]"
  local b
  for b in apiBudgetOpenai apiBudgetAnthropic apiBudgetAgentRouter; do
    check "A25: $b defaults to 0, range 0 to 1000 step 5, zero is off" "$(field ".$b | [.default, .min, .max, .step, .zero]")" '[0,0,1000,5,"off"]'
  done
  check "A25: keepWarm defaults to 50, range 0 to 59, zero is off, group Context" "$(field '.keepWarm | [.default, .min, .max, .zero, .group]')" '[50,0,59,"off","Context"]'
}

a27() {
  local note="$P/../../docs/dforge/notes/2026-11-14-agy-hydrogen-review.md"
  local verdict model effort version row
  verdict=$(grep -E '^Verdict: ' "$note" | tail -1 | tr -d '\r')
  model=$(printf '%s' "$verdict" | awk '{print $2}'); effort=$(printf '%s' "$verdict" | awk '{print $3}')
  version=$(sed -n 's/^agy version: *//p' "$note" | head -1 | tr -d '\r ')
  row=$(awk '/^```agy-judge$/ { f = 1; next } f && /^```$/ { exit } f && NF { last = $0 } END { print last }' "$P/reference/ladder.md" | tr -d '\r')
  check "fixture: the note ends with a Verdict line naming a model and an effort" "$([ "$(tail -1 "$note" | tr -d '\r')" = "$verdict" ] && [ -n "$model" ] && [ -n "$effort" ] && echo yes || echo no)" "yes"
  check "A27: the agy-judge block's last row names the Verdict line's model and effort" "$(printf '%s' "$row" | awk '{print $1, $2}')" "$model $effort"
  check "A27: agy-policy.json calibrated is the agy version the note records" "$(jq -r .calibrated "$P/reference/agy-policy.json" | tr -d '\r')" "$version"
  case "$model" in
    *hydrogen*) check "A27: a Hydrogen verdict sets min_version to the version too" "$(jq -r .min_version "$P/reference/agy-policy.json" | tr -d '\r')" "$version" ;;
    *) check "A27: the verdict is not Hydrogen: min_version is a version string (not asserted equal)" "$(jq -r '.min_version | type' "$P/reference/agy-policy.json" | tr -d '\r')" "string" ;;
  esac
}

a28() {
  local first
  first=$(awk '/^```agy-judge$/ { f = 1; next } f && NF { print; exit }' "$P/reference/ladder.md" | tr -d '\r')
  check "A28: the first row of the agy-judge block is still claude-opus-5-5 high 5400" "$first" "claude-opus-5-5 high 5400"
}

a31() {
  local plan="$P/skills/writing-plans/references/auto-run-plan.md" ar="$P/reference/auto-run.md"
  check "A31: auto-run-plan.md does not name dforge:judge-opus" "$(grep -c 'dforge:judge-opus' "$plan" || true)" "0"
  check "A31: it sends an approach or planning choice to auto-run.md §Rulings" "$(tr '\n' ' ' < "$plan" | sed 's/  */ /g' | grep -c 'approach or planning choice.* you would ask about goes up the ladder in auto-run.md §Rulings')" "1"
  local section pending decide judge
  section=$(awk '/^## Rulings$/ { f = 1; next } f && /^## / { exit } f { print }' "$ar")
  pending=$(printf '%s\n' "$section" | grep -n 'The pending list' | head -1 | cut -d: -f1)
  decide=$(printf '%s\n' "$section" | grep -n 'scripts/decide ask' | head -1 | cut -d: -f1)
  judge=$(printf '%s\n' "$section" | grep -n 'scripts/run-api-judge --prompt' | head -1 | cut -d: -f1)
  check "fixture: §Rulings holds the pending-list rung and both calls" "$([ -n "$pending" ] && [ -n "$decide" ] && [ -n "$judge" ] && echo yes || echo no)" "yes"
  check "A31: scripts/decide ask appears above the pending-list rung" "$([ "${decide:-999999}" -lt "${pending:-0}" ] && echo yes || echo no)" "yes"
  check "A31: scripts/run-api-judge appears above the pending-list rung" "$([ "${judge:-999999}" -lt "${pending:-0}" ] && echo yes || echo no)" "yes"
}

SEL=("$@")
want() { local s; [ "${#SEL[@]}" -eq 0 ] && return 0; for s in "${SEL[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }
for n in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 25 27 28 31; do
  if want "A$n"; then "a$n"; fi
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
