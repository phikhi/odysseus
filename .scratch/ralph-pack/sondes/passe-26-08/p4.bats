#!/usr/bin/env bats
#
# Passe transversale — probes 4: the angle [15] wrote down for [13]/[27].
#
# `tracker_local__next_nn` reads the directory, takes the max and writes. It has
# no lock and three producers now (`failures_reslice`, [14]'s escalation,
# `capability_propose`). The window is not the millisecond one might assume:
# `tracker_local_open_ticket` computes `nn` **before** it reads the body from
# stdin, so it is open for as long as the caller takes to produce the body.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "P4a two openings in flight take the same NN, and nothing repairs it" {
  use_tickets 01-alpha 02-beta
  fifo="$RALPH_TEST_DIR/body.fifo"
  mkfifo "$fifo"

  # A first opening whose body is slow to arrive. It computes NN, then blocks.
  pack_run_bg 'tracker_open_ticket first "First" <'"$fifo"' >'"$RALPH_TEST_DIR"'/first.id'
  exec 9>"$fifo"
  sleep 1

  # A second opening, all the way through, while the first is still holding NN.
  pack_run 'printf "second body\n" | tracker_open_ticket second "Second"'
  echo "=== second opened: $output"

  printf 'first body\n' >&9
  exec 9>&-
  wait "$PACK_BG_PID" || true
  echo "=== first opened: $(cat "$RALPH_TEST_DIR/first.id")"

  echo "=== tracker"
  ls "$TRACKER_DIR"

  echo "=== can a bare number resolve?"
  nn="$(cat "$RALPH_TEST_DIR/first.id" | cut -d- -f1)"
  pack_run "tracker_local__path $nn"
  echo "rc=$status out=$output"

  echo "=== what the preflight would have said"
  pack_run 'tracker_preflight'
  echo "rc=$status"
  printf '%s\n' "$output"

  echo "=== and a ticket blocked on that number"
  printf '# %s — blocked\n\n**Status:** ready-for-agent\n\n**Blocked by:** %s\n' \
    "09" "$nn" >"$TRACKER_DIR/09-blocked.md"
  pack_run 'tracker_frontier'
  echo "frontier: $output"
  false
}

@test "P4b the quarantine will not renumber what the loop itself created" {
  use_tickets 01-alpha
  # Two tickets carrying 02, exactly as two concurrent loop-side openings leave
  # them, and both in the register of loop writes ([13]/[42]).
  printf '# 02 — a\n\n**Status:** ready-for-human\n\n**Blocked by:** None\n' \
    >"$TRACKER_DIR/02-first.md"
  printf '# 02 — b\n\n**Status:** ready-for-human\n\n**Blocked by:** None\n' \
    >"$TRACKER_DIR/02-second.md"

  pack_run 'export RALPH_TRACKER_LOG="'"$RALPH_TEST_DIR"'/register"
    printf "02-first\n02-second\n" >"$RALPH_TRACKER_LOG"
    failures_quarantine_strays 01-alpha "01-alpha" 0
    printf "rc=%s\n" "$?"
    ls "'"$TRACKER_DIR"'"'
  echo "=== with the ids in the register"
  printf '%s\n' "$output"

  pack_run 'export RALPH_TRACKER_LOG="'"$RALPH_TEST_DIR"'/register2"
    : >"$RALPH_TRACKER_LOG"
    failures_quarantine_strays 01-alpha "01-alpha" 0
    printf "rc=%s\n" "$?"
    ls "'"$TRACKER_DIR"'"'
  echo "=== with an empty register (a session would have written them)"
  printf '%s\n' "$output"
  false
}
