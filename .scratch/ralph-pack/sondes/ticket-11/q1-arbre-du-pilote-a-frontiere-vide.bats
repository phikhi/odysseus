#!/usr/bin/env bats
#
# [11] — Q1 : que voit `router__tree_dirt` dans l'arbre du pilote, à frontière
# vide, après un run qui a livré ?
#
# La contrainte posée par [56] dans le corps de [11] demande de mesurer ça
# **avant** de décider par où passe la réinjection d'un playthrough rouge :
# « un refus qui tomberait sur l'écriture du pack serait un run qui refuse
# d'avancer et le dit dans une phrase écrite pour un humain ».
#
# Instrument, pas test : il imprime dans un fichier, il n'asserte rien.
# Sortie : .scratch/ralph-pack/sondes/ticket-11/q1-out.txt

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

@test "Q1 l'arbre du pilote à la fin d'un run, vu par router__tree_dirt" {
  out="$RALPH_PACK_ROOT/.scratch/ralph-pack/sondes/ticket-11/q1-out.txt"
  : >"$out"

  # Le quatrième layer allumé, comme un projet l'installe : c'est lui qui écrit
  # dans l'arbre principal (LEARNINGS.md, learning-records/, docs/adr/).
  set_config RETRO "$(config_default RETRO)"
  use_tickets 01-alpha
  retro_answer 'RALPH-RETRO-LESSON: une lecon ecrite par la sonde' \
    'RALPH-RETRO-WHY: pour salir l arbre du pilote'

  run_loop
  {
    printf '=== rc du run : %s\n' "$status"
    printf '=== sortie ---------------------------------------\n%s\n' "$output"
    printf '=== git status --porcelain -----------------------\n'
    git -C "$PROJECT_DIR" status --porcelain
  } >>"$out"

  pack_run 'router__tree_dirt'
  printf '=== router__tree_dirt (rc=%s) --------------------\n%s\n' \
    "$status" "$output" >>"$out"

  pack_run 'router_pin 01-alpha; router_may_reinject 01-alpha; printf "rc=%s\n" "$?"'
  printf '=== router_may_reinject --------------------------\n%s\n' "$output" >>"$out"
}
