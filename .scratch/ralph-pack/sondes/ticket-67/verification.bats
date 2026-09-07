#!/usr/bin/env bats
#
# Ticket [67] — vérification sur des runs et des drains réels, après correctif.
#
# Les sondes de la passe (`passe-06-09/q2` et `q3`) ont mesuré les deux moitiés du
# défaut. Ce que `test/human-loop.bats` pose est le même état par des lignes
# **écrites par le test** dans `run.log` ; l'écart que la leçon 3 du CLAUDE.md
# demande de sonder est celui-là : une session routée qui écrit vraiment et qui
# commite, un run AFK réel qui passe derrière, et les deux écrivains du même
# fichier qui se croisent.
#
# Ce qui est demandé ici et que la suite ne demande pas :
#
#   V1  Q3a rejoué sur le code livré — un écrasement de `run.log` par une session
#       routée, entre deux décisions d'un humain
#   V2  témoin appairé, et le plus cher à tenir : une session routée qui déplace
#       un ticket voisin (donc `router_protect_tracker` journalise) **et** qui
#       commite. Le drain ne doit pas s'accuser
#   V3  les deux écrivains qui se croisent : un drain, puis un run AFK réel
#       derrière lui, puis un second drain. Personne ne doit s'accuser des lignes
#       de l'autre
#   V4  Q2b rejoué — une session routée pose `successor-armed` sur un `run.log`
#       portant `budget-wall`
#   V5  le bruit : un run AFK ordinaire, puis un drain. La nouvelle phrase ne doit
#       pas arriver sur un matin où rien n'a heurté le mur
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
  local id="${1:-20-decision}" file
  file="$TRACKER_DIR/$id.md"
  {
    printf '# %s — pour le drain\n\n' "$id"
    printf '**What to build:** Something a human has to arbitrate.\n\n'
    printf '**Status:** ready-for-human\n\n'
    printf '**Escalation:** decision\n\n'
    printf '**Write-surface:** `src/%s.txt`\n\n' "$id"
    printf '**Blocked by:** None\n'
  } >"$file"
  harness__commit "sonde: $id"
}

sonde__journal() {
  printf '=== %s\n' "$1"
  sed 's/^/    /' "$FEATURE_DIR/run.log" 2>/dev/null || printf '    (pas de run.log)\n'
}

sonde__complaints() {
  printf '%s\n' "$1" | grep -c 'does not hold exactly' || true
}

@test "V1 une session routée écrase run.log entre deux décisions d un humain" {
  sonde__ticket 20-decision
  sonde__ticket 21-second

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/ | head -1)"
printf '2026-09-06T00:00:00Z\t-\tnothing ever happened here\tturns=0\tcost=0\ttokens=0\taction=none\n' \
  >"$dir/run.log"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "c\no\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  printf '=== le drain se plaint-il de son journal ? : %s\n' "$(sonde__complaints "$output")"
  printf '=== ce qu il dit :\n'
  printf '%s\n' "$output" | grep -n 'does not hold exactly\|^ralph: journal: ' | sed 's/^/    /'
  printf '=== Status 20-decision / 21-second : %s / %s\n' \
    "$(ticket_status 20-decision)" "$(ticket_status 21-second)"
  sonde__journal "run.log après le drain"

  set -e
  false
}

@test "V2 une session routée qui déplace un ticket voisin et qui commite n accuse personne" {
  sonde__ticket 20-decision
  sonde__ticket 21-second
  # Le journal porte déjà les lignes d un run précédent : la borne du drain n est
  # pas zéro, ce qui est le cas que la suite ne pose qu une fois.
  {
    printf '2026-09-05T00:00:00Z\t01-old\tresolved\tturns=3\tcost=1\ttokens=9\taction=none\n'
    printf '2026-09-05T00:00:01Z\t02-old\tresolved\tturns=2\tcost=1\ttokens=8\taction=none\n'
    printf '2026-09-05T00:00:02Z\t-\tplaythrough-green\tturns=0\tcost=0\ttokens=0\taction=none\n'
  } >>"$FEATURE_DIR/run.log"

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
# Ce qu une vraie session fait et que le faux de la suite ne fait pas : elle écrit
# dans l arbre et elle commite.
mkdir -p "$root/src"
printf 'HUMAN-FIX\n' >"$root/src/human-note.txt"
git -C "$root" add src/human-note.txt
git -C "$root" -c user.name=sonde -c user.email=sonde@local commit -q -m 'la session commite'
# Et elle déplace le ticket d en face, ce qui fait journaliser router_protect_tracker.
perl -pi -e 's/^\*\*Status:\*\* .*$/**Status:** resolved/' "$tracker/21-second.md"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nn\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  printf '=== le drain s accuse-t-il ? (0 attendu) : %s\n' "$(sonde__complaints "$output")"
  printf '=== la dérive a-t-elle été journalisée ? : %s\n' \
    "$(grep -c 'tracker-drift' "$FEATURE_DIR/run.log" || true)"
  printf '=== ce que le drain a dit du tracker :\n'
  printf '%s\n' "$output" | grep -n '21-second was moved\|put back to' | sed 's/^/    /'
  sonde__journal "run.log après le drain"

  set -e
  false
}

@test "V3 un drain, un run AFK réel derrière lui, puis un second drain" {
  # Les deux écrivains du même fichier, dans l ordre où un matin les produit. La
  # borne de chacun est prise sur ce que l autre a laissé : une fausse accusation
  # ici serait un défaut que ni la suite du drain ni celle du run ne voit, chacune
  # ne connaissant qu un écrivain.
  use_tickets 01-alpha
  sonde__ticket 20-decision

  script_claude <<'FAKE'
#!/usr/bin/env bash
# Dans le cwd et pas dans le projet : une itération travaille dans un worktree.
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain 1 rc=%s, plaintes : %s\n' "$status" "$(sonde__complaints "$output")"
  sonde__journal "run.log après le drain 1"

  run_loop
  printf '=== run AFK rc=%s, plaintes : %s\n' "$status" "$(sonde__complaints "$output")"
  printf '%s\n' "$output" | grep -n 'does not hold exactly' | sed 's/^/    /'
  sonde__journal "run.log après le run"

  run bash -c 'printf "c\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain 2 rc=%s, plaintes : %s\n' "$status" "$(sonde__complaints "$output")"
  printf '=== Status 20-decision : %s\n' "$(ticket_status 20-decision)"
  sonde__journal "run.log après le drain 2"

  set -e
  false
}

@test "V4 une session routée pose successor-armed sur un run.log portant budget-wall" {
  sonde__ticket 20-decision
  sonde__ticket 21-second
  printf '2026-09-06T00:00:00Z\t-\tbudget-wall\tturns=0\tcost=0\ttokens=0\taction=none\n' \
    >>"$FEATURE_DIR/run.log"

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/ | head -1)"
printf '2026-09-06T00:00:01Z\t-\tsuccessor-armed\tturns=0\tcost=0\ttokens=0\taction=none\n' \
  >>"$dir/run.log"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  # Premier drain : la note « tué pendant le drainage » est dite, la session ajoute
  # sa ligne. Second drain : la note doit être remplacée par le retrait nommé, pas
  # par un silence.
  run bash -c 'printf "o\nn\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain 1 rc=%s\n' "$status"
  printf '%s\n' "$output" | grep -n 'budget-wall' | sed 's/^/    /'

  run bash -c 'printf "n\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain 2 rc=%s\n' "$status"
  printf '=== ce que le drain 2 dit de budget-wall :\n'
  printf '%s\n' "$output" | grep -n 'budget-wall' | sed 's/^/    /'
  printf '=== réserve dite ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'as cheap to arrange as one that is there' || true)"
  sonde__journal "run.log au second drain"

  set -e
  false
}

@test "V5 un matin ordinaire : un run AFK vert, puis un drain" {
  # Le prix du correctif. La nouvelle phrase est un second bras d un `if` qui ne
  # se déclenchait pas ; si elle arrivait sur tous les matins, elle serait le bruit
  # que [37] a interdit.
  use_tickets 01-alpha
  sonde__ticket 20-decision

  script_claude <<'FAKE'
#!/usr/bin/env bash
# Dans le cwd et pas dans le projet : une itération travaille dans un worktree.
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== run AFK rc=%s\n' "$status"
  sonde__journal "run.log après le run"

  run bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  printf '=== lignes de note de run dites : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'run.log carries' || true)"
  printf '=== réserve dite ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'as cheap to arrange as one that is there' || true)"
  printf '=== les douze premières lignes du drain :\n'
  printf '%s\n' "$output" | sed -n '1,12p' | sed 's/^/    /'

  set -e
  false
}
