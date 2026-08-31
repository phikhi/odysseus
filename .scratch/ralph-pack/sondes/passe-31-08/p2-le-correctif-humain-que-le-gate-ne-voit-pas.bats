#!/usr/bin/env bats
#
# Passe transversale du 31/08 — question 4 posée au second point d'entrée :
# *qu'hérite le run AFK de ce qu'une boucle humaine laisse derrière elle ?*
#
# Le drain promet, à la touche `r` : « back on the frontier, retry budget
# cleared — a fresh session and the whole gate decide now ». Le prompt de la
# session routée promet la même chose : « Whatever code comes out of this
# conversation goes back through the gate. It is re-injected on the frontier and
# ground by a fresh session ».
#
# Mais la session routée écrit dans l'**arbre principal**, sans rien qui commite,
# et depuis [13] une itération AFK tourne dans un worktree créé au **tip de la
# branche** (`concurrency_worktree_add` : `git worktree add --detach "$dir"
# "$(git rev-parse HEAD)"`). Ce qui n'est pas commité n'est donc pas là.
#
# La sonde mesure le gate sur ce que le correctif humain a écrit, et rien
# d'autre : `TEST_CMD` demande le fichier que la session routée a écrit.
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

drain() {
  run bash "$PACK_DIR/human-loop.sh"
}

# La session routée : elle écrit le correctif dans l'arbre où le drain l'a
# lancée, hors de la write-surface du ticket pour que la session AFK (qui écrit
# `src/theta.txt`) ne le fabrique pas elle-même.
routed_session_writes_the_fix() {
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
mkdir -p src
printf 'HUMAN-FIX\n' >src/human-note.txt
exit 0
SCRIPT
}

# ── P2a — le correctif n'est pas commité, ce qui est l'état par défaut ─────────

@test "P2a le correctif d'une session routée, non commité, n'atteint pas le gate" {
  use_tickets 09-escalated
  # Le gate ne juge plus qu'une chose : le correctif humain est-il là ?
  set_config TEST_CMD 'test -f src/human-note.txt'
  routed_session_writes_the_fix

  drain <<'ANSWERS'
o
r
ANSWERS
  printf '=== rc du drain   : %s\n' "$status"
  printf '=== Status après  : %s\n' "$(ticket_status 09-escalated)"

  printf '=== arbre principal après le drain -----------------\n'
  printf '  contenu : %s\n' "$(cat "$PROJECT_DIR/src/human-note.txt" 2>/dev/null || printf '<absent>')"
  printf '  git status --porcelain :\n'
  git -C "$PROJECT_DIR" status --porcelain | sed 's/^/    /'

  # La session AFK reprend le shim par défaut : elle livre la write-surface du
  # ticket, comme une session ordinaire.
  rm -f "$SHIM_STATE/claude.script"
  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== Status final  : %s\n' "$(ticket_status 09-escalated)"
  printf '=== Failures      : %s\n' "$(ticket_field 09-escalated Failures)"
  printf '=== Escalation    : %s\n' "$(ticket_field 09-escalated Escalation)"
  printf '=== verdicts du gate ------------------------------\n'
  printf '%s\n' "$output" | grep -i 'tests=\|scope=\|verdict\|red\|green' | sed 's/^/  /'

  printf '=== arbre principal après le run AFK ---------------\n'
  printf '  contenu : %s\n' "$(cat "$PROJECT_DIR/src/human-note.txt" 2>/dev/null || printf '<absent>')"
  printf '  git status --porcelain :\n'
  git -C "$PROJECT_DIR" status --porcelain | sed 's/^/    /'

  set -e
  false
}

# ── P2b — le témoin appairé : le même correctif, commité ──────────────────────

@test "P2b le même correctif, commité à la main, est jugé" {
  use_tickets 09-escalated
  set_config TEST_CMD 'test -f src/human-note.txt'
  routed_session_writes_the_fix

  drain <<'ANSWERS'
o
r
ANSWERS
  printf '=== rc du drain   : %s\n' "$status"

  # La seule différence avec P2a : un humain qui commite avant de partir. Rien
  # dans le pack ne le lui demande.
  git -C "$PROJECT_DIR" add src/human-note.txt
  git -C "$PROJECT_DIR" commit -q -m 'humain: le correctif'

  rm -f "$SHIM_STATE/claude.script"
  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== Status final  : %s\n' "$(ticket_status 09-escalated)"
  printf '=== verdicts du gate ------------------------------\n'
  printf '%s\n' "$output" | grep -i 'tests=\|scope=\|verdict\|red\|green' | sed 's/^/  /'

  set -e
  false
}
