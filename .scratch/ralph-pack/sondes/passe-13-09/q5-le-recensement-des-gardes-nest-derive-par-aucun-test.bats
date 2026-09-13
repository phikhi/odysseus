#!/usr/bin/env bats
#
# Passe transversale du 13/09 — Q5.
#
# [77] a fermé son ticket sur une question ; la passe du 10/09 l'a mesurée (trois
# `state_guard_take` sur six recensés) et [81] a écrit les trois manquants dans
# `gate__guard_paths`. Ce qui reste de la question est sa seconde moitié, que [77]
# écrivait déjà : *« la liste est `gate_guards`, et son critère est écrit dans son
# commentaire, pas vérifié par un test qui lirait les `state_guard_take` du pack
# comme `test/gate.bats` lit ses `mktemp` »*.
#
# Cette sonde mesure les deux côtés et cherche le test qui les relierait.
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

@test "Q5a les six preneurs de garde du pack, et les trois zones recensées" {
  printf '=== les `state_guard_take` de la source livrée :\n'
  LC_ALL=C grep -rn 'state_guard_take "' "$PACK_DIR" 2>/dev/null |
    LC_ALL=C grep -v '^.*state.sh:' | sed 's|.*/\.claude/||' | sed 's/^/    /'

  printf '=== ce que `gate__guard_paths` compose, sur un run mis en scène :\n'
  local script="$RALPH_TEST_DIR/zones.sh"
  cat >"$script" <<'ASK'
RALPH_RETRO_STATE="$(mktemp -d)"
mkdir -p "$RALPH_RETRO_STATE/index.guard"
printf '%s\n' "$$" >"$RALPH_RETRO_STATE/index.guard/pid"
gate__guard_paths | sed 's/^/    /'
rm -rf "$RALPH_RETRO_STATE"
ASK
  pack_run "FEATURE=demo; . '$script'"
  printf '%s\n' "$output"

  printf '=== un test du dépôt qui dérive la liste de son critère ?\n'
  printf '    tests qui nomment state_guard_take hors test/state.bats :\n'
  LC_ALL=C grep -rln 'state_guard_take' "$BATS_TEST_DIRNAME/../../../../test" 2>/dev/null |
    LC_ALL=C grep -v '/state.bats$' | sed 's|.*/test/|        |'
  printf '    et ce quils en font :\n'
  LC_ALL=C grep -rn 'state_guard_take' "$BATS_TEST_DIRNAME/../../../../test"/*.bats 2>/dev/null |
    LC_ALL=C grep -v '^.*/state.bats:' | sed 's|.*/test/|        |' | cut -c1-110

  printf '=== le témoin appairé : ce que `test/gate.bats` fait pour les mktemp :\n'
  LC_ALL=C grep -n "grep -rn 'mktemp'\|only a mktemp call composes\|gate_tmp_names carries" \
    "$BATS_TEST_DIRNAME/../../../../test/gate.bats" | sed 's/^/        /'

  set -e
  false
}
