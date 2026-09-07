#!/usr/bin/env bats
#
# Ticket [68] — vérification sur des drains et des runs réels, après correctif.
#
# `passe-06-09/q5` a mesuré le défaut : une session routée réécrit `spec.md`, le
# gate de valeur du run suivant rejoue le flux forgé, et ni le drain ni le run
# n'en disent un mot. Ce que `test/human-loop.bats` pose est le même état avec un
# faux `claude` qui n'écrit rien d'autre ; l'écart que la leçon 3 du CLAUDE.md
# demande de sonder est celui-là : une session routée qui écrit **et commite**,
# un run AFK réel derrière elle, et le drainage suivant.
#
#   V1  Q5a rejoué sur le code livré. Le drain doit nommer la réécriture ; le
#       **coût résiduel** doit être visible : l'écriture survit, le drainage
#       suivant l'épingle comme sa propre base et ne dit plus rien, et le gate de
#       valeur du run d'après rejoue toujours le flux forgé
#   V2  la session efface `spec.md`. La phrase doit dire que ce que ça coûte est
#       la clôture, et le run suivant doit effectivement refuser de clore
#   V3  témoin appairé, le plus cher à tenir : une session qui écrit, commite et
#       déplace un ticket voisin — donc `router_protect_tracker` journalise.
#       Zéro ligne `spec-drift`, et le drain ne s'accuse pas de son propre journal
#   V4  un run AFK **réel** avant le drain : les producteurs du pack (le témoin de
#       [11], le journal, le reçu) ne doivent pas être nommés comme une dérive
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

sonde__spec() {
  printf '=== %s\n' "$1"
  printf '    spec.md porte le marqueur forgé ? : %s\n' \
    "$(grep -c 'FORGED BY A ROUTED SESSION' "$FEATURE_DIR/spec.md" 2>/dev/null || true)"
  printf '    spec.md est-il là ?               : %s\n' \
    "$([ -e "$FEATURE_DIR/spec.md" ] && echo oui || echo non)"
}

sonde__said() {
  printf '=== ce que le drain a dit du flux :\n'
  printf '%s\n' "$1" | grep -n 'spec.md' | sed 's/^/    /' || printf '    (rien)\n'
  printf '=== se plaint-il de son journal ? (0 attendu) : %s\n' \
    "$(printf '%s\n' "$1" | grep -c 'does not hold exactly' || true)"
  printf '=== lignes spec-drift dans run.log : %s\n' \
    "$(grep -c 'spec-drift' "$FEATURE_DIR/run.log" 2>/dev/null || true)"
}

# Une session routée qui réécrit le flux, écrit du code et commite.
sonde__session_forge() {
  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/ | head -1)"
printf '# spec\n\n## User flow\n\nFORGED BY A ROUTED SESSION: the user opens the app and everything already works.\n' \
  >"$dir/spec.md"
mkdir -p "$root/src" && printf 'human fix\n' >"$root/src/20-decision.txt"
git -C "$root" add src/20-decision.txt
git -C "$root" -c user.email=h@x -c user.name=h commit -q -m "correctif humain"
exit 0
FAKE
}

@test "V1 la session réécrit le flux : le drain le nomme, et le coût résiduel se mesure" {
  sonde__ticket 20-decision
  sonde__spec 'avant le drain'
  sonde__session_forge

  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  local said="$output"
  printf '=== drain rc=%s\n' "$status"
  sonde__said "$said"
  sonde__spec 'après le drain'

  # Le résidu 1 : l'écriture survit, donc le drainage suivant l'épingle comme sa
  # propre base — et ne dit plus rien.
  script_claude <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== second drainage : dit-il quelque chose du flux ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'spec.md' || true)"

  # Le résidu 2 : le gate de valeur du run suivant rejoue ce que le disque porte.
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

  set -e
  false
}

@test "V2 la session efface le flux : ce que ça coûte est la clôture, et le run suivant le montre" {
  sonde__ticket 20-decision
  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/ | head -1)"
rm -f "$dir/spec.md"
exit 0
FAKE

  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  local said="$output"
  printf '=== drain rc=%s\n' "$status"
  sonde__said "$said"
  sonde__spec 'après le drain'

  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== le run dit-il que la feature ne peut pas être close ? :\n'
  printf '%s\n' "$output" | grep -n 'spec.md' | sed 's/^/    /' || printf '    (rien)\n'
  printf '=== appels du gate de valeur : %s\n' "$(playthrough_call_count 2>/dev/null || true)"

  set -e
  false
}

@test "V3 témoin appairé : une session qui écrit, commite et déplace un voisin ne fait dire aucun mot du flux" {
  sonde__ticket 20-decision
  sonde__ticket 21-second
  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
perl -pi -e 's/^\*\*Failures:\*\* .*$//' "$tracker/21-second.md"
printf '\n**Failures:** 2\n' >>"$tracker/21-second.md"
mkdir -p "$root/src" && printf 'human fix\n' >"$root/src/20-decision.txt"
git -C "$root" add src/20-decision.txt
git -C "$root" -c user.email=h@x -c user.name=h commit -q -m "correctif humain"
exit 0
FAKE

  run bash -c 'printf "o\nn\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  local said="$output"
  printf '=== drain rc=%s\n' "$status"
  sonde__said "$said"
  printf '=== a-t-il bien nommé la dérive du tracker (attendu >0) : %s\n' \
    "$(printf '%s\n' "$said" | grep -c 'tracker-drift\|Failures:' || true)"

  set -e
  false
}

@test "V4 un run AFK réel avant le drain : rien de ce que le pack écrit n'est nommé comme une dérive" {
  use_tickets 01-alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
  run_loop
  printf '=== rc du run AFK : %s\n' "$status"

  sonde__ticket 20-decision
  script_claude <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE
  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain rc=%s\n' "$status"
  printf '=== dit-il quelque chose du flux ? (0 attendu) : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'spec.md' || true)"
  printf '=== lignes spec-drift dans run.log (0 attendu) : %s\n' \
    "$(grep -c 'spec-drift' "$FEATURE_DIR/run.log" 2>/dev/null || true)"

  set -e
  false
}
