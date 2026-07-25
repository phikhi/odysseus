# shellcheck shell=bash
# Frontier selection — a memoryless scan.
#
# Nothing is carried from one iteration to the next: the frontier is re-derived
# from the tracker every time, so a crashed run, a human edit between
# iterations and a cold start all behave identically. Backend-agnostic on
# purpose; it only ever calls the adapter interface.

# The frontier: open, unblocked, ready-for-agent, unclaimed. Min-NN first.
select_frontier() {
  tracker_frontier
}

# The next task, or nothing at all when the frontier is empty. Empty is not an
# error — it is the signal for the terminal value gate.
select_next_ticket() {
  local frontier
  frontier="$(tracker_frontier)" || return 1
  [ -n "$frontier" ] || return 0
  printf '%s\n' "$frontier" | sed -n '1p'
}

select_frontier_count() {
  tracker_frontier | awk 'END { print NR }'
}
