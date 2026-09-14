#!/usr/bin/env bats
#
# Passe transversale du 14/09 — Q3.
#
# `loop_session_prompt` porte quatre règles. Une seule est **dérivée** du module
# qui la tient — les règles de langue, `$(lang_session_rules)`, et son commentaire
# écrit la règle générale de [17] :
#
#     « the sentence a session is asked to follow and the check that keeps it
#       live in one file, so the prompt cannot go on promising a guarantee the
#       day the check moves. It says "checked" only where it is. »
#
# Les trois autres sont tapées dans le heredoc. Deux n'ont pas de liste à dériver
# (la write-surface, le statut du ticket). La troisième en a une, et elle est
# fausse d'un cran : le prompt dit `.scratch/`, le désindexage est scopé sur
# `issues/`.
#
# Instrument, pas test : le cas finit par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

@test "Q3 les quatre règles du prompt, et ce qui tient chacune" {
  printf '=== le prompt, tel qu il est écrit :\n'
  sed -n '/^## Rules$/,/^PROMPT$/p' "$RALPH_PACK_ROOT/.claude/loop.sh" | sed 's/^/    /'

  printf '=== la seule dérivée :\n'
  grep -n 'lang_session_rules' "$RALPH_PACK_ROOT/.claude/loop.sh" "$RALPH_PACK_ROOT/.claude/lib/lang.sh" |
    sed 's/^/    /'

  printf '=== ce que le désindexage couvre vraiment :\n'
  grep -n 'git -C "\$root" reset -q --' "$RALPH_PACK_ROOT/.claude/lib/tracker-local.sh" | sed 's/^/    /'
  grep -n 'tracker_local__issues_relpath() {' -A 9 "$RALPH_PACK_ROOT/.claude/lib/tracker-local.sh" |
    sed 's/^/    /'

  printf '=== donc, sous .scratch/<feature>/, ce que le prompt promet et ce qui tombe :\n'
  printf '    issues/**   désindexé par tracker_local_snapshot_moved, restauré par [21]\n'
  printf '    spec.md     ni désindexé ni restauré — gate_is_bookkeeping le retire\n'
  printf '                du rapport du scope-guard et du rollback\n'
  printf '=== gate_is_bookkeeping, pour mémoire :\n'
  grep -n 'gate_is_bookkeeping() {' -A 5 "$RALPH_PACK_ROOT/.claude/lib/gate.sh" | sed 's/^/    /'

  set -e
  false
}
