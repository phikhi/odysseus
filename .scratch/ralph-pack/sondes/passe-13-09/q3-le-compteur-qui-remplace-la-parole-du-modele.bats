#!/usr/bin/env bats
#
# Passe transversale du 13/09 — Q3.
#
# `lib/capability.sh` écrit sa propre raison d'être :
#
#     « Both arms are computed from the inventory and from a counter this loop
#       keeps, never from the model's own claim to have seen something before. A
#       model asked "is this recurrent?" answers yes, and that answer would be a
#       guarantee resting on a sentence in a prompt — which is what
#       docs/frontiere-de-confiance.md exists to refuse. »
#
# Le compteur est `capability.seen`, dans le porteur du rétro. Il est créé par
# `capability__seen` à la **première revue de capacités**, donc après la prise du
# sceau de [81] (Q1a, Q1b) : rien ne le tient.
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

retro_on() {
  set_config RETRO on
}

opened_ticket() {
  ls "$TRACKER_DIR" 2>/dev/null | grep "$1" | head -1
}

# Voir la sonde Q1 : `script_claude` remplace le faux **entier**, donc la sonde
# doit rendre elle-même la réponse du rétro.
sonde__session() {
  { printf '#!/usr/bin/env bash\nprompt="$(cat)"\n'
    cat <<'HEAD'
if printf '%s' "$prompt" | grep -q 'RALPH-RETRO-NOTHING'; then
  a="$(awk '{ printf "%s\\n", $0 }' "$RALPH_SHIM_STATE/retro.answer" 2>/dev/null)"
  [ -n "$a" ] || a='RALPH-RETRO-NOTHING'
  printf '{"type":"assistant","message":{"model":"m","id":"m1","type":"message","role":"assistant","content":[{"type":"text","text":"%s"}],"usage":{"input_tokens":10,"output_tokens":2}},"session_id":"s"}\n' "$a"
  printf '{"type":"result","subtype":"success","is_error":false,"result":"%s","num_turns":1,"total_cost_usd":0.02}\n' "$a"
  exit 0
fi
HEAD
    printf '%s\n' "$1"
    cat <<'TAIL'
surface="$(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' |
  head -1 | tr -d '`\r' | tr ',' ' ')"
for t in $surface; do mkdir -p "$(dirname "$t")"; printf 'written\n' >"$t"; done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
TAIL
  } | script_claude
}

sonde__stage() {
  use_tickets 01-alpha
  retro_on
  # Quelque chose répond déjà pour ce nom : c'est le bras `recurrent` qu'on
  # mesure, celui où une seule observation est « une opinion » et où
  # CAPABILITY_RECUR_AT en demande deux.
  mkdir -p "$PROJECT_DIR/.claude/skills/migrations"
  retro_answer \
    "RALPH-RETRO-CAPABILITY: skill migrations" \
    "RALPH-RETRO-CAPABILITY-WHY: rien ici na lu les migrations de ce ticket"
}

sonde__verdict() {
  printf '=== rc du run : %s\n' "$status"
  printf '=== CAPABILITY_RECUR_AT : %s\n' "$(config_default CAPABILITY_RECUR_AT)"
  # Le porteur du rétro est démonté à la fin du run (`retro_close`), donc le
  # compteur ne survit pas au run : ce qu'on lit est ce qu'il a décidé.
  printf '=== ce que le reçu dit :\n'
  grep -h -i "capab\|counted, not proposed" \
    "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md 2>/dev/null | sed 's/^/    /'
  printf '=== ticket ouvert sur le puits humain : %s\n' \
    "$(opened_ticket 'capability-skill-migrations')"
  local opened
  opened="$(opened_ticket 'capability-skill-migrations')"
  if [ -n "$opened" ]; then
    printf '=== ce que le ticket dit du bras franchi :\n'
    sed -n '/Why now/,/Cheapest/p' "$TRACKER_DIR/$opened" | sed 's/^/    /'
  fi
  printf '=== un mot du run sur un témoin déplacé ?\n'
  printf '%s\n' "$output" | grep -i "witness" | sed 's/^/    /' ||
    printf '    (aucun)\n'
}

@test "Q3a la session écrit une observation dans le compteur du rétro" {
  sonde__stage
  sonde__session '
for d in "${TMPDIR:-/tmp}"/ralph-retro.*; do
  [ -d "$d" ] || continue
  printf "skill/migrations\n" >>"$d/capability.seen"
done'

  run_loop_own_tmp
  sonde__verdict

  set -e
  false
}

@test "Q3b témoin appairé : le même run, sans le geste" {
  sonde__stage
  sonde__session ':'

  run_loop_own_tmp
  sonde__verdict

  set -e
  false
}
