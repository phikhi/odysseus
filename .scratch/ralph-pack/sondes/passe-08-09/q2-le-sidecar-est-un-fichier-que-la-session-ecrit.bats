#!/usr/bin/env bats
#
# Passe transversale du 08/09 — Q2.
#
# Sur un backend distant, trois faits locaux vivent dans **un fichier de la zone
# comptable** : `.scratch/<feature>/.forge-claims`, en append-only, dernière
# ligne gagnante (`forge__local_record` / `forge__record_local`).
#
#   claim    `owner=<qui> at=<iso>` — l'autorité de `tracker_field ID Claimed`,
#            donc de toute la liveness de `lib/claim.sh`
#   request  le numéro de la requête, pour ne pas la rouvrir
#   receipt  **l'URL que `router_dossier` montre à un humain comme le reçu**
#
# `gate_is_bookkeeping` exclut tout `.scratch/<FEATURE>/` du scope-guard, la
# protection de [21] ne regarde que `issues/` (et sur ce backend elle ne regarde
# rien du tout), le témoin de [70] ne connaît que refs, reçus-fichiers et
# playthrough, et `router_tree_note` ne voit pas cette zone. Une session
# d'itération atteint l'arbre principal par `git worktree list`.
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

sonde__sink_and_work() {
  forge_seed 1 decision 'Pour le drain' <<'T'
# 1 — Pour le drain

**What to build:** Something a human has to arbitrate.

**Status:** ready-for-human

**Escalation:** decision

**Write-surface:** `src/one.txt`

**Blocked by:** None
T
  forge_seed 2 alpha Alpha <<'T'
# 2 — Alpha

**What to build:** Write the alpha marker file.

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
}

@test "Q2a une itération VERTE dont la session écrit le reçu du ticket du puits dans le sidecar" {
  use_forge github
  set_config STERILE_K 1
  set_config PLAYTHROUGH off
  sonde__sink_and_work

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
# L'arbre principal, que `git worktree list` nomme — et la feature, qu'un
# répertoire de `.scratch/` nomme.
main="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
feature="$(basename "$(ls -d "$main"/.scratch/*/ | head -1)")"
printf '1-decision\treceipt\thttps://forge.invalid/pull/9999\n' \
  >>"$main/.scratch/$feature/.forge-claims"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== 2-alpha sur la forge : %s / %s\n' "$(forge_field 2 Status)" "$(forge_state 2)"
  printf '=== le run dit-il un mot du sidecar ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'forge-claims' || true)"
  printf '=== ce que le run dit des zones que rien ne garde :\n'
  printf '%s\n' "$output" | grep -E 'does not keep|nothing here restores' | sed 's/^/    /'
  printf '=== le sidecar après le run :\n'
  sed 's/^/    /' "$FEATURE_DIR/.forge-claims" 2>/dev/null || printf '    aucun\n'

  run bash -c 'printf "n\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== rc du drain : %s\n' "$status"
  printf '=== ce que le dossier montre comme preuve :\n'
  printf '%s\n' "$output" | grep -E 'branch |receipt |journal |not a path|reaches over' |
    sed 's/^/    /'

  set -e
  false
}

@test "Q2b témoin appairé : le même run vert, sans la ligne forgée" {
  use_forge github
  set_config STERILE_K 1
  set_config PLAYTHROUGH off
  sonde__sink_and_work

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run AFK : %s\n' "$status"

  run bash -c 'printf "n\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== ce que le dossier montre comme preuve :\n'
  printf '%s\n' "$output" | grep -E 'branch |receipt |journal ' | sed 's/^/    /'

  set -e
  false
}

sonde__claimed_by_a_dead_run() {
  forge_seed 2 alpha Alpha <<'T'
# 2 — Alpha

**Status:** claimed

**Claimed:** owner=pid:999999 at=2020-01-01T00:00:00Z

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
  # Le claim d'un run mort, tel que ce backend le range : dans le sidecar, parce
  # que la liveness est locale (spec §152). Le champ du corps est là pour un
  # humain et n'est jamais lu par ce backend.
  mkdir -p "$FEATURE_DIR"
  printf '2-alpha\tclaim\towner=pid:999999 at=2020-01-01T00:00:00Z\n' \
    >>"$FEATURE_DIR/.forge-claims"
}

@test "Q2c le claim d un run mort, tel quel : la liveness le rend" {
  use_forge github
  sonde__claimed_by_a_dead_run

  pack_run 'printf "Claimed=[%s]\n" "$(tracker_field 2-alpha Claimed)"
    printf "reclaim: [%s]\n" "$(claim_reclaim_stale)"'
  printf '=== ce que le pack lit et ce qu il en fait :\n'
  printf '%s\n' "$output" | sed 's/^/    /'
  printf '=== le Status sur la forge après : %s\n' "$(forge_field 2 Status)"

  set -e
  false
}

@test "Q2d le même claim, avec une ligne qu une session a appendue derrière" {
  use_forge github
  sonde__claimed_by_a_dead_run

  # Un process vivant qui appartient à cet utilisateur — ce qu'une session peut
  # laisser derrière elle en une ligne. `kill -0 1` ne prouve rien ici : un pid
  # qu'on n'a pas le droit de signaler est lu comme mort.
  sleep 120 &
  local victim=$!
  printf '2-alpha\tclaim\towner=pid:%s at=%s\n' "$victim" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >>"$FEATURE_DIR/.forge-claims"

  pack_run 'printf "Claimed=[%s]\n" "$(tracker_field 2-alpha Claimed)"
    printf "reclaim: [%s]\n" "$(claim_reclaim_stale)"'
  printf '=== ce que le pack lit et ce qu il en fait :\n'
  printf '%s\n' "$output" | sed 's/^/    /'
  printf '=== le Status sur la forge après : %s\n' "$(forge_field 2 Status)"
  printf '=== la frontière : [%s]\n' "$(pack_run 'tracker_frontier'; printf '%s' "$output")"

  kill "$victim" 2>/dev/null || true
  set -e
  false
}

@test "Q2e le garde : un répertoire posé par une session refuse les claims du run" {
  use_forge github
  set_config STERILE_K 2
  set_config PLAYTHROUGH off
  forge_seed 2 alpha Alpha <<'T'
# 2 — Alpha

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
  # `forge__guard` vit dans le répertoire de la feature, à côté du verrou de run
  # ([49]), et `state_guard_take` respecte un pid **vivant**.
  sleep 120 &
  local victim=$!
  mkdir -p "$FEATURE_DIR/.forge.guard"
  printf '%s\n' "$victim" >"$FEATURE_DIR/.forge.guard/pid"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run : %s\n' "$status"
  printf '=== ce que le run dit du ticket :\n'
  printf '%s\n' "$output" | grep -E 'claim|sterile|iteration|stopping|frontier' | sed 's/^/    /'
  printf '=== le Status sur la forge après le run : %s\n' "$(forge_field 2 Status)"

  kill "$victim" 2>/dev/null || true
  set -e
  false
}

@test "Q2f le même geste sur le backend LOCAL, ticket par ticket" {
  # `tracker_local_claim` prend `issues/<id>.md.guard` sans réessayer, et [49] a
  # décidé que ces transitoires ne sont **pas** restaurés par
  # `failures_protect_tracker` (ce ne sont pas des chemins de ticket). La zone
  # entière est comptable, donc le scope-guard ne la juge pas non plus.
  use_tickets 01-alpha
  set_config STERILE_K 2
  set_config PLAYTHROUGH off

  sleep 120 &
  local victim=$!
  mkdir -p "$TRACKER_DIR/01-alpha.md.guard"
  printf '%s\n' "$victim" >"$TRACKER_DIR/01-alpha.md.guard/pid"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run : %s\n' "$status"
  printf '=== ce que le run dit :\n'
  printf '%s\n' "$output" | grep -E 'claim|sterile|iteration|frontier' | sed 's/^/    /'
  printf '=== le Status de 01-alpha après le run : %s\n' "$(ticket_status 01-alpha)"

  kill "$victim" 2>/dev/null || true
  set -e
  false
}
