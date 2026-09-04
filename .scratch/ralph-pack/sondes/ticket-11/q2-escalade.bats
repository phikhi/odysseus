#!/usr/bin/env bats
# [11] — Q2 : pourquoi l'escalade n'ouvre pas de ticket. Instrument.
load ../../../../test/helpers/harness
load ../../../../test/helpers/assert
setup() { harness_setup; }
teardown() { harness_teardown; }
@test "Q2 escalade" {
  out="$RALPH_PACK_ROOT/.scratch/ralph-pack/sondes/ticket-11/q2-out.txt"; : >"$out"
  use_tickets 01-alpha
  playthrough_answer \
    'RALPH-PLAYTHROUGH-HOLE: the spec asks for a summary nothing was built for' \
    'RALPH-PLAYTHROUGH-CLASS: contract' \
    'RALPH-PLAYTHROUGH-TITLE: the summary does not exist' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'
  run_loop
  { printf 'rc=%s\n' "$status"; printf '%s\n' "$output"; printf -- '--- tracker:\n'; ls "$TRACKER_DIR"; } >>"$out"
  pack_run 'playthrough__escalate "a title from the probe" "because"; printf "rc=%s\n" "$?"'
  { printf -- '--- escalate direct (rc=%s):\n%s\n' "$status" "$output"; ls "$TRACKER_DIR"; } >>"$out"
}
