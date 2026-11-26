#!/usr/bin/env bash
# Acceptance checks for docs/dforge/specs/2026-11-25-auto-run-cleanup-and-long-runs-design.md,
# plan 1's script statements (A1, A3-A7, A9-A14, A41, A44, A49; the cockpit
# statements are in auto-run-cleanup-and-long-runs.acceptance.test.ts): a run
# follows its session out of the directory it started in, and the budget acts
# in every phase. Every expectation is a literal from the spec's text.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/../../plugins/dforge" && pwd)"
S="$P/scripts"
AR="$S/auto-run"
TMP="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then TMP=$(cygpath -m "$TMP"); fi
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"
mkdir -p "$HOME/.claude/dforge/sessions/by-id"
export LC_ALL=C MSYS_NO_PATHCONV=1 DFORGE_NO_SETTINGS=1 GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid \
  GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
. "$HERE/fixtures/cockpit-ack.sh"
cockpit_ack_start "$HOME"
unset DFORGE_BIND_WAIT DFORGE_BUDGET DFORGE_JQ DFORGE_FLOCK DR_SUPERPOWERS_BUDGET DR_SUPERPOWERS_JQ CLAUDE_CONFIG_DIR CODEX_HOME \
  CLAUDE_CODE_SESSION_ID AR_SESSION CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA
# A compaction window of 800,000 and a pinned task budget of 300,000 make the
# spec's numbers literal: limit 300k, hard 375k, early compaction at 240k.
printf '{"autoCompactWindow":800000}\n' > "$HOME/.claude/settings.json"
export DFORGE_BUDGET=300000

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
has() { # has <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       missing: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
lacks() { # lacks <name> <haystack> <needle>
  if grep -qF -- "$3" <<<"$2"; then printf 'FAIL - %s\n       unexpected: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1))
  else printf 'ok   - %s\n' "$1"; pass=$((pass + 1)); fi
}
matches() { # matches <name> <haystack> <extended regex>
  if grep -qE -- "$3" <<<"$2"; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       no match: [%s]\n       in: [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

SPEC=docs/dforge/specs/2026-11-26-widget-design.md
PLAN=docs/dforge/plans/2026-11-26-widget.md
RUN="$HOME/.claude/dforge/sessions/run"
repo() { # repo: a fresh repository with one commit; prints its path
  local d
  d=$(mktemp -d "$TMP/r.XXXXXX")
  git init -q -b main "$d"
  git -C "$d" commit -q --allow-empty -m init
  printf '%s\n' "$d"
}
beat() { # beat <session>: the heartbeat a live cockpit writes
  local f
  f="$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"
  mkdir -p "$(dirname "$f")"
  printf '%s\n' "$(date +%s)" > "$f"
}
unbeat() { rm -f "$HOME/.claude/dforge/sessions/cockpit/$(printf '%s' "$1" | tr -c 'A-Za-z0-9' '-')"; }
ar() { # ar <dir> <session> <args...>: auto-run for the session, from dir
  local d=$1 s=$2
  shift 2
  beat "$s"
  (cd "$d" && CLAUDE_CODE_SESSION_ID=$s bash "$AR" --session "$s" "$@")
}
size() { # size <session> <tokens> <cwd>: the session's record and a transcript at that size
  local tp="$TMP/tr-$1.jsonl"
  jq -nc --argjson t "$2" '{type:"assistant",isSidechain:false,message:{model:"claude-opus-5-5",usage:{input_tokens:$t,cache_creation_input_tokens:0,cache_read_input_tokens:0}}}' > "$tp"
  jq -nc --arg s "$1" --arg tp "$tp" --arg cwd "${3:-$TMP}" '{session_id:$s,transcript_path:$tp,cwd:$cwd}' \
    > "$HOME/.claude/dforge/sessions/by-id/$1.json"
}
ctx() { # ctx <dir> <session> <args...>: context-size as that session
  local d=$1 s=$2
  shift 2
  (cd "$d" && CLAUDE_CODE_SESSION_ID=$s bash "$S/context-size" "$@" 2>/dev/null)
}
lastline() { tail -n 1 <<<"$1"; }
verdict() { sed -n 's/.* — \(ok\|compact\|handoff\) — source.*/\1/p' <<<"$1" | tail -n 1; }
limitk() { sed -n 's/.* of \([0-9][0-9]*\)k (.*/\1/p' <<<"$1" | tail -n 1; }
state() { printf '%s/.dforge/sdd/auto-run.json' "$1"; }
field() { jq -r --arg f "$2" '.[$f] | tostring' < "$(state "$1")" | tr -d '\r'; }
sum() { { cksum < "$1"; } 2>/dev/null || echo absent; }
bfield() { jq -r --arg f "$2" '.[$f] | tostring' "$RUN/$1.json" 2>/dev/null | tr -d '\r'; }
mkplan() { # mkplan <dir> <tasks>: spec and plan committed in dir
  local d=$1 n=$2 i
  mkdir -p "$d/docs/dforge/specs" "$d/docs/dforge/plans"
  printf '# Spec\n' > "$d/$SPEC"
  {
    printf '# Widget Implementation Plan\n\n**Spec:** `%s`\n\n' "$SPEC"
    printf '**Execution:** inline — `claude --model sonnet --effort high` — Task 1 scores 4\n\n## Task index\n\n'
    for ((i = 1; i <= n; i++)); do printf '%s. Task %s\n' "$i" "$i"; done
    for ((i = 1; i <= n; i++)); do
      printf '\n### Task %s: Task %s\n\n**Evaluation:** files 0 - spec 0 - coupling 1 - risk 0 = 1\n\nBody.\n' "$i" "$i"
    done
  } > "$d/$PLAN"
  git -C "$d" add -A
  git -C "$d" commit -q -m plan
}
CKPT="done: x; verified: y; remaining: none; discovered: none; assumptions: none"
hook() { # hook <session> <cwd> <last message>: the Stop hook's output
  jq -nc --arg s "$1" --arg c "$2" --arg m "$3" '{hook_event_name:"Stop",session_id:$s,cwd:$c,last_assistant_message:$m}' \
    | bash "$S/turn-end.sh" 2>/dev/null
}

# --- A1 and A44 (hook half): the Stop hook follows the binding ---
b1=$(repo)
a1=$(repo)
ar "$b1" s-a1 start --spec "$SPEC" >/dev/null 2>&1
size s-a1 400000 "$a1"
ar "$b1" s-a1 due --tokens 400000 >/dev/null 2>&1
check "A1: setup, the run in B is pending compact" "$(ar "$b1" s-a1 pending 2>/dev/null)" "compact"
out=$(hook s-a1 "$a1" "Still working on it.")
check "A1: a turn that ends without the pending sentinel is held" "$(jq -r '.decision // "none"' <<<"$out" 2>/dev/null)" "block"
has "A44: the hook's hold message names the run's checkout" "$(jq -r '.reason // ""' <<<"$out" 2>/dev/null)" "cd '$b1' &&"
out=$(hook s-a1 "$a1" $'Compacting now.\n\nAuto run: compacting')
check "A1: a turn that ends on the pending sentinel passes" "$out" ""
size s-a1 400000 "$b1"
out=$(hook s-a1 "$b1" "Still working on it.")
check "A1: setup, a hold in the run's own checkout is still a hold" "$(jq -r '.decision // "none"' <<<"$out" 2>/dev/null)" "block"
lacks "A44: inside the starting directory the hold message has no cd prefix" "$(jq -r '.reason // ""' <<<"$out" 2>/dev/null)" "cd '$b1' &&"
size s-a1 400000 "$a1"
ar "$b1" s-a1 stop --reason "finished" >/dev/null 2>&1
out=$(hook s-a1 "$a1" "Still working on it.")
check "A1: with B's run stopped the hook behaves as it does in A (passes, silent)" "$out" ""

# --- A2 (script half): the cockpit's script calls act on B's run while the session's directory is A ---
b2=$(repo)
a2=$(repo)
mkplan "$b2" 1
ar "$b2" s-a2 start --spec "$SPEC" --isolation in-place >/dev/null 2>&1
ar "$b2" s-a2 attach --plan "$PLAN" >/dev/null 2>&1
(cd "$b2" && bash "$S/next-step" "$PLAN" >/dev/null 2>&1)
size s-a2 400000 "$a2"
ar "$a2" s-a2 due --tokens 400000 >/dev/null 2>&1
check "A2: due from A books the stage on B's run" "$(field "$b2" pending)" "compact"
ar "$a2" s-a2 compacted >/dev/null 2>&1; rc=$?
check "A2: compacted from A succeeds and counts on B's run" "$rc|$(field "$b2" compactions)|$(field "$b2" pending)" "0|1|after-compact"
ar "$b2" s-a2 clear --phase >/dev/null 2>&1; rc=$?
check "A2: clear --phase in the run's checkout succeeds for the session started in A" "$rc|$(field "$b2" pending)" "0|clear"
ar "$b2" s-a2 rebind --to s-a2b >/dev/null 2>&1; rc=$?
check "A2: rebind --to after the clear succeeds and moves B's run to the new session, bound to B" "$rc|$(field "$b2" session)|$(bfield s-a2b primary)" "0|s-a2b|$b2"
check "A2: A holds no state of its own" "$(sum "$(state "$a2")")" "absent"
# the same call made with the session's directory (A) as the working directory
b2c=$(repo)
a2c=$(repo)
mkplan "$b2c" 1
ar "$b2c" s-a2c start --spec "$SPEC" --isolation in-place >/dev/null 2>&1
ar "$b2c" s-a2c attach --plan "$PLAN" >/dev/null 2>&1
(cd "$b2c" && bash "$S/next-step" "$PLAN" >/dev/null 2>&1)
size s-a2c 100000 "$a2c"
ar "$b2c" s-a2c clear --phase >/dev/null 2>&1
ar "$a2c" s-a2c rebind --to s-a2d >/dev/null 2>&1; rc=$?
check "A2: rebind --to run with A as the working directory succeeds and binds the new session to B's run" "$rc|$(field "$b2c" session)|$(bfield s-a2d primary)" "0|s-a2d|$b2c"

# --- A3: a start or resume the cockpit does not echo is undone ---
b3=$(repo)
mkplan "$b3" 1
ar "$b3" s-a3x start --spec "$SPEC" >/dev/null 2>&1
a3home="$TMP/home-a3"
quiet() { # quiet <args...>: auto-run as in a session whose cockpit echoes nothing
  HOME="$a3home" DFORGE_BIND_WAIT=1 "$@"
}
rm -rf "$a3home"
mkdir -p "$a3home"
cp -R "$HOME/.claude" "$a3home/.claude"
sf=$(state "$b3")
st0=$(sum "$sf")
bnd0=$(sum "$a3home/.claude/dforge/sessions/run/s-a3x.json")
out=$(quiet ar "$b3" s-a3y start --spec "$SPEC" --force 2>&1); rc=$?
has "A3: start --force over another run says the cockpit does not see it" "$out" "auto-run: the cockpit in this session does not see this run"
check "A3: start --force exits 2, leaves the state byte-identical, leaves no binding for the caller" \
  "$rc|$(sum "$sf")|$([ -e "$a3home/.claude/dforge/sessions/run/s-a3y.json" ] && echo present || echo absent)" "2|$st0|absent"
out=$(quiet ar "$b3" s-a3x start --spec "$SPEC" --force 2>&1); rc=$?
check "A3: start --force by a bound session exits 2, restores its earlier binding, leaves the state" \
  "$rc|$(sum "$a3home/.claude/dforge/sessions/run/s-a3x.json")|$(sum "$sf")" "2|$bnd0|$st0"
ar "$b3" s-a3x stop --reason "paused" >/dev/null 2>&1
rm -rf "$a3home"
mkdir -p "$a3home"
cp -R "$HOME/.claude" "$a3home/.claude"
st1=$(sum "$sf")
bnd1=$(sum "$a3home/.claude/dforge/sessions/run/s-a3x.json")
out=$(quiet ar "$b3" s-a3x resume 2>&1); rc=$?
has "A3: resume says the cockpit does not see it" "$out" "auto-run: the cockpit in this session does not see this run"
check "A3: resume exits 2, restores the earlier binding and leaves the state byte-identical" \
  "$rc|$(sum "$a3home/.claude/dforge/sessions/run/s-a3x.json")|$(sum "$sf")" "2|$bnd1|$st1"
out=$(quiet ar "$b3" s-a3z resume 2>&1); rc=$?
check "A3: resume by a session with no binding exits 2, leaves no binding and the state" \
  "$rc|$([ -e "$a3home/.claude/dforge/sessions/run/s-a3z.json" ] && echo present || echo absent)|$(sum "$sf")" "2|absent|$st1"
c3=$(repo)
out=$(quiet ar "$c3" s-a3w start --spec "$SPEC" 2>&1); rc=$?
check "A3: a first start with no echo exits 2, writes no state and no binding" \
  "$rc|$(sum "$(state "$c3")")|$([ -e "$a3home/.claude/dforge/sessions/run/s-a3w.json" ] && echo present || echo absent)" "2|absent|absent"

# --- A4: the binding, rebind, and status's cockpit line ---
b4=$(repo)
mkplan "$b4" 1
ar "$b4" s-a4 start --spec "$SPEC" --isolation in-place >/dev/null 2>&1
check "A4: start writes a binding naming the primary with a nonce and a time" \
  "$(bfield s-a4 primary)|$(bfield s-a4 nonce | grep -c .)|$(jq -r '.at | type' "$RUN/s-a4.json" 2>/dev/null)" "$b4|1|number"
n1=$(bfield s-a4 nonce)
ar "$b4" s-a4 stop --reason "pause" >/dev/null 2>&1
ar "$b4" s-a4 resume >/dev/null 2>&1
n2=$(bfield s-a4 nonce)
check "A4: resume writes a binding with a fresh nonce" "$([ -n "$n2" ] && [ "$n1" != "$n2" ] && echo fresh)" "fresh"
has "A4: status prints the cockpit line after an acknowledged bind" "$(ar "$b4" s-a4 status 2>&1)" "cockpit: sees this run"
rm -f "$RUN/s-a4.seen"
has "A4: status says the cockpit does not see the run when .seen is missing" "$(ar "$b4" s-a4 status 2>&1)" "cockpit: does not see this run"
printf '%s' '{"primary":"'"$b4"'","nonce":"another","at":1}' > "$RUN/s-a4.seen"
has "A4: status says the cockpit does not see the run when .seen carries another nonce" "$(ar "$b4" s-a4 status 2>&1)" "cockpit: does not see this run"
lacks "A4: ... and does not claim it sees it" "$(ar "$b4" s-a4 status 2>&1)" "cockpit: sees this run"
# A clear, then rebind to the new session, in a session whose cockpit echoes nothing: no wait.
git -C "$b4" checkout -q -b auto/widget
ar "$b4" s-a4 attach --plan "$PLAN" >/dev/null 2>&1
(cd "$b4" && bash "$S/next-step" "$PLAN" >/dev/null 2>&1)
ar "$b4" s-a4 clear --phase >/dev/null 2>&1; crc=$?
check "A4: setup, a phase clear is booked" "$crc" "0"
a4home="$TMP/home-a4"
rm -rf "$a4home"
mkdir -p "$a4home"
cp -R "$HOME/.claude" "$a4home/.claude"
t0=$(date +%s)
HOME="$a4home" DFORGE_BIND_WAIT=30 ar "$b4" s-a4 rebind --to s-a4n >/dev/null 2>&1; rrc=$?
t1=$(date +%s)
check "A4: rebind --to exits 0 and writes the new session's binding" \
  "$rrc|$(jq -r .primary "$a4home/.claude/dforge/sessions/run/s-a4n.json" 2>/dev/null)|$(jq -r '.nonce | length > 0' "$a4home/.claude/dforge/sessions/run/s-a4n.json" 2>/dev/null)" "0|$b4|true"
check "A4: rebind --to writes the state's new session" "$(field "$b4" session)" "s-a4n"
check "A4: rebind --to does not wait for an acknowledgement" "$([ $((t1 - t0)) -lt 20 ] && echo fast)" "fast"

# --- A5: prompts name the checkout of a run started elsewhere ---
b5=$(repo)
a5=$(repo)
mkplan "$b5" 1
ar "$b5" s-a5 start --spec "$SPEC" --isolation in-place >/dev/null 2>&1
ar "$b5" s-a5 attach --plan "$PLAN" >/dev/null 2>&1
size s-a5 1000 "$a5"
fp() { sed -n '/^Paste as the first prompt/,$p' <<<"$1"; }
ns() { (cd "$b5" && CLAUDE_CODE_SESSION_ID=s-a5 bash "$S/next-step" "$@" 2>&1); }
target=$(ns --target "$PLAN")
check "A5: setup, next-step --target resolves a handoff in B" "$(dirname "$(dirname "$target")")" "$b5/.dforge"
prompt=$(fp "$(ns "$PLAN")")
has "A5: the first prompt it writes names the checkout with cd" "$prompt" "cd '$b5' &&"
lacks "A5: ... and no longer says to enter it first" "$prompt" "enter it first"
handoff=$(fp "$(cat "$target" 2>/dev/null)")
has "A5: the handoff file's first prompt holds the cd prefix" "$handoff" "cd '$b5' &&"
size s-a5 1000 "$b5"
prompt=$(fp "$(ns --print "$PLAN")")
lacks "A5: inside the session's starting directory the prompt has no cd prefix" "$prompt" "cd '$b5' &&"
has "A5: ... and keeps today's wording" "$prompt" "enter it first"
ar "$b5" s-a5 stop --reason "done" >/dev/null 2>&1
size s-a5 1000 "$a5"
prompt=$(fp "$(ns --print "$PLAN")")
lacks "A5: outside an auto run the prompt has no cd prefix" "$prompt" "cd '$b5' &&"
has "A5: ... and keeps today's wording outside a run" "$prompt" "enter it first"

# --- A6: the run log survives the next start ---
b6=$(repo)
mkplan "$b6" 1
git -C "$b6" checkout -q -b auto/widget
ar "$b6" s-a6 start --spec "$SPEC" --isolation in-place >/dev/null 2>&1
ar "$b6" s-a6 attach --plan "$PLAN" >/dev/null 2>&1
(cd "$b6" && bash "$S/next-step" "$PLAN" >/dev/null 2>&1)
size s-a6 100000 "$b6"
ar "$b6" s-a6 compacted >/dev/null 2>&1
ar "$b6" s-a6 clear --phase >/dev/null 2>&1
ar "$b6" s-a6 rebind --to s-a6b >/dev/null 2>&1
ar "$b6" s-a6b stop --reason "the disk is full" >/dev/null 2>&1
ar "$b6" s-a6c start --spec "$SPEC" --isolation in-place >/dev/null 2>&1; src=$?
check "A6: setup, a later start replaces the state file" "$src|$(field "$b6" session)|$(field "$b6" stopped)" "0|s-a6c|null"
log=$(ar "$b6" s-a6c log 2>&1); lrc=$?
check "A6: log exits 0" "$lrc" "0"
matches "A6: the log prints the earlier run's start" "$log" $'\tstart\ts-a6\t'
matches "A6: ... a compaction" "$log" $'\tcompact[a-z]*\ts-a6\t'
matches "A6: ... a clear" "$log" $'\tclear\ts-a6\t'
matches "A6: ... the stop with its reason" "$log" $'\tstop\ts-a6b\t[^\t]*\t.*the disk is full'
first=$(grep -n $'\tstart\ts-a6\t' <<<"$log" | head -n 1 | cut -d: -f1)
stopn=$(grep -n 'the disk is full' <<<"$log" | head -n 1 | cut -d: -f1)
second=$(grep -n $'\tstart\ts-a6c\t' <<<"$log" | head -n 1 | cut -d: -f1)
check "A6: the rows keep their order, the new start last" "$([ "$first" -lt "$stopn" ] && [ "$stopn" -lt "$second" ] && echo ordered)" "ordered"

# --- A7: preflight ---
b7=$(repo)
out=$(cd "$b7" && bash "$AR" preflight --isolation worktree 2>&1); rc=$?
check "A7: with nothing to report preflight exits 0" "$rc" "0"
check "A7: ... and prints preflight: ok" "$(grep -c '^preflight: ok$' <<<"$out")" "1"
reviews=$(grep -c '^preflight: review ' <<<"$out")
check "A7: one line per external review family" "$reviews|$(grep -c '^preflight: review agy' <<<"$out")|$(grep -c '^preflight: review codex' <<<"$out")" "2|1|1"
for fam in agy codex; do
  gate=$(HOME="$TMP/none" bash "$S/$fam-gate" 2>/dev/null | head -n 1 | tr -d '\r')
  line=$(grep "^preflight: review $fam" <<<"$out")
  has "A7: the $fam line carries the gate's answer" "$line" "${gate#"$fam-gate "}"
  has "A7: ... and the setting" "$line" "setting off"
done
mkdir -p "$HOME/.dforge"
printf '{"codexReview":true}\n' > "$HOME/.dforge/config.json"
out=$(cd "$b7" && env -u DFORGE_NO_SETTINGS bash "$AR" preflight --isolation in-place 2>&1)
has "A7: a review family whose setting is on says so" "$(grep '^preflight: review codex' <<<"$out")" "setting on"
has "A7: ... and a family whose setting is off still says so" "$(grep '^preflight: review agy' <<<"$out")" "setting off"
rm -rf "$HOME/.dforge"
out=$(cd "$b7" && DFORGE_PREFLIGHT_FREE=100 bash "$AR" preflight --isolation in-place 2>&1); rc=$?
check "A7: free space below the threshold gives a line, exit 0, and no ok line" \
  "$rc|$([ "$(grep -c 'free space' <<<"$out")" -ge 1 ] && echo line)|$(grep -c '^preflight: ok$' <<<"$out")" "0|line|0"
git -C "$b7" update-ref refs/dforge/preflight/blocker HEAD
out=$(cd "$b7" && bash "$AR" preflight --isolation in-place 2>&1); rc=$?
check "A7: a refused git write in the primary checkout gives a line, exit 0, and no ok line" \
  "$rc|$(grep -ci 'git write' <<<"$out")|$(grep -c '^preflight: ok$' <<<"$out")" "0|1|0"
git -C "$b7" update-ref -d refs/dforge/preflight/blocker
b7w=$(repo)
printf 'not a directory\n' > "$b7w/.worktrees"
out=$(cd "$b7w" && bash "$AR" preflight --isolation worktree 2>&1); rc=$?
check "A7: with --isolation worktree a scratch worktree that cannot be added gives a line, exit 0, and no ok line" \
  "$rc|$(grep -ci 'worktree' <<<"$(grep -v '^preflight: review' <<<"$out")")|$(grep -c '^preflight: ok$' <<<"$out")" "0|1|0"
out=$(cd "$b7w" && bash "$AR" preflight --isolation in-place 2>&1)
check "A7: with --isolation in-place no worktree line is printed" "$(grep -ci 'worktree' <<<"$(grep -v '^preflight: review' <<<"$out")")" "0"

# --- A9: the limit holds in every phase ---
newrun() { # newrun <dir> <session> <phase>: a fresh run in that phase
  ar "$1" "$2" start --spec "$SPEC" --force >/dev/null 2>&1
  [ "$3" = spec ] || ar "$1" "$2" phase "$3" >/dev/null 2>&1
}
b9=$(repo)
for ph in plan final finish; do
  s=s-a9-$ph
  newrun "$b9" "$s" "$ph"
  size "$s" 310000 "$b9"
  out=$(ctx "$b9" "$s"); rc=$?
  check "A9: in $ph at the limit context-size exits 6 with compact" "$rc|$(verdict "$out")" "6|compact"
  ar "$b9" "$s" compacted >/dev/null 2>&1
  size "$s" 100000 "$b9"
  ar "$b9" "$s" after-compact >/dev/null 2>&1
  size "$s" 310000 "$b9"
  out=$(ctx "$b9" "$s"); rc=$?
  check "A9: in $ph after a compaction has run, the size back at the limit still exits 6 with compact" "$rc|$(verdict "$out")" "6|compact"
done
newrun "$b9" s-a9-ff final
size s-a9-ff 310000 "$b9"
out=$(ctx "$b9" s-a9-ff --final); rc=$?
check "A9: in final, context-size --final exits 6 with compact" "$rc|$(verdict "$out")" "6|compact"
newrun "$b9" s-a9-fn finish
size s-a9-fn 310000 "$b9"
out=$(ctx "$b9" s-a9-fn --finish); rc=$?
check "A9: in finish, context-size --finish exits 6 with compact" "$rc|$(verdict "$out")" "6|compact"
for ph in spec plan final finish; do
  s=s-a9-hi-$ph
  newrun "$b9" "$s" "$ph"
  size "$s" 310000 "$b9"
  ar "$b9" "$s" compacted >/dev/null 2>&1
  size "$s" 260000 "$b9"
  ar "$b9" "$s" after-compact >/dev/null 2>&1
  out=$(ctx "$b9" "$s")
  has "A9: in $ph a compaction that leaves 260k puts the run in the high regime" "$out" "budget (auto, high)"
  lim=$(limitk "$out")
  check "A9: in $ph the high regime's limit never exceeds hard (375k)" "$([ -n "$lim" ] && [ "$lim" -le 375 ] && echo within)" "within"
done
for ph in spec plan final finish; do
  s=s-a9-cap-$ph
  newrun "$b9" "$s" "$ph"
  size "$s" 310000 "$b9"
  rcs=""
  for _ in 1 2 3; do ar "$b9" "$s" compacted >/dev/null 2>&1; rcs="$rcs$?"; done
  reason=$(field "$b9" stopped)
  matches "A9: in $ph the run stops at the cap with its reason" "$rcs|$(field "$b9" active)|$reason" "^[0-9]*5[|]false[|][0-9]+ compactions in $ph without progress$"
done
# progress restarts the count: two compactions, progress, two more
plan9=$(repo)
mkplan "$plan9" 2
git -C "$plan9" checkout -q -b auto/widget
progress_case() { # progress_case <name> <phase> <progress command>
  local name=$1 ph=$2 s=s-a9-pg-$1 first second
  ar "$plan9" "$s" start --spec "$SPEC" --isolation in-place --force >/dev/null 2>&1
  ar "$plan9" "$s" attach --plan "$PLAN" >/dev/null 2>&1
  [ "$ph" = spec ] || ar "$plan9" "$s" phase "$ph" >/dev/null 2>&1
  size "$s" 310000 "$plan9"
  first=""
  for _ in 1 2; do ar "$plan9" "$s" compacted >/dev/null 2>&1; first="$first$?"; done
  (cd "$plan9" && eval "$3")
  second=""
  for _ in 1 2; do ar "$plan9" "$s" compacted >/dev/null 2>&1; second="$second$?"; done
  check "A9: $name between two compactions restarts the count" "$first$second|$(field "$plan9" active)" "0000|true"
}
LEDGER="$plan9/.dforge/sdd/2026-11-26-widget/progress.md"
mkdir -p "$(dirname "$LEDGER")"
printf '# SDD ledger — plan: %s\n' "$PLAN" > "$LEDGER"
progress_case "a ledger line" final 'printf "Task 1: implementer inline (assigned; base abc1234)\n" >> "$LEDGER"'
progress_case "a commit" final 'git commit -q --allow-empty -m progress'
progress_case "a saved draft (the spec)" spec 'touch -d "2031-01-02 03:04:05" "$SPEC"'
progress_case "a saved draft (the plan)" plan 'touch -d "2032-01-02 03:04:05" "$PLAN"'
ar "$plan9" s-a9-nop start --spec "$SPEC" --isolation in-place --force >/dev/null 2>&1
ar "$plan9" s-a9-nop attach --plan "$PLAN" >/dev/null 2>&1
ar "$plan9" s-a9-nop phase final >/dev/null 2>&1
size s-a9-nop 310000 "$plan9"
rcs=""
for _ in 1 2 3; do ar "$plan9" s-a9-nop compacted >/dev/null 2>&1; rcs="$rcs$?"; done
check "A9: the same three compactions with no progress stop the run" "$rcs|$(field "$plan9" active)" "005|false"

# --- A10 (script half): due books compact at the limit and prints the limit the next budget line uses ---
b10=$(repo)
for ph in spec plan final finish; do
  s=s-a10-$ph
  newrun "$b10" "$s" "$ph"
  size "$s" 300000 "$b10"
  out=$(ar "$b10" "$s" due --tokens 300000 2>&1)
  check "A10: in $ph due at the limit books compact" "$(ar "$b10" "$s" pending 2>&1)" "compact"
  dl=$(sed -n 's/.*limit[= ]*\([0-9][0-9]*\).*/\1/p' <<<"$out" | head -n 1)
  bl=$(limitk "$(ctx "$b10" "$s")")
  check "A10: in $ph the limit due prints is the limit of the next budget line" "$dl|$((dl / 1000))" "300000|$bl"
done
newrun "$b10" s-a10-hi plan
size s-a10-hi 310000 "$b10"
ar "$b10" s-a10-hi compacted >/dev/null 2>&1
size s-a10-hi 260000 "$b10"
ar "$b10" s-a10-hi after-compact >/dev/null 2>&1
out=$(ar "$b10" s-a10-hi due --tokens 100000 2>&1)
dl=$(sed -n 's/.*limit[= ]*\([0-9][0-9]*\).*/\1/p' <<<"$out" | head -n 1)
check "A10: in the high regime due prints the limit of the next budget line" "$((dl / 1000))" "$(limitk "$(ctx "$b10" s-a10-hi)")"

# --- A11: early compaction at a task boundary, in execute ---
b11=$(repo)
mkplan "$b11" 4
ar "$b11" s-a11 start --spec "$SPEC" --isolation in-place >/dev/null 2>&1
ar "$b11" s-a11 attach --plan "$PLAN" >/dev/null 2>&1
git -C "$b11" checkout -q -b auto/widget
ar "$b11" s-a11 setup-branch auto/widget >/dev/null 2>&1
ar "$b11" s-a11 phase execute >/dev/null 2>&1
check "A11: setup, the run is in execute" "$(field "$b11" phase)" "execute"
brief() { (cd "$b11" && CLAUDE_CODE_SESSION_ID=s-a11 bash "$S/task-brief" --open "$PLAN" "$1" 2>&1); }
close() { (cd "$b11" && CLAUDE_CODE_SESSION_ID=s-a11 bash "$S/task-close" "$PLAN" "$1" "$CKPT" 2>&1); }
size s-a11 239999 "$b11"
check "A11: task-brief at 239,999 of a 300k budget says ok" "$(verdict "$(lastline "$(brief 1)")")" "ok"
check "A11: task-close at 239,999 says ok" "$(verdict "$(lastline "$(close 1)")")" "ok"
size s-a11 240000 "$b11"
check "A11: task-brief at 240,000 says compact" "$(verdict "$(lastline "$(brief 2)")")" "compact"
check "A11: task-close at 240,000 says compact" "$(verdict "$(lastline "$(close 2)")")" "compact"
size s-a11 159999 "$b11"
check "A11: a 200k budget moves the point to 160k: task-brief at 159,999 says ok" "$(verdict "$(lastline "$(DFORGE_BUDGET=200000 brief 3)")")" "ok"
size s-a11 160000 "$b11"
check "A11: ... and task-close at 160,000 says compact" "$(verdict "$(lastline "$(DFORGE_BUDGET=200000 close 3)")")" "compact"

# --- A12: strict mode outside an auto run ---
b12=$(repo)
size s-a12 100000 "$b12"
vd() { # vd <tokens> <budget> <context-size args...>: verdict and exit status
  local t=$1 b=$2 out rc
  shift 2
  size s-a12 "$t" "$b12"
  out=$(DFORGE_BUDGET=$b ctx "$b12" s-a12 "$@"); rc=$?
  printf '%s|%s' "$(verdict "$out")" "$rc"
}
for mode in "--final" "--tail 1" "--tail 2" "--plan" "--finish"; do
  check "A12: $mode says ok past the budget (310k) but below hard" "$(vd 310000 300000 $mode)" "ok|0"
  check "A12: $mode says ok at 374,999 (hard is 375k)" "$(vd 374999 300000 $mode)" "ok|0"
  check "A12: $mode says handoff at hard (375,000)" "$(vd 375000 300000 $mode)" "handoff|5"
  check "A12: $mode follows a 200k budget: ok at 249,999, handoff at 250,000" "$(vd 249999 200000 $mode)/$(vd 250000 200000 $mode)" "ok|0/handoff|5"
done
# 93% of the 800,000 window is 744,000; 1.25 x 600,000 would pass it.
check "A12: hard stays 40,000 below the compaction point: a 600k budget is ok at 703,999, handoff at 704,000" "$(vd 703999 600000 --final)/$(vd 704000 600000 --final)" "ok|0/handoff|5"
check "A12: an ordinary task past the budget still says handoff" "$(vd 310000 300000)" "handoff|5"
check "A12: an ordinary task below the budget says ok" "$(vd 290000 300000)" "ok|0"

# --- A13: the budget line is the last line of these verbs ---
b13=$(repo)
mkplan "$b13" 2
size s-a13 100000 "$b13"
ar "$b13" s-a13 start --spec "$SPEC" --isolation in-place >/dev/null 2>&1
isbudget() { case $(lastline "$1") in 'budget (auto'*) echo budget ;; *) echo "other: $(lastline "$1")" ;; esac; }
nobudget() { if grep -q '^budget' <<<"$1"; then echo budget; else echo none; fi; }
out=$(CLAUDE_CODE_SESSION_ID=s-a13 ar "$b13" s-a13 phase plan 2>&1); rc=$?
check "A13: phase plan prints the budget line last and exits 0" "$(isbudget "$out")|$rc" "budget|0"
out=$(ar "$b13" s-a13 attach --plan "$PLAN" 2>&1); rc=$?
check "A13: attach prints no budget line" "$(nobudget "$out")|$rc" "none|0"
git -C "$b13" checkout -q -b auto/widget
ar "$b13" s-a13 setup-branch auto/widget >/dev/null 2>&1
out=$(ar "$b13" s-a13 phase execute 2>&1); rc=$?
check "A13: phase execute prints the budget line last and exits 0" "$(isbudget "$out")|$rc" "budget|0"
out=$(ar "$b13" s-a13 ruling add "a ruling" 2>&1); rc=$?
check "A13: ruling add prints the budget line last and exits 0" "$(isbudget "$out")|$rc" "budget|0"
out=$(ar "$b13" s-a13 task-complete 2>&1); rc=$?
check "A13: task-complete prints the budget line last and exits 0" "$(isbudget "$out")|$rc" "budget|0"
out=$(ar "$b13" s-a13 phase final 2>&1); rc=$?
check "A13: phase final prints the budget line last and exits 0" "$(isbudget "$out")|$rc" "budget|0"
out=$(ar "$b13" s-a13 phase finish 2>&1); rc=$?
check "A13: phase finish prints no budget line and exits 0" "$(nobudget "$out")|$rc" "none|0"

# --- A14 (script half): below the limit nothing is booked ---
b14=$(repo)
for ph in spec plan final finish; do
  s=s-a14-$ph
  newrun "$b14" "$s" "$ph"
  size "$s" 299999 "$b14"
  ar "$b14" "$s" due --tokens 299999 >/dev/null 2>&1
  check "A14: in $ph below the limit due books nothing" "$(ar "$b14" "$s" pending 2>&1)|$(field "$b14" pending)" "none|null"
  ctx "$b14" "$s" >/dev/null
  check "A14: in $ph below the limit the budget line books nothing either" "$(ar "$b14" "$s" pending 2>&1)|$(field "$b14" pending)" "none|null"
done

# --- A41: a bound session works from another repository ---
b41=$(repo)
a41=$(repo)
ar "$b41" s-a41 start --spec "$SPEC" >/dev/null 2>&1
size s-a41 100000 "$a41"
outA=$(ar "$a41" s-a41 status 2>&1); rcA=$?
outB=$(ar "$b41" s-a41 status 2>&1); rcB=$?
check "A41: status from A acts on B's run and exits as it does in B" "$rcA|$outA" "$rcB|$outB"
has "A41: ... and it names B's run" "$outA" "$SPEC"
check "A41: A has no state file of its own after it" "$(sum "$(state "$a41")")" "absent"
ar "$b41" s-a41 compacted >/dev/null 2>&1
outA=$(ar "$a41" s-a41 after-compact 2>&1); rcA=$?
ar "$b41" s-a41 compacted >/dev/null 2>&1
outB=$(ar "$b41" s-a41 after-compact 2>&1); rcB=$?
check "A41: after-compact from A acts on B's run and exits as it does in B" "$rcA|$outA" "$rcB|$outB"
check "A41: ... and it found the run (not exit 3)" "$([ "$rcA" != 3 ] && echo found)" "found"
before=$(sum "$(state "$b41")")
out=$(ar "$a41" s-a41 task-complete 2>&1); rc=$?
check "A41: task-complete from A exits 7 and names B's checkout" "$rc|$out" "7|auto-run: run this from the run's checkout: cd '$b41' && …"
out=$(ar "$a41" s-a41 phase final 2>&1); rc=$?
check "A41: phase final from A exits 7 and names B's checkout" "$rc|$out" "7|auto-run: run this from the run's checkout: cd '$b41' && …"
check "A41: neither changed B's state file" "$(sum "$(state "$b41")")" "$before"
# resume and stop --stale act on the repository they run in
ar "$a41" s-a41-u start --spec "$SPEC" >/dev/null 2>&1
unbeat s-a41-u
before=$(sum "$(state "$b41")")
out=$(ar "$a41" s-a41 stop --stale 2>&1); rc=$?
check "A41: stop --stale from A stops A's run whatever S's binding names" "$rc|$(field "$a41" active)|$(sum "$(state "$b41")")|$(field "$b41" active)" "0|false|$before|true"
out=$(ar "$a41" s-a41 resume 2>&1); rc=$?
check "A41: resume in A resumes A's run for the caller, and B's state stays" "$rc|$(field "$a41" active)|$(field "$a41" session)|$(sum "$(state "$b41")")" "0|true|s-a41|$before"

# --- A49: a start elsewhere never touches the finished run the binding names ---
b49=$(repo)
a49=$(repo)
ar "$b49" s-a49 start --spec "$SPEC" >/dev/null 2>&1
ar "$b49" s-a49 stop --reason "finished" >/dev/null 2>&1
before=$(sum "$(state "$b49")")
out=$(ar "$a49" s-a49 start --spec "$SPEC" 2>&1); rc=$?
check "A49: start in A by a session bound to B's finished run succeeds and writes A's state" \
  "$rc|$(field "$a49" active)|$(field "$a49" session)" "0|true|s-a49"
check "A49: B's state file is byte-identical" "$(sum "$(state "$b49")")" "$before"
check "A49: the session's binding names A now" "$(bfield s-a49 primary)" "$a49"

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
