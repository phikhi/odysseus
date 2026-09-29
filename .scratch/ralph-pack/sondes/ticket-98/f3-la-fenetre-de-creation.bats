#!/usr/bin/env bats
#
# Ticket [101], deuxième passe complète — le rouge du test de [96] (« a process the
# session left behind finds no workspace to forge ») sur une ligne que [101]
# n'avait pas touchée. Le nom `ralph-receipt.*` existe entre le `mktemp` et le
# `rm -f` de `receipt_open` ; le survivant du test dormait 10 ms entre deux regards
# et tombait parfois dans cet instant. Ici le survivant boucle SANS dormir, ouvre ce
# qu'il trouve et garde le descripteur. → ticket [103].
#
# Instrument, pas test : le cas finit par un `false` volontaire.
load ../../../../test/helpers/harness
load ../../../../test/helpers/assert
setup() { harness_setup; }
teardown() { harness_teardown; }
receipt_path() { printf "%s/receipts/%s/%s.md\n" "$PROJECT_DIR" "$RALPH_TEST_FEATURE" "$1"; }

@test "W1 a survivor that busy-polls TMPDIR, opens the receipt's file in its creation window and keeps it" {
  use_tickets 01-alpha
  set_config RETRY_N 3
  set_config STERILE_K 4
  stub_exit tests 1
  printf 'FAIL: 3 of 12 tests failed in src/alpha\n' >"$SHIM_STATE/stub-tests.out"
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
nohup bash -c '
  trap "" TERM
  end=$((SECONDS + 60))
  held=0
  while [ "$SECONDS" -lt "$end" ]; do
    for d in "$TMPDIR"/ralph-receipt.*; do
      [ -f "$d" ] || continue
      if exec 7>>"$d"; then
        held=$((held + 1))
        printf "held %s\n" "$d" >>"$RALPH_SHIM_STATE/window.held"
        # keep writing on the descriptor after the pack has unlinked the name
        ( k=0; while [ $k -lt 400 ]; do printf "note\tFORGED-THROUGH-THE-CREATION-WINDOW\n" >&7; sleep 0.05; k=$((k+1)); done ) &
        exec 7>&-
      fi
    done
  done
' >/dev/null 2>&1 &
printf '%s\n' "$!" >"$state/survivor.pid"
chmod -x "$state/claude.script"
exec claude "$@"
SCRIPT
  run_loop_own_tmp
  printf '=== rc=%s\n' "$status"
  printf '=== windows the survivor won: %s\n' "$(grep -c . "$SHIM_STATE/window.held" 2>/dev/null || echo 0)"
  printf '=== forged lines in the receipt: %s\n' "$(grep -c 'FORGED-THROUGH' "$(receipt_path 01-alpha)" 2>/dev/null || echo 0)"
  pkill -KILL -f 'FORGED-THROUGH-THE-CREATION-WINDOW' 2>/dev/null || true
  kill -KILL "$(cat "$SHIM_STATE/survivor.pid")" 2>/dev/null || true
  set -e
  false
}
