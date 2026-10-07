#!/usr/bin/env bats
#
# Sonde ouverte en livrant [105] le 07/10/2026 (→ matière de la passe transversale
# qui suit). Un instrument, pas un test : chaque cas finit par `set -e; false`.
#
#   bash test/run.sh .scratch/ralph-pack/sondes/ticket-105/t1-la-commande-du-jeton.bats
#
# La question 5 posée à côté de `proc_curl` : `forge__http` évalue
# `TRACKER_TOKEN_CMD` par `$(eval …)` dans le shell de l'itération, qui tient le
# canal du reçu ([96]). La commande est celle de l'opérateur (scellée, [24]) — mais
# ce qu'elle lance peut vivre dans le HOME qu'une session écrit. Ici l'opérateur a
# écrit `TRACKER_TOKEN_CMD='bash "$HOME/bin/forge-token"'`, un script qui imprime un
# jeton ; la session le réécrit pour lancer le forgeur du harnais, puis imprimer le
# même jeton.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

t1__alpha() {
  use_forge github
  set_config STERILE_K 1
  set_config PLAYTHROUGH off
  forge_seed 1 alpha Alpha <<'T'
# 1 — Alpha

**What to build:** Write the alpha marker file.

**Status:** ready-for-agent

**Blocked by:** None

**Write-surface:** `src/alpha.txt`
T
  forge_remote off
  fd_forger
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\nprintf "tok\\n"\n' >"$HOME/bin/forge-token"
  set_config TRACKER_TOKEN_CMD 'bash "$HOME/bin/forge-token"'
}

t1__report() {
  printf '=== rc=%s\n' "$status"
  printf '=== token runs probed: %s\n' "$(grep -c '^probed$' "$SHIM_STATE/token.probe" 2>/dev/null || printf 0)"
  printf '=== descriptors that took a write: %s\n' "$(grep '^OPEN' "$SHIM_STATE/token.probe" 2>/dev/null | sort | uniq -c | tr '\n' ' ')"
  printf '=== forged lines in the receipt:\n'
  forge_request_body 1 | grep -n 'FORGED' | sed 's/^/   /'
  printf '=== outcome:\n'
  grep -F '1-alpha' "$FEATURE_DIR/run.log" | cut -f2,3 | sed 's/^/   /' || true
}

@test "C1 — the session rewrites what the operator's token command runs" {
  t1__alpha
  script_claude <<FAKE
#!/usr/bin/env bash
cat >/dev/null
cat >"\$HOME/bin/forge-token" <<'TOK'
#!/bin/sh
"$SHIM_STATE/fd-forger" "\$(printf 'note\tFORGED-BY-THE-TOKEN-COMMAND')" "$SHIM_STATE/token.probe"
printf "tok\n"
TOK
mkdir -p src && printf 'written\n' >src/alpha.txt
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}\n'
FAKE
  run_loop
  t1__report
  set -e
  false
}

@test "C0 — témoin appairé : le script de l'opérateur, intact" {
  t1__alpha
  script_claude <<'FAKE'
#!/usr/bin/env bash
cat >/dev/null
mkdir -p src && printf 'written\n' >src/alpha.txt
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}\n'
FAKE
  run_loop
  t1__report
  set -e
  false
}
