#!/usr/bin/env bats
#
# [61] — `router_prompt` appelé directement, sortie écrite dans un fichier.
#
# Instrument, pas test.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

mk_ticket() {
  local id="$1" file
  shift
  file="$TRACKER_DIR/$id.md"
  {
    printf '# %s — written by a sonde\n\n' "$id"
    printf '**What to build:** A fixture for the human sink.\n\n'
    while [ "$#" -ge 2 ]; do
      printf '**%s:** %s\n\n' "$1" "$2"
      shift 2
    done
    printf -- '- [ ] Something a human decides about.\n'
  } >"$file"
  harness__commit "sonde: $id"
}

@test "Q2 router_prompt rendu dans un fichier" {
  mk_ticket 20-first Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/one.txt`' 'Blocked by' None

  pack_run 'router_pin 20-first; router_prompt 20-first >/tmp/ralph-61-prompt.txt; printf "rc=%s\n" "$?"'
  printf '=== rc de pack_run : %s\n' "$status"
  printf '=== sortie ---------------------------------------\n%s\n' "$output"
  printf '=== octets du prompt : %s\n' "$(wc -c </tmp/ralph-61-prompt.txt)"

  set -e
  false
}
