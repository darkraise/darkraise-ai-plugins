# Sourced by shell suites: a task's review state as task-step review first
# builds it, for suites that drive verdict on a hand-set state.

# seed_step SCRIPTS PLAN N [SUITE] — from inside the checkout, open task N
# (task-brief --open writes its open line) and write the step state review
# builds from that line at HEAD, with SUITE as its suite command. An existing
# state is replaced.
seed_step() {
  local ws
  bash "$1/task-brief" --open "$2" "$3" >/dev/null || return
  ws=$(bash "$1/sdd-workspace" "$2") || return
  jq -n --argjson t "$((10#$3))" --arg b "$(git rev-parse HEAD | tr -d '\r')" --arg s "${4:-}" \
    '{tasks: [$t], base: $b, head: null, reviewHead: null, round: 0, t0: null}
     + (if $s == "" then {} else {suite: $s} end)' > "$ws/task-$3-step.json"
}
