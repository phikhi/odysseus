#!/usr/bin/env bats
#
# Passe transversale du 07/09 — Q4.
#
# Les deux points d'entrée écrivent le **même** `run.log`, et chacun porte un
# témoin qui affirme être le seul écrivain entre sa base et sa vérification
# (`loop_journal_verify` [10], `router_journal_verify` [67]).
#
# `human_loop_main` prend sa base, puis appelle `human_loop_preflight` — qui
# **journalise** les constats du tracker ([64]) — et **seulement ensuite**
# demande les deux verrous. Un drainage démarré pendant qu'un run tourne écrit
# donc dans le journal du run avant de découvrir qu'il n'a pas le droit de
# tourner.
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

# Deux tickets portant le même NN : `tracker_preflight` rend un constat
# `ambiguous-id`, que les deux points d'entrée journalisent au démarrage.
sonde__ambiguous() {
  local n
  for n in a b; do
    {
      printf '# 20-%s — homonyme\n\n' "$n"
      printf '**What to build:** x\n\n'
      printf '**Status:** ready-for-human\n\n'
      printf '**Escalation:** decision\n\n'
      printf '**Blocked by:** None\n'
    } >"$TRACKER_DIR/20-$n.md"
  done
  harness__commit "sonde: deux tickets portant 20"
}

@test "Q4a un drainage démarré pendant qu un run tourne" {
  sonde__ambiguous
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
: >"$RALPH_SHIM_STATE/in-session"
while [ ! -e "$RALPH_SHIM_STATE/go" ]; do sleep 0.05; done
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/run.out" 2>&1 &
  local pid=$!
  wait_for_file "$SHIM_STATE/in-session" 400 || printf '=== le run n a jamais ouvert de session\n'

  printf '=== run.log pendant que le run tient les verrous : %s ligne(s)\n' \
    "$(awk 'END { print NR + 0 }' "$FEATURE_DIR/run.log" 2>/dev/null || printf 0)"

  set +e
  printf 'q\n' | bash "$PACK_DIR/human-loop.sh" >"$RALPH_TEST_DIR/drain.out" 2>&1
  local drc=$?
  set -e
  printf '=== rc du drainage : %s (1 = un run tient ce verrou)\n' "$drc"
  printf '=== ce que le drainage a écrit dans run.log avant de refuser :\n'
  grep -v '01-alpha' "$FEATURE_DIR/run.log" 2>/dev/null | sed 's/^/    /' || true
  printf '=== sortie du drainage :\n'
  sed 's/^/    /' "$RALPH_TEST_DIR/drain.out"

  : >"$SHIM_STATE/go"
  wait "$pid" || true
  printf '=== sortie du run, fin :\n'
  tail -8 "$RALPH_TEST_DIR/run.out" | sed 's/^/    /'
  printf '=== le run accuse-t-il quelqu un d avoir réécrit son journal ? : %s\n' \
    "$(grep -c 'does not hold exactly' "$RALPH_TEST_DIR/run.out" || true)"
  printf '=== 01-alpha : %s\n' "$(ticket_status 01-alpha)"

  set -e
  false
}

@test "Q4b témoin appairé : le même run, sans drainage à côté" {
  sonde__ambiguous
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run : %s\n' "$status"
  printf '=== le run accuse-t-il quelqu un d avoir réécrit son journal ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'does not hold exactly' || true)"
  printf '=== run.log :\n'
  sed 's/^/    /' "$FEATURE_DIR/run.log" 2>/dev/null || true

  set -e
  false
}

@test "Q4c l autre sens : un run AFK démarré pendant qu un drainage tient les verrous" {
  sonde__ambiguous
  use_tickets 01-alpha

  # Le drainage tient les deux verrous et attend une réponse sur stdin.
  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE
  mkfifo "$RALPH_TEST_DIR/answers"
  bash "$PACK_DIR/human-loop.sh" <"$RALPH_TEST_DIR/answers" \
    >"$RALPH_TEST_DIR/drain.out" 2>&1 &
  local dpid=$!
  exec 9>"$RALPH_TEST_DIR/answers"
  wait_for_file "$(run_lock_dir)" 400 || printf '=== le drainage n a jamais pris le verrou\n'

  printf '=== run.log pendant que le drainage tient les verrous : %s ligne(s)\n' \
    "$(awk 'END { print NR + 0 }' "$FEATURE_DIR/run.log" 2>/dev/null || printf 0)"

  run_loop
  printf '=== rc du run AFK : %s (1 = un drainage tient ce verrou)\n' "$status"
  printf '=== ce que le run a écrit dans run.log avant de refuser :\n'
  sed 's/^/    /' "$FEATURE_DIR/run.log" 2>/dev/null || true

  printf 'q\n' >&9
  exec 9>&-
  wait "$dpid" || true
  printf '=== le drainage accuse-t-il quelqu un d avoir réécrit son journal ? : %s\n' \
    "$(grep -c 'does not hold exactly' "$RALPH_TEST_DIR/drain.out" || true)"
  printf '=== sortie du drainage, fin :\n'
  tail -6 "$RALPH_TEST_DIR/drain.out" | sed 's/^/    /'

  set -e
  false
}
