#!/usr/bin/env bats
#
# Passe transversale du 05/09 — Q3.
#
# [48] a écrit, en commentaire de `tracker_local__refuse_name` :
#
#   « the line has to survive being printed from a subshell: every consumer reads
#     these lists as `$(tracker_ids)`, so a "say it once" flag kept in a variable
#     would be forgotten between two callers and would quietly say it never. »
#
# Le raisonnement porte sur la substitution de commande. Il ne porte pas sur la
# redirection : quatre consommateurs lisent `$(tracker_ids 2>/dev/null)` ou
# `tracker_field … 2>/dev/null`, et jettent la ligne.
#
#   playthrough.sh:494  playthrough__injected      [11]
#   router.sh:539       router__tracker_state      [61]
#   router.sh:646       router_protect_tracker     [55]
#
# Ce que [48] a écrit dans `docs/frontiere-de-confiance.md` : « aucun garde ne
# bouge et la ligne stderr du producteur est le seul témoin ». Et la contrainte
# d'interface écrite pour [18] est « un backend ne rend jamais un id porteur d'un
# saut de ligne, **il refuse à voix haute** ».
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

# Le fichier au nom porteur d'un saut de ligne, posé AVANT le run — le cas que
# [48] a laissé au décor : aucun garde ne le voit bouger.
sonde__plant() {
  local name="50-a"$'\n'"b.md"
  {
    printf '# 50 — a ticket nobody can address\n\n'
    printf '**Status:** ready-for-agent\n\n'
    printf '**Write-surface:** `src/nowhere.txt`\n\n'
    printf '**Blocked by:** None\n'
  } >"$TRACKER_DIR/$name"
  printf '=== fichier posé : %s\n' "$(ls "$TRACKER_DIR" | LC_ALL=C tr '\n' '|')"
}

sonde__count() {
  printf '%s\n' "$1" | grep -c 'carries a newline in its name' || true
}

mk_human_ticket() {
  local file="$TRACKER_DIR/20-first.md"
  {
    printf '# 20-first — for the drain\n\n'
    printf '**Status:** ready-for-human\n\n'
    printf '**Escalation:** failed-impl\n\n'
    printf '**Write-surface:** `src/one.txt`\n\n'
    printf '**Blocked by:** None\n'
  } >"$file"
  harness__commit "sonde: 20-first"
}

@test "Q3a un run AFK avec le fichier inadressable : combien de fois la ligne est dite" {
  use_tickets 01-alpha
  sonde__plant

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run                       : %s\n' "$status"
  printf '=== la ligne de refus, combien de fois : %s\n' "$(sonde__count "$output")"
  printf '=== run.log existe ?                : %s (%s lignes)\n' \
    "$([ -f "$FEATURE_DIR/run.log" ] && echo oui || echo NON)" \
    "$(awk 'END { print NR + 0 }' "$FEATURE_DIR/run.log" 2>/dev/null)"
  printf '=== run.log porte la ligne ?        : %s\n' \
    "$(grep -c 'carries a newline' "$FEATURE_DIR/run.log" 2>/dev/null | head -1)"
  printf '=== run.log ------------------------------------------\n%s\n' \
    "$(sed 's/^/    /' "$FEATURE_DIR/run.log" 2>/dev/null)"
  printf '=== le reçu porte-t-il la ligne ?   : %s\n' \
    "$(grep -rc 'carries a newline' "$PROJECT_DIR/receipts" 2>/dev/null | head -3)"
  printf '=== le playthrough la porte-t-il ?  : %s\n' \
    "$(grep -c 'carries a newline' "$(playthrough_file)" 2>/dev/null | head -1)"
  printf '=== sortie du run -----------------------------------\n%s\n' "$output"

  set -e
  false
}

@test "Q3b le drain humain avec le même fichier : combien de fois la ligne est dite" {
  mk_human_ticket
  sonde__plant

  run bash "$PACK_DIR/human-loop.sh" <<'ANSWERS'
q
ANSWERS
  printf '=== rc du drain                     : %s\n' "$status"
  printf '=== la ligne de refus, combien de fois : %s\n' "$(sonde__count "$output")"
  printf '=== sortie du drain ---------------------------------\n%s\n' "$output"

  set -e
  false
}

@test "Q3c le drain qui ouvre une session routée : router_protect_tracker et le pin" {
  mk_human_ticket
  sonde__plant

  script_claude <<'FAKE'
#!/usr/bin/env bash
printf 'fixed by the routed session\n' >src/one.txt 2>/dev/null || true
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run bash "$PACK_DIR/human-loop.sh" <<'ANSWERS'
o
q
ANSWERS
  printf '=== rc du drain                     : %s\n' "$status"
  printf '=== la ligne de refus, combien de fois : %s\n' "$(sonde__count "$output")"
  printf '=== sortie du drain ---------------------------------\n%s\n' "$output"

  set -e
  false
}

@test "Q3d playthrough__injected au module : la voix passe-t-elle ?" {
  use_tickets 01-alpha
  sonde__plant

  pack_run 'playthrough__injected'
  printf '=== playthrough__injected rc=%s\n' "$status"
  printf '=== ce quon entend :\n%s\n' "$output"

  pack_run 'tracker_ids'
  printf '=== tracker_ids nu, rc=%s :\n%s\n' "$status" "$output"

  set -e
  false
}

@test "Q3e un ticket au slug du gate de valeur, créé par une session : la borne" {
  use_tickets 01-alpha
  # Ce qu'une session peut déposer dans `issues/` : [21] laisse en place les
  # fichiers CRÉÉS (statut `A`), la quarantaine [07] les renumérote.
  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/issues 2>/dev/null | head -1)"
for n in 60 61 62; do
  {
    printf '# %s-playthrough-wiring-forged — planted by a session\n\n' "$n"
    printf '**Status:** ready-for-agent\n\n'
    printf '**Write-surface:** `src/forged.txt`\n\n'
    printf '**Blocked by:** None\n'
  } >"$dir/$n-playthrough-wiring-forged.md"
done
mkdir -p src && printf 'alpha\n' >src/alpha.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  local runrc="$status" runout="$output"
  printf '=== rc du run                : %s\n' "$runrc"
  printf '=== tickets présents         : %s\n' "$(ls -1 "$TRACKER_DIR" | tr '\n' ' ')"
  printf '=== git status du dépôt      :\n%s\n' \
    "$(git -C "$PROJECT_DIR" status --porcelain | sed 's/^/    /')"
  pack_run 'playthrough__injected'
  printf '=== playthrough__injected    : %s\n' "$output"
  printf '=== sortie du run -----------------------------------\n%s\n' "$runout"

  set -e
  false
}
