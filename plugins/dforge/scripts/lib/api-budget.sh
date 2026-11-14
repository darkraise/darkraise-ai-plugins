# Sourced. Which API budgets are open, their prices, and charging them.
# Key values are only ever tested for emptiness, never printed.

_API_BUDGET_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_API_BUDGET_DIR/dforge-env.sh"

api_budget_key_var() {
  case $1 in
    anthropic) printf 'DFORGE_ANTHROPIC_API_KEY\n' ;;
    openai) printf 'DFORGE_OPENAI_API_KEY\n' ;;
    agentrouter) printf 'DFORGE_AGENTROUTER_API_KEY\n' ;;
    *) return 1 ;;
  esac
}

_api_budget_cap_setting() {
  case $1 in
    anthropic) printf 'apiBudgetAnthropic' ;;
    openai) printf 'apiBudgetOpenai' ;;
    agentrouter) printf 'apiBudgetAgentRouter' ;;
    *) return 1 ;;
  esac
}

api_budget_spend_file() { printf '%s\n' "${DFORGE_API_SPEND_FILE:-$HOME/.dforge/api-spend.json}"; }

api_budget_state() {
  local id=$1 var setting cap spent file reason unreadable
  var=$(api_budget_key_var "$id") || return 1
  setting=$(_api_budget_cap_setting "$id")
  cap=$(dforge_setting "$setting" 0)
  [[ $cap =~ ^[0-9]+(\.[0-9]+)?$ ]] || cap=0
  file=$(api_budget_spend_file)
  spent=0 unreadable=no
  if [ -f "$file" ]; then
    spent=$(MSYS_NO_PATHCONV=1 jq -r --arg id "$id" '.[$id].spent_usd // 0 | numbers' < "$file" 2>/dev/null | tr -d '\r')
    # A spend file that cannot be read closes the budget: reading it as 0 would lift the cap.
    [[ $spent =~ ^[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?$ ]] || { spent=0 unreadable=yes; }
  fi
  if awk -v c="$cap" 'BEGIN { exit !(c + 0 == 0) }'; then reason=off
  elif [ "$unreadable" = yes ]; then reason=unreadable
  elif [ -z "${!var:-}" ]; then reason=no-key
  elif awk -v s="$spent" -v c="$cap" 'BEGIN { exit !(s + 0 >= 0.95 * c) }'; then reason=spent
  else reason=ok
  fi
  awk -v id="$id" -v s="$spent" -v c="$cap" -v r="$reason" \
    'BEGIN { printf "api-budget %s open=%s spent=%.4f cap=%.4f reason=%s\n", id, (r == "ok" ? "true" : "false"), s, c, r }'
  [ "$reason" = ok ]
}

api_budget_price() {
  local table="${DFORGE_API_PRICES:-$_API_BUDGET_DIR/../../reference/api-prices.json}" price
  case $2 in input|cached_input|output) ;; *) return 1 ;; esac
  [ -f "$table" ] || return 1
  price=$(MSYS_NO_PATHCONV=1 jq -r --arg m "$1" --arg f "$2" '.models[$m][$f] | numbers' < "$table" 2>/dev/null | tr -d '\r')
  [ -n "$price" ] || return 1
  printf '%s\n' "$price"
}

api_budget_charge() {
  bash "$_API_BUDGET_DIR/../api-spend" add "$1" "$2"
}
