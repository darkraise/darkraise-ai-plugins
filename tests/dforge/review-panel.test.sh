#!/usr/bin/env bash
# run-review-panel runs every open reviewer family at once. Stub gates and
# stub runners stand in for codex-gate, agy-gate and the two runners.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/../../plugins/dforge"
PANEL="$P/scripts/run-review-panel"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
# Without setsid and pgrep (Git Bash) the panel cannot reach a hang runner's
# children, so the suite ends them itself.
TMP=$(mktemp -d); trap 'kill $(cat "$TMP/children" 2>/dev/null) 2>/dev/null; rm -rf "$TMP"' EXIT
export CLAUDE_CODE_SESSION_ID=s1
printf '# r\n' > "$TMP/prompt.md"
mkdir -p "$TMP/work"
for fam in codex agy; do
  cat > "$TMP/$fam-gate" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\${${fam^^}_GATE_LINE:-$fam-gate usable=true reason=ok review=true resets_at=- source=cache}"
EOF
  cat > "$TMP/$fam-runner" <<EOF
#!/usr/bin/env bash
# Records its start and end times, so the test can see overlap.
args="\$*"; out=""; tier=heavy
while [ \$# -gt 0 ]; do case "\$1" in --out) out="\$2"; shift 2 ;; --tier) tier="\$2"; shift 2 ;; *) shift ;; esac; done
printf '%s start %s\n' $fam "\$(date +%s%N)" >> "$TMP/times"
printf '%s\n' "\$args" > "$TMP/$fam.args"
sleep "\${${fam^^}_SLEEP:-1}"
printf '%s end %s\n' $fam "\$(date +%s%N)" >> "$TMP/times"
printf '{}' > "\$out"
model=\$( [ "\$tier" = light ] && echo $( [ $fam = codex ] && echo gpt-6.1-sol/xhigh || echo gemini-4-argon/high) || echo $( [ $fam = codex ] && echo gpt-6-astra/xhigh || echo claude-opus-5-5/high))
printf '%s-judge %s status=%s exit=0 out=%s evidence=none\n' $fam "\$model" "\${${fam^^}_STATUS:-OK}" "\$out"
EOF
  chmod +x "$TMP/$fam-gate" "$TMP/$fam-runner"
done
export PANEL_CODEX_GATE="$TMP/codex-gate" PANEL_AGY_GATE="$TMP/agy-gate" PANEL_CODEX_RUNNER="$TMP/codex-runner" PANEL_AGY_RUNNER="$TMP/agy-runner"
panel() { rm -f "$TMP/times" "$TMP"/*.args; rm -rf "$TMP/out"; out=$(bash "$PANEL" --cwd "$TMP/work" --out-dir "$TMP/out" "$@" 2>"$TMP/err"); rc=$?; }

panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "a task panel prints both reviewers in ranked order and a summary" "$out" "agy-judge claude-opus-5-5/high status=OK exit=0 out=$TMP/out/agy.json evidence=none
codex-judge gpt-6-astra/xhigh status=OK exit=0 out=$TMP/out/codex.json evidence=none
panel tier=heavy lists=2"
check "the panel exits 0" "$rc" "0"
first_end=$(awk '$2 == "end" { print $3; exit }' "$TMP/times")
last_start=$(awk '$2 == "start" { s = $3 } END { print s }' "$TMP/times")
check "both reviewers run at the same time" "$([ "$last_start" -lt "$first_end" ] && echo overlap || echo serial)" "overlap"
check "the heavy tier reaches the runners" "$(grep -c -- '--tier heavy' "$TMP/codex.args" "$TMP/agy.args" | awk -F: '{ s += $2 } END { print s }')" "2"

panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "heavy panel runs Astra and agy Opus" "$(grep -c -e 'gpt-6-astra/xhigh status=OK' -e 'claude-opus-5-5/high status=OK' <<<"$out")" "2"

AGY_STATUS=FALLBACK panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "a FALLBACK runner counts as a list" "$(tail -1 <<<"$out")" "panel tier=heavy lists=2"

AGY_GATE_LINE='agy-gate usable=false reason=setting review=false resets_at=- claude=on claude_resets_at=- source=setting' \
  panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "a closed gate skips its family with the gate's reason" "$(head -1 <<<"$out")" "agy-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=setting"
check "a skipped family is never started" "$([ -f "$TMP/agy.args" ] && echo started || echo skipped)" "skipped"
AGY_GATE_LINE='agy-gate usable=true reason=ok review=false resets_at=- claude=on claude_resets_at=- source=probe' \
  panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "an untrusted surface is skipped as untrusted" "$(head -1 <<<"$out")" "agy-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=untrusted"
CODEX_GATE_LINE='codex-gate usable=false reason=logged-out review=false resets_at=- source=probe' \
AGY_GATE_LINE='agy-gate usable=false reason=quota review=false resets_at=- claude=on claude_resets_at=- source=cache' \
  panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "with both skipped the panel has no list" "$(tail -1 <<<"$out")" "panel tier=heavy lists=0"
check "with both skipped the panel still exits 0" "$rc" "0"
CLAUDE_CODE_SESSION_ID= AGY_GATE_LINE='agy-gate usable=true reason=ok review=false resets_at=- claude=on claude_resets_at=- source=probe' \
  panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "no session id is named as the reason" "$(head -1 <<<"$out" | grep -o 'reason=.*')" "reason=no-session-id"
printf '%s\n' '#!/usr/bin/env bash' 'echo "agy-gate: jq is required" >&2' 'exit 2' > "$TMP/dead-gate"
PANEL_AGY_GATE="$TMP/dead-gate" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "a gate that dies skips its family as gate" "$(head -1 <<<"$out")" "agy-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=gate"
check "a gate's stderr has its own file" "$(cat "$TMP/out/agy.gate.log" 2>/dev/null)" "agy-gate: jq is required"

panel --kind final --tier heavy --base HEAD
check "a final panel writes one list per reviewer" "$(ls "$TMP/out" | grep -c '\.md$')" "2"
check "a final panel never passes --tier" "$(cat "$TMP/codex.args" "$TMP/agy.args" | grep -c -- '--tier')" "0"

panel --kind plan --prompt "$TMP/prompt.md"
check "a plan panel writes one JSON list per reviewer" "$(ls "$TMP/out" | grep -c '\.json$')" "2"
check "a plan panel never passes --tier" "$(cat "$TMP/codex.args" "$TMP/agy.args" | grep -c -- '--tier')" "0"
check "a plan panel runs on the heavy rows" "$(tail -1 <<<"$out")" "panel tier=heavy lists=2"

AGY_STATUS=FAILED panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "each runner's stderr has its own file" "$(ls "$TMP/out"/*.stderr | wc -l | tr -d ' ')" "2"
check "a FAILED runner is not counted as a list" "$(tail -1 <<<"$out")" "panel tier=heavy lists=1"
check "a FAILED runner's out file is removed" "$([ -e "$TMP/out/agy.json" ] && echo kept || echo removed)" "removed"
check "an OK runner's list is kept" "$([ -e "$TMP/out/codex.json" ] && echo kept || echo removed)" "kept"

cat > "$TMP/hang-runner" <<EOF
#!/usr/bin/env bash
out=""; while [ \$# -gt 0 ]; do case "\$1" in --out) out="\$2"; shift 2 ;; *) shift ;; esac; done
sleep 300 & printf '%s\n' \$! > "$TMP/child.pid"; printf '%s\n' \$! >> "$TMP/children"; wait
EOF
chmod +x "$TMP/hang-runner"
PANEL_BOUND_SECONDS=3 PANEL_AGY_RUNNER="$TMP/hang-runner" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "a runner past the bound is reported as TIMEOUT" "$(head -1 <<<"$out")" "agy-judge none/none status=TIMEOUT exit=124 out=$TMP/out/agy.json evidence=none reason=timeout"
if command -v setsid >/dev/null 2>&1; then
  check "the bound kills the runner's children" "$(kill -0 "$(cat "$TMP/child.pid")" 2>/dev/null && echo alive || echo dead)" "dead"
fi
# Called without panel(), which clears the out dir, so an earlier run's list is there.
mkdir -p "$TMP/out"; printf '{"stale":true}' > "$TMP/out/agy.json"
PANEL_BOUND_SECONDS=3 PANEL_AGY_RUNNER="$TMP/hang-runner" bash "$PANEL" --cwd "$TMP/work" --out-dir "$TMP/out" \
  --kind task --tier heavy --prompt "$TMP/prompt.md" >/dev/null 2>&1
check "a timed-out runner leaves no list from an earlier run" "$([ -e "$TMP/out/agy.json" ] && echo stale || echo none)" "none"

cat > "$TMP/slow-gate" <<EOF
#!/usr/bin/env bash
sleep 10
exec bash "$TMP/agy-gate"
EOF
chmod +x "$TMP/slow-gate"
# A 10 s gate against a 10 s bound: counted from panel start the run ends near
# 10 s, counted after the gates at 20 s or more, and 16 s leaves room for slow forks.
t0=$(date +%s)
PANEL_BOUND_SECONDS=10 PANEL_AGY_GATE="$TMP/slow-gate" PANEL_AGY_RUNNER="$TMP/hang-runner" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "the bound counts from panel start, gates included" "$([ $(( $(date +%s) - t0 )) -le 16 ] && echo inside || echo over)" "inside"

for fam in codex agy; do
  cat > "$TMP/$fam-count-gate" <<EOF
#!/usr/bin/env bash
printf '%s\n' $fam >> "$TMP/gates.log"
exec bash "$TMP/$fam-gate"
EOF
  chmod +x "$TMP/$fam-count-gate"
done
: > "$TMP/gates.log"
PANEL_CODEX_GATE="$TMP/codex-count-gate" PANEL_AGY_GATE="$TMP/agy-count-gate" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "one panel run reads each gate once" "$(sort "$TMP/gates.log" | uniq -c | awk '{ printf "%s=%s ", $2, $1 }')" "agy=1 codex=1 "

# Each wrong rule gives another figure: the last rows (485), the graces
# swapped (1190), or a closed family still counted (1180).
printf '%s\n' '```codex-judge' 'gpt-6-astra xhigh 1000' 'gpt-6.1-sol xhigh 300' '```' \
  '```agy-judge' 'claude-opus-5-5 high 900' 'gemini-4-argon high 295' '```' > "$TMP/bound-ladder.md"
bound_of() { grep -o 'bound .*' "$TMP/err" | tr -d '\r'; }
PANEL_LADDER="$TMP/bound-ladder.md" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "the heavy bound takes the first rows" "$(bound_of)" "bound 1180 s, watchdog at 1165 s"
CODEX_GATE_LINE='codex-gate usable=false reason=setting review=false resets_at=- source=setting' \
  PANEL_LADDER="$TMP/bound-ladder.md" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "a skipped family adds nothing to the bound" "$(bound_of)" "bound 1090 s, watchdog at 1075 s"
printf '%s\n' '```codex-judge' 'gpt-6-astra xhigh 30' 'gpt-6.1-sol xhigh 20' '```' > "$TMP/codex-only-ladder.md"
PANEL_LADDER="$TMP/codex-only-ladder.md" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "a family with no ladder block fails as error" "$(head -1 <<<"$out")" "agy-judge none/none status=FAILED exit=0 out=- evidence=none reason=error"
check "and its cause is in its stderr file" "$(grep -c 'agy-judge block' "$TMP/out/agy.stderr" 2>/dev/null)" "1"
check "and the other family still runs" "$(grep -c '^codex-judge .* status=OK ' <<<"$out")" "1"
check "a missing ladder block is no usage error" "$rc" "0"

panel --kind task --prompt "$TMP/prompt.md"
check "a task panel without --tier takes the heavy rows" "$rc|$(tail -1 <<<"$out")" "0|panel tier=heavy lists=2"
panel --kind task --tier light --prompt "$TMP/prompt.md"
check "a task panel names no tier but heavy" "$rc" "2"

# --- without setsid, a timed-out runner leaves no descendant (row 58) ---
# The grandchild is the case today's walk misses: it signals a child before
# listing that child's children, which are reparented once it dies.
cat > "$TMP/tree-runner" <<EOF
#!/usr/bin/env bash
( sleep 300 & printf '%s\n' \$! >> "$TMP/tree-pids"; printf '%s\n' \$! >> "$TMP/children"; wait ) &
printf '%s\n' \$! >> "$TMP/tree-pids"; printf '%s\n' \$! >> "$TMP/children"
wait
EOF
chmod +x "$TMP/tree-runner"
if command -v pgrep >/dev/null 2>&1; then
  : > "$TMP/tree-pids"
  PANEL_NO_SETSID=1 PANEL_BOUND_SECONDS=3 PANEL_AGY_RUNNER="$TMP/tree-runner" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
  check "no setsid: the timed-out runner is reported as TIMEOUT" "$(head -1 <<<"$out" | grep -c 'status=TIMEOUT')" "1"
  alive=0; while read -r p; do kill -0 "$p" 2>/dev/null && alive=$((alive + 1)); done < "$TMP/tree-pids"
  check "no setsid: no child or grandchild survives the timeout" "$alive:$(wc -l < "$TMP/tree-pids" | tr -d ' ')" "0:2"
else
  printf 'skip - no setsid tree walk: pgrep is not on PATH (Git Bash)\n'
fi

# --- without setsid or pgrep the tree cannot be walked, and the panel says so ---
nopgrep_path() { # PATH with no pgrep: a directory holding it stood in for by links to its other programs
  local d f m out='' IFS=:
  for d in $PATH; do
    if [ -x "$d/pgrep" ]; then
      m="$TMP/nopgrep/$(printf '%s' "$d" | tr -c 'A-Za-z0-9' '_')"
      mkdir -p "$m"
      for f in "$d"/*; do [ "${f##*/}" = pgrep ] || ln -s "$f" "$m/" 2>/dev/null; done
      d=$m
    fi
    out=${out:+$out:}$d
  done
  printf '%s\n' "$out"
}
: > "$TMP/tree-pids"
NOPGREP_PATH=$(nopgrep_path)
PATH="$NOPGREP_PATH" PANEL_NO_SETSID=1 PANEL_BOUND_SECONDS=3 PANEL_AGY_RUNNER="$TMP/tree-runner" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "no setsid or pgrep: the panel says the runner's children were not stopped" "$(grep -c 'neither setsid nor pgrep is on PATH' "$TMP/err")" "1"
while read -r p; do kill -KILL "$p" 2>/dev/null; done < "$TMP/tree-pids"

# --- quota skips in an auto run: a runner whose status line names a quota ---
for fam in codex agy; do
  cat > "$TMP/$fam-quota-runner" <<EOF
#!/usr/bin/env bash
echo x >> "$TMP/$fam.calls"
printf '%s-judge %s status=FAILED exit=1 out=- evidence=none reason=quota%s\n' $fam "\${${fam^^}_MODEL:-m/high}" "\${${fam^^}_UNTIL:+ until=\${${fam^^}_UNTIL}}"
EOF
  chmod +x "$TMP/$fam-quota-runner"
done
calls() { wc -l < "$TMP/$1.calls" | tr -d ' '; }
qn=0
runrepo() { # runrepo [STATE] — a fresh checkout Q, with an auto run of s1 when STATE is given; resets the call counts
  qn=$((qn + 1)); Q="$TMP/q$qn"; QS="$Q/.dforge/sdd/auto-run.json"
  git init -q "$Q"
  [ -z "${1:-}" ] || { mkdir -p "$Q/.dforge/sdd"; printf '%s\n' "$1" > "$QS"; }
  : > "$TMP/codex.calls"; : > "$TMP/agy.calls"
}
RUN='{"active":true,"session":"s1","phase":"execute","decisions":[],"rulings":[]}'
qpanel() { # qpanel — the panel with --cwd Q
  out=$(HOME="$TMP/home" DFORGE_NO_SETTINGS=1 bash "$PANEL" --cwd "$Q" --out-dir "$TMP/qout$qn" --kind task --tier heavy --prompt "$TMP/prompt.md" 2>"$TMP/err"); rc=$?
}
skips() { jq -c '[(.reviewSkips // [])[] | [.family, .kind, (if .until == null then null else .until - .failedAt end)]]' "$QS"; }
past() { jq '.reviewSkips[0].until = 1' "$QS" > "$QS.t" && mv "$QS.t" "$QS"; }

# --- quota_skip_in_run ---
runrepo "$RUN"
now=$(date +%s)
CODEX_UNTIL=$((now + 3600)) PANEL_CODEX_RUNNER="$TMP/codex-quota-runner" qpanel
check "quota_skip_in_run: the quota failure records a codex skip until the line's until=" \
  "$(jq -c --argjson u $((now + 3600)) '[.reviewSkips[] | [.family, .until == $u, .kind]]' "$QS")" '[["codex",true,"quota"]]'
PANEL_CODEX_RUNNER="$TMP/codex-quota-runner" qpanel
check "quota_skip_in_run: a second panel within the hour skips codex" "$(grep '^codex-judge' <<<"$out")" \
  "codex-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=quota-skip"
check "quota_skip_in_run: and never runs the codex runner" "$(calls codex)" "1"
check "quota_skip_in_run: the other family still runs" "$(grep -c '^agy-judge claude-opus-5-5/high status=OK' <<<"$out")" "1"
past
PANEL_CODEX_RUNNER="$TMP/codex-quota-runner" qpanel
check "quota_skip_in_run: with until in the past codex runs again" "$(calls codex)" "2"
runrepo "$RUN"
PANEL_CODEX_RUNNER="$TMP/codex-quota-runner" qpanel
check "quota_skip_in_run: with no until the skip lasts 5 hours" "$(skips)" '[["codex","quota",18000]]'

# --- second_quota_failure_skips_run ---
runrepo "$RUN"
CODEX_UNTIL=$(( $(date +%s) + 60 )) PANEL_CODEX_RUNNER="$TMP/codex-quota-runner" qpanel
past
CODEX_UNTIL=$(( $(date +%s) + 60 )) PANEL_CODEX_RUNNER="$TMP/codex-quota-runner" qpanel
check "second_quota_failure_skips_run: the second quota failure skips codex for the rest of the run" "$(skips)" '[["codex","quota",null]]'
PANEL_CODEX_RUNNER="$TMP/codex-quota-runner" qpanel
check "second_quota_failure_skips_run: a later panel skips codex" \
  "$(calls codex):$(grep -c 'codex-judge none/none status=SKIPPED .* reason=quota-skip' <<<"$out")" "2:1"

# --- agy_claude_quota: the gate routes agy to its Gemini row, so nothing is recorded ---
runrepo "$RUN"
AGY_MODEL=claude-opus-5-5/high AGY_UNTIL=$(( $(date +%s) + 3600 )) PANEL_AGY_RUNNER="$TMP/agy-quota-runner" qpanel
check "agy_claude_quota: a Claude-row quota records no skip" "$(skips)" '[]'
AGY_MODEL=gemini-4-argon/high PANEL_AGY_RUNNER="$TMP/agy-quota-runner" qpanel
check "agy_claude_quota: the next panel runs agy again" "$(calls agy)" "2"
check "agy_claude_quota: a Gemini-row quota records the agy skip" "$(skips)" '[["agy","quota",18000]]'

# --- no_run_no_record ---
runrepo
PANEL_CODEX_RUNNER="$TMP/codex-quota-runner" qpanel
check "no_run_no_record: outside an auto run a quota failure writes no state file" "$([ -e "$QS" ] && echo written || echo none)" "none"
PANEL_CODEX_RUNNER="$TMP/codex-quota-runner" qpanel
check "no_run_no_record: and the next panel runs codex" "$(calls codex)" "2"

# --- failures_book_total ---
cat > "$TMP/codex-denied-runner" <<EOF
#!/usr/bin/env bash
printf 'codex-judge m/high status=FAILED exit=1 out=- evidence=none reason=denied\n'
EOF
chmod +x "$TMP/codex-denied-runner"
runrepo "$RUN"
CODEX_STATUS=FAILED PANEL_BOUND_SECONDS=3 PANEL_AGY_RUNNER="$TMP/hang-runner" qpanel
check "failures_book_total: a FAILED and a TIMEOUT line add 2 panel failures" \
  "$(grep -c -e ' status=FAILED ' -e ' status=TIMEOUT ' <<<"$out"):$(jq -r .totals.panelFailures "$QS")" "2:2"
PANEL_CODEX_RUNNER="$TMP/codex-denied-runner" qpanel
check "failures_book_total: a reason=denied line counts too" "$(jq -r .totals.panelFailures "$QS")" "3"
qpanel
check "failures_book_total: OK lines add nothing" "$(jq -r .totals.panelFailures "$QS")" "3"
runrepo '{"active":true,"session":"s2","phase":"execute","decisions":[],"rulings":[]}'
CODEX_STATUS=FAILED qpanel
check "failures_book_total: a run bound to another session books nothing" "$(jq -r '.totals.panelFailures // 0' "$QS")" "0"

# --- hyphen_id_seam: a hyphenated family id reaches its seams ---
rm -rf "$TMP/reg"; mkdir -p "$TMP/reg" "$TMP/home"
cp "$P/reference/executors/codex.json" "$TMP/reg/"
jq '.id = "agy-two"' < "$P/reference/executors/agy.json" > "$TMP/reg/agy-two.json"
cat > "$TMP/agy-two-runner" <<EOF
#!/usr/bin/env bash
out=""; while [ \$# -gt 0 ]; do case "\$1" in --out) out="\$2"; shift 2 ;; *) shift ;; esac; done
printf '{}' > "\$out"
printf 'agy-two-judge claude-opus-5-5/high status=OK exit=0 out=%s evidence=none\n' "\$out"
EOF
chmod +x "$TMP/agy-two-runner"
HOME="$TMP/home" DR_EXECUTORS_DIR="$TMP/reg" PANEL_AGY_TWO_GATE="$TMP/agy-gate" PANEL_AGY_TWO_RUNNER="$TMP/agy-two-runner" \
  panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "hyphen_id_seam" "$(grep '^agy-two-judge' <<<"$out")" "agy-two-judge claude-opus-5-5/high status=OK exit=0 out=$TMP/out/agy-two.json evidence=none"

# --- gate_call_bounded: a gate whose child ignores TERM is killed and skipped ---
printf '%s\n' '#!/usr/bin/env bash' "trap '' TERM" 'sleep 30' > "$TMP/stuck-gate"; chmod +x "$TMP/stuck-gate"
t0=$(date +%s)
PANEL_GATE_SECONDS=1 PANEL_AGY_GATE="$TMP/stuck-gate" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "gate_call_bounded" "$(head -1 <<<"$out")" "agy-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=gate"
check "gate_call_bounded: the panel returns within 15 s" "$([ $(( $(date +%s) - t0 )) -le 15 ] && echo inside || echo over)" "inside"

# --- gate_child_reaped: a gate's child outlives a timeout that signals only the gate ---
# The stub timeout behaves as uutils' does: TERM, then KILL, to the command alone.
if command -v setsid >/dev/null 2>&1; then
  mkdir -p "$TMP/utimeout"
  cat > "$TMP/utimeout/timeout" <<'EOF'
#!/usr/bin/env bash
k=0; [ "$1" = -k ] && { k=$2; shift 2; }
n=$1; shift
"$@" & c=$!
end=$(( $(date +%s) + n ))
while kill -0 "$c" 2>/dev/null && [ "$(date +%s)" -lt "$end" ]; do sleep 0.2; done
kill -0 "$c" 2>/dev/null || { wait "$c"; exit; }
kill -TERM "$c" 2>/dev/null; end=$(( $(date +%s) + k ))
while kill -0 "$c" 2>/dev/null && [ "$(date +%s)" -lt "$end" ]; do sleep 0.2; done
kill -KILL "$c" 2>/dev/null; wait "$c"; exit 124
EOF
  printf '%s\n' '#!/usr/bin/env bash' "trap '' TERM" "sleep 30 & printf '%s\\n' \$! > '$TMP/gate-child.pid'; printf '%s\\n' \$! >> '$TMP/children'" 'wait' > "$TMP/stuck-gate-child"
  chmod +x "$TMP/utimeout/timeout" "$TMP/stuck-gate-child"
  rm -f "$TMP/gate-child.pid"
  PATH="$TMP/utimeout:$PATH" PANEL_GATE_SECONDS=1 PANEL_AGY_GATE="$TMP/stuck-gate-child" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
  gc=$(cat "$TMP/gate-child.pid" 2>/dev/null)
  for _ in $(seq 1 20); do [ -n "$gc" ] && kill -0 "$gc" 2>/dev/null || break; sleep 0.1; done
  check "gate_child_reaped" "$([ -n "$gc" ] && kill -0 "$gc" 2>/dev/null && echo alive || echo dead):$(head -1 <<<"$out" | grep -o 'reason=.*')" "dead:reason=gate"
else
  printf 'skip - gate_child_reaped: setsid is not on PATH\n'
fi

# --- term_escalates_to_kill: a runner that ignores TERM is killed when the panel is ---
if command -v setsid >/dev/null 2>&1; then
  printf '%s\n' '#!/usr/bin/env bash' "trap '' TERM" "printf '%s\\n' \$\$ > '$TMP/runner.pid'; printf '%s\\n' \$\$ >> '$TMP/children'" 'sleep 60' > "$TMP/term-runner"
  chmod +x "$TMP/term-runner"
  rm -f "$TMP/runner.pid"; rm -rf "$TMP/out"
  AGY_GATE_LINE='agy-gate usable=false reason=setting review=false resets_at=- claude=on claude_resets_at=- source=setting' \
    PANEL_CODEX_RUNNER="$TMP/term-runner" bash "$PANEL" --cwd "$TMP/work" --out-dir "$TMP/out" \
    --kind task --tier heavy --prompt "$TMP/prompt.md" >/dev/null 2>&1 &
  pp=$!
  for _ in $(seq 1 100); do [ -s "$TMP/runner.pid" ] && break; sleep 0.1; done
  rp=$(cat "$TMP/runner.pid" 2>/dev/null)
  kill -TERM "$pp" 2>/dev/null
  sleep 10
  check "term_escalates_to_kill" "$([ -n "$rp" ] && kill -0 "$rp" 2>/dev/null && echo alive || echo gone)" "gone"
  kill -KILL "$pp" 2>/dev/null; wait "$pp" 2>/dev/null
else
  printf 'skip - term_escalates_to_kill: setsid is not on PATH\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
