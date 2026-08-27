#!/usr/bin/env bats
#
# [37] — s1 : un id est un nom de fichier que la session choisit.
#
# La sonde que le ticket demande : une session dépose
# `.scratch/<feature>/issues/99-my ticket.md`, puis on regarde ce que
# `failures_quarantine_strays` met en quarantaine et sous quel nom.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "S1a un ticket à espace vu par la détection d'intrus" {
  use_tickets 01-alpha

  printf '# 99 — invented\n\n**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Write-surface:** `*`\n' \
    >"$TRACKER_DIR/99-my ticket.md"

  echo "=== ce que tracker_ids rend"
  pack_run 'tracker_ids'
  printf '%s\n' "$output"

  echo "=== ce que failures_tracker_snapshot rend (le format d'échange)"
  pack_run 'printf "[%s]\n" "$(failures_tracker_snapshot)"'
  printf '%s\n' "$output"

  echo "=== ce que failures__strays voit"
  pack_run 'failures__strays "01-alpha"'
  printf '%s\n' "$output"

  echo "=== la quarantaine"
  pack_run 'failures_quarantine_strays 01-alpha "01-alpha"; printf "rc=%s\n" "$?"'
  printf '%s\n' "$output"

  echo "=== le tracker après"
  ls "$TRACKER_DIR"

  echo "=== le statut du ticket à espace"
  pack_run 'tracker_field "99-my ticket" Status; printf "rc=%s\n" "$?"'
  printf '%s\n' "$output"
  false
}

@test "S1b le témoin appairé : le même scénario sans espace" {
  use_tickets 01-alpha

  printf '# 99 — invented\n\n**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Write-surface:** `*`\n' \
    >"$TRACKER_DIR/99-invented.md"

  pack_run 'failures_quarantine_strays 01-alpha "01-alpha"; printf "rc=%s\n" "$?"'
  printf '%s\n' "$output"
  ls "$TRACKER_DIR"
  false
}

@test "S1c un id à métacaractère de glob" {
  use_tickets 01-alpha

  printf '# 99 — invented\n\n**Status:** ready-for-agent\n\n**Blocked by:** None\n' \
    >"$TRACKER_DIR/99-a[0].md"
  # Ce que le glob trouverait dans le répertoire courant à sa place.
  : >"$RALPH_TEST_DIR/99-a0"

  echo "=== depuis un répertoire où le glob matche quelque chose"
  pack_run 'cd "'"$RALPH_TEST_DIR"'"; failures__strays "01-alpha"'
  printf '%s\n' "$output"

  echo "=== la quarantaine"
  pack_run 'cd "'"$RALPH_TEST_DIR"'"; failures_quarantine_strays 01-alpha "01-alpha"; printf "rc=%s\n" "$?"'
  printf '%s\n' "$output"
  ls "$TRACKER_DIR"
  false
}
