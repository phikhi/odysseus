#!/usr/bin/env bats
#
# Ticket [69] — vérification sur un run réel, après correctif.
#
# La sonde de la passe (`passe-06-09/q4`) a mesuré le défaut sur le seul décor qui
# le produit : un run réel, tué au `KILL` pendant le gate. Q4a — le drainage
# démarré derrière nommait **0** résidu ; Q4b — témoin appairé, un run AFK sur le
# même décor en nommait **3**.
#
# Ce que `test/human-loop.bats` pose est le même état par des fichiers **posés par
# le test** : trois entrées vieillies à la main dans `$TMPDIR`, un garde dont le
# pid est mort, un marqueur écrit au `printf`, un worktree ajouté au `git`. L'écart
# entre ce décor et celui qu'un run tué produit vraiment est exactement ce que la
# leçon 3 du CLAUDE.md demande de sonder : une session qui écrit, un gate qui
# tourne, un `kill -KILL` au milieu.
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

sonde__yesterday() {
  date -v-25H '+%Y%m%d%H%M' 2>/dev/null || date -d '25 hours ago' '+%Y%m%d%H%M'
}

# Le ticket que le drain va offrir. Un `ready-for-human` ne fait démarrer aucun
# gate : c'est `01-alpha` (`ready-for-agent`) qui fait tourner le run qu'on tue.
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

# Un run réel, tué au KILL pendant le gate : le seul cas où les résidus restent.
sonde__kill_a_run() {
  local tmp="$1"
  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
  set_config TEST_CMD 'sleep 0.3
: >"$RALPH_SHIM_STATE/gate-running"
sleep 20'

  env TMPDIR="$tmp" bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!
  wait_for_file "$SHIM_STATE/gate-running" 300 || printf '=== le gate n a jamais démarré\n'
  for _pid in $(pack_iteration_pids); do kill -KILL "$_pid" 2>/dev/null || true; done
  kill -KILL "$PACK_BG_PID" 2>/dev/null || true
  wait "$PACK_BG_PID" 2>/dev/null || true
  PACK_BG_PID=""
  sleep 1
  # Le verrou de run du mort, sinon rien ne redémarre.
  rm -rf "$(run_lock_dir)" "$(tree_lock_dir)"
  # Les résidus de $TMPDIR sont comptés au-delà de 24 h.
  find "$tmp" -maxdepth 1 -mindepth 1 -exec touch -t "$(sonde__yesterday)" {} \; 2>/dev/null || true
  # Le marqueur de successeur qu'un run tué laisse ([53]).
  printf '%s\t%s\t%s\n' "$(($(date +%s) - 60))" at 'an hour ago' \
    >"$(git rev-parse --git-common-dir)/ralph.successor"
}

sonde__debris() {
  printf '=== ce que le run tué a laissé :\n'
  printf '    $TMPDIR      : %s entrée(s)\n' "$(ls -1 "$1" 2>/dev/null | wc -l | tr -d ' ')"
  ls -1 "$1" 2>/dev/null | sed 's/^/      /'
  printf '    gardes       : %s\n' "$(ls -d "$FEATURE_DIR"/*.guard "$FEATURE_DIR"/.*.guard 2>/dev/null | tr '\n' ' ')"
  printf '    successeur   : %s\n' \
    "$([ -f "$(git rev-parse --git-common-dir)/ralph.successor" ] && echo présent || echo absent)"
  printf '    worktrees    : %s\n' "$(git worktree list 2>/dev/null | wc -l | tr -d ' ')"
}

sonde__count_leftovers() {
  printf '%s\n' "$1" | grep -c \
    'from earlier runs are still in\|exclusion guard(s) left in\|one-shot successor marker is still in\|worktree' || true
}

@test "V1 le drainage démarré après le run tué nomme les résidus" {
  local tmp="$RALPH_TEST_DIR/tmp"
  mkdir -p "$tmp"
  sonde__ticket
  sonde__kill_a_run "$tmp"
  sonde__debris "$tmp"

  # `n` puis EOF : le drain laisse le ticket où il est. Ce qu'on mesure est ce
  # qu'il dit AVANT le premier dossier.
  run env TMPDIR="$tmp" bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s (3 = ticket laissé dans le puits, pas un refus)\n' "$status"
  printf '=== lignes de résidu que le drain nomme : %s\n' "$(sonde__count_leftovers "$output")"
  printf '=== lesquelles :\n'
  printf '%s\n' "$output" | grep -n \
    'from earlier runs are still in\|exclusion guard(s) left in\|one-shot successor marker is still in\|worktree' |
    sed 's/^/    /'
  printf '=== les dix premières lignes du drain :\n'
  printf '%s\n' "$output" | sed -n '1,10p' | sed 's/^/    /'

  set -e
  false
}

@test "V2 et il n a rien refusé : le ticket du puits est offert et fermé" {
  local tmp="$RALPH_TEST_DIR/tmp"
  mkdir -p "$tmp"
  sonde__ticket
  sonde__kill_a_run "$tmp"

  run env TMPDIR="$tmp" bash -c 'printf "c\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s (0 = puits vidé)\n' "$status"
  printf '=== lignes de résidu : %s\n' "$(sonde__count_leftovers "$output")"
  printf '=== Status de 20-decision : %s\n' "$(ticket_status 20-decision)"

  set -e
  false
}
