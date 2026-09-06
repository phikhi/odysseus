#!/usr/bin/env bats
#
# Passe transversale du 06/09 — Q3.
#
# [10] a rendu `run.log` **détectable** plutôt qu'inviolable : le pilote garde en
# mémoire chaque ligne qu'il a écrite (`RALPH_JOURNAL_WITNESS`, une variable de
# son propre process) et `loop_journal_verify` compare, une fois, en fin de run.
#
# [16] a ajouté un second écrivain de ce fichier — `router_journal` — et aucun
# témoin. Ce que le drain journalise est pourtant la seule trace de ce qu'un
# **humain** a décidé : `drained/reinjected`, `drained/signed-off`,
# `drained/closed`, `tracker-drift/skipped`, et depuis [64] les constats du
# préflight.
#
# Instrument, pas test : chaque cas finit par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

sonde__ticket() {
  local id="${1:-20-decision}" file
  file="$TRACKER_DIR/$id.md"
  {
    printf '# %s — pour le drain\n\n' "$id"
    printf '**What to build:** Something a human has to arbitrate.\n\n'
    printf '**Status:** ready-for-human\n\n'
    printf '**Escalation:** decision\n\n'
    printf '**Write-surface:** `src/one.txt`\n\n'
    printf '**Blocked by:** None\n'
  } >"$file"
  harness__commit "sonde: $id"
}

@test "Q3a une session routée efface la décision qu un humain vient de prendre dans le même drain" {
  sonde__ticket 20-decision
  sonde__ticket 21-second

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/ | head -1)"
printf '2026-09-06T00:00:00Z\t-\tnothing ever happened here\tturns=0\tcost=0\ttokens=0\taction=none\n' \
  >"$dir/run.log"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  # Premier ticket : `c`, une décision d humain, journalisée. Second ticket : `o`,
  # la session routée écrase le journal, puis `n`.
  run bash -c 'printf "c\no\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  printf '=== le drain se plaint-il de son journal ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'does not hold exactly')"
  printf '=== ce que le drain a dit de ce que la session a laissé :\n'
  printf '%s\n' "$output" | grep -n 'path(s)' | sed 's/^/    /'
  printf '=== Status 20-decision / 21-second : %s / %s\n' \
    "$(ticket_status 20-decision)" "$(ticket_status 21-second)"
  printf '=== run.log après le drain :\n'
  sed 's/^/    /' "$FEATURE_DIR/run.log"
  printf '=== la décision de l humain sur 20-decision est-elle encore au journal ? : %s\n' \
    "$(grep -c 'drained' "$FEATURE_DIR/run.log" || true)"

  set -e
  false
}

@test "Q3b témoin appairé : le même effacement, côté AFK" {
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/ | head -1)"
printf '2026-09-06T00:00:00Z\t-\tnothing ever happened here\tturns=0\tcost=0\ttokens=0\taction=none\n' \
  >"$dir/run.log"
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== le run se plaint-il de son journal ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'does not hold exactly')"
  printf '=== ce qu il dit :\n'
  printf '%s\n' "$output" | grep -n 'does not hold exactly\|journal:' | sed 's/^/    /'
  printf '=== run.log après le run :\n'
  sed 's/^/    /' "$FEATURE_DIR/run.log"

  set -e
  false
}

@test "Q3c témoin appairé : le même drain, sans l effacement" {
  sonde__ticket

  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nc\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  printf '=== Status du ticket : %s\n' "$(ticket_status 20-decision)"
  printf '=== run.log après le drain :\n'
  sed 's/^/    /' "$FEATURE_DIR/run.log"

  set -e
  false
}
