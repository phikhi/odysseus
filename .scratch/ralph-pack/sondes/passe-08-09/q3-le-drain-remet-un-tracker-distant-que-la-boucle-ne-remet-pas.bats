#!/usr/bin/env bats
#
# Passe transversale du 08/09 — Q3.
#
# [73] est ouvert sur « rien ne restaure le tracker d'un backend distant », et le
# ticket dit que la remise demande de rendre `failures_protect_tracker`
# agnostique du transport. La moitié qui n'est écrite nulle part : **le drain le
# fait déjà**. `router_pin` prend l'état du tracker par l'adaptateur
# (`router__tracker_state`, cinq champs plus le corps par ticket) et
# `router__put_back` remet un voisin par `tracker_mark_*` — deux opérations de
# l'interface, donc du réseau sur un backend distant.
#
# Les deux moitiés, mesurées côte à côte sur le même geste : une session résout
# le ticket d'en face.
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

sonde__two_tickets() {
  forge_seed 1 decision 'Pour le drain' <<'T'
# 1 — Pour le drain

**What to build:** Something a human has to arbitrate.

**Status:** ready-for-human

**Escalation:** decision

**Write-surface:** `src/one.txt`

**Blocked by:** None
T
  forge_seed 2 alpha Alpha <<'T'
# 2 — Alpha

**What to build:** Write the alpha marker file.

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
}

@test "Q3a une session ROUTÉE résout le voisin : le drain le remet, par le réseau" {
  use_forge github
  sonde__two_tickets

  # La session que le drain ouvre sur `1-decision` touche `2-alpha`.
  script_claude <<FAKE
#!/usr/bin/env bash
{
  printf '# 2 — Alpha\n\n'
  printf '**Status:** resolved\n\n'
  printf '**Blocked by:** None\n\n'
  printf '**Slug:** alpha\n'
} >"$SHIM_STATE/forge/issue.2.body"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run bash -c 'printf "o\no\nn\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== rc du drain : %s\n' "$status"
  printf '=== ce que le drain dit du tracker :\n'
  printf '%s\n' "$output" | sed 's/^/    /'
  printf '=== 2-alpha sur la forge : %s\n' "$(forge_field 2 Status)"

  set -e
  false
}

@test "Q3b une session d ITÉRATION résout le voisin : rien ne le remet" {
  use_forge github
  set_config STERILE_K 1
  set_config PLAYTHROUGH off
  set_config RETRY_N 1
  sonde__two_tickets

  # La session d'itération de `2-alpha` sort `1-decision` du puits humain en le
  # marquant `resolved`. C'est l'écriture que [58] existe pour attraper côté
  # drain et que [21] restaure côté boucle — sur le backend local.
  script_claude <<FAKE
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
# La forge, telle que ce harnais la tient : des fichiers. Ce qu'une vraie session
# ferait par le réseau, celle-ci le fait sur l'état du mock — c'est le même fait
# du point de vue du pack, qui ne voit que ce que le listing rend.
{
  printf '# 1 — Pour le drain\n\n'
  printf '**Status:** resolved\n\n'
  printf '**Blocked by:** None\n\n'
  printf '**Slug:** decision\n'
} >"$SHIM_STATE/forge/issue.1.body"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  printf '=== 1-decision avant le run : %s\n' "$(forge_field 1 Status)"
  run_loop
  printf '=== rc du run : %s\n' "$status"
  printf '=== ce que le run dit du tracker :\n'
  printf '%s\n' "$output" | grep -E 'tracker|restored|wrote' | sed 's/^/    /'
  printf '=== 1-decision après le run : %s\n' "$(forge_field 1 Status)"
  printf '=== 2-alpha après le run : %s\n' "$(forge_field 2 Status)"

  set -e
  false
}

@test "Q3c témoin appairé : le même geste sur le backend LOCAL" {
  use_tickets 01-alpha
  set_config STERILE_K 1
  set_config PLAYTHROUGH off
  set_config RETRY_N 1
  cat >"$TRACKER_DIR/20-decision.md" <<'T'
# 20 — Pour le drain

**Status:** ready-for-human

**Escalation:** decision

**Write-surface:** `src/one.txt`

**Blocked by:** None
T
  harness__commit "sonde: 20-decision"

  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'alpha\n' >src/alpha.txt
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
perl -0pi -e 's/\*\*Status:\*\* ready-for-human/**Status:** resolved/' \
  "$tracker/20-decision.md"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE

  run_loop
  printf '=== rc du run : %s\n' "$status"
  printf '=== ce que le run dit du tracker :\n'
  printf '%s\n' "$output" | grep -E 'tracker|restored|wrote' | sed 's/^/    /'
  printf '=== 20-decision après le run : %s\n' "$(ticket_status 20-decision)"
  printf '=== 01-alpha après le run : %s\n' "$(ticket_status 01-alpha)"

  set -e
  false
}
