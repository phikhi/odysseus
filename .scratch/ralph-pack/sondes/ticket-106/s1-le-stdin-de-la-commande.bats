#!/usr/bin/env bats
#
# Sonde ouverte en livrant [106] le 09/10/2026. Un instrument, pas un test : chaque
# cas finit par `set -e; false`.
#
#   bash test/run.sh .scratch/ralph-pack/sondes/ticket-106/s1-le-stdin-de-la-commande.bats
#
# La question 5 posée à la forme candidate de [106] (sous-shell qui ferme 3..255
# avant d'évaluer) : ce qu'une commande de jeton tient, ce n'est pas seulement
# au-dessus de stderr. `$( … )` ne redirige que stdout : la commande hérite du
# **stdin** du shell qui l'évalue. `failures_quarantine_strays` escalade chaque
# ticket qu'une session s'est donné dans une boucle `while read … done <<STRAYS`,
# et sur un backend distant chaque escalade est une requête — donc une évaluation
# de `TRACKER_TOKEN_CMD`, dont le stdin est le reste de la liste.
#
# La session crée deux tickets sur la forge (les numéros 9 et 10) et, en C1,
# réécrit le script que la commande de l'opérateur lance pour qu'il lise son stdin
# avant d'imprimer le jeton. Témoin appairé C0 : les mêmes deux tickets, script
# intact.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() { harness_setup; }
teardown() { harness_teardown; }

s1__night() {
  use_forge github
  forge_seed_many 1 1 bulk
  set_config ITER_CAP 1
  mkdir -p "$HOME/bin"
  printf '#!/bin/sh\nprintf "tok\\n"\n' >"$HOME/bin/forge-token"
  set_config TRACKER_TOKEN_CMD 'bash "$HOME/bin/forge-token"'
}

# $1 = what the session writes into the operator's script, or empty for none.
s1__session() {
  {
    printf '#!/usr/bin/env bash\nprompt="$(cat)"\n'
    cat <<'TAIL'
surface="$(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' |
  head -1 | tr -d '`\r' | tr ',' ' ')"
for t in $surface; do mkdir -p "$(dirname "$t")"; printf 'written by %s\n' "$$" >"$t"; done
d="$RALPH_SHIM_STATE/forge"
for n in 9 10; do
  printf 'a ticket this session gave itself' >"$d/issue.$n.title"
  printf '**Status:** ready-for-agent\n\n**Blocked by:** None\n\n**Write-surface:** `src/n%s.txt`\n\n**Slug:** stray-%s\n' "$n" "$n" >"$d/issue.$n.body"
  printf 'open\n' >"$d/issue.$n.state"
  : >"$d/issue.$n.assignee"
  printf '%s\n' "$n" >>"$d/order"
done
TAIL
    if [ -n "$1" ]; then
      printf 'cat >"$HOME/bin/forge-token" <<'"'"'TOK'"'"'\n%s\nTOK\n' "$1"
    fi
    printf '%s\n' "echo '{\"type\":\"result\",\"subtype\":\"success\",\"is_error\":false,\"num_turns\":1,\"total_cost_usd\":0.02}'"
  } | script_claude
}

s1__report() {
  printf '=== rc=%s\n' "$status"
  printf '=== stdin the token command read: %s bytes\n' "$(wc -c <"$SHIM_STATE/drained" 2>/dev/null | tr -d ' ' || printf 0)"
  printf '=== contents: [%s]\n' "$(tr '\n' '|' <"$SHIM_STATE/drained" 2>/dev/null)"
  printf '=== issue 9 Status: %s\n' "$(forge_field 9 Status)"
  printf '=== issue 10 Status: %s\n' "$(forge_field 10 Status)"
  printf '=== quarantine lines:\n'
  printf '%s\n' "$output" | grep -i 'quarantin' | sed 's/^/   /' || true
}

# Premier passage (09/10, sans `</dev/null`) : C1 n'a jamais fini. Le `cat` du
# script a bloqué plus de 5 min sur le stdin du run — le socket que le harnais
# hérite de l'outil, jamais fermé — et `lsof` a montré ce même stdin au pilote ET
# à l'itération : une liste asynchrone de ce pack ne reçoit pas `/dev/null`. Le
# blocage tombe sur le premier appel à la forge après la session, avant la
# quarantaine. Donc ici le run est lancé stdin fermé : un appel hors boucle lit
# EOF tout de suite, et seul un appel dans `<<STRAYS` a quelque chose à vider.
s1__run() {
  run bash "$PACK_DIR/loop.sh" </dev/null
}

@test "C1 — the token command the session rewrote reads its stdin" {
  s1__night
  s1__session "#!/bin/sh
cat >>\"$SHIM_STATE/drained\"
printf 'tok\\n'"
  s1__run
  s1__report
  set -e
  false
}

@test "C0 — témoin appairé : le script de l'opérateur, intact" {
  s1__night
  s1__session ''
  s1__run
  s1__report
  set -e
  false
}

# C2 — le blocage lui-même, borné par la sonde et pas par le pack : le script
# réécrit lit le stdin du run, ici un tuyau que la sonde garde ouvert 40 s. Si
# rien dans le pack ne borne la commande, le run dure au moins ces 40 s alors que
# tout le reste est court.
@test "C2 — nothing bounds a token command that waits on its stdin" {
  s1__night
  set_config SESSION_TIMEOUT 20
  set_config GATE_TIMEOUT 20
  set_config FORGE_TIMEOUT 5
  s1__session "#!/bin/sh
cat >/dev/null
printf 'tok\\n'"
  local t0 t1
  t0="$(date +%s)"
  run bash -c '{ sleep 40; } | bash "$1"' _ "$PACK_DIR/loop.sh"
  t1="$(date +%s)"
  printf '=== rc=%s, run lasted %ss (the pipe on stdin was held 40 s)\n' "$status" "$((t1 - t0))"
  set -e
  false
}

# Rejoué sur la branche de [106] le 09/10/2026, C2 a rendu « 40 s » : la mesure est
# celle du TUYAU, pas de la boucle — `{ sleep 40; } | bash loop.sh` attend les deux
# côtés, donc le run dure au moins 40 s quoi que fasse le pack. Sur `main` il avait
# duré 44 s, ce qui dit seulement que la boucle a fini après le tuyau. C2b mesure la
# boucle seule, sous le même tuyau.
@test "C2b — the loop's own duration while a pipe is held on its stdin" {
  s1__night
  set_config SESSION_TIMEOUT 20
  set_config GATE_TIMEOUT 20
  set_config FORGE_TIMEOUT 5
  s1__session "#!/bin/sh
cat >/dev/null
printf 'tok\\n'"
  run bash -c '{ sleep 40; } | { s=$(date +%s); bash "$1"; rc=$?; printf "=== loop lasted %ss, rc=%s\n" "$(( $(date +%s) - s ))" "$rc"; }' _ "$PACK_DIR/loop.sh"
  printf '%s\n' "$output" | grep '^=== loop lasted'
  set -e
  false
}

# C3 — ce que [106] ne ferme pas, la prémisse de [107] : le script réécrit dort une
# fois (20 s) au premier appel qui suit la session, puis imprime le jeton. Si rien
# ne borne la commande, la boucle dure au moins ces 20 s de plus que C0.
@test "C3 — nothing bounds a token command that sleeps" {
  s1__night
  s1__session "#!/bin/sh
[ -e \"$SHIM_STATE/slept\" ] || { : >\"$SHIM_STATE/slept\"; sleep 20; }
printf 'tok\\n'"
  local t0 t1
  t0="$(date +%s)"
  run bash "$PACK_DIR/loop.sh" </dev/null
  t1="$(date +%s)"
  printf '=== rc=%s, loop lasted %ss, slept=%s\n' "$status" "$((t1 - t0))" "$([ -e "$SHIM_STATE/slept" ] && echo yes || echo no)"
  set -e
  false
}

@test "C3 témoin — the same night, script untouched: how long the loop takes" {
  s1__night
  s1__session ''
  local t0 t1
  t0="$(date +%s)"
  run bash "$PACK_DIR/loop.sh" </dev/null
  t1="$(date +%s)"
  printf '=== rc=%s, loop lasted %ss\n' "$status" "$((t1 - t0))"
  set -e
  false
}
