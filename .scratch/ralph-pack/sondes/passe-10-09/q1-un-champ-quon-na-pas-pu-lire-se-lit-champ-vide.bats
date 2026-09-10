#!/usr/bin/env bats
#
# Passe transversale du 10/09 — Q1.
#
# [71] a écrit *comment* une opération d'adaptateur refuse : un code non nul, et
# l'appelant décide. [74] et [78] ont fait lire ce code au point d'entrée (la
# frontière) et à l'ouverture. Ce que personne n'a redemandé : une opération de
# **lecture** n'a qu'UN code non nul pour deux faits qui envoient un lecteur à
# deux endroits différents —
#
#     « ce ticket ne porte pas ce champ »   (une réponse)
#     « je n'ai pas pu savoir »              (un refus)
#
# et les 28 sites de `tracker_field` du pack les écrasent tous les deux en la
# chaîne vide (`|| status=''`, `2>/dev/null || true`, `[ "$(…)" = x ]`).
#
# La mise en scène est celle de [78], la moins chère : `FORGE_PAGE 2` +
# `FORGE_PAGES 1` sur un tracker qui porte au moins deux issues fait refuser
# **tous** les listings, sans simuler de panne.
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

# Deux issues, dont une qui déclare une write-surface et un tag de lentille.
sonde__seed() {
  use_forge github
  forge_seed 1 alpha Alpha <<'BODY'
# 1 — Alpha

**What to build:** the alpha marker.

**Blocked by:** None

**Write-surface:** `src/alpha.txt`

**Tags:** `security`

**Status:** ready-for-agent
BODY
  forge_seed 2 beta Beta <<'BODY'
# 2 — Beta

**What to build:** the beta marker.

**Blocked by:** None

**Write-surface:** `src/beta.txt`

**Status:** ready-for-agent
BODY
}

# Le plafond qui fait refuser tous les listings ([78]).
sonde__ceiling_refuses() {
  set_config FORGE_PAGE 2
  set_config FORGE_PAGES 1
}

@test "Q1a un champ refusé et un ticket absent rendent le même code" {
  sonde__seed
  sonde__ceiling_refuses

  pack_run 'v="$(tracker_field 1-alpha Status)" && printf "rc=0 valeur=[%s]\n" "$v" || printf "rc=%s valeur=[%s]\n" "$?" "$v"'
  printf '=== 1-alpha, qui EXISTE et est ready-for-agent, sous un listing refusé :\n    %s\n' "$output"

  pack_run 'v="$(tracker_field 999-nexistepas Status)" && printf "rc=0 valeur=[%s]\n" "$v" || printf "rc=%s valeur=[%s]\n" "$?" "$v"'
  printf '=== 999-nexistepas, qui N EXISTE PAS, même plafond :\n    %s\n' "$output"

  pack_run 'v="$(tracker_read_ticket 1-alpha)" && printf "rc=0 corps=[%s]\n" "$v" || printf "rc=%s corps=[%s]\n" "$?" "$v"'
  printf '=== tracker_read_ticket 1-alpha :\n    %s\n' "$output"

  printf '=== et la forme que 28 sites du pack écrivent :\n'
  pack_run 'status="$(tracker_field 1-alpha Status 2>/dev/null)" || status=""; printf "status=[%s]\n" "$status"'
  printf '    %s\n' "$output"

  set -e
  false
}

@test "Q1b la write-surface d un ticket refusé se lit « rien n est dans le périmètre »" {
  sonde__seed
  sonde__ceiling_refuses

  pack_run 'printf "surface=[%s]\n" "$(gate_write_surface 1-alpha)"'
  printf '=== gate_write_surface 1-alpha (le ticket déclare src/alpha.txt) :\n    %s\n' "$output"

  pack_run 'if gate_in_surface src/alpha.txt "$(gate_write_surface 1-alpha)"; then printf "DANS la surface\n"; else printf "HORS de la surface\n"; fi'
  printf '=== src/alpha.txt, que le ticket déclare, contre la surface lue :\n    %s\n' "$output"

  pack_run 'gate__surface_owner src/alpha.txt 2-beta; printf "(rc=%s)\n" "$?"'
  printf '=== qui revendique src/alpha.txt, vu depuis 2-beta :\n%s\n' "$(printf '%s\n' "$output" | sed 's/^/    /')"

  set -e
  false
}

@test "Q1c une lentille gatée par un tag ne voit pas un ticket que le listing a refusé" {
  sonde__seed
  sonde__ceiling_refuses

  pack_run 'if lenses_has_tag 1-alpha security; then printf "la lentille security VOIT le ticket\n"; else printf "la lentille security NE VOIT PAS le ticket\n"; fi'
  printf '=== 1-alpha porte `Tags: security` :\n    %s\n' "$output"

  set -e
  false
}

@test "Q1d témoin appairé : le même tracker sous un plafond qui tient" {
  sonde__seed
  set_config FORGE_PAGE 2
  set_config FORGE_PAGES 20

  pack_run 'v="$(tracker_field 1-alpha Status)" && printf "rc=0 valeur=[%s]\n" "$v" || printf "rc=%s valeur=[%s]\n" "$?" "$v"'
  printf '=== 1-alpha Status :\n    %s\n' "$output"
  pack_run 'v="$(tracker_field 999-nexistepas Status)" && printf "rc=0 valeur=[%s]\n" "$v" || printf "rc=%s valeur=[%s]\n" "$?" "$v"'
  printf '=== 999-nexistepas Status :\n    %s\n' "$output"
  pack_run 'printf "surface=[%s]\n" "$(gate_write_surface 1-alpha)"'
  printf '=== gate_write_surface 1-alpha :\n    %s\n' "$output"
  pack_run 'if lenses_has_tag 1-alpha security; then printf "la lentille security VOIT le ticket\n"; else printf "la lentille security NE VOIT PAS le ticket\n"; fi'
  printf '=== lenses_has_tag :\n    %s\n' "$output"
  pack_run 'gate__surface_owner src/alpha.txt 2-beta; printf "(rc=%s)\n" "$?"'
  printf '=== gate__surface_owner src/alpha.txt (depuis 2-beta) :\n%s\n' "$(printf '%s\n' "$output" | sed 's/^/    /')"

  set -e
  false
}
