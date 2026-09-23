#!/usr/bin/env bats
#
# Passe transversale du 23/09 — Q3.
#
# Ce que le pack donne à la commande du projet. `gate__start "$dir" tests bash
# -c "$TEST_CMD"` est un fork du **pilote** : il hérite de son environnement
# entier. Le sceau de [81] tient parce qu'il vit « dans une variable du shell du
# pilote, la seule réserve qu'une session jugée ne peut provablement pas
# atteindre : `claude` est spawné avec un environnement, celle-ci n'est jamais
# exportée ». La phrase parle de `claude`. `TEST_CMD` n'est pas `claude`.
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

@test "Q3a ce que TEST_CMD voit de l'environnement du pilote" {
  use_tickets 01-alpha
  cat >"$RALPH_TEST_DIR/spy.sh" <<'SCRIPT'
#!/usr/bin/env bash
env | LC_ALL=C sort >"$SPY_OUT"
printf '%s\n' "$PWD" >"$SPY_OUT.pwd"
exit 0
SCRIPT
  chmod +x "$RALPH_TEST_DIR/spy.sh"
  set_config TEST_CMD "SPY_OUT=$RALPH_TEST_DIR/env.txt bash $RALPH_TEST_DIR/spy.sh"

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== cwd de TEST_CMD : %s\n' "$(cat "$RALPH_TEST_DIR/env.txt.pwd" 2>/dev/null)"
  printf '=== variables RALPH_* visibles par TEST_CMD :\n'
  grep -E '^RALPH_' "$RALPH_TEST_DIR/env.txt" 2>/dev/null |
    sed 's/^\([^=]*\)=\(.\{0,60\}\).*/    \1=\2/' || printf '    aucune\n'
  printf '=== le sceau des témoins y est-il ? %s\n' \
    "$(grep -c '^RALPH_WITNESS_SEAL=' "$RALPH_TEST_DIR/env.txt" 2>/dev/null || echo 0)"
  printf '=== autres noms du pack (non RALPH_) :\n'
  grep -E '^(GATE_|LENSES|TRACKER|FEATURE|MAX_PARALLEL|RETRY_N|GUARDED_PATHS|MODEL|CLAIM_|BUDGET_|STERILE_)' \
    "$RALPH_TEST_DIR/env.txt" 2>/dev/null |
    sed 's/^\([^=]*\)=\(.\{0,50\}\).*/    \1=\2/' || printf '    aucun\n'
  printf '=== total de variables : %s\n' \
    "$(grep -c . "$RALPH_TEST_DIR/env.txt" 2>/dev/null || echo 0)"

  set -e
  false
}
