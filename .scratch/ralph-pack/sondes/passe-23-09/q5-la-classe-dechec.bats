#!/usr/bin/env bats
#
# Passe transversale du 23/09 — Q5.
#
# Le troisième objet du répertoire du gate. La ligne 35 du tableau le nomme
# depuis [92] — « `$dir/scope.class` (la classe d'échec, donc le budget de
# reprise — jamais un vert) » — et personne ne l'a mesuré. Ce qu'une classe
# `contract` achète, d'après `failures_handle` : `reason=decision`, et la
# branche `*)` du `case` — celle qui appelle `tracker_bump_failures` — n'est
# jamais prise.
#
# Témoin appairé : Q4a du même dossier (même suite rouge, sans survivant) →
# `Failures: 3`, trois tentatives, `escalated:failed-impl`.
#
# Instrument, pas test : le cas finit par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

@test "Q5 un survivant écrit la classe d'échec du gate" {
  use_tickets 01-alpha
  stub_exit tests 1
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
nohup bash -c '
  trap "" TERM
  end=$((SECONDS + 60))
  while [ "$SECONDS" -lt "$end" ]; do
    for d in "$TMPDIR"/ralph-gate.*; do
      [ -d "$d" ] || continue
      printf "contract\n" >"$d/scope.class"
      printf "forged\n" >>"$RALPH_SHIM_STATE/class.forged"
    done
    sleep 0.01
  done
' >/dev/null 2>&1 &
printf '%s\n' "$!" >"$state/survivor.pid"
chmod -x "$state/claude.script"
exec claude "$@"
SCRIPT

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== ticket : Status=%s Failures=%s\n' \
    "$(ticket_field 01-alpha Status || true)" \
    "$(ticket_field 01-alpha Failures || true)"
  printf '=== forgé %s fois\n' \
    "$(grep -c . "$SHIM_STATE/class.forged" 2>/dev/null || echo 0)"
  printf '=== ce que le run a dit :\n'
  printf '%s\n' "$output" | grep -iE 'escalat|retry|overflow|scope|iteration [0-9]' |
    sed 's/^/    /' | head -12

  kill -KILL "$(cat "$SHIM_STATE/survivor.pid" 2>/dev/null)" 2>/dev/null || true
  set -e
  false
}
