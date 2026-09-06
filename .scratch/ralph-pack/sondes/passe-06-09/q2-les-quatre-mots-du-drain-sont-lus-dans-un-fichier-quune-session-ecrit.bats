#!/usr/bin/env bats
#
# Passe transversale du 06/09 — Q2.
#
# `router_run_notes` lit `run.log` et en tire **quatre conclusions** qu'il dit à
# l'humain une fois, au démarrage du drain, sans une réserve. Son voisin
# `router_journal_lines`, deux fonctions plus haut, lit le *même fichier* et
# imprime la réserve avec les lignes :
#
#   « That file is under `.scratch/`, which nothing in this pack guards: the
#     session these lines are about could have written them. Read them, do not
#     rely on them. »
#
# Et l'une des quatre est une **négation** :
#
#   grep -q 'budget-wall' && ! grep -q 'successor-armed\|weekly-pause\|successor-blocked-'
#
# — dont le commentaire dit « Nothing in this pack writes that end down as a
# state », c'est-à-dire que cette phrase est le seul endroit où cet état est dit.
#
# La session routée écrit dans l'arbre principal, sans worktree, sans gate, sans
# rollback. `.scratch/<feature>/` n'est gardé par rien et ne peut pas l'être.
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

# Un `run.log` dans la forme exacte que `loop_journal_append` écrit — sept champs
# séparés par des tabulations. Le run qui l'a écrit est mis en scène ; ce qui est
# mesuré ci-dessous est `router_run_notes` et qui peut écrire ce fichier.
sonde__journal() {
  local outcome="$1"
  printf '2026-09-06T00:00:00Z\t-\t%s\tturns=0\tcost=0\ttokens=0\taction=none\n' \
    "$outcome" >>"$FEATURE_DIR/run.log"
}

sonde__notes() {
  printf '=== %s\n' "$1"
  printf '    run.log :\n'
  sed 's/^/      /' "$FEATURE_DIR/run.log" 2>/dev/null || printf '      (aucun)\n'
  pack_run 'router_run_notes'
  printf '    router_run_notes rc=%s\n' "$status"
  printf '%s\n' "$output" | sed 's/^/      /'
}

@test "Q2a un run.log qui porte budget-wall seul : ce que le drain dit à l humain" {
  sonde__ticket
  sonde__journal budget-wall
  sonde__notes 'avant toute session'

  set -e
  false
}

@test "Q2b une session routée ajoute une ligne portant successor-armed : la note disparaît" {
  sonde__ticket
  sonde__journal budget-wall
  sonde__notes 'avant la session'

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/ | head -1)"
printf '2026-09-06T01:00:00Z\t-\tsuccessor-armed\tturns=0\tcost=0\ttokens=0\taction=none\n' \
  >>"$dir/run.log"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n1 rc=%s\n' "$status"
  printf '    ce que le drain a dit de ce que la session a laissé :\n'
  printf '%s\n' "$output" | grep -n 'path(s)' | sed 's/^/      /'

  sonde__notes 'après la session'

  run bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n2 — les notes de run que lit l humain :\n'
  printf '%s\n' "$output" | sed -n '1,8p' | sed 's/^/    /'

  set -e
  false
}

@test "Q2c témoin appairé : la même session, sans la ligne" {
  sonde__ticket
  sonde__journal budget-wall

  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n1 rc=%s\n' "$status"
  sonde__notes 'après une session qui n écrit rien'

  run bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n2 — les notes de run que lit l humain :\n'
  printf '%s\n' "$output" | sed -n '1,8p' | sed 's/^/    /'

  set -e
  false
}

@test "Q2d l autre sens : une session routée fabrique claim-refused" {
  sonde__ticket
  sonde__notes 'un run.log vierge'

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/ | head -1)"
printf '2026-09-06T01:00:00Z\t01-alpha\tclaim-refused\tturns=0\tcost=0\ttokens=0\taction=none\n' \
  >>"$dir/run.log"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n1 rc=%s\n' "$status"

  run bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n2 — les notes de run que lit l humain :\n'
  printf '%s\n' "$output" | sed -n '1,8p' | sed 's/^/    /'

  set -e
  false
}

@test "Q2e ce que le run AFK suivant dit d une ligne écrite avant lui" {
  use_tickets 01-alpha
  sonde__journal claim-refused
  printf '=== run.log avant le run :\n'
  sed 's/^/    /' "$FEATURE_DIR/run.log"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== le run se plaint-il de son journal ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'does not hold exactly')"
  printf '=== run.log après le run :\n'
  sed 's/^/    /' "$FEATURE_DIR/run.log"
  pack_run 'router_run_notes'
  printf '=== router_run_notes rc=%s :\n' "$status"
  printf '%s\n' "$output" | sed 's/^/    /'

  set -e
  false
}
