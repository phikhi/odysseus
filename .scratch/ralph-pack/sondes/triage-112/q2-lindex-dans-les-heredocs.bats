#!/usr/bin/env bats
#
# Tri de [112], 29/10/2026 — l'index des leçons passe-t-il par un heredoc, donc par
# un fichier nommé `/var/tmp/sh-thd-*` (bash 3.2, [98]/[108]) ?
#
# Le tableau (ligne de [108]) le dit déjà de « la prose — trente-trois `cat <<X` » :
# le prompt, l'index de leçons et le brief injectés. Ce qui se mesure ici est la
# GARANTIE et pas l'efficacité d'une attaque (méthode de [108]) : l'espion du harnais
# voit-il un heredoc qui porte l'index, et ce qu'il y réécrit arrive-t-il quelque part ?
#
# `heredoc_spy` réécrit en `x` tout heredoc dont une ligne COMMENCE par un marqueur.
#   "# LEARNINGS"                          la tête que `retro__render` sort par `cat <<'HEAD'`
#   "## Lessons earlier iterations left"   le bloc que `loop__prompt_lessons` sort par `cat <<LESSONS`
#   "You are the retro subagent"           le prompt du rétro, `cat <<PROMPT`, qui inline `retro_index`
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

@test "Q2a le prompt du rétro (objet de [111]) traverse-t-il un heredoc nommé ?" {
  use_tickets 01-alpha 02-beta
  set_config RETRO on
  retro_answer "RALPH-RETRO-LESSON: read the suite before the ticket" \
    "RALPH-RETRO-WHY: the suite says what the ticket assumes"
  heredoc_spy 90 "# LEARNINGS" "## Lessons earlier iterations left" "You are the retro subagent"

  run_loop_own_tmp

  printf '=== statut du run : %s\n' "$status"
  printf '=== heredocs vus par l espion : %s\n' "$(wc -l <"$RALPH_TEST_DIR/spy.seen" 2>/dev/null | tr -d ' ')"
  local m
  for m in "# LEARNINGS" "## Lessons earlier iterations left" "You are the retro subagent"; do
    printf '=== réécrits pour « %s » : %s\n' "$m" \
      "$(grep -c '^--- /var/tmp' "$RALPH_TEST_DIR/spy.$m" 2>/dev/null || printf 0)"
  done
  printf '=== stdin de chaque appel — rôle, lignes x, lignes LR- :\n'
  local d
  for d in "$SHIM_STATE"/claude.calls/*; do
    [ -f "$d/stdin" ] || continue
    printf '    appel %s (%s) : x=%s LR=%s\n' "$(basename "$d")" \
      "$(head -1 "$d/stdin" | cut -c1-40)" \
      "$(grep -cE '^x+$' "$d/stdin")" "$(grep -c 'LR-' "$d/stdin")"
  done
  printf '=== LEARNINGS.md :\n'
  if [ -f "$PROJECT_DIR/LEARNINGS.md" ]; then
    printf '    lignes x : %s, entrées LR- : %s, titres ## : %s\n' \
      "$(grep -cE '^x+$' "$PROJECT_DIR/LEARNINGS.md")" \
      "$(grep -c '^- LR-' "$PROJECT_DIR/LEARNINGS.md")" \
      "$(grep -c '^## ' "$PROJECT_DIR/LEARNINGS.md")"
    head -5 "$PROJECT_DIR/LEARNINGS.md" | sed 's/^/    | /'
  else
    printf '    absent\n'
  fi
  printf '=== ce que le run a dit :\n'
  printf '%s\n' "$output" | grep -iE 'lesson|LEARNINGS|seen again' | cut -c1-200 | sed 's/^/    /' | head -10

  # L espion ignore TERM et survit au test (90 s) : sans ceci il réécrit les heredocs du run suivant.
  kill -KILL "$PACK_BG_PID" 2>/dev/null || true
  set -e
  false
}

@test "Q2b l index seul, sans viser le prompt du rétro" {
  use_tickets 01-alpha 02-beta
  set_config RETRO on
  retro_answer "RALPH-RETRO-LESSON: read the suite before the ticket" \
    "RALPH-RETRO-WHY: the suite says what the ticket assumes"
  heredoc_spy 90 "# LEARNINGS" "## Lessons earlier iterations left"

  run_loop_own_tmp

  printf '=== statut du run : %s\n' "$status"
  printf '=== heredocs vus par l espion : %s\n' "$(wc -l <"$RALPH_TEST_DIR/spy.seen" 2>/dev/null | tr -d ' ')"
  local m
  for m in "# LEARNINGS" "## Lessons earlier iterations left" "You are the retro subagent"; do
    printf '=== réécrits pour « %s » : %s\n' "$m" \
      "$(grep -c '^--- /var/tmp' "$RALPH_TEST_DIR/spy.$m" 2>/dev/null || printf 0)"
  done
  printf '=== stdin de chaque appel — rôle, lignes x, lignes LR- :\n'
  local d
  for d in "$SHIM_STATE"/claude.calls/*; do
    [ -f "$d/stdin" ] || continue
    printf '    appel %s (%s) : x=%s LR=%s\n' "$(basename "$d")" \
      "$(head -1 "$d/stdin" | cut -c1-40)" \
      "$(grep -cE '^x+$' "$d/stdin")" "$(grep -c 'LR-' "$d/stdin")"
  done
  printf '=== LEARNINGS.md :\n'
  if [ -f "$PROJECT_DIR/LEARNINGS.md" ]; then
    printf '    lignes x : %s, entrées LR- : %s, titres ## : %s\n' \
      "$(grep -cE '^x+$' "$PROJECT_DIR/LEARNINGS.md")" \
      "$(grep -c '^- LR-' "$PROJECT_DIR/LEARNINGS.md")" \
      "$(grep -c '^## ' "$PROJECT_DIR/LEARNINGS.md")"
    head -5 "$PROJECT_DIR/LEARNINGS.md" | sed 's/^/    | /'
  else
    printf '    absent\n'
  fi
  printf '=== ce que le run a dit :\n'
  printf '%s\n' "$output" | grep -iE 'lesson|LEARNINGS|seen again' | cut -c1-200 | sed 's/^/    /' | head -10

  # L espion ignore TERM et survit au test (90 s) : sans ceci il réécrit les heredocs du run suivant.
  kill -KILL "$PACK_BG_PID" 2>/dev/null || true
  set -e
  false
}
