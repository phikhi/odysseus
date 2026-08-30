#!/usr/bin/env bats
#
# [50] — troisième AC, sondée avant d'écrire.
#
# « Ce qui n'a pas pu être stagé n'a pas non plus à être désindexé, et l'arbre
# principal doit refléter ce qui a réellement été commité. »
#
# `concurrency__refresh` marche sur la liste approuvée et pose une seule
# question : ce chemin est-il dans `HEAD` ? Non → il est traité comme une
# suppression de l'itération, donc `rm -f` dans l'**arbre principal**. Un chemin
# que `git add` a refusé n'est pas dans `HEAD` non plus — et l'arbre principal,
# lui, peut très bien porter un fichier à cet endroit : un projet qui ignore
# `.claude/` y a les fichiers locaux d'un humain.
#
# Lancer :
#   bash test/run.sh .scratch/ralph-pack/sondes/ticket-50/p2-le-rafraichissement-supprime-ce-quil-na-pas-commite.bats

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

@test "P2 un chemin que git a refusé emporte le fichier de l'humain dans l'arbre principal" {
  use_tickets 01-alpha
  printf '.claude/\n' >>"$PROJECT_DIR/.gitignore"
  harness__commit "sonde: le projet ignore .claude/"

  perl -pi -e \
    's|^\*\*Write-surface:\*\* .*|**Write-surface:** `src/*`, `.claude/cache/*`|' \
    "$(ticket_file 01-alpha)"
  harness__commit "sonde: un ticket qui livre du code et du pack"

  # Le fichier d'un humain, dans la zone ignorée que GUARDED_PATHS garde. Jamais
  # commité — il est ignoré — donc jamais dans HEAD.
  mkdir -p "$PROJECT_DIR/.claude/cache"
  printf 'notes locales\n' >"$PROJECT_DIR/.claude/cache/keep.txt"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src .claude/cache
printf 'written\n' >src/alpha.txt
printf 'écrit par la session\n' >.claude/cache/keep.txt
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf 'RUN\n%s\n' "$output" >&2
  assert_success
  assert_ticket_status 01-alpha resolved

  run bash -c "ls -l '$PROJECT_DIR/.claude/cache/' 2>&1"
  printf 'LIB\n%s\n' "$output" >&2
  # Le run n'a rien commité à cet endroit : il n'a donc rien à y supprimer.
  assert_file_exists "$PROJECT_DIR/.claude/cache/keep.txt"
}

@test "P2z la sonde est une sonde" {
  false
}
