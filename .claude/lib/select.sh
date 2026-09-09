# shellcheck shell=bash
# Frontier selection — a memoryless scan.
#
# Nothing is carried from one iteration to the next: the frontier is re-derived
# from the tracker every time, so a crashed run, a human edit between
# iterations and a cold start all behave identically. Backend-agnostic on
# purpose; it only ever calls the adapter interface.

# The frontier: open, unblocked, ready-for-agent, unclaimed. Min-NN first.
#
# **Its status is the adapter's, and the caller has to read it** ([74]). This is
# one call and no logic exactly so that a refusal arrives whole: "no tickets" and
# "the tracker could not be listed" are two different answers, and only the first
# one means this run has finished. The shape that loses it is a command
# substitution nested in a heredoc — the lines come through and the status does
# not — which is what `loop__next_ticket` did until [74].
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

# How many, or nothing at all when the tracker refused to say ([74]). The same
# rule as the two above, and it takes three lines instead of one because a
# pipeline answers for its **last** command: `tracker_frontier | awk` printed `0`
# on a listing that never happened, which is the one number a caller must not read
# as "the frontier is empty". `printf '%s'` and not `'%s\n'`: an empty frontier is
# no lines, and a bare newline would be counted as one.
select_frontier_count() {
  local frontier
  frontier="$(tracker_frontier)" || return 1
  printf '%s' "$frontier" | awk 'END { print NR }'
}
