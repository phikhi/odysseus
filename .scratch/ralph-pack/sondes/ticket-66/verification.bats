#!/usr/bin/env bats
#
# Ticket [66] — vérification sur des drains et un run réels, après correctif.
#
# `passe-06-09/q1` a mesuré le défaut dans les deux sens. Ce que
# `test/human-loop.bats` pose est le même état avec un faux `claude` qui n'écrit
# rien d'autre ; l'écart que la leçon 3 du CLAUDE.md demande de sonder est
# celui-là : une session routée qui écrit vraiment et qui commite, un run AFK réel
# qui écrit une **vraie** ref `failed/<id>`, et le ticket voisin que le même
# drainage atteint ensuite.
#
# Ce qui est demandé ici et que la suite ne demande pas :
#
#   V1  Q1a rejoué sur le code livré — la session crée la ref. Le guichet doit
#       tenir dans ce drainage, la création doit être nommée, et le **coût
#       résiduel** doit être visible : le drainage suivant épingle la ref forgée
#   V2  Q1c rejoué — la session efface la ref d'une tentative réellement jugée.
#       La phrase doit dire que la preuve est perdue, et le drainage suivant doit
#       montrer qu'elle l'est vraiment
#   V3  témoin appairé, et le plus cher à tenir : une session qui écrit, commite
#       et déplace un ticket voisin — donc `router_protect_tracker` journalise.
#       Zéro ligne de ref, et le drain ne s'accuse pas de son propre journal
#   V4  un run AFK **réel** qui écrit une vraie `failed/<id>`, puis un drain.
#       Le producteur du pack ne doit pas être nommé comme une dérive
#   V5  le voisin : la session écrit `failed/21-second` pendant que le drain est
#       sur `20-decision`. Où atterrit le guichet de `21-second` dans le même
#       drainage
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

sonde__refs() {
  printf '=== %s\n' "$1"
  printf '    refs failed/*            : %s\n' \
    "$(git -C "$PROJECT_DIR" for-each-ref --format='%(refname)' refs/heads/failed/ |
      tr '\n' ' ')"
}

sonde__said() {
  printf '=== ce que le drain a dit des refs :\n'
  printf '%s\n' "$1" | grep -n 'refs/heads/failed' | sed 's/^/    /' ||
    printf '    (rien)\n'
  printf '=== se plaint-il de son journal ? (0 attendu) : %s\n' \
    "$(printf '%s\n' "$1" | grep -c 'does not hold exactly' || true)"
  printf '=== lignes ref-drift dans run.log : %s\n' \
    "$(grep -c 'ref-drift' "$FEATURE_DIR/run.log" 2>/dev/null || true)"
}

sonde__dossier() {
  printf '=== dossier de %s dans ce drainage :\n' "$2"
  printf '%s\n' "$1" | sed -n "/── $2 ──/,/receipt/p" | sed 's/^/    /'
}

@test "V1 la session crée la ref : le guichet tient, la création est nommée, le coût résiduel est visible" {
  sonde__ticket 20-decision
  sonde__refs 'avant'

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
git -C "$root" update-ref refs/heads/failed/20-decision HEAD
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\no\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain 1 rc=%s, sessions=%s\n' "$status" "$(claude_call_count)"
  sonde__said "$output"
  printf '=== le guichet de la seconde session (admit attendu) :\n'
  printf '%s\n' "$output" | grep -n 'opening a .* session' | sed 's/^/    /'
  sonde__dossier "$output" 20-decision
  sonde__refs 'après'

  # Le coût résiduel : rien n'a effacé la ref, donc le drainage suivant l'épingle.
  run bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain 2 — le guichet que la ref forgée achète :\n'
  sonde__dossier "$output" 20-decision

  set -e
  false
}

@test "V2 la session efface la ref d une tentative jugée : la phrase dit que la preuve est perdue" {
  sonde__ticket 20-decision
  git -C "$PROJECT_DIR" branch failed/20-decision
  sonde__refs 'avant — une tentative réellement jugée'

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
git -C "$root" update-ref -d refs/heads/failed/20-decision
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\no\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain 1 rc=%s\n' "$status"
  sonde__said "$output"
  printf '=== la phrase entière :\n'
  printf '%s\n' "$output" | grep 'is gone, and this drain took' | fold -w 76 |
    sed 's/^/    /'
  printf '=== le guichet de la seconde session (arbitrate attendu) :\n'
  printf '%s\n' "$output" | grep -n 'opening a .* session' | sed 's/^/    /'
  sonde__refs 'après — rien ne la remet'

  run bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain 2 — ce qu il reste à lire, la preuve étant perdue :\n'
  sonde__dossier "$output" 20-decision

  set -e
  false
}

@test "V3 témoin appairé : une session qui écrit, commite et déplace un voisin ne fait dire aucune ref" {
  sonde__ticket 20-decision
  sonde__ticket 21-second
  git -C "$PROJECT_DIR" branch failed/20-decision
  {
    printf '2026-09-05T00:00:00Z\t01-old\tresolved\tturns=3\tcost=1\ttokens=9\taction=none\n'
    printf '2026-09-05T00:00:01Z\t02-old\tresolved\tturns=2\tcost=1\ttokens=8\taction=none\n'
  } >>"$FEATURE_DIR/run.log"

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
mkdir -p "$root/src"
printf 'HUMAN-FIX\n' >"$root/src/human-note.txt"
git -C "$root" add src/human-note.txt
git -C "$root" -c user.name=sonde -c user.email=sonde@local commit -q -m 'la session commite'
perl -pi -e 's/^\*\*Status:\*\* .*$/**Status:** resolved/' "$tracker/21-second.md"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nn\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  sonde__said "$output"
  printf '=== la dérive du tracker a-t-elle bien été journalisée ? : %s\n' \
    "$(grep -c 'tracker-drift' "$FEATURE_DIR/run.log" || true)"
  printf '=== run.log :\n'
  sed 's/^/    /' "$FEATURE_DIR/run.log"

  set -e
  false
}

@test "V4 un run AFK réel écrit une vraie failed/<id> : le drain ne la nomme pas comme une dérive" {
  # Le producteur du pack, pas une ref plantée par une sonde. Un ticket que le
  # gate refuse trois fois écrit `failed/<id>` et escalade dans le puits ; le
  # drain qui arrive derrière doit l'épingler comme une preuve légitime et n'en
  # rien dire.
  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
# Dans le cwd : une itération travaille dans un worktree. Le fichier est hors du
# TEST_CMD, donc le gate rougit et le run finit par escalader.
mkdir -p src && printf 'broken\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
  set_config TEST_CMD 'false'

  run_loop
  printf '=== run AFK rc=%s\n' "$status"
  sonde__refs 'après le run'
  printf '=== Status 01-alpha : %s / Escalation : %s\n' \
    "$(ticket_status 01-alpha)" "$(ticket_field 01-alpha Escalation)"

  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE
  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  sonde__said "$output"
  sonde__dossier "$output" 01-alpha

  set -e
  false
}

@test "V5 le voisin : la ref est écrite sur 21-second pendant que le drain est sur 20-decision" {
  sonde__ticket 20-decision
  sonde__ticket 21-second

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
git -C "$root" update-ref refs/heads/failed/21-second HEAD
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nn\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  sonde__said "$output"
  printf '=== le guichet que 21-second reçoit dans CE drainage :\n'
  sonde__dossier "$output" 21-second
  printf '=== lignes du journal portant 21-second :\n'
  awk -F'\t' '$2 == "21-second"' "$FEATURE_DIR/run.log" | sed 's/^/    /'

  set -e
  false
}
