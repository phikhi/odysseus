#!/usr/bin/env bats
#
# [50] — sonde avant d'écrire, demandée par le ticket.
#
# Le cas armé n'est pas `vendor/` : c'est le pack sur lui-même. Un projet qui
# `gitignore` `.claude/` — ce que font les projets Claude Code réels pour ne pas
# versionner leur configuration locale — a `GUARDED_PATHS=.claude` par défaut.
# `gate_tree_snapshot` force donc `.claude/` dans l'arbre jugé ([24]), le
# scope-guard approuve l'édition, et `failures_make_durable` fait `git add` sans
# `-f`, que git refuse pour un chemin ignoré.
#
# P1a  la livraison arrive-t-elle dans l'historique ? (attendu AVANT : non)
# P1b  la même chose pour la famille de [30] : un fichier que la session écrit
#      puis cache par un `.gitignore` de son cru.
#
# Lancer :
#   bash test/run.sh .scratch/ralph-pack/sondes/ticket-50/p1-le-cas-par-defaut-du-pack-sur-lui-meme.bats

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "P1a le pack se livre à lui-même dans un projet qui ignore .claude" {
  use_tickets 01-alpha
  # Le défaut du pack, pris au fichier que l'installeur dépose. Écrit
  # `${GUARDED_PATHS-.claude}` (sans `:`), que `config_default` ne sait pas lire.
  run grep -c '^GUARDED_PATHS="\${GUARDED_PATHS-\.claude}"$' "$PACK_DIR/ralph.config.sh.example"
  assert_equal "$output" "1"
  printf '.claude/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "sonde: le projet ignore .claude/, comme tout projet Claude Code"

  perl -pi -e \
    's|^\*\*Write-surface:\*\* .*|**Write-surface:** `.claude/lib/thing.sh`|' \
    "$(ticket_file 01-alpha)"
  harness__commit "sonde: un ticket dont la surface est le code du pack"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p .claude/lib
printf 'thing_do() { :; }\n' >.claude/lib/thing.sh
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf 'RUN\n%s\n' "$output" >&2
  assert_success
  assert_ticket_status 01-alpha resolved

  run git -C "$PROJECT_DIR" ls-tree -r --name-only HEAD
  printf 'HEAD\n%s\n' "$output" >&2
  assert_output_contains ".claude/lib/thing.sh"
}

@test "P1b un fichier que la session cache par sa propre règle arrive quand même" {
  use_tickets 01-alpha
  perl -pi -e \
    's|^\*\*Write-surface:\*\* .*|**Write-surface:** `build/*`, `.gitignore`|' \
    "$(ticket_file 01-alpha)"
  harness__commit "sonde: un ticket qui livre dans build/ et écrit la règle"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p build
printf 'livre\n' >build/out.txt
printf 'build/\n' >>.gitignore
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf 'RUN\n%s\n' "$output" >&2
  assert_success
  assert_ticket_status 01-alpha resolved

  run git -C "$PROJECT_DIR" ls-tree -r --name-only HEAD
  printf 'HEAD\n%s\n' "$output" >&2
  assert_output_contains "build/out.txt"
}

@test "P1z la sonde est une sonde" {
  false
}
