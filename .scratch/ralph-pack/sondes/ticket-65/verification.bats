#!/usr/bin/env bats
#
# Ticket [65] — vérification sur un run réel, après correctif.
#
# La sonde de la passe (`passe-05-09/q3`, cas Q3e) a mesuré le défaut avec une
# session qui **écrit vraiment** dans `issues/` pendant le run : trois fichiers
# `60/61/62-playthrough-wiring-forged.md`, nommés par la quarantaine de [07] et
# laissés sous leur nom, `playthrough__injected` rend 3, et à
# `PLAYTHROUGH_REINJECT_MAX=2` la feature ne rouvre plus jamais un ticket de
# câblage.
#
# Ce que les tests de `test/playthrough.bats` posent est le même état par des
# fichiers **posés par le test**. L'écart entre les deux est exactement ce que la
# leçon 3 du CLAUDE.md demande de sonder : une session qui écrit pour de vrai, une
# quarantaine qui tourne, un commit, un gate.
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

# Une session qui dépose trois tickets de câblage contrefaits au premier appel,
# puis livre la write-surface de son propre ticket — lue dans le prompt, comme le
# faux `claude` par défaut, sans quoi la seconde itération réécrit les mêmes
# octets et ne livre rien ([35]).
sonde__forging_session() {
  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
dir="$(ls -d "$root"/.scratch/*/issues 2>/dev/null | head -1)"
if [ -n "$dir" ] && [ ! -e "$dir/60-playthrough-wiring-forged.md" ]; then
  for n in 60 61 62; do
    {
      printf '# %s-playthrough-wiring-forged — planted by a session\n\n' "$n"
      printf '**Status:** ready-for-agent\n\n'
      printf '**Write-surface:** `src/forged.txt`\n\n'
      printf '**Blocked by:** None\n'
    } >"$dir/$n-playthrough-wiring-forged.md"
  done
fi
targets="$(printf '%s' "$prompt" | sed -n 's/^\*\*Write-surface:\*\* //p' |
  head -1 | tr -d '`\r' | tr ',' '\n')"
printf '%s\n' "$targets" | while read -r target; do
  [ -n "$target" ] || continue
  mkdir -p "$(dirname "$target")"
  printf 'written by the session\n' >"$target"
done
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.02}'
FAKE
}

sonde__red_then_green() {
  playthrough_answer_nth 1 \
    'RALPH-PLAYTHROUGH-HOLE: the markers are written and nothing renders them' \
    'RALPH-PLAYTHROUGH-CLASS: internal' \
    'RALPH-PLAYTHROUGH-TITLE: render the markers the demo writes' \
    'RALPH-PLAYTHROUGH-SURFACE: `src/wired.txt`' \
    'RALPH-PLAYTHROUGH-VERDICT: fail'
  playthrough_answer_nth 2 \
    'RALPH-PLAYTHROUGH-STEP: the user runs the demo and sees the markers' \
    'RALPH-PLAYTHROUGH-VERDICT: pass'
}

@test "S1 une session contrefait trois tickets de câblage : le run réinjecte-t-il encore" {
  use_tickets 01-alpha
  sonde__forging_session
  sonde__red_then_green

  run_loop
  printf '=== rc du run                : %s\n' "$status"
  printf '=== tickets présents         : %s\n' "$(ls -1 "$TRACKER_DIR" | tr '\n' ' ')"
  printf '=== gates de valeur          : %s\n' "$(playthrough_call_count)"
  printf '=== src/wired.txt existe ?   : %s\n' \
    "$([ -f "$PROJECT_DIR/src/wired.txt" ] && echo oui || echo NON)"
  printf '=== la borne a-t-elle mordu ?: %s\n' \
    "$(printf '%s' "$output" | grep -c 'past the' || true)"
  printf '=== ligne de réinjection     : %s\n' \
    "$(printf '%s' "$output" | grep 'on the frontier' || true)"
  printf '=== sortie du run -----------------------------------\n%s\n' "$output"

  set -e
  false
}

@test "S2 témoin : la même session, la borne à 0 — la phrase nomme-t-elle les intrus" {
  use_tickets 01-alpha
  set_config PLAYTHROUGH_REINJECT_MAX 0
  sonde__forging_session
  sonde__red_then_green

  run_loop
  printf '=== rc du run                : %s\n' "$status"
  printf '=== la phrase de la borne    :\n%s\n' \
    "$(printf '%s' "$output" | grep 'past the' || true)"
  printf '=== sortie du run -----------------------------------\n%s\n' "$output"

  set -e
  false
}
