#!/usr/bin/env bash
# run-review-panel runs every open reviewer family at once. Stub gates and
# stub runners stand in for codex-gate, agy-gate and the two runners.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$HERE/.."
PANEL="$P/scripts/run-review-panel"
pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
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

panel --kind task --tier light --prompt "$TMP/prompt.md"
check "light panel prints both reviewers in ranked order and a summary" "$out" "agy-judge gemini-4-argon/high status=OK exit=0 out=$TMP/out/agy.json evidence=none
codex-judge gpt-6.1-sol/xhigh status=OK exit=0 out=$TMP/out/codex.json evidence=none
panel tier=light lists=2"
check "the panel exits 0" "$rc" "0"
first_end=$(awk '$2 == "end" { print $3; exit }' "$TMP/times")
last_start=$(awk '$2 == "start" { s = $3 } END { print s }' "$TMP/times")
check "both reviewers run at the same time" "$([ "$last_start" -lt "$first_end" ] && echo overlap || echo serial)" "overlap"
check "the light tier reaches the runners" "$(grep -c -- '--tier light' "$TMP/codex.args" "$TMP/agy.args" | awk -F: '{ s += $2 } END { print s }')" "2"

panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "heavy panel runs Astra and agy Opus" "$(grep -c -e 'gpt-6-astra/xhigh status=OK' -e 'claude-opus-5-5/high status=OK' <<<"$out")" "2"

AGY_STATUS=FALLBACK panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "a FALLBACK runner counts as a list" "$(tail -1 <<<"$out")" "panel tier=heavy lists=2"

AGY_GATE_LINE='agy-gate usable=false reason=setting review=false resets_at=- claude=on claude_resets_at=- source=setting' \
  panel --kind task --tier light --prompt "$TMP/prompt.md"
check "a closed gate skips its family with the gate's reason" "$(head -1 <<<"$out")" "agy-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=setting"
check "a skipped family is never started" "$([ -f "$TMP/agy.args" ] && echo started || echo skipped)" "skipped"
AGY_GATE_LINE='agy-gate usable=true reason=ok review=false resets_at=- claude=on claude_resets_at=- source=probe' \
  panel --kind task --tier light --prompt "$TMP/prompt.md"
check "an untrusted surface is skipped as untrusted" "$(head -1 <<<"$out")" "agy-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=untrusted"
CODEX_GATE_LINE='codex-gate usable=false reason=logged-out review=false resets_at=- source=probe' \
AGY_GATE_LINE='agy-gate usable=false reason=quota review=false resets_at=- claude=on claude_resets_at=- source=cache' \
  panel --kind task --tier light --prompt "$TMP/prompt.md"
check "with both skipped the panel has no list" "$(tail -1 <<<"$out")" "panel tier=light lists=0"
check "with both skipped the panel still exits 0" "$rc" "0"
CLAUDE_CODE_SESSION_ID= AGY_GATE_LINE='agy-gate usable=true reason=ok review=false resets_at=- claude=on claude_resets_at=- source=probe' \
  panel --kind task --tier light --prompt "$TMP/prompt.md"
check "no session id is named as the reason" "$(head -1 <<<"$out" | grep -o 'reason=.*')" "reason=no-session-id"
printf '%s\n' '#!/usr/bin/env bash' 'echo "agy-gate: jq is required" >&2' 'exit 2' > "$TMP/dead-gate"
PANEL_AGY_GATE="$TMP/dead-gate" panel --kind task --tier light --prompt "$TMP/prompt.md"
check "a gate that dies skips its family as gate" "$(head -1 <<<"$out")" "agy-judge none/none status=SKIPPED exit=0 out=- evidence=none reason=gate"
check "a gate's stderr has its own file" "$(cat "$TMP/out/agy.gate.log" 2>/dev/null)" "agy-gate: jq is required"

panel --kind final --tier heavy --base HEAD
check "a final panel writes one list per reviewer" "$(ls "$TMP/out" | grep -c '\.md$')" "2"
check "a final panel never passes --tier" "$(cat "$TMP/codex.args" "$TMP/agy.args" | grep -c -- '--tier')" "0"

AGY_STATUS=FAILED panel --kind task --tier light --prompt "$TMP/prompt.md"
check "each runner's stderr has its own file" "$(ls "$TMP/out"/*.stderr | wc -l | tr -d ' ')" "2"
check "a FAILED runner is not counted as a list" "$(tail -1 <<<"$out")" "panel tier=light lists=1"
check "a FAILED runner's out file is removed" "$([ -e "$TMP/out/agy.json" ] && echo kept || echo removed)" "removed"
check "an OK runner's list is kept" "$([ -e "$TMP/out/codex.json" ] && echo kept || echo removed)" "kept"

cat > "$TMP/hang-runner" <<EOF
#!/usr/bin/env bash
out=""; while [ \$# -gt 0 ]; do case "\$1" in --out) out="\$2"; shift 2 ;; *) shift ;; esac; done
sleep 300 & printf '%s\n' \$! > "$TMP/child.pid"; wait
EOF
chmod +x "$TMP/hang-runner"
PANEL_BOUND_SECONDS=3 PANEL_AGY_RUNNER="$TMP/hang-runner" panel --kind task --tier light --prompt "$TMP/prompt.md"
check "a runner past the bound is reported as TIMEOUT" "$(head -1 <<<"$out")" "agy-judge none/none status=TIMEOUT exit=124 out=$TMP/out/agy.json evidence=none reason=timeout"
if command -v setsid >/dev/null 2>&1; then
  check "the bound kills the runner's children" "$(kill -0 "$(cat "$TMP/child.pid")" 2>/dev/null && echo alive || echo dead)" "dead"
fi
# Called without panel(), which clears the out dir, so an earlier run's list is there.
mkdir -p "$TMP/out"; printf '{"stale":true}' > "$TMP/out/agy.json"
PANEL_BOUND_SECONDS=3 PANEL_AGY_RUNNER="$TMP/hang-runner" bash "$PANEL" --cwd "$TMP/work" --out-dir "$TMP/out" \
  --kind task --tier light --prompt "$TMP/prompt.md" >/dev/null 2>&1
check "a timed-out runner leaves no list from an earlier run" "$([ -e "$TMP/out/agy.json" ] && echo stale || echo none)" "none"

cat > "$TMP/slow-gate" <<EOF
#!/usr/bin/env bash
sleep 3
exec bash "$TMP/agy-gate"
EOF
chmod +x "$TMP/slow-gate"
t0=$(date +%s)
PANEL_BOUND_SECONDS=3 PANEL_AGY_GATE="$TMP/slow-gate" PANEL_AGY_RUNNER="$TMP/hang-runner" panel --kind task --tier light --prompt "$TMP/prompt.md"
check "the bound counts from panel start, gates included" "$([ $(( $(date +%s) - t0 )) -le 5 ] && echo inside || echo over)" "inside"

for fam in codex agy; do
  cat > "$TMP/$fam-count-gate" <<EOF
#!/usr/bin/env bash
printf '%s\n' $fam >> "$TMP/gates.log"
exec bash "$TMP/$fam-gate"
EOF
  chmod +x "$TMP/$fam-count-gate"
done
: > "$TMP/gates.log"
PANEL_CODEX_GATE="$TMP/codex-count-gate" PANEL_AGY_GATE="$TMP/agy-count-gate" panel --kind task --tier light --prompt "$TMP/prompt.md"
check "one panel run reads each gate once" "$(sort "$TMP/gates.log" | uniq -c | awk '{ printf "%s=%s ", $2, $1 }')" "agy=1 codex=1 "
check "the agy runner makes no roster probe" "$(grep -c 'detect-executors' "$P/scripts/run-agy-review.sh")" "0"

# Each wrong rule gives another figure: the first row on light (1180), the
# graces swapped (490), or a closed family still counted (485).
printf '%s\n' '```codex-judge' 'gpt-6-astra xhigh 1000' 'gpt-6.1-sol xhigh 300' '```' \
  '```agy-judge' 'claude-opus-5-5 high 900' 'gemini-4-argon high 295' '```' > "$TMP/bound-ladder.md"
bound_of() { grep -o 'bound .*' "$TMP/err" | tr -d '\r'; }
PANEL_LADDER="$TMP/bound-ladder.md" panel --kind task --tier light --prompt "$TMP/prompt.md"
check "the light bound is the slower last row plus its grace and 120 s" "$(bound_of)" "bound 485 s, watchdog at 470 s"
PANEL_LADDER="$TMP/bound-ladder.md" panel --kind task --tier heavy --prompt "$TMP/prompt.md"
check "the heavy bound takes the first rows" "$(bound_of)" "bound 1180 s, watchdog at 1165 s"
AGY_GATE_LINE='agy-gate usable=false reason=setting review=false resets_at=- claude=on claude_resets_at=- source=setting' \
  PANEL_LADDER="$TMP/bound-ladder.md" panel --kind task --tier light --prompt "$TMP/prompt.md"
check "a skipped family adds nothing to the bound" "$(bound_of)" "bound 480 s, watchdog at 465 s"
printf '%s\n' '```codex-judge' 'gpt-6-astra xhigh 30' 'gpt-6.1-sol xhigh 20' '```' > "$TMP/codex-only-ladder.md"
PANEL_LADDER="$TMP/codex-only-ladder.md" panel --kind task --tier light --prompt "$TMP/prompt.md"
check "a family with no ladder block fails as error" "$(head -1 <<<"$out")" "agy-judge none/none status=FAILED exit=0 out=- evidence=none reason=error"
check "and its cause is in its stderr file" "$(grep -c 'agy-judge block' "$TMP/out/agy.stderr" 2>/dev/null)" "1"
check "and the other family still runs" "$(grep -c '^codex-judge .* status=OK ' <<<"$out")" "1"
check "a missing ladder block is no usage error" "$rc" "0"

panel --kind task --prompt "$TMP/prompt.md"
check "a task panel without --tier is a usage error" "$rc" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
