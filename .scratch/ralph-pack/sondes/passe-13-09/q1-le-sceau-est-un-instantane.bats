#!/usr/bin/env bats
#
# Passe transversale du 13/09 — Q1.
#
# [81] a remplacé la liste écrite à la main par un **recensement dérivé** : le
# sceau est « une marche de ce que le pack vient d'écrire », prise dans `loop.sh`
# en dernier, après le dernier écrivain des bases de la nuit et avant la première
# session. Le commentaire de `gate_witness_seal` dit la règle :
#
#     « A thirteenth object put in one of these directories tomorrow is sealed by
#       the line that creates it and by nothing else. »
#
# Vraie pour un objet créé par une ligne qui tourne **avant** la prise du sceau.
# Ces sondes demandent ce que devient un objet que le pack crée dans les mêmes
# porteurs **après** — la dérivation est complète dans l'espace et figée dans le
# temps.
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

# Le tier est off dans le harnais ([06], [14]) ; les deux helpers sont ceux de
# `test/capability.bats`, recopiés ici pour que la sonde ne charge pas un .bats.
retro_on() {
  set_config RETRO on
}

opened_ticket() {
  ls "$TRACKER_DIR" 2>/dev/null | grep "$1" | head -1
}

# Une session honnête qui, en plus, exécute le geste qu'on lui donne — et qui
# rend au rétro la réponse que `retro_answer` a écrite, parce que
# `script_claude` remplace le faux **entier** (shim `claude`, ligne 190) et
# qu'une sonde qui l'oublie mesure un rétro muet.
sonde__session() {
  { printf '#!/usr/bin/env bash\nprompt="$(cat)"\n'
    cat <<'HEAD'
if printf '%s' "$prompt" | grep -q 'RALPH-RETRO-NOTHING'; then
  printf 'un\n' >>"$RALPH_SHIM_STATE/retro.seen"
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

@test "Q1a un fichier créé dans un porteur après la prise du sceau" {
  local script="$RALPH_TEST_DIR/apres-le-sceau.sh"
  cat >"$script" <<'ASK'
d="$(mktemp -d)"
printf 'pinned\n' >"$d/ledger"
printf 'pinned\n' >"$d/manifest"
RALPH_WITNESS_SEAL="$(gate_witness_seal "$d")"
printf '=== ce que le sceau couvre :\n'
printf '%s\n' "$RALPH_WITNESS_SEAL" | sed 's|.*/|    |'

printf 'forged\n' >"$d/apres-coup"
printf '=== gate_witness_moved après la création dun treizieme objet :\n'
gate_witness_moved | sed 's/^/    /' || printf '    (rien — silence)\n'
printf '=== gate_witness_note :\n'
gate_witness_note | sed 's/^/    /' || printf '    (rien — silence)\n'

printf '=== et le même fichier réécrit ensuite :\n'
printf 'again\n' >"$d/apres-coup"
gate_witness_moved | sed 's/^/    /' || printf '    (rien — silence)\n'

printf '=== témoin appairé : un fichier qui ÉTAIT dans le sceau, réécrit :\n'
printf 'rewritten\n' >"$d/manifest"
gate_witness_moved | sed 's/^/    /' || printf '    (rien — silence)\n'
rm -rf "$d"
ASK
  pack_run ". '$script'"
  printf '%s\n' "$output"

  set -e
  false
}

@test "Q1b ce que le pack lui-même crée dans ses porteurs après les avoir scellés" {
  # Une session honnête qui relève ce qu'il y a dans les deux porteurs au moment
  # où elle tourne — aucun nom ne lui est donné, elle globbe — et qui déborde sa
  # write-surface à sa première tournée, pour que l'itération soit rejouée : le
  # brief de [14] n'existe que sur une deuxième tentative.
  use_tickets 01-alpha 02-beta
  retro_on
  mkdir -p "$PROJECT_DIR/.claude/skills/migrations"
  retro_answer \
    "RALPH-RETRO-CAPABILITY: skill migrations" \
    "RALPH-RETRO-CAPABILITY-WHY: rien ici na lu les migrations"

  sonde__session '
n="$(ls "$RALPH_SHIM_STATE"/releve.* 2>/dev/null | wc -l | tr -d " ")"
n=$((n + 1))
{ for d in "${TMPDIR:-/tmp}"/ralph-retro.* "${TMPDIR:-/tmp}"/ralph-frontier.*; do
    [ -d "$d" ] || continue
    printf "%s :\n" "${d##*/}"
    ls -A "$d" | sed "s/^/    /"
  done
} >"$RALPH_SHIM_STATE/releve.$n"
if [ "$n" = 1 ]; then mkdir -p rogue; printf "hors surface\n" >rogue/out.txt; fi'

  run_loop_own_tmp
  printf '=== rc du run : %s\n' "$status"
  local f
  for f in "$SHIM_STATE"/releve.*; do
    [ -f "$f" ] || continue
    printf '=== relevé %s (une session de livraison) :\n' "${f##*.}"
    sed 's/^/    /' "$f"
  done
  printf '=== rétros passés par la sonde : %s\n' \
    "$(wc -l <"$SHIM_STATE/retro.seen" 2>/dev/null | tr -d ' ')"
  printf '=== ce que le reçu dit de la capacité :\n'
  grep -h -i "capab" "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE"/*.md 2>/dev/null |
    sed 's/^/    /'
  printf '=== ce que le run a dit dun témoin déplacé :\n'
  printf '%s\n' "$output" | grep -i "witness\|témoin" | sed 's/^/    /' ||
    printf '    (aucun)\n'

  set -e
  false
}
