#!/usr/bin/env bats
#
# Passe transversale du 22/09 — Q2.
#
# [52] a sorti le `PATH` de la ligne « limite assumée » du tableau : il décide
# de ce que le pack exécute, donc la résolution et le contenu des noms que le
# pack lance par leur nom nu sont épinglés au démarrage du run. La liste est
# `gate_path_programs`, **écrite à la main**, trente-deux noms — et le document
# nomme déjà la dette (« un site d'appel ajouté au pack dans un programme absent
# de la liste rouvre le trou sans que rien le remarque »).
#
# Question de la passe : quel nom manque ? Pas un nom ajouté depuis, un nom qui
# n'y a jamais été.
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

@test "Q2a ce que le pack lance par son nom nu, et ce que la liste connaît" {
  printf '=== gate_path_programs :\n'
  pack_run 'gate_path_programs'
  printf '%s\n' "$output" | tr '\n' ' ' | fold -w 76 -s | sed 's/^/    /'

  printf '\n=== les invocations de `bash` par son nom nu dans le pack livré :\n'
  grep -nE '(^|[[:space:];&|(])bash([[:space:]]|$)' \
    "$RALPH_PACK_ROOT"/.claude/loop.sh "$RALPH_PACK_ROOT"/.claude/human-loop.sh \
    "$RALPH_PACK_ROOT"/.claude/lib/*.sh |
    grep -v ':[[:space:]]*#' | sed "s|$RALPH_PACK_ROOT/||" | sed 's/^/    /'

  printf '\n=== `bash` est-il dans la liste ?\n'
  pack_run 'gate_path_programs'
  if printf '%s\n' "$output" | grep -qx bash; then
    printf '    oui\n'
  else
    printf '    NON\n'
  fi

  set -e
  false
}

@test "Q2b le manifeste que le run épingle" {
  local dir="$RALPH_TEST_DIR/witness"
  mkdir -p "$dir"
  pack_run "gate_path_witness '$dir'"
  printf '=== %s lignes dans le manifeste, une par nom surveillé :\n' \
    "$(grep -c . <"$dir/path")"
  cut -f1 <"$dir/path" | tr '\n' ' ' | fold -w 76 -s | sed 's/^/    /'
  printf '\n=== une ligne pour bash ?\n'
  if cut -f1 <"$dir/path" | grep -qx bash; then printf '    oui\n'; else printf '    NON\n'; fi

  set -e
  false
}

@test "Q2c une itération réelle, avec un bash planté en tête de PATH" {
  local rec="$RALPH_TEST_DIR/plant"
  mkdir -p "$rec"
  {
    printf '#!/bin/bash\n'
    printf 'printf "%%s\\n" "$*" >>"%s/bash-ran"\n' "$SHIM_STATE"
    printf 'exec /bin/bash "$@"\n'
  } >"$rec/bash"
  chmod +x "$rec/bash"
  export PATH="$rec:$PATH"

  use_tickets 01-alpha
  run_loop
  printf '=== statut du run : %s\n' "$status"
  assert_ticket_status 01-alpha resolved

  printf '=== ce qui est passé par le bash planté (%s appels) :\n' \
    "$(grep -c . "$SHIM_STATE/bash-ran" 2>/dev/null || echo 0)"
  sed -n '1,40p' "$SHIM_STATE/bash-ran" 2>/dev/null | cut -c1-76 | sed 's/^/    /'

  printf '=== les appels qui portent le verdict :\n'
  grep -nE '^-c ' "$SHIM_STATE/bash-ran" 2>/dev/null | cut -c1-90 | sed 's/^/    /'

  set -e
  false
}
