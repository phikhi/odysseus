#!/usr/bin/env bats
#
# [37] — s2 : jusqu'où un id à espace survit *ailleurs* que dans la boucle
# d'intrus. Le préflight, le registre de [13]/[42], le propriétaire de surface
# du scope-guard, et la reprise de claim de [12].

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "S2a le préflight compte les porteurs d'un numéro en mots" {
  use_tickets 01-alpha
  # UN seul porteur de 99, dont le nom porte une espace.
  printf '# 99 — a\n\n**Status:** ready-for-agent\n\n**Blocked by:** None\n' \
    >"$TRACKER_DIR/99-my ticket.md"

  echo "=== tracker_preflight (aucun numéro n'est réellement ambigu)"
  pack_run 'tracker_preflight; printf "rc=%s\n" "$?"'
  printf '%s\n' "$output"

  echo "=== tracker__carriers 99"
  pack_run 'printf "[%s]\n" "$(tracker__carriers "$(tracker_ids)" 99)"'
  printf '%s\n' "$output"
  false
}

@test "S2b le registre de [13] exempte par une clôture de mots" {
  use_tickets 01-alpha
  # Ce que la boucle a écrit dans la fenêtre : un ticket à espace.
  printf '# 99 — loop\n\n**Status:** ready-for-agent\n\n**Blocked by:** None\n' \
    >"$TRACKER_DIR/99-my ticket.md"
  # Ce que la session a écrit : un ticket qui n'est PAS celui-là.
  printf '# 98 — session\n\n**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Write-surface:** `*`\n' \
    >"$TRACKER_DIR/99-my.md"

  pack_run 'export RALPH_TRACKER_LOG="'"$RALPH_TEST_DIR"'/register"
    printf "99-my ticket\n" >"$RALPH_TRACKER_LOG"
    printf "fence=[%s]\n" "$(tracker_writes_since 0)"
    failures_quarantine_strays 01-alpha "01-alpha" 0
    printf "rc=%s\n" "$?"'
  printf '%s\n' "$output"

  echo "=== le statut de 99-my, que la session s'est écrit"
  pack_run 'tracker_field 99-my Status'
  printf '%s\n' "$output"
  false
}

@test "S2c le propriétaire de surface du scope-guard" {
  use_tickets 01-alpha
  printf '# 99 — a\n\n**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Write-surface:** `src/beta.txt`\n' \
    >"$TRACKER_DIR/99-my ticket.md"

  pack_run 'gate__surface_owner src/beta.txt 01-alpha; printf "rc=%s\n" "$?"'
  printf '%s\n' "$output"
  false
}

@test "S2d la reprise de claim de [12] : la liste des ids en vol" {
  use_tickets 01-alpha
  # Un ticket réclamé par un propriétaire mort, dont le nom porte une espace.
  printf '# 99 — a\n\n**Status:** claimed\n\n**Blocked by:** None\n\n**Claimed:** owner=pid:999999 at=2020-01-01T00:00:00Z\n' \
    >"$TRACKER_DIR/99-my ticket.md"

  # Cet ordre-là et pas l'inverse : une reprise *rend* le ticket
  # (`failures_after_dead_owner` → `tracker_unclaim`), donc le cas exempté
  # n'aurait plus rien de réclamé à regarder s'il passait en second.
  echo "=== un frère nommé 99-my en vol : il ne doit PAS être exempté"
  pack_run 'claim_reclaim_stale "99-my"'
  printf '%s\n' "$output"
  pack_run 'tracker_field "99-my ticket" Status'
  echo "statut après: $output"

  echo "=== rien en vol : il doit être repris"
  pack_run 'claim_reclaim_stale ""'
  printf '%s\n' "$output"
  false
}
