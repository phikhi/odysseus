#!/usr/bin/env bats
#
# Passe transversale du 14/09 — Q4.
#
# `harness__clear_env` **dérive** les clés de configuration du `.example` et les
# unset une par une ; puis il unset une **liste écrite à la main** de six noms
# `RALPH_*`. La règle que cette liste tient est celle que [40] a écrite :
#
#     « `loop.sh` l'assigne aujourd'hui sans condition, ce qui est la seule
#       raison pour laquelle une valeur héritée du shell d'un développeur est
#       inoffensive — et c'est aussi pour ça que `harness__clear_env` peut se
#       permettre de ne pas le connaître. »
#
# Le namespace fait quarante-deux noms. Cinq d'entre eux sont assignés par leur
# lib au moment du `source`, en `${X:-}`, c'est-à-dire en **préservant** une
# valeur héritée : `RALPH_PLAYTHROUGH_SPEC`, `RALPH_PLAYTHROUGH_OPENED`,
# `RALPH_RECEIPT`, `RALPH_TRACKER_SAID`, `RALPH_RETRO_STATE`.
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

@test "Q4a le namespace, et ce que le harnais en connaît" {
  printf '=== tous les RALPH_* nommés dans le pack livré :\n'
  local all
  all="$(grep -rhoE 'RALPH_[A-Z0-9_]+' "$RALPH_PACK_ROOT/.claude" | LC_ALL=C sort -u)"
  printf '%s\n' "$all" | sed 's/^/    /'
  printf '    (%s noms)\n' "$(printf '%s\n' "$all" | grep -c .)"

  printf '=== ce que harness__clear_env unset à la main :\n'
  grep -n '^  unset DISABLE_AUTO_COMPACT' -A 1 "$RALPH_PACK_ROOT/test/helpers/harness.bash" |
    sed 's/^/    /'

  printf '=== ce qu il dérive, juste au-dessus :\n'
  grep -n 'for key in \$(sed -n' -A 3 "$RALPH_PACK_ROOT/test/helpers/harness.bash" | sed 's/^/    /'

  printf '=== les libs qui préservent une valeur héritée au source :\n'
  grep -rn '^RALPH_[A-Z0-9_]*="\${RALPH_' "$RALPH_PACK_ROOT/.claude" | sed 's/^/    /'

  set -e
  false
}

@test "Q4b ce qu une valeur héritée survit à traverser" {
  local dir="$RALPH_TEST_DIR/inj"
  mkdir -p "$dir/state"

  printf '=== trois RALPH_* exportés, puis le pack sourcé comme un point d entrée le source :\n'
  env RALPH_RECEIPT="$dir/receipt" RALPH_RETRO_STATE="$dir/state" \
    RALPH_PLAYTHROUGH_SPEC="$dir/spec.md" \
    bash -c '
      set -u
      RALPH_DIR="$1"
      . "$1/ralph.config.sh.example"
      for l in "$1"/lib/*.sh; do . "$l"; done
      printf "    RALPH_RECEIPT=%s\n" "$RALPH_RECEIPT"
      printf "    RALPH_RETRO_STATE=%s\n" "$RALPH_RETRO_STATE"
      printf "    RALPH_PLAYTHROUGH_SPEC=%s\n" "$RALPH_PLAYTHROUGH_SPEC"
      printf "    retro_guards -> %s\n" "$(retro_guards 2>&1 || printf REFUS)"
    ' _ "$RALPH_PACK_ROOT/.claude"

  printf '=== ce que retro_guards alimente, pour mémoire ([85]) :\n'
  grep -n 'retro_guards' "$RALPH_PACK_ROOT/.claude/lib/gate.sh" | sed 's/^/    /'

  set -e
  false
}
