#!/usr/bin/env bash
# The bash 3.2 run (contract C4): macOS ships bash 3.2 and no CI job runs
# macOS, so the paths the review found broken there run in docker's bash:3.2
# image, both plugins, with the repository mounted read-only: context-size
# with no arguments, in-flight's role read and task-step's unnamed marker.
# Prints `skip - <reason>` and exits 0 when docker, the image or jq inside it
# is unavailable, when no timeout command bounds docker, or when the daemon
# cannot mount this host's files.
set -uo pipefail
# The container inherits neither, but a suite that runs context-size names both.
unset AR_SESSION CLAUDE_CODE_SESSION_ID

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

pass=0 fail=0
skip() { printf 'skip - %s\n' "$1"; exit 0; }
check() { # check <name> <got> <want>
  if [ "$2" = "$3" ]; then printf 'ok   - %s\n' "$1"; pass=$((pass + 1))
  else printf 'FAIL - %s\n       want: [%s]\n       got:  [%s]\n' "$1" "$3" "$2"; fail=$((fail + 1)); fi
}

case "$(uname -s)" in MINGW* | MSYS* | CYGWIN*) skip "bash 3.2 run: no Linux containers on Windows" ;; esac
command -v docker >/dev/null 2>&1 || skip "bash 3.2 run: docker unavailable"
command -v timeout >/dev/null 2>&1 || skip "bash 3.2 run: no timeout command to bound docker with"
timeout 30 docker info >/dev/null 2>&1 || skip "bash 3.2 run: the docker daemon is unavailable"
docker image inspect bash:3.2 >/dev/null 2>&1 || timeout 300 docker pull -q bash:3.2 >/dev/null 2>&1 \
  || skip "bash 3.2 run: bash:3.2 unavailable"

TMP="$(mktemp -d)"
NAME="dforge-bash32-$$"
# The container is removed by name: a timeout kills the docker client, not the container.
trap 'docker rm -f "$NAME" >/dev/null 2>&1; rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home"

printf '%s\n' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"tool_use","id":"toolu_dev","name":"Bash","input":{"description":"Dev server","command":"npm run dev","run_in_background":true}}]}}' \
  '{"type":"user","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"toolu_dev","content":"Command running in background with ID: d1. Output is being written to: /tmp/d1.output."}]}}' \
  > "$TMP/transcript.jsonl"

# Runs inside the container under bash 3.2; each block's output lands in /t.
cat > "$TMP/inner.sh" <<'EOF'
cd /r
export HOME=/t/home
printf '%s\n' "$BASH_VERSION" > /t/version
for p in dforge dagents; do
  bash "plugins/$p/scripts/context-size" > "/t/$p-context.out" 2>&1
  bash -uc '. "plugins/$0/scripts/lib/in-flight.sh"; inflight_scan /t/transcript.jsonl' "$p" > "/t/$p-scan.out" 2>&1
  sed -n '/^suite_fail_set() {$/,/^}$/p' "plugins/$p/scripts/task-step" > "/t/$p-fail-set.sh"
  bash -uc '. "$0"; suite_failing_lines() { return 1; }; suite_fail_set /dev/null 1' "/t/$p-fail-set.sh" > "/t/$p-marker.out" 2>&1
done
exit 0
EOF

timeout 300 docker run --rm --name "$NAME" -v "$ROOT":/r:ro -v "$TMP":/t bash:3.2 \
  sh -c 'timeout 120 apk add --no-cache jq >/dev/null 2>&1 || exit 77; timeout 120 bash /t/inner.sh' >/dev/null 2>&1
rc=$?
[ "$rc" -eq 77 ] && skip "bash 3.2 run: jq could not be installed in bash:3.2"
# A daemon on another host (DOCKER_HOST, or a socket shared from outside a
# runner container) mounts its own paths: the run leaves nothing here.
[ "$rc" -ne 0 ] || [ -e "$TMP/version" ] || skip "bash 3.2 run: the docker daemon cannot mount this host's files"
check "the container ran bash 3.2" "$rc|$(cut -c1-4 "$TMP/version" 2>/dev/null)" "0|3.2."

errors() { grep -cE 'unbound variable|command not found' "$1" 2>/dev/null; }
check "context-size under bash 3.2" \
  "$(errors "$TMP/dforge-context.out")|$(errors "$TMP/dagents-context.out")|$(grep -c '^budget' "$TMP/dforge-context.out")|$(grep -c '^budget' "$TMP/dagents-context.out")" \
  "0|0|1|1"

marker='^command exit 1 \(unnamed [0-9]+-[0-9]+\)$'
# dforge's scan ends each line in the shell's role; dagents' scan reads no roles.
check "in-flight and task-step under bash 3.2" \
  "$(errors "$TMP/dforge-scan.out")|$(errors "$TMP/dagents-scan.out")|$(cut -f1,2,6 "$TMP/dforge-scan.out" | tr '\t' ' ')|$(cut -f1,2 "$TMP/dagents-scan.out" | tr '\t' ' ')|$(errors "$TMP/dforge-marker.out")|$(errors "$TMP/dagents-marker.out")|$(grep -cE "$marker" "$TMP/dforge-marker.out")|$(grep -cE "$marker" "$TMP/dagents-marker.out")" \
  "0|0|shell d1 service|shell d1|0|0|1|1"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
