#!/usr/bin/env bats
#
# Sonde ouverte en commençant [98] le 07/10/2026 (→ [105]). Un instrument, pas un
# test : chaque cas finit par `set -e; false` pour que microbats imprime ce qu'il a
# mesuré.
#
#   bash test/run.sh .scratch/ralph-pack/sondes/ticket-98/f4-le-curlrc.bats
#
# La question : le `curl` que le pack lance lit `~/.curlrc`, qu'une session écrit
# (même HOME que l'opérateur). Une config qui ajoute une URL `file://` et une
# `output = "/dev/fd/5"` fait-elle écrire ce que la session veut dans le bout
# écrivain du reçu d'audit ([96]) — que l'itération tient quand elle appelle
# l'adaptateur d'un backend distant ?
#
# Le `curl` de la suite est un faux (`test/helpers/shims/curl`), qui ne lit aucune
# config. Le faux est donc enveloppé : l'enveloppe lance d'abord le VRAI
# `/usr/bin/curl` vers un port fermé — à la place exacte où le pack lance `curl`,
# donc avec ses descripteurs, et avec le HOME du test — puis rend la main au faux,
# qui sert la forge comme d'habitude. Ce que le vrai curl fait de la config est ce
# qu'il ferait dans un vrai run ; la forge, elle, reste celle du harnais.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

f4__wrap_curl() {
  mv "$SHIM_BIN/curl" "$SHIM_BIN/curl.shim"
  cat >"$SHIM_BIN/curl" <<WRAP
#!/bin/bash
/usr/bin/curl -sS --max-time 2 -o /dev/null http://127.0.0.1:9/ >/dev/null 2>&1
exec "$SHIM_BIN/curl.shim" "\$@"
WRAP
  chmod +x "$SHIM_BIN/curl"
}

f4__alpha() {
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
}

f4__report() {
  printf '=== rc=%s\n' "$status"
  printf '=== ~/.curlrc: %s\n' "$([ -f "$HOME/.curlrc" ] && printf present || printf absent)"
  printf '=== curl calls: %s\n' "$(grep -c . "$SHIM_STATE/curl.calls" 2>/dev/null || printf 0)"
  printf '=== forged lines in the receipt (the request body):\n'
  forge_request_body 1 | grep -n 'FORGED' | sed 's/^/   /' || printf '   none\n'
  printf '=== outcome in the journal:\n'
  grep -F '1-alpha' "$FEATURE_DIR/run.log" | cut -f2,3 | sed 's/^/   /' || true
}

@test "C1 — a session writes ~/.curlrc, the iteration's curl writes into its receipt" {
  f4__alpha
  f4__wrap_curl
  script_claude <<FAKE
#!/usr/bin/env bash
printf 'note\tFORGED-BY-CURLRC-ON-FD-5\n' >"\$HOME/forged.txt"
printf 'url = "file://%s/forged.txt"\noutput = "/dev/fd/5"\n' "\$HOME" >"\$HOME/.curlrc"
mkdir -p src && printf 'written\n' >src/alpha.txt
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}\n'
FAKE
  run_loop
  f4__report
  set -e
  false
}

@test "C0 — témoin appairé : la même nuit sans ~/.curlrc" {
  f4__alpha
  f4__wrap_curl
  script_claude <<'FAKE'
#!/usr/bin/env bash
mkdir -p src && printf 'written\n' >src/alpha.txt
printf '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}\n'
FAKE
  run_loop
  f4__report
  set -e
  false
}
