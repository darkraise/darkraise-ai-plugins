#!/usr/bin/env bash
# The selection rule and the outcome policy are the two things a review seat
# gets wrong silently: a wrong model still produces a review, and a failed run
# still produces a file. Both are asserted here against a stub codex, so no
# model call is made and every branch is reachable.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../scripts/run-codex-review.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

pass=0 fail=0
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}
present() { # present <name> <haystack> <needle>
  case "$2" in
    *"$3"*) printf 'ok   - %s\n' "$1"; pass=$((pass + 1)) ;;
    *) printf 'FAIL - %s\n       missing: [%s]\n' "$1" "$3"; fail=$((fail + 1)) ;;
  esac
}

mkdir -p "$TMP/bin" "$TMP/codexhome" "$TMP/work"
BASH_BIN=$(command -v bash)
for dep in jq timeout head tr sed awk grep cat mktemp rm; do
  printf '#!%s\nexec "%s" "$@"\n' "$BASH_BIN" "$(command -v "$dep")" > "$TMP/bin/$dep"
  chmod +x "$TMP/bin/$dep"
done

# A stub roster, so selection is tested without probing the real machine.
write_roster() { # write_roster <advertised-json>
  cat > "$TMP/bin/detect-stub" <<STUB
#!$BASH_BIN
cat <<'JSON'
[{"id":"codex","present":true,"path":"/stub/codex","version":"codex-cli 0.153.4",
  "authed":true,"auth_status":"authenticated","batch_capable":true,"usable":true,
  "reason":null,"advertised":$1}]
JSON
STUB
  chmod +x "$TMP/bin/detect-stub"
}

ASTRA='{"fetched_at":"2026-09-14T13:35:00Z","client_version":"0.153.4","pairs":[{"model":"gpt-6-astra","effort":"high"}]}'
SOL_ONLY='{"fetched_at":"2026-09-14T13:35:00Z","client_version":"0.153.4","pairs":[{"model":"gpt-5.6-sol","effort":"high"}]}'
EMPTY='{"fetched_at":"2026-09-14T13:35:00Z","client_version":"0.153.4","pairs":[]}'

run() { # run <args...>
  PATH="$TMP/bin:$PATH" CODEX_REVIEW_ROSTER="$TMP/bin/detect-stub" \
    "$BASH_BIN" "$SCRIPT" "$@" 2>"$TMP/err"
}

check "script exists" "$([ -f "$SCRIPT" ] && echo yes || echo no)" "yes"

# --- selection ---------------------------------------------------------------
write_roster "$ASTRA"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "advertised astra selects astra" "$out" "codex-judge gpt-6-astra/high"
present "dry run reports OK" "$out" "status=OK"
present "dry run carries the cache date as evidence" "$out" "evidence=2026-09-14T13:35:00Z"
# Line-exact: --dry-run prints one argv token per line, and a substring test
# for "review" would also match the schema filename.
tok() { printf '%s\n' "$2" | grep -qx -- "$3"; }
if tok x "$out" review; then printf 'ok   - final kind uses codex exec review\n'; pass=$((pass + 1))
else printf 'FAIL - final kind uses codex exec review\n'; fail=$((fail + 1)); fi
if tok x "$out" '--base' && tok x "$out" main; then
  printf 'ok   - final kind passes the base\n'; pass=$((pass + 1))
else printf 'FAIL - final kind passes the base\n'; fail=$((fail + 1)); fi
present "selected effort reaches the command" "$out" "model_reasoning_effort=high"
# Both judge rows run at high, so the effort check cannot tell them apart. Only
# a token check on -m proves the selected model is the one that runs.
if tok x "$out" gpt-6-astra; then printf 'ok   - the selected model reaches -m\n'; pass=$((pass + 1))
else printf 'FAIL - the selected model reaches -m\n'; fail=$((fail + 1)); fi

# Fail closed: three distinct states, one outcome.
write_roster "$SOL_ONLY"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "catalog without astra falls back to sol" "$out" "codex-judge gpt-5.6-sol/high"
if tok x "$out" gpt-5.6-sol; then printf 'ok   - the sol row reaches -m\n'; pass=$((pass + 1))
else printf 'FAIL - the sol row reaches -m\n'; fail=$((fail + 1)); fi

write_roster "$EMPTY"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "empty catalog falls back to sol" "$out" "codex-judge gpt-5.6-sol/high"
if tok x "$out" gpt-5.6-sol; then printf 'ok   - the empty-catalog sol row reaches -m\n'; pass=$((pass + 1))
else printf 'FAIL - the empty-catalog sol row reaches -m\n'; fail=$((fail + 1)); fi

write_roster null
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "absent catalog falls back to sol" "$out" "codex-judge gpt-5.6-sol/high"
if tok x "$out" gpt-5.6-sol; then printf 'ok   - the absent-catalog sol row reaches -m\n'; pass=$((pass + 1))
else printf 'FAIL - the absent-catalog sol row reaches -m\n'; fail=$((fail + 1)); fi
present "absent catalog reports unknown evidence" "$out" "evidence=unknown"

# --- the two kinds differ ----------------------------------------------------
write_roster "$ASTRA"
printf 'prompt text\n' > "$TMP/p.txt"
out=$(run --kind risk3 --cwd "$TMP/work" --out "$TMP/o.json" --prompt "$TMP/p.txt" --dry-run)
if tok x "$out" '--output-schema'; then printf 'ok   - risk3 passes a schema flag\n'; pass=$((pass + 1))
else printf 'FAIL - risk3 passes a schema flag\n'; fail=$((fail + 1)); fi
present "risk3 is read-only" "$out" "read-only"
present "risk3 passes the review schema" "$out" "codex-review-schema.json"
if tok x "$out" review; then printf 'FAIL - risk3 never uses codex exec review\n'; fail=$((fail + 1))
else printf 'ok   - risk3 never uses codex exec review\n'; pass=$((pass + 1)); fi

# The unusable branch has its own status line and must still be parseable.
cat > "$TMP/bin/detect-stub" <<STUB
#!$BASH_BIN
cat <<'JSON'
[{"id":"codex","present":true,"path":null,"version":null,"authed":false,
  "auth_status":"logged_out","batch_capable":true,"usable":false,
  "reason":"present but not authenticated; run codex login","advertised":null}]
JSON
STUB
chmod +x "$TMP/bin/detect-stub"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run); rc=$?
present "an unusable codex is FAILED" "$out" "status=FAILED"
present "the unusable status line keeps the model/effort shape" "$out" "codex-judge none/none"
check "an unusable codex exits 1" "$rc" "1"

# --- usage errors are exit 2, before any call --------------------------------
run --kind risk3 --cwd "$TMP/work" --out "$TMP/o.json" --dry-run >/dev/null; rc=$?
check "risk3 without --prompt is a usage error" "$rc" "2"
run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --dry-run >/dev/null; rc=$?
check "final without --base is a usage error" "$rc" "2"
run --kind bogus --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run >/dev/null; rc=$?
check "an unknown kind is a usage error" "$rc" "2"

# --- the outcome policy ------------------------------------------------------
# A stub codex whose behaviour is chosen per case by CODEX_STUB_MODE. The
# fallback cases need the stub to behave differently on its second invocation,
# so it counts its own calls.
cat > "$TMP/bin/codex" <<STUB
#!$BASH_BIN
n=\$(cat "$TMP/calls" 2>/dev/null || echo 0); n=\$((n + 1)); printf '%s' "\$n" > "$TMP/calls"
model=""; prev=""
for a in "\$@"; do [ "\$prev" = "-m" ] && model="\$a"; prev="\$a"; done
outfile=""; prev=""
for a in "\$@"; do [ "\$prev" = "-o" ] && outfile="\$a"; prev="\$a"; done
case "\$CODEX_STUB_MODE" in
  ok) printf '{"spec_verdict":"met","task_quality":18,"cannot_verify":[]}' > "\$outfile"; exit 0 ;;
  ok-final) printf 'a review\n' > "\$outfile"; exit 0 ;;
  empty) : > "\$outfile"; exit 0 ;;
  noout) exit 0 ;;
  # The observed form: a real refusal from codex 0.154.0, captured on
  # 2026-09-14, arrives on stderr as a column-0 ERROR: line.
  refuse-then-ok)
    if [ "\$model" = gpt-6-astra ]; then
      echo 'ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The gpt-6-astra model is not supported when using Codex with a ChatGPT account."}}' >&2; exit 1
    fi
    printf 'a review\n' > "\$outfile"; exit 0 ;;
  refuse-always) echo "ERROR: {"type":"error","status":400,"error":{"type":"invalid_request_error","message":"The \$model model is not supported when using Codex with a ChatGPT account."}}" >&2; exit 1 ;;
  # A run that merely mentions a refusal in its prose - what every review of
  # this plugin's own tests looks like - is not a refusal.
  prose-fail) echo "the diff mentions an unsupported model" >&2; exit 1 ;;
  # An API-level refusal arrives on the JSON event stream, which is stdout.
  refuse-stdout)
    if [ "\$model" = gpt-6-astra ]; then
      echo '{"type":"error","message":"http 400: model not available"}'; exit 1
    fi
    printf 'a review\n' > "\$outfile"; exit 0 ;;
  authfail) echo "stream error: 401 unauthorized" >&2; exit 1 ;;
  cancel) exit 130 ;;
  # 124 is what coreutils timeout returns after it kills the child; the stub
  # returns it directly, so this asserts the classification, not the deadline.
  hang) exit 124 ;;
esac
exit 1
STUB
chmod +x "$TMP/bin/codex"

seat() { # seat <mode> <kind> <extra-args...>
  rm -f "$TMP/calls" "$TMP"/o.md* "$TMP"/o.json*
  local mode="$1" k="$2"; shift 2
  CODEX_STUB_MODE="$mode" run --kind "$k" --cwd "$TMP/work" "$@"
}

write_roster "$ASTRA"

out=$(seat ok-final final --out "$TMP/o.md" --base main); rc=$?
present "a complete run with output is OK" "$out" "status=OK"
check "OK exits 0" "$rc" "0"

out=$(seat empty final --out "$TMP/o.md" --base main); rc=$?
present "exit 0 with an empty report is FAILED" "$out" "status=FAILED"
check "FAILED exits 1" "$rc" "1"

out=$(seat noout final --out "$TMP/o.md" --base main)
present "exit 0 with no report at all is FAILED" "$out" "status=FAILED"

out=$(seat ok risk3 --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "a schema-shaped risk3 report is OK" "$out" "status=OK"

out=$(seat ok-final risk3 --out "$TMP/o.json" --prompt "$TMP/p.txt")
present "risk3 output that is not schema-shaped is FAILED" "$out" "status=FAILED"

out=$(seat hang final --out "$TMP/o.md" --base main); rc=$?
present "exit 124 is TIMEOUT, never a model change" "$out" "status=TIMEOUT"
check "TIMEOUT exits 1" "$rc" "1"
check "TIMEOUT does not run a second seat" "$(cat "$TMP/calls")" "1"

out=$(seat refuse-then-ok final --out "$TMP/o.md" --base main); rc=$?
present "a refused model falls back once" "$out" "status=FALLBACK"
present "the fallback line names the model that ran" "$out" "codex-judge gpt-5.6-sol/high"
check "FALLBACK exits 0" "$rc" "0"
check "the fallback runs exactly one extra seat" "$(cat "$TMP/calls")" "2"

out=$(seat refuse-always final --out "$TMP/o.md" --base main)
present "a fallback that also fails is FAILED" "$out" "status=FAILED"
check "the fallback is attempted at most once" "$(cat "$TMP/calls")" "2"

out=$(seat prose-fail final --out "$TMP/o.md" --base main)
present "prose that mentions a refusal is not a refusal" "$out" "status=FAILED"
check "a prose mention runs no second seat" "$(cat "$TMP/calls")" "1"

out=$(seat authfail final --out "$TMP/o.md" --base main)
present "an auth failure is FAILED, not a model change" "$out" "status=FAILED"
check "an auth failure runs no second seat" "$(cat "$TMP/calls")" "1"

# A cancelled run is the owner's decision, not a capability signal.
out=$(seat cancel final --out "$TMP/o.md" --base main)
present "a cancelled run is FAILED, not a model change" "$out" "status=FAILED"
check "a cancelled run runs no second seat" "$(cat "$TMP/calls")" "1"

# Already on the fallback row: there is nothing to fall back to.
write_roster "$SOL_ONLY"
out=$(seat refuse-always final --out "$TMP/o.md" --base main)
present "a refusal on the fallback row is FAILED" "$out" "status=FAILED"
check "the fallback row is never retried against itself" "$(cat "$TMP/calls")" "1"

write_roster "$ASTRA"
out=$(seat refuse-stdout final --out "$TMP/o.md" --base main)
present "a refusal on stdout also falls back" "$out" "status=FALLBACK"
check "the stdout refusal runs exactly one extra seat" "$(cat "$TMP/calls")" "2"

# The refusal must survive the fallback run, because the ledger quotes it.
seat refuse-then-ok final --out "$TMP/o.md" --base main >/dev/null
check "the refusal's own logs are kept" \
  "$([ -s "$TMP/o.md.stderr" ] && echo yes || echo no)" "yes"
check "the fallback writes its own logs" \
  "$([ -f "$TMP/o.md.fallback.stderr" ] && echo yes || echo no)" "yes"

# The caller must defer to the runner's outcome rather than running its own
# retry rule: a FAILED seat that redispatches turns one refused run into two.
SDD="$HERE/../skills/subagent-driven-development/SKILL.md"
sdd=$(cat "$SDD")
present "the risk-3 caller names the runner" "$sdd" "run-codex-review.sh"
present "the risk-3 caller defers on FAILED" "$sdd" "TIMEOUT or FAILED"
# Needle must be unique to the new text: SKILL.md's recovery table already
# carries a bare "never re-dispatch", so a shorter needle would pass untouched.
present "the risk-3 caller does not redispatch a decided seat" "$sdd" "never re-dispatch the Codex seat"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
