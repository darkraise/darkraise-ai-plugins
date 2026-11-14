#!/usr/bin/env bash
# decide: the Decisions API rung of an auto run's ruling ladder, against a local stub endpoint.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
unset CLAUDE_CONFIG_DIR DFORGE_NO_SETTINGS DFORGE_API_SPEND_FILE AR_SESSION CLAUDE_PROJECT_DIR DFORGE_DECISIONS_TIMEOUT
unset DFORGE_ANTHROPIC_API_KEY DFORGE_AGENTROUTER_API_KEY OPENAI_API_KEY ANTHROPIC_API_KEY
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL GIT_CONFIG_GLOBAL XDG_CONFIG_HOME

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { case "$2" in *"$3"*) check "$1" yes yes ;; *) check "$1" "[$2]" "contains [$3]" ;; esac; }
lacks() { case "$2" in *"$3"*) check "$1" "[$2]" "lacks [$3]" ;; *) check "$1" yes yes ;; esac; }

TMP=$(mktemp -d); stub=""
trap '[ -n "$stub" ] && kill "$stub" 2>/dev/null; rm -rf "$TMP"' EXIT
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
export HOME="$TMP/home" CLAUDE_CODE_SESSION_ID=s1
export DFORGE_OPENAI_API_KEY=sk-test-openai-SENTINEL STUB_DECISIONS_KEY=sk-test-openai-SENTINEL
WORK="$TMP/work"; LOG="$WORK/.dforge/decisions.jsonl"; REQ="$TMP/requests.jsonl"
mkdir -p "$HOME/.dforge" "$HOME/.claude/dforge/sessions/cockpit" "$WORK/docs" "$WORK/.dforge"
DECIDE="$P/scripts/decide"; SPEND="$P/scripts/api-spend"

settings() { printf '%s\n' "$1" > "$HOME/.dforge/config.json"; }
j() { jq -r "$1" | tr -d '\r'; }
printf '%s\n' '{"checked":"2026-11-14","models":{"gpt-6-luna":{"source":"https://example.invalid/pricing","input":0.1}}}' > "$TMP/prices.json"
export DFORGE_API_PRICES="$TMP/prices.json"

git -C "$WORK" init -q
printf '.dforge/\nsecret.env\n' > "$WORK/.gitignore"
printf '# Spec\nThe lock must hold on uutils.\n' > "$WORK/docs/s.md"
printf 'TOKEN=abc\n' > "$WORK/secret.env"
printf 'state note\n' > "$WORK/.dforge/note.md"
git -C "$WORK" add -A
git -C "$WORK" -c user.name=t -c user.email=t@example.invalid commit -qm init
date +%s > "$HOME/.claude/dforge/sessions/cockpit/s1"
(cd "$WORK" && bash "$P/scripts/auto-run" --session s1 start --spec docs/s.md >/dev/null 2>&1)
check "fixture: an auto run is bound to the session" "$( (cd "$WORK" && bash "$P/scripts/auto-run" status >/dev/null 2>&1); echo $?)" "0"

reply() { # reply <choice> <confidence> <reversed choice> <reversed confidence> <needs_more> <guarded>
  jq -n --arg a "$1" --argjson ca "$2" --arg b "$3" --argjson cb "$4" --argjson nm "$5" --argjson g "$6" '{status: 200, body: {answers: [
    {type: "choice", name: "ruling", choice: $a, probabilities: [], confidence: $ca},
    {type: "choice", name: "ruling_reversed", choice: $b, probabilities: [], confidence: $cb},
    {type: "predicate", name: "needs_more", probability: $nm},
    {type: "predicate", name: "guarded", probability: $g}], usage: {input_tokens: 2000000}}}' > "$TMP/reply.json"
}
raw() { printf '%s\n' "$1" > "$TMP/reply.json"; }
reply option_1 0.93 option_1 0.91 0.05 0.02
node "$P/tests/fixtures/stub-decisions/server.mjs" "$TMP/port" "$TMP/reply.json" "$REQ" & stub=$!
for _ in $(seq 1 100); do [ -s "$TMP/port" ] && break; sleep 0.1; done
export DFORGE_DECISIONS_URL="http://127.0.0.1:$(cat "$TMP/port")/v1/decisions"

ask() { out=$(cd "$WORK" && bash "$DECIDE" ask "$@" </dev/null 2>>"$TMP/err"); rc=$?; out=${out//$'\r'/}; printf '%s\n' "$out" >> "$TMP/all.out"; }
sent() { if [ -f "$REQ" ]; then wc -l < "$REQ" | tr -d ' '; else echo 0; fi; }
logged() { if [ -f "$LOG" ]; then wc -l < "$LOG" | tr -d ' '; else echo 0; fi; }
last() { tail -1 "$LOG" | j "$1"; }
spent() { bash "$SPEND" status | tr -d '\r' | sed -n 's/^api-budget openai .* spent=\([0-9.]*\) .*/\1/p'; }
Q=(--id q1 --question "Which lock does the spend file take?" --options "a noclobber lock file | flock")

# --- A1: both orders agree, confidently ---
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
ask "${Q[@]}" --evidence docs/s.md
check "A1: a confident answer in both orders rules, at the lower confidence" "$rc:$out" "0:ruling: a noclobber lock file — Decisions API (confidence 0.91)"
check "A1: one request was sent" "$(sent)" "1"
r=$(tail -1 "$REQ")
check "the request: endpoint, model and the four questions in order" \
  "$(printf '%s' "$r" | j '[.method, .url, .body.model, (.body.questions | map(.name) | join(","))] | join(" ")')" \
  "POST /v1/decisions gpt-6-luna ruling,ruling_reversed,needs_more,guarded"
check "the request: question types" "$(printf '%s' "$r" | j '.body.questions | map(.type) | join(",")')" "choice,choice,predicate,predicate"
check "the request: options in the order given, other last" "$(printf '%s' "$r" | j '.body.questions[0].choices | map(.value) | join(",")')" "option_1,option_2,other"
check "the request: options reversed, other still last" "$(printf '%s' "$r" | j '.body.questions[1].choices | map(.value) | join(",")')" "option_2,option_1,other"
check "the request: a value keeps its option's text in both orders" \
  "$(printf '%s' "$r" | j '[.body.questions[0].choices[1].description, .body.questions[1].choices[0].description] | join(" = ")')" "flock = flock"
check "the request: carries the key as a bearer token" "$(printf '%s' "$r" | j '.authorized')" "true"
has "the request: the input holds the question" "$(printf '%s' "$r" | j '.body.input')" "Which lock does the spend file take?"
has "the request: the input holds the evidence" "$(printf '%s' "$r" | j '.body.input')" "The lock must hold on uutils."
check "A16: the request is charged to openai from its input tokens" "$(spent)" "0.2000"
check "A6: the ask is logged with both answers" \
  "$(last '[.kind, .id, (.options | join("/")), .mode, .outcome, .choice, .choice_reversed, .confidence, .confidence_reversed, .needs_more, .guarded] | map(tostring) | join(" | ")')" \
  "ask | q1 | a noclobber lock file/flock | on | ruled | a noclobber lock file | a noclobber lock file | 0.93 | 0.91 | 0.05 | 0.02"

# --- A2: every way an answer fails to rule ---
while IFS='|' read -r name a ca b cb nm g token; do
  reply "$a" "$ca" "$b" "$cb" "$nm" "$g"
  ask "${Q[@]}"
  check "A2: $name" "$rc:$out" "3:no ruling reason=$token"
done <<'ROWS'
the orders disagree|option_1|0.95|option_2|0.95|0.05|0.02|disagree
the first order answers other|other|0.95|option_1|0.95|0.05|0.02|needs-more
the reversed order answers other|option_1|0.95|other|0.95|0.05|0.02|needs-more
the first confidence is below the setting|option_1|0.84|option_1|0.95|0.05|0.02|low-confidence
the reversed confidence is below the setting|option_1|0.95|option_1|0.84|0.05|0.02|low-confidence
more information is needed|option_1|0.95|option_1|0.95|0.16|0.02|needs-more
an option is guarded|option_1|0.95|option_1|0.95|0.05|0.11|guarded
ROWS
while IFS='|' read -r name ca cb nm g; do
  reply option_2 "$ca" option_2 "$cb" "$nm" "$g"
  ask "${Q[@]}"
  check "the limits are inclusive: $name" "$rc:$out" "0:ruling: flock — Decisions API (confidence 0.85)"
done <<'ROWS'
a confidence at the setting|0.85|0.99|0.05|0.02
needs_more at 0.15|0.99|0.85|0.15|0.02
guarded at 0.10|0.85|0.85|0.05|0.10
ROWS
settings '{"decisionApi":"on","apiBudgetOpenai":10,"decisionConfidence":95}'
reply option_1 0.93 option_1 0.94 0.05 0.02
ask "${Q[@]}"; check "A2: decisionConfidence moves the floor" "$rc:$out" "3:no ruling reason=low-confidence"
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
raw '{"status":200,"body":{"answers":[{"type":"refusal","name":"ruling"},{"type":"choice","name":"ruling_reversed","choice":"option_1","probabilities":[],"confidence":0.95},{"type":"predicate","name":"needs_more","probability":0.05},{"type":"predicate","name":"guarded","probability":0.02}],"usage":{"input_tokens":1000}}}'
ask "${Q[@]}"; check "A2: a refusal" "$rc:$out" "3:no ruling reason=refusal"
raw '{"status":500,"body":{"error":{"message":"boom"}}}'
ask "${Q[@]}"; check "A2: a failed request" "$rc:$out" "3:no ruling reason=error"
raw '{"status":200,"body":{"answers":[{"type":"choice","name":"ruling","choice":"option_1","probabilities":[],"confidence":0.95}]}}'
head -c 200000 /dev/zero | tr '\0' 'a' > "$WORK/mid.txt"
was=$(spent)
ask "${Q[@]}" --evidence mid.txt; check "A2: an answer with a question missing" "$rc:$out" "3:no ruling reason=error"
check "A16: an answer with no usage is charged an estimate, not nothing" "$(awk -v a="$was" -v b="$(spent)" 'BEGIN { print (b > a ? "charged" : "free") }')" "charged"
raw '{"status":200,"delayMs":8000,"body":{}}'
before=$(date +%s)
DFORGE_DECISIONS_TIMEOUT=1 ask "${Q[@]}"
check "A2: no answer inside the timeout" "$rc:$out" "3:no ruling reason=error"
check "the timeout bounds the wait" "$([ $(( $(date +%s) - before )) -lt 8 ] && echo yes || echo no)" "yes"
was=$(spent)
DFORGE_DECISIONS_URL="http://127.0.0.1:1/v1/decisions" ask "${Q[@]}" --evidence mid.txt
check "A2: an endpoint that cannot be reached" "$rc:$out" "3:no ruling reason=error"
check "a request that never reached the endpoint is charged nothing" "$(spent)" "$was"
check "A2: only the four ruling cases above printed a ruling" "$(grep -c '^ruling:' "$TMP/all.out")" "4"

# --- A3: when no request is made ---
reply option_1 0.95 option_1 0.95 0.05 0.02
n=$(sent); l=$(logged)
settings '{"decisionApi":"off","apiBudgetOpenai":10}'
ask "${Q[@]}"; check "A3: off sends and logs nothing" "$rc:$out:$(( $(sent) - n )):$(( $(logged) - l ))" "3:no ruling reason=off:0:0"
settings '{"apiBudgetOpenai":10}'
ask "${Q[@]}"; check "A3: off is the default" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=off:0"
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
CLAUDE_CODE_SESSION_ID=other ask "${Q[@]}"; check "A3: no run bound to the session" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=no-run:0"
settings '{"decisionApi":"on","apiBudgetOpenai":0}'
ask "${Q[@]}"; check "A3: the openai budget is closed" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=closed:0"
check "A6: an ask refused before any request is logged, with no answers" "$(last '[.outcome, .choice, .confidence, .needs_more] | map(tostring) | join(" ")')" "closed null null null"
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
printf '%s\n' '{"checked":"2026-11-14","models":{}}' > "$TMP/noprices.json"
DFORGE_API_PRICES="$TMP/noprices.json" ask "${Q[@]}"; check "no price for the model closes the rung" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=closed:0"
settings '{"decisionApi":"shadow","apiBudgetOpenai":10}'
ask "${Q[@]}"; check "A3: shadow sends the request and never rules" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=shadow:1"
check "A6: shadow logs what the answer would have ruled" "$(last '[.mode, .outcome, .choice] | join(" ")')" "shadow ruled a noclobber lock file"

# --- A4, A5: what may be sent as evidence ---
settings '{"decisionApi":"on","apiBudgetOpenai":10}'
printf 'outside\n' > "$TMP/outside.txt"
mkdir -p "$WORK/vendor/.git"; printf '[remote "origin"]\n' > "$WORK/vendor/.git/config"
head -c 400001 /dev/zero | tr '\0' 'a' > "$WORK/big.txt"
n=$(sent)
while IFS='|' read -r name file; do
  ask "${Q[@]}" --evidence "$file"
  check "A4: $name" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=evidence:0"
done <<ROWS
a file outside the working tree and both roots|$TMP/outside.txt
a file git ignores|secret.env
a file in the git directory|.git/config
a file in a nested repository's git directory|vendor/.git/config
more than 400000 bytes|big.txt
a file that does not exist|docs/missing.md
ROWS
check "A6: a refused evidence file is logged" "$(last '.outcome')" "evidence"
mkdir -p "$WORK/Vendor2/.GIT"; printf '[core]\n' > "$WORK/Vendor2/.GIT/config"
ask "${Q[@]}" --evidence Vendor2/.GIT/config
check "A4: a git directory spelled in capitals" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=evidence:0"
ln -s "$TMP/outside.txt" "$WORK/link.txt" 2>/dev/null
if [ -L "$WORK/link.txt" ]; then
  ask "${Q[@]}" --evidence link.txt
  check "A4: a link inside the working tree to a file outside it" "$rc:$out:$(( $(sent) - n ))" "3:no ruling reason=evidence:0"
fi
ask "${Q[@]}" --evidence docs/s.md --evidence .dforge/note.md
check "A5: a file under the state root is accepted though git ignores it" "$rc:$(( $(sent) - n ))" "0:1"
has "A5: its text is sent" "$(tail -1 "$REQ" | j '.body.input')" "state note"
# The documents root in the darkmem mirror, outside the working tree (the fixture
# tests/dforge-dir.test.sh uses: home, repository, project, documents store, progress store).
. "$HERE/fixtures/darkmem-stores.sh"
M=$(stores_home "$HOME" "$WORK" proj darkmem local)
jq '. + {decisionApi: "on", apiBudgetOpenai: 10}' < "$HOME/.dforge/config.json" > "$TMP/config.json" && mv "$TMP/config.json" "$HOME/.dforge/config.json"
docs=$(cd "$WORK" && bash "$P/scripts/dforge-path" docs | tr -d '\r')
mkdir -p "$docs/specs"; printf 'mirror spec text\n' > "$docs/specs/s.md"
check "fixture: the documents root is outside the working tree" "$(case "$docs" in "$WORK"/*) echo inside ;; *) echo outside ;; esac)" "outside"
ask "${Q[@]}" --evidence "$docs/specs/s.md"
check "A5: a spec under the documents root outside the working tree is accepted" "$rc:$(( $(sent) - n ))" "0:2"
has "A5: the mirror spec's text is sent" "$(tail -1 "$REQ" | j '.body.input')" "mirror spec text"

# --- usage ---
(cd "$WORK" && bash "$DECIDE" ask --question q --options "a | b" 2>/dev/null); check "a missing --id: exit 2" "$?" "2"
(cd "$WORK" && bash "$DECIDE" ask --id q2 --question q --options "only one" 2>/dev/null); check "fewer than two options: exit 2" "$?" "2"
(cd "$WORK" && bash "$DECIDE" ask --id q2 --question q --options "a | other" 2>/dev/null); check "an option named other: exit 2" "$?" "2"
(cd "$WORK" && bash "$DECIDE" frob 2>/dev/null); check "an unknown command: exit 2" "$?" "2"

# --- A7: record and report ---
rec() { (cd "$WORK" && bash "$DECIDE" record "$@" 2>>"$TMP/err"); }
report() { (cd "$WORK" && bash "$DECIDE" report 2>>"$TMP/err") | tr -d '\r'; }
l=$(logged)
rec --id q1 --ruling "flock"; check "A7: record takes a listed option" "$?" "0"
check "A7: the record line" "$(tail -1 "$LOG" | tr -d '\r')" '{"kind":"record","id":"q1","ruling":"flock"}'
rec --id q1 --ruling "other"; check "A7: record takes other" "$?" "0"
rec --id q1 --ruling "a third way"; check "A7: record refuses any other text: exit 2" "$?" "2"
rec --id never-asked --ruling "flock"; check "A7: record refuses an id that was never asked: exit 2" "$?" "2"
check "A7: a refused record writes nothing" "$(( $(logged) - l ))" "2"

ask_line() { # ask_line <id> <confidence> <reversed confidence> <choice> [reversed choice]
  printf '{"kind":"ask","id":"%s","options":["A","B"],"mode":"shadow","outcome":"ruled","choice":"%s","choice_reversed":"%s","confidence":%s,"confidence_reversed":%s,"needs_more":0.05,"guarded":0.02}\n' "$1" "$4" "${5:-$4}" "$2" "$3"
}
rec_line() { printf '{"kind":"record","id":"%s","ruling":"%s"}\n' "$1" "$2"; }
fixture() { # fixture <confident asks> <how many of their records say B>
  : > "$LOG"
  for i in $(seq 1 "$1"); do
    ask_line "c$i" 0.97 0.95 A >> "$LOG"
    if [ "$i" -le "$2" ]; then rec_line "c$i" B >> "$LOG"; else rec_line "c$i" A >> "$LOG"; fi
  done
  ask_line low1 0.75 0.72 A >> "$LOG"; rec_line low1 B >> "$LOG"
  ask_line mid1 0.90 0.82 A >> "$LOG"; rec_line mid1 A >> "$LOG"
  ask_line split1 0.99 0.99 A B >> "$LOG"; rec_line split1 A >> "$LOG"
  ask_line unrecorded 0.99 0.99 A >> "$LOG"
  printf '{"kind":"ask","id":"refused","options":["A","B"],"mode":"shadow","outcome":"evidence","choice":null,"choice_reversed":null,"confidence":null,"confidence_reversed":null,"needs_more":null,"guarded":null}\n' >> "$LOG"
  rec_line refused A >> "$LOG"
}
fixture 19 1
check "A7: report counts matches per band of the lower confidence" "$(report)" \
"band 50-59: 0 recorded, 0 match
band 60-69: 0 recorded, 0 match
band 70-79: 1 recorded, 0 match
band 80-89: 1 recorded, 1 match
band 90-100: 20 recorded, 18 match
promote: no (20 recorded, 90% match)"
fixture 19 0
check "A7: 20 confident items, exactly 95% matching, promote" "$(report | tail -1)" "promote: yes"
fixture 18 0
check "A7: fewer than 20 confident recorded items never promote" "$(report | tail -1)" "promote: no (19 recorded, 94% match)"
: > "$LOG"
check "A7: an empty log" "$(report | tail -1)" "promote: no (0 recorded, 0% match)"
settings '{"decisionApi":"on","apiBudgetOpenai":10,"decisionConfidence":99}'
fixture 20 0
check "A7: decisionConfidence decides which items count toward promotion" "$(report | tail -1)" "promote: no (1 recorded, 0% match)"
settings '{"decisionApi":"on","apiBudgetOpenai":10}'

# --- A8: no key value is printed, logged or stored ---
lacks "A8: no key value in stdout, stderr, the log or the spend file" \
  "$(cat "$TMP/all.out" "$TMP/err" "$LOG" "$HOME/.dforge/api-spend.json" 2>/dev/null)" "SENTINEL"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
