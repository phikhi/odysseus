#!/usr/bin/env bats
#
# Passe transversale du 05/09 — Q1.
#
# `gate__tmp_leftovers` dit : « N temporary director(ies) from earlier runs are
# still in $TMPDIR: a run killed mid-iteration leaves one behind, and nothing
# here removes them ». C'est un CRITÈRE : ce qu'un run tué laisse dans `$TMPDIR`.
# Ce qu'il énumère est une LISTE de cinq noms — `ralph-gate.*`, `ralph-ignore.*`,
# `ralph-worktree.*`, `ralph-slot.*`, `ralph-frontier.*`. Le pack en `mktemp`
# dix-huit.
#
# Forme exacte de [31] (un scellement plus étroit que son critère) et de [45]
# (un reçu avec moins de producteurs que son critère).
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

# Les noms de premier niveau que le pack pose dans `$TMPDIR`, relevés par
# `grep -rn mktemp .claude/` le 05/09/2026. `d` = `mktemp -d`, `f` = `mktemp`.
sonde__names() {
  cat <<'NAMES'
d ralph-slot loop.sh:1087 le-slot-d-une-iteration
f ralph-slot.writes loop.sh:1396 le-registre-des-ecritures-du-tracker
f ralph-tracker failures.sh:764 index-de-restauration-du-tracker
f ralph-failed failures.sh:1029 index-de-la-branche-failed
f ralph-durable failures.sh:1112 index-du-commit-durable
f ralph-reslice failures.sh:1259 le-plan-de-re-tranchage
f ralph-spec playthrough.sh:229 le-temoin-du-flux-utilisateur-11
d ralph-playthrough playthrough.sh:699 l-espace-de-travail-du-gate-de-valeur-11
d ralph-receipt receipt.sh:100 l-espace-de-travail-du-recu-d-audit
d ralph-frontier gate.sh:656 les-regles-epinglees
d ralph-ignore gate.sh:764 le-pin-d-ignore
f ralph-index gate.sh:2224 index-de-l-arbre-juge
f ralph-restore gate.sh:2441 index-de-restauration-du-gate
d ralph-gate gate.sh:3130 l-espace-de-travail-du-gate
d ralph-retro retro.sh:164 l-etat-du-retro
f ralph-fold concurrency.sh:533 index-du-fold
f ralph-refresh concurrency.sh:652 index-du-refresh
d ralph-worktree concurrency.sh:298 le-worktree-d-une-iteration
NAMES
}

sonde__yesterday() {
  date -v-25H +%Y%m%d%H%M 2>/dev/null || date -d '25 hours ago' +%Y%m%d%H%M
}

@test "Q1a les dix-huit noms que le pack pose dans TMPDIR, vieillis d un jour" {
  local list="$RALPH_TEST_DIR/names.txt" total i kind name where what solo
  sonde__names >"$list"
  total="$(awk 'END { print NR }' "$list")"
  printf '=== noms de premier niveau posés par le pack dans TMPDIR : %s\n' "$total"

  # Tous ensemble, comme après un run tué.
  local tmp="$RALPH_TEST_DIR/tmp"
  mkdir -p "$tmp"
  i=1
  while [ "$i" -le "$total" ]; do
    read -r kind name where what <<ENTRY
$(sed -n "${i}p" "$list")
ENTRY
    if [ "$kind" = d ]; then mkdir -p "$tmp/$name.AAAAAA"; else : >"$tmp/$name.AAAAAA"; fi
    touch -t "$(sonde__yesterday)" "$tmp/$name.AAAAAA"
    i=$((i + 1))
  done
  printf '=== posés : %s\n' "$(ls -1 "$tmp" | wc -l | tr -d ' ')"

  pack_run "TMPDIR='$tmp' gate__tmp_leftovers"
  printf '=== rc de gate__tmp_leftovers : %s\n' "$status"
  printf '=== ce qu il dit             : %s\n' "$output"

  # Un par un, pour savoir lesquels sont vus.
  printf '=== vu / pas vu, nom par nom :\n'
  solo="$RALPH_TEST_DIR/solo"
  i=1
  while [ "$i" -le "$total" ]; do
    read -r kind name where what <<ENTRY
$(sed -n "${i}p" "$list")
ENTRY
    rm -rf "$solo"
    mkdir -p "$solo"
    if [ "$kind" = d ]; then mkdir -p "$solo/$name.AAAAAA"; else : >"$solo/$name.AAAAAA"; fi
    touch -t "$(sonde__yesterday)" "$solo/$name.AAAAAA"
    pack_run "TMPDIR='$solo' gate__tmp_leftovers"
    if [ "$status" = 0 ]; then
      printf '    VU       %-1s %-20s %-22s %s\n' "$kind" "$name" "$where" "$what"
    else
      printf '    PAS VU   %-1s %-20s %-22s %s\n' "$kind" "$name" "$where" "$what"
    fi
    i=$((i + 1))
  done

  set -e
  false
}

@test "Q1b un run réel tué en pleine itération : ce qu il laisse vraiment" {
  use_tickets 01-alpha 02-beta
  local tmp="$RALPH_TEST_DIR/tmp" left counted
  mkdir -p "$tmp"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  # Le gate bloque assez longtemps pour que le kill tombe pendant l'itération.
  set_config TEST_CMD 'sleep 0.3
: >"$RALPH_SHIM_STATE/gate-running"
sleep 20'

  env TMPDIR="$tmp" bash "$PACK_DIR/loop.sh" >"$RALPH_TEST_DIR/loop.out" 2>&1 &
  PACK_BG_PID=$!

  wait_for_file "$SHIM_STATE/gate-running" 300 ||
    printf '=== le gate n a jamais démarré\n'

  # KILL et pas TERM : ce que le critère décrit est un run TUÉ, donc un run dont
  # aucun trap ne tourne. C'est le seul cas où les résidus restent.
  for _pid in $(pack_iteration_pids); do kill -KILL "$_pid" 2>/dev/null || true; done
  kill -KILL "$PACK_BG_PID" 2>/dev/null || true
  wait "$PACK_BG_PID" 2>/dev/null || true
  PACK_BG_PID=""
  sleep 1

  printf '=== ce qui reste dans TMPDIR après le kill :\n'
  ls -1 "$tmp" 2>/dev/null | sed 's/^/    /'
  printf '=== par famille :\n'
  ls -1 "$tmp" 2>/dev/null | sed 's/\.[A-Za-z0-9]\{6\}$//' | sort | uniq -c | sed 's/^/    /'

  # Vieillir tout ce qui reste, puis demander au gate ce qu'il en compte.
  find "$tmp" -maxdepth 1 -mindepth 1 -exec touch -t "$(sonde__yesterday)" {} \; 2>/dev/null || true

  pack_run "TMPDIR='$tmp' gate__tmp_leftovers"
  printf '=== gate__tmp_leftovers rc=%s : %s\n' "$status" "$output"

  left="$(ls -1 "$tmp" 2>/dev/null | wc -l | tr -d ' ')"
  counted="$(printf '%s' "$output" | awk '{ print $1 }')"
  printf '=== posés par le run tué : %s — comptés : %s\n' "$left" "${counted:-0}"

  printf '=== queue de la sortie du run :\n'
  tail -20 "$RALPH_TEST_DIR/loop.out" 2>/dev/null | sed 's/^/    /'

  set -e
  false
}

@test "Q1c témoin : un run qui finit normalement ne laisse rien" {
  use_tickets 01-alpha
  local tmp="$RALPH_TEST_DIR/tmp"
  mkdir -p "$tmp"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run env TMPDIR="$tmp" bash "$PACK_DIR/loop.sh"
  printf '=== rc du run : %s\n' "$status"
  printf '=== ce qui reste dans TMPDIR :\n'
  ls -1 "$tmp" 2>/dev/null | sed 's/^/    /'
  printf '=== compte : %s\n' "$(ls -1 "$tmp" 2>/dev/null | wc -l | tr -d ' ')"

  set -e
  false
}
