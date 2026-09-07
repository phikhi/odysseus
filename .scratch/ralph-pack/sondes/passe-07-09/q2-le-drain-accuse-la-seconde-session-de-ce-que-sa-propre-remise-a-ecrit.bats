#!/usr/bin/env bats
#
# Passe transversale du 07/09 — Q2.
#
# `router__say_unrestored` porte sa propre garde, et elle est écrite au singulier :
#
#   « Called only where the two restorable states are unchanged, so it never
#     doubles up on a line that already reported a restore — a status put back
#     rewrites the file, which would move the digest by this drain's own hand. »
#
# La garde vaut pour UN appel. Le menu est re-offert après une session ([57]) :
# `router_protect_tracker` est donc appelé une fois par session, contre un pin
# pris une seule fois par ticket — et la remise que le premier appel a écrite est
# toujours sur le disque au second.
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

sonde__tickets() {
  {
    printf '# 20-decision — le ticket devant l humain\n\n'
    printf '**What to build:** Something a human has to arbitrate.\n\n'
    printf '**Status:** ready-for-human\n\n'
    printf '**Escalation:** decision\n\n'
    printf '**Write-surface:** `src/one.txt`\n\n'
    printf '**Blocked by:** None\n'
  } >"$TRACKER_DIR/20-decision.md"
  # Le voisin, tel qu un humain le tape : dans le puits, SANS `Escalation:`.
  # C est le desk `request`, et c est le cas que `router_protect_tracker`
  # nomme lui-même (« a ticket that was in this sink without an `Escalation:`
  # comes back with an empty one »).
  {
    printf '# 21-second — le voisin\n\n'
    printf '**What to build:** Something somebody typed.\n\n'
    printf '**Status:** ready-for-human\n\n'
    printf '**Blocked by:** None\n'
  } >"$TRACKER_DIR/21-second.md"
  harness__commit "sonde: deux tickets dans le puits"
}

sonde__show() {
  printf '=== 21-second, %s :\n' "$1"
  sed 's/^/    | /' "$TRACKER_DIR/21-second.md"
  printf '    digest cksum : %s\n' "$(cksum <"$TRACKER_DIR/21-second.md" | awk '{print $1"."$2}')"
}

@test "Q2a une session bouge le voisin, le drain le remet, puis une SECONDE session qui n écrit rien" {
  sonde__tickets
  sonde__show 'avant le drain'

  script_claude <<'FAKE'
#!/usr/bin/env bash
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
n="$(cat "$RALPH_SHIM_STATE/sonde-n" 2>/dev/null || printf 0)"
n=$((n + 1))
printf '%s\n' "$n" >"$RALPH_SHIM_STATE/sonde-n"
if [ "$n" = 1 ]; then
  perl -pi -e 's/^\*\*Status:\*\* ready-for-human$/**Status:** resolved/' \
    "$tracker/21-second.md"
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\no\nn\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== rc du drain : %s\n' "$status"
  printf '=== nombre de sessions ouvertes : %s\n' "$(claude_call_count)"
  printf '=== ce que le drain a dit de 21-second :\n'
  printf '%s\n' "$output" | grep '21-second' | sed 's/^/    /'
  printf '=== lignes tracker-drift dans run.log :\n'
  grep 'tracker-drift' "$FEATURE_DIR/run.log" 2>/dev/null | sed 's/^/    /' || true
  sonde__show 'après le drain'

  set -e
  false
}

@test "Q2b témoin appairé : les deux mêmes sessions, aucune n écrit le voisin" {
  sonde__tickets

  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\no\nn\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== rc du drain : %s\n' "$status"
  printf '=== nombre de sessions ouvertes : %s\n' "$(claude_call_count)"
  printf '=== ce que le drain a dit de 21-second : %s ligne(s)\n' \
    "$(printf '%s\n' "$output" | grep -c '21-second reads' || true)"
  printf '=== lignes tracker-drift dans run.log : %s\n' \
    "$(grep -c 'tracker-drift' "$FEATURE_DIR/run.log" 2>/dev/null || printf 0)"

  set -e
  false
}

@test "Q2c le même scénario avec UNE seule session : ce que le drain dit alors" {
  sonde__tickets

  script_claude <<'FAKE'
#!/usr/bin/env bash
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
perl -pi -e 's/^\*\*Status:\*\* ready-for-human$/**Status:** resolved/' \
  "$tracker/21-second.md"
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nn\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== rc du drain : %s\n' "$status"
  printf '=== ce que le drain a dit de 21-second :\n'
  printf '%s\n' "$output" | grep '21-second' | sed 's/^/    /'
  printf '=== lignes tracker-drift dans run.log :\n'
  grep 'tracker-drift' "$FEATURE_DIR/run.log" 2>/dev/null | sed 's/^/    /' || true
  sonde__show 'après le drain'

  set -e
  false
}

@test "Q2d le voisin PORTE une Escalation : la remise est-elle octet pour octet ?" {
  sonde__tickets
  perl -pi -e 's/^(\*\*Status:\*\* ready-for-human)$/$1\n\n**Escalation:** decision/' \
    "$TRACKER_DIR/21-second.md"
  harness__commit "sonde: 21-second porte une escalation"
  sonde__show 'avant le drain'

  script_claude <<'FAKE'
#!/usr/bin/env bash
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
n="$(cat "$RALPH_SHIM_STATE/sonde-n" 2>/dev/null || printf 0)"
n=$((n + 1))
printf '%s\n' "$n" >"$RALPH_SHIM_STATE/sonde-n"
if [ "$n" = 1 ]; then
  perl -pi -e 's/^\*\*Status:\*\* ready-for-human$/**Status:** resolved/' \
    "$tracker/21-second.md"
fi
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\no\nn\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== rc du drain : %s\n' "$status"
  printf '=== ce que le drain a dit de 21-second :\n'
  printf '%s\n' "$output" | grep '21-second' | sed 's/^/    /'
  sonde__show 'après le drain'

  set -e
  false
}
