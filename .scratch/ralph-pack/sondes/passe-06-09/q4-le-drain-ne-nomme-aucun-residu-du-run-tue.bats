#!/usr/bin/env bats
#
# Passe transversale du 06/09 — Q4. Le constat resté ouvert dans [16].
#
# `loop_main` dit au démarrage ce que les runs précédents ont laissé dehors
# (`gate_leftovers` : $TMPDIR, les gardes morts de [49], le successeur de [53])
# et dedans (`concurrency_leftovers` : un worktree enregistré). `human_loop_main`
# n'appelle ni l'un ni l'autre — alors qu'un drainage démarré après un run tué
# est exactement la situation où un humain vient voir ce qui s'est passé.
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

@test "Q4a un drainage démarré après un run tué : ce qu il nomme" {
  local tmp="$RALPH_TEST_DIR/tmp"
  mkdir -p "$tmp"
  sonde__ticket
  sonde__kill_a_run "$tmp"
  sonde__debris "$tmp"

  run env TMPDIR="$tmp" bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  printf '=== lignes de résidu que le drain nomme : %s\n' "$(sonde__count_leftovers "$output")"
  printf '=== les huit premières lignes du drain :\n'
  printf '%s\n' "$output" | sed -n '1,8p' | sed 's/^/    /'

  set -e
  false
}

@test "Q4b témoin appairé : un run AFK démarré sur le même décor" {
  local tmp="$RALPH_TEST_DIR/tmp"
  mkdir -p "$tmp"
  sonde__ticket
  sonde__kill_a_run "$tmp"
  sonde__debris "$tmp"

  # Un gate qui finit, pour que le run démarre et parle.
  set_config TEST_CMD 'true'
  run env TMPDIR="$tmp" bash "$PACK_DIR/loop.sh"
  printf '=== rc du run : %s\n' "$status"
  printf '=== lignes de résidu que le run nomme : %s\n' "$(sonde__count_leftovers "$output")"
  printf '=== lesquelles :\n'
  printf '%s\n' "$output" | grep -n \
    'from earlier runs are still in\|exclusion guard(s) left in\|one-shot successor marker is still in\|worktree' |
    sed 's/^/    /'

  set -e
  false
}
