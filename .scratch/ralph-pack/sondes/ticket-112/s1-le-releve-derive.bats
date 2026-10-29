#!/usr/bin/env bats
#
# Livraison de [112], 29/10/2026 — la moitié **dérivée** du survivant de
# `script_index_survivor` (harnais), seule : les noms que l'index traversait sont
# retirés du script, il ne reste que « tout fichier de $TMPDIR qui porte le gist ».
#
# Mesuré sur `main` (c87726c, worktree) : le relevé trouve `ralph-retro.*/index`
# (60 ajouts), et les marques arrivent aux appels 4 et 5 et dans LEARNINGS.md.
# Sur la branche de [112] : ce que ce fichier imprime.
#
# Instrument, pas test : finit par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "S1 le relevé dérivé seul" {
  use_tickets 01-alpha 02-beta
  set_config RETRO on
  retro_answer "RALPH-RETRO-LESSON: read the suite before the ticket"
  script_index_survivor "read the suite before the ticket"
  perl -0pi -e 's/      for f in "\$d\/index".*?      done\n//s' "$SHIM_STATE/claude.script"
  ! grep -q 'index.next' "$SHIM_STATE/claude.script" || { echo "la boucle des noms est encore là"; false; }
  run_loop_own_tmp
  stop_index_survivor
  printf '=== statut : %s\n' "$status"
  printf '=== le survivant a vu : %s\n' "$(sed "s#$RALPH_TEST_DIR/##" "$SHIM_STATE/survivor.saw" 2>/dev/null)"
  printf '=== relevé dérivé (fichiers qui portaient le gist) :\n'
  sed "s#$RALPH_TEST_DIR/##" "$SHIM_STATE/survivor.derived" 2>/dev/null | sort | uniq -c || true
  printf '=== appels dont le stdin porte une marque :\n'
  grep -l FORGED-112 "$SHIM_STATE"/claude.calls/*/stdin 2>/dev/null | sed "s#$SHIM_STATE/##" || true
  printf '=== marques dans LEARNINGS.md : %s\n' "$(grep -c FORGED-112 "$PROJECT_DIR/LEARNINGS.md" 2>/dev/null)"
  printf '=== appels dont le stdin porte le gist (livraison 2 et rétro 2, attendu : 2) : %s\n' \
    "$(grep -c 'read the suite' "$SHIM_STATE/claude.calls"/*/stdin | awk -F: '$2 > 0' | wc -l | tr -d ' ')"
  set -e
  false
}

@test "S2 le survivant entier, SANS l exclusion des prompts de session (ce que [111] lèvera)" {
  use_tickets 01-alpha 02-beta
  set_config RETRO on
  retro_answer "RALPH-RETRO-LESSON: read the suite before the ticket"
  script_index_survivor "read the suite before the ticket"
  perl -0pi -e 's/      case "\$f" in \*\/ralph-retro\.\*\/session\.\*\/prompt\) continue ;; esac\n//' "$SHIM_STATE/claude.script"
  ! grep -q 'session\.\*/prompt' "$SHIM_STATE/claude.script" || { echo "l exclusion est encore là"; false; }
  run_loop_own_tmp
  stop_index_survivor
  printf '=== statut : %s\n' "$status"
  printf '=== relevé dérivé :\n'
  sed "s#$RALPH_TEST_DIR/##" "$SHIM_STATE/survivor.derived" 2>/dev/null | sort | uniq -c || true
  printf '=== appels dont le stdin porte une marque (rôle) :\n'
  for f in $(grep -l FORGED-112 "$SHIM_STATE"/claude.calls/*/stdin 2>/dev/null); do
    printf '    %s : %s\n' "${f#"$SHIM_STATE"/}" "$(head -1 "$f" | cut -c1-50)"
  done
  printf '=== marques dans LEARNINGS.md : %s\n' "$(grep -c FORGED-112 "$PROJECT_DIR/LEARNINGS.md" 2>/dev/null)"
  set -e
  false
}
