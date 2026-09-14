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

# Fail closed: three distinct states, one outcome.
write_roster "$SOL_ONLY"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "catalog without astra falls back to sol" "$out" "codex-judge gpt-5.6-sol/high"

write_roster "$EMPTY"
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "empty catalog falls back to sol" "$out" "codex-judge gpt-5.6-sol/high"

write_roster null
out=$(run --kind final --cwd "$TMP/work" --out "$TMP/o.md" --base main --dry-run)
present "absent catalog falls back to sol" "$out" "codex-judge gpt-5.6-sol/high"
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

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
