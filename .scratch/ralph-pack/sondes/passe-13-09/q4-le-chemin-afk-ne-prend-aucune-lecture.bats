#!/usr/bin/env bats
#
# Passe transversale du 13/09 — Q4.
#
# [75] a donné à `tracker.sh` deux opérations et une clause :
#
#     « And neither call is one an entry point may skip on a hunch: the two
#       moments `cache_prime` is called are the two where a reading taken earlier
#       would be wrong — the top of a ticket, and the return of a session that may
#       have written the tracker where nothing of this pack can see it. »
#
# `human-loop.sh` appelle `tracker_cache_prime` trois fois. `loop.sh` ne l'appelle
# **jamais** : il prend `tracker_cache_open` (donc le registre d'invalidation, donc
# son coût) et ne prend aucune lecture. La clause est dans un commentaire, et rien
# ne la tient.
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

# Les compteurs de `test/tracker-remote.bats`, à l'identique : le *listing* et
# non chaque appel, et jamais le dépôt, qui voyage percent-encodé.
sonde__listings() {
  forge_calls | grep -c '^GET .*/issues?state=' || true
}

sonde__forget_calls() {
  : >"$SHIM_STATE/forge/calls"
}

sonde__session() {
  { printf '#!/usr/bin/env bash\nprompt="$(cat)"\n'
    cat <<'TAIL'
surface="$(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' |
  head -1 | tr -d '`\r' | tr ',' ' ')"
for t in $surface; do mkdir -p "$(dirname "$t")"; printf 'written\n' >"$t"; done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
TAIL
  } | script_claude
}

# Douze tickets ready-for-agent : le nombre est ce qui compte, le pack pose
# plusieurs questions par ticket et il y a une frontière à calculer à chaque tour.
sonde__douze() {
  forge_seed_many 1 12 bulk
}

@test "Q4a le même run AFK, avec et sans la lecture partagée" {
  use_forge github
  sonde__session
  sonde__douze
  set_config ITER_CAP 3
  sonde__forget_calls
  run_loop
  printf '=== rc du run (lecture partagée disponible) : %s\n' "$status"
  local avec
  avec="$(sonde__listings)"

  use_forge github
  sonde__session
  sonde__douze
  set_config ITER_CAP 3
  set_config FORGE_CACHE_TTL 0
  sonde__forget_calls
  run_loop
  printf '=== rc du run (lecture partagée coupée) : %s\n' "$status"
  local sans
  sans="$(sonde__listings)"

  printf '=== listings demandés au forge :\n'
  printf '    avec FORGE_CACHE_TTL par défaut : %s\n' "$avec"
  printf '    avec FORGE_CACHE_TTL=0          : %s\n' "$sans"
  printf '=== le pack appelle-t-il cache_prime depuis loop.sh ?\n'
  grep -c "tracker_cache_prime" "$PACK_DIR/loop.sh" | sed 's/^/    loop.sh       : /'
  grep -c "tracker_cache_prime" "$PACK_DIR/human-loop.sh" | sed 's/^/    human-loop.sh : /'
  printf '=== et cache_open ?\n'
  grep -c "tracker_cache_open" "$PACK_DIR/loop.sh" | sed 's/^/    loop.sh       : /'
  grep -c "tracker_cache_open" "$PACK_DIR/human-loop.sh" | sed 's/^/    human-loop.sh : /'

  set -e
  false
}

@test "Q4b témoin appairé : le drain, sur le même tracker" {
  use_forge github
  sonde__douze
  sonde__forget_calls
  run bash -c 'printf "q\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== rc du drain : %s\n' "$status"
  local avec
  avec="$(sonde__listings)"

  use_forge github
  sonde__douze
  set_config FORGE_CACHE_TTL 0
  sonde__forget_calls
  run bash -c 'printf "q\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  local sans
  sans="$(sonde__listings)"

  printf '=== listings demandés au forge par le drain :\n'
  printf '    avec FORGE_CACHE_TTL par défaut : %s\n' "$avec"
  printf '    avec FORGE_CACHE_TTL=0          : %s\n' "$sans"

  set -e
  false
}
