#!/usr/bin/env bats
#
# Sondes de [56] — la chaîne complète, **après** la réparation.
#
# La passe du 31/08 avait mesuré le défaut de bout en bout
# (`../passe-31-08/p2-*.bats`) : la session routée écrit le correctif dans
# l'arbre principal, rien ne commite, le drain réinjecte quand même en promettant
# « a fresh session and the whole gate decide now », et le run AFK — qui tourne
# depuis [13] dans un worktree créé au tip de la branche — juge l'**absence** du
# correctif. Trois itérations rouges, budget de retries brûlé, retour au puits en
# `Failures: 3` / `failed-impl`.
#
# Ce que ces sondes rejouent : le même scénario sur le code livré. Le gate est
# réduit à la seule question qui compte, `TEST_CMD='test -f src/human-note.txt'`,
# et la session routée écrit ce fichier **hors** de la write-surface du ticket —
# sans quoi la session AFK le fabriquerait elle-même et la sonde serait verte des
# deux côtés.
#
# Instruments, pas tests : chacune finit par un `false` volontaire.

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

routed_session_writes_the_fix() {
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
mkdir -p src
printf 'HUMAN-FIX\n' >src/human-note.txt
exit 0
SCRIPT
}

# ── S1 — l'état par défaut : personne n'a commité ─────────────────────────────

@test "S1 un correctif non commité n'est plus promis au gate" {
  use_tickets 09-escalated
  set_config TEST_CMD 'test -f src/human-note.txt'
  routed_session_writes_the_fix

  drain <<'ANSWERS'
o
r
n
ANSWERS
  printf '=== rc du drain   : %s\n' "$status"
  printf '=== ce que le drain a dit de l’arbre ---------------\n'
  printf '%s\n' "$output" |
    grep -i 'left \|already uncommitted\|cannot go back\|back on the frontier' |
    sed 's/^/  /'
  printf '=== Status après  : %s\n' "$(ticket_status 09-escalated)"
  printf '=== Failures      : %s\n' "$(ticket_field 09-escalated Failures)"

  # Et ce que le run AFK en fait : le ticket n'est pas sur la frontière, donc
  # aucune session n'est dépensée et aucun budget n'est brûlé.
  rm -f "$SHIM_STATE/claude.script"
  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== sessions AFK  : %s\n' "$(claude_call_count)"
  printf '=== Status final  : %s\n' "$(ticket_status 09-escalated)"
  printf '=== Failures      : %s\n' "$(ticket_field 09-escalated Failures)"

  set -e
  false
}

# ── S2 — le témoin appairé : le correctif commité, dans le bon ordre ──────────

@test "S2 le même correctif, commité, est réinjecté et jugé" {
  use_tickets 09-escalated
  set_config TEST_CMD 'test -f src/human-note.txt'
  routed_session_writes_the_fix

  # Premier drainage : la conversation produit le correctif, l'humain le laisse
  # dans le puits le temps de commiter.
  drain <<'ANSWERS'
o
n
ANSWERS
  printf '=== drain 1 rc    : %s\n' "$status"

  git -C "$PROJECT_DIR" add src/human-note.txt
  git -C "$PROJECT_DIR" commit -q -m 'humain: le correctif'

  drain <<'ANSWERS'
r
ANSWERS
  printf '=== drain 2 rc    : %s\n' "$status"
  printf '%s\n' "$output" | grep -i 'back on the frontier' | sed 's/^/  /'
  printf '=== Status après  : %s\n' "$(ticket_status 09-escalated)"

  rm -f "$SHIM_STATE/claude.script"
  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== Status final  : %s\n' "$(ticket_status 09-escalated)"
  printf '=== verdicts du gate ------------------------------\n'
  printf '%s\n' "$output" | grep -i 'tests=\|gate:' | sed 's/^/  /'

  set -e
  false
}

# ── S3 — ce que le refus lit est un arbre que la session écrit aussi ──────────

@test "S3 une session routée qui reprend ce qu'elle a écrit rend l'arbre propre" {
  # Question 5 rejouée sur le code livré : le refus compare l'arbre à `HEAD` par
  # git, et la session routée peut écrire les deux. Elle peut donc rendre l'arbre
  # propre sans que le correctif soit sur la branche.
  #
  # Ce que ça coûte et ce que ça ne coûte pas est la question de la sonde : la
  # promesse « le gate décide sur ce qui est commité » reste vraie — c'est `HEAD`
  # qu'un worktree neuf porte, et personne n'a besoin de le dire au drain.
  use_tickets 09-escalated
  set_config TEST_CMD 'test -f src/human-note.txt'
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
mkdir -p src
printf 'HUMAN-FIX\n' >src/human-note.txt
rm -f src/human-note.txt
rmdir src 2>/dev/null || true
exit 0
SCRIPT

  drain <<'ANSWERS'
o
r
ANSWERS
  printf '=== rc du drain   : %s\n' "$status"
  printf '=== ce que le drain a dit de l’arbre ---------------\n'
  printf '%s\n' "$output" |
    grep -i 'left \|already uncommitted\|cannot go back\|back on the frontier' |
    sed 's/^/  /'
  printf '=== Status après  : %s\n' "$(ticket_status 09-escalated)"

  rm -f "$SHIM_STATE/claude.script"
  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== Status final  : %s\n' "$(ticket_status 09-escalated)"
  printf '=== Escalation    : %s\n' "$(ticket_field 09-escalated Escalation)"
  printf '=== verdicts du gate ------------------------------\n'
  printf '%s\n' "$output" | grep -i 'tests=\|gate:' | sed 's/^/  /'

  set -e
  false
}
