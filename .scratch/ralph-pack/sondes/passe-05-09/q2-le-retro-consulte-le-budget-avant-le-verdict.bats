#!/usr/bin/env bats
#
# Passe transversale du 05/09 — Q2.
#
# [43] a posé la règle et [11] l'a réécrite en toutes lettres dans
# `playthrough_close` : **le verdict prime sur l'événement**. Un signal in-band
# peut annoncer `blocked` pour la fenêtre *suivante* pendant que la session en
# cours répond parfaitement ; une session qui a répondu a regardé, et ce qu'elle
# a dit tient.
#
#   `lenses_refused_posture`  — `[ "$(lenses__verdict …)" = none ] || return 1`
#                               PUIS `budget_refused`.
#   `playthrough_close`       — `[ "$verdict" = none ] && budget_refused …`
#   `retro_run`               — `budget_refused "$posture"` **d'abord**, et les
#                               `retro__said` ne sont lus qu'après.
#
# Ce que le rétro peut dire et qui est jeté par cet ordre : une LEÇON (l'index
# `LEARNINGS.md`), une DÉCISION D'ARCHITECTURE (`docs/adr/`), une ESCALADE (un
# ticket sur le puits humain) et une CAPACITÉ ([15]). Plus `RALPH_RETRO_QUOTA`,
# qui écrase le posture du slot et **arrête le run**.
#
# Le harnais lui-même porte l'asymétrie : [11] a ajouté `playthrough_rate_limit`
# (événement AVEC réponse) pour son propre palier, et le rétro n'a que
# `retro_refused` (événement SANS réponse, `exit 1`). Le cas ne pouvait pas
# s'écrire.
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

# Un faux `claude` qui répond en rétro ET porte l'événement in-band demandé.
# La session de livraison, elle, écrit son fichier et son flux dit `allowed`.
sonde__script() {
  local status="$1"
  cat >"$SHIM_STATE/sonde-status" <<STATUS
$status
STATUS
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
prompt="$(cat)"
state="$RALPH_SHIM_STATE"
allowed='{"status":"allowed","resetsAt":4102444800,"rateLimitType":"five_hour","isUsingOverage":false}'

if printf '%s' "$prompt" | grep -q 'RALPH-RETRO-NOTHING'; then
  st="$(cat "$state/sonde-status")"
  info="{\"status\":\"$st\",\"resetsAt\":4102444800,\"rateLimitType\":\"seven_day\",\"isUsingOverage\":false}"
  answer='RALPH-RETRO-LESSON: the flow has to be wired before the last ticket\nRALPH-RETRO-WHY: three iterations rebuilt the same wiring\nRALPH-RETRO-ADR: who owns the flow document\nRALPH-RETRO-DECISION: the loop owns it and no session may write it\nRALPH-RETRO-BECAUSE: a session cannot vouch for what it wrote itself\nRALPH-RETRO-ESCALATE: add a lint that fails when the flow is not wired'
  : >"$state/retro-was-called"
  cat <<EOF
{"type":"system","subtype":"init","cwd":"$PWD","session_id":"s-retro","uuid":"u-retro-init","model":"m","permissionMode":"bypassPermissions"}
{"type":"rate_limit_event","rate_limit_info":$info,"uuid":"u-retro-rate","session_id":"s-retro"}
{"type":"assistant","message":{"model":"m","id":"msg-retro","type":"message","role":"assistant","content":[{"type":"text","text":"$answer"}],"usage":{"input_tokens":10,"output_tokens":10}},"session_id":"s-retro","uuid":"u-retro-msg"}
{"type":"result","subtype":"success","is_error":false,"result":"$answer","session_id":"s-retro","uuid":"u-retro-result","num_turns":1,"duration_ms":10,"total_cost_usd":0.01,"usage":{"input_tokens":10,"output_tokens":10}}
EOF
  exit 0
fi

mkdir -p src && printf 'alpha\n' >src/alpha.txt
cat <<EOF
{"type":"system","subtype":"init","cwd":"$PWD","session_id":"s-deliver","uuid":"u-d-init","model":"m","permissionMode":"bypassPermissions"}
{"type":"rate_limit_event","rate_limit_info":$allowed,"uuid":"u-d-rate","session_id":"s-deliver"}
{"type":"assistant","message":{"model":"m","id":"msg-d","type":"message","role":"assistant","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":10,"output_tokens":10}},"session_id":"s-deliver","uuid":"u-d-msg"}
{"type":"result","subtype":"success","is_error":false,"result":"done","session_id":"s-deliver","uuid":"u-d-result","num_turns":1,"duration_ms":10,"total_cost_usd":0.02,"usage":{"input_tokens":10,"output_tokens":10}}
EOF
exit 0
SCRIPT
}

sonde__report() {
  printf '=== rc du run                       : %s\n' "$status"
  printf '=== le rétro a-t-il été appelé ?    : %s\n' \
    "$([ -f "$SHIM_STATE/retro-was-called" ] && echo oui || echo non)"
  printf '=== LEARNINGS.md existe ?           : %s\n' \
    "$([ -f "$PROJECT_DIR/LEARNINGS.md" ] && echo oui || echo NON)"
  if [ -f "$PROJECT_DIR/LEARNINGS.md" ]; then
    printf '=== LEARNINGS.md ------------------------------------\n'
    sed 's/^/    /' "$PROJECT_DIR/LEARNINGS.md"
  fi
  printf '=== docs/adr/                       : %s\n' \
    "$(ls -1 "$PROJECT_DIR/docs/adr" 2>/dev/null | tr '\n' ' ')"
  printf '=== tickets présents                : %s\n' \
    "$(ls -1 "$TRACKER_DIR" 2>/dev/null | tr '\n' ' ')"
  printf '=== Status 01-alpha / 02-beta       : %s / %s\n' \
    "$(ticket_status 01-alpha)" "$(ticket_status 02-beta)"
  printf '=== reçus                           : %s\n' \
    "$(ls -1 "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE" 2>/dev/null | tr '\n' ' ')"
  printf '=== ce que le reçu dit du rétro     :\n%s\n' \
    "$(grep -rh 'retro' "$PROJECT_DIR/receipts" 2>/dev/null | sed 's/^/    /')"
  printf '=== lignes du run qui parlent quota :\n%s\n' \
    "$(printf '%s\n' "$output" | grep -i 'quota\|budget\|refused\|subscription' | sed 's/^/    /')"
  printf '=== sortie du run -----------------------------------\n%s\n' "$output"
}

@test "Q2a le rétro répond une leçon, un ADR et une escalade, et son flux dit blocked" {
  use_tickets 01-alpha 02-beta
  set_config RETRO on
  sonde__script blocked

  run bash "$PACK_DIR/loop.sh"
  sonde__report

  set -e
  false
}

@test "Q2b témoin appairé : le même flux, le même rétro, l événement dit allowed" {
  use_tickets 01-alpha 02-beta
  set_config RETRO on
  sonde__script allowed

  run bash "$PACK_DIR/loop.sh"
  sonde__report

  set -e
  false
}
