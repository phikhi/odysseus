#!/usr/bin/env bats
#
# Passe transversale du 06/09 — Q5.
#
# `playthrough_witness` est un **contrôle** et le dit :
#
#   « a delivery session can rewrite the user flow this gate replays, and a value
#     gate reading the file on disk would be asking "does the feature do what the
#     last session said it promised". […] Across runs it is the file on disk that
#     seeds it, and that limit is the lesson index's own: **a human who corrects
#     the spec between two runs is heard, a session that rewrites it during one is
#     not.** »
#
# La borne est « pendant un run » contre « entre deux runs », et l'argument qui la
# rend sûre est que ce qui écrit entre deux runs est un humain. [16] a ajouté un
# point d'entrée qui met une session **non jugée** dans l'arbre principal,
# précisément entre deux runs.
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
  local file="$TRACKER_DIR/20-decision.md"
  {
    printf '# 20-decision — pour le drain\n\n'
    printf '**What to build:** Something a human has to arbitrate.\n\n'
    printf '**Status:** ready-for-human\n\n'
    printf '**Escalation:** decision\n\n'
    printf '**Write-surface:** `src/one.txt`\n\n'
    printf '**Blocked by:** None\n'
  } >"$file"
  harness__commit "sonde: 20-decision"
}

sonde__spec_state() {
  printf '=== %s\n' "$1"
  printf '    spec.md porte le marqueur forgé ? : %s\n' \
    "$(grep -c 'FORGED BY A ROUTED SESSION' "$FEATURE_DIR/spec.md" || true)"
}

@test "Q5a une session routée réécrit spec.md : ce que le gate de valeur rejoue au run suivant" {
  sonde__ticket
  sonde__spec_state 'avant le drain'

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/ | head -1)"
printf '# spec\n\n## User flow\n\nFORGED BY A ROUTED SESSION: the user opens the app and everything already works.\n' \
  >"$dir/spec.md"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  printf '=== ce que le drain a dit de ce que la session a laissé :\n'
  printf '%s\n' "$output" | grep -n 'path(s)' | sed 's/^/    /'
  sonde__spec_state 'après le drain'

  # Le run AFK suivant : le gate de valeur prend son témoin au démarrage, sur le
  # fichier tel qu'il est sur le disque.
  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== le run dit-il quoi que ce soit du flux ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'spec')"
  printf '=== le prompt du gate de valeur porte le flux forgé ? : %s\n' \
    "$(playthrough_call_stdin 1 2>/dev/null | grep -c 'FORGED BY A ROUTED SESSION' || true)"
  printf '=== extrait du prompt entre les marqueurs :\n'
  playthrough_call_stdin 1 2>/dev/null |
    sed -n '/--- spec begins ---/,/--- spec ends ---/p' | sed 's/^/    /'

  set -e
  false
}

@test "Q5b témoin appairé : le même run sans le drain" {
  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== le prompt du gate de valeur porte le flux forgé ? : %s\n' \
    "$(playthrough_call_stdin 1 2>/dev/null | grep -c 'FORGED BY A ROUTED SESSION' || true)"
  printf '=== extrait du prompt entre les marqueurs :\n'
  playthrough_call_stdin 1 2>/dev/null |
    sed -n '/--- spec begins ---/,/--- spec ends ---/p' | head -12 | sed 's/^/    /'

  set -e
  false
}

@test "Q5c la même réécriture, mais par une session AFK pendant le run" {
  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/ | head -1)"
printf '# spec\n\n## User flow\n\nFORGED BY A ROUTED SESSION: the user opens the app and everything already works.\n' \
  >"$dir/spec.md"
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== spec.md sur le disque porte le marqueur ? : %s\n' \
    "$(grep -c 'FORGED BY A ROUTED SESSION' "$FEATURE_DIR/spec.md" || true)"
  printf '=== le prompt du gate de valeur porte le flux forgé ? : %s\n' \
    "$(playthrough_call_stdin 1 2>/dev/null | grep -c 'FORGED BY A ROUTED SESSION' || true)"

  set -e
  false
}
