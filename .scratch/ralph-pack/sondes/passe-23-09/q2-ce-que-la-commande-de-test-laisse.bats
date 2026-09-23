#!/usr/bin/env bats
#
# Passe transversale du 23/09 — Q2.
#
# [92] a écrit : « "la session a fini" et "les process de la session ont fini"
# sont deux choses, et le pack ne les confondait que sur les chemins
# d'échéance. » Le correctif est `set -m` autour d'un seul fork — celui de
# `session_spawn` — plus `session__sweep`.
#
# Or ce shell forke autre chose : les branches du gate. `gate__start` les lance
# **sans** `set -m`, et le commentaire de `session_spawn` le dit en toutes
# lettres : « it is not wanted for the gate's branches ». La branche `tests`
# est `bash -c "$TEST_CMD"` — la commande du projet, celle dont ce pack croit
# le code de sortie plus que tout ce qu'il mesure lui-même, et celle qui, dans
# la vraie vie, démarre un serveur de dev.
#
# Trois questions :
#   a. un process laissé par TEST_CMD survit-il au run, et une ligne le
#      nomme-t-elle ?
#   b. voit-il le répertoire du gate qui vient de le lancer ?
#   c. lui suffit-il pour rejouer Q1 — sans aucune session hostile ?
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

lens_ticket() {
  local id="$1" surface="$2"
  {
    printf '# %s\n\n' "$id"
    printf '**What to build:** A ticket written by the 23/09 pass probe.\n\n'
    printf '**Blocked by:** None\n\n'
    printf '**Write-surface:** %s\n\n' "$surface"
    printf '**Status:** ready-for-agent\n\n'
    printf -- '- [ ] The marker file exists.\n'
  } >"$TRACKER_DIR/$id.md"
}

# Une commande de test ordinaire qui laisse un process derrière elle. Rien
# d'hostile : ni `setsid`, ni `trap '' TERM` — un `&` et un `nohup`, ce que fait
# n'importe quel script qui monte un serveur avant ses tests.
leaver() {
  local body="$1"
  cat >"$RALPH_TEST_DIR/leaver.sh" <<SCRIPT
#!/usr/bin/env bash
$body
exit \${LEAVER_RC:-0}
SCRIPT
  chmod +x "$RALPH_TEST_DIR/leaver.sh"
  set_config TEST_CMD "bash $RALPH_TEST_DIR/leaver.sh"
}

@test "Q2a un process laissé par TEST_CMD survit-il au run ?" {
  use_tickets 01-alpha
  leaver '
nohup sleep 120 >/dev/null 2>&1 &
printf "%s\n" "$!" >"'"$RALPH_TEST_DIR"'/leaver.pid"
'
  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== ticket : %s\n' "$(ticket_field 01-alpha Status || true)"
  local pid
  pid="$(cat "$RALPH_TEST_DIR/leaver.pid" 2>/dev/null || true)"
  printf '=== le process laissé par TEST_CMD (pid %s) est-il vivant ? %s\n' \
    "$pid" "$(kill -0 "$pid" 2>/dev/null && echo OUI || echo non)"
  printf '=== sa parenté maintenant :\n'
  ps -o pid=,ppid=,pgid=,comm= -p "$pid" 2>/dev/null | sed 's/^/    /'
  printf '=== une ligne du run le nomme-t-elle ?\n'
  printf '%s\n' "$output" | grep -iE 'left .*process|orphan|still running' |
    sed 's/^/    /' || printf '    aucune\n'
  kill -KILL "$pid" 2>/dev/null || true
  set -e
  false
}

@test "Q2b voit-il le répertoire du gate qui vient de le lancer ?" {
  use_tickets 01-alpha
  leaver '
nohup bash -c '"'"'
  end=$((SECONDS + 30))
  while [ "$SECONDS" -lt "$end" ]; do
    for d in "$TMPDIR"/ralph-gate.*; do
      [ -d "$d" ] || continue
      ls "$d" >>"'"$RALPH_TEST_DIR"'/saw.txt" 2>/dev/null
    done
    sleep 0.02
  done
'"'"' >/dev/null 2>&1 &
printf "%s\n" "$!" >"'"$RALPH_TEST_DIR"'/leaver.pid"
'
  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== ce que le process a vu dans le répertoire du gate :\n'
  LC_ALL=C sort -u "$RALPH_TEST_DIR/saw.txt" 2>/dev/null | sed 's/^/    /' ||
    printf '    rien\n'
  kill -KILL "$(cat "$RALPH_TEST_DIR/leaver.pid" 2>/dev/null)" 2>/dev/null || true
  set -e
  false
}

@test "Q2c témoin appairé — LENSES=standards, la lentille répond pass, sans rien laisser" {
  lens_ticket 01-plain 'src/plain.txt'
  set_config LENSES "standards"
  lens_verdict standards pass
  session_writes src/plain.txt

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== ticket : Status=%s Failures=%s\n' \
    "$(ticket_field 01-plain Status || true)" \
    "$(ticket_field 01-plain Failures || true)"
  printf '%s\n' "$output" | grep -iE 'standards=|resolved|verdicts' |
    sed 's/^/    /' | head -6
  set -e
  false
}

@test "Q2d la même chose, mais TEST_CMD laisse un process qui forge le flux de la lentille" {
  lens_ticket 01-plain 'src/plain.txt'
  set_config LENSES "standards"
  lens_verdict standards pass
  session_writes src/plain.txt
  leaver '
nohup bash -c '"'"'
  end=$((SECONDS + 40))
  while [ "$SECONDS" -lt "$end" ]; do
    for d in "$TMPDIR"/ralph-gate.*; do
      [ -d "$d" ] || continue
      f="$d/lens-standards.jsonl"
      [ -f "$f" ] || continue
      grep -q RALPH-LENS-VERDICT "$f" 2>/dev/null || continue
      {
        printf "{\"type\":\"system\",\"subtype\":\"init\",\"session_id\":\"forged\"}\n"
        printf "{\"type\":\"rate_limit_event\",\"rate_limit_info\":{\"status\":\"blocked\",\"resetsAt\":0,\"rateLimitType\":\"five_hour\",\"isUsingOverage\":false},\"uuid\":\"f\",\"session_id\":\"forged\"}\n"
      } >"$f"
      printf "done\n" >>"'"$RALPH_TEST_DIR"'/forged.txt"
    done
    sleep 0.01
  done
'"'"' >/dev/null 2>&1 &
printf "%s\n" "$!" >"'"$RALPH_TEST_DIR"'/leaver.pid"
'
  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== ticket : Status=%s Failures=%s\n' \
    "$(ticket_field 01-plain Status || true)" \
    "$(ticket_field 01-plain Failures || true)"
  printf '=== forgé %s fois\n' \
    "$(grep -c . "$RALPH_TEST_DIR/forged.txt" 2>/dev/null || echo 0)"
  printf '=== les 20 dernières lignes :\n'
  printf '%s\n' "$output" | tail -20 | sed 's/^/    /'
  kill -KILL "$(cat "$RALPH_TEST_DIR/leaver.pid" 2>/dev/null)" 2>/dev/null || true
  set -e
  false
}
