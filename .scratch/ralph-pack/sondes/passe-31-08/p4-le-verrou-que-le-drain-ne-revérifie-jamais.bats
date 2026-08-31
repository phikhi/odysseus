#!/usr/bin/env bats
#
# Passe transversale du 31/08 — question 4 : *qu'hérite [16] de ce que [22] et
# [12] ont laissé, et qu'est-ce que [16] laisse à [11] ?*
#
# `loop.sh` repose une question à chaque itération (l. 1468 et 1477) :
#
#   « the run lock is gone or not ours any more … stopping rather than grinding
#     beside another run »
#   « the working-tree lock is gone or not ours any more … »
#
# Elle existe parce que le verrou de run vit sous `.scratch/<feature>/`, que le
# scope-guard laisse comme bookkeeping, et que [12] a montré qu'une session peut
# l'effacer. `state.sh` l'écrit comme un fait acquis : « the run and tree locks
# are re-checked for ownership on every iteration (`*_is_ours`) ».
#
# `run_lock_is_ours` et `tree_lock_is_ours` n'ont chacun **qu'un appelant**, et
# c'est `loop.sh`. `human-loop.sh` prend les deux verrous et ne les redemande
# jamais — alors que c'est le point d'entrée qui met un `claude` **non jugé**
# dans l'arbre principal, donc celui où perdre le verrou coûte le plus cher.
#
# La sonde met deux tickets dans le puits. La session routée du premier efface
# les deux verrous ; celle du second enregistre ce qu'il en reste, pendant que le
# drain tourne encore.
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

drain() {
  run bash "$PACK_DIR/human-loop.sh"
}

# Deux sessions routées : la première agit, la seconde observe. Le compteur est
# un `mkdir`, comme les slots du faux `claude` — un `cat + 1` mentirait dès que
# les appels ne sont plus séquentiels.
script_two_sessions() {
  local first="$1"
  cat >"$SHIM_STATE/claude.script" <<SCRIPT
#!/usr/bin/env bash
state="\$RALPH_SHIM_STATE"
root="\$(cat "\$state/project-dir")"
if mkdir "\$state/routed.first" 2>/dev/null; then
  $first
else
  {
    printf 'run lock  : '
    [ -d "\$root/.scratch/demo/.run.lock" ] && printf 'présent\n' || printf 'ABSENT\n'
    printf 'tree lock : '
    [ -d "\$root/.git/ralph.tree.lock" ] && printf 'présent\n' || printf 'ABSENT\n'
  } >"\$state/observed"
fi
exit 0
SCRIPT
  chmod +x "$SHIM_STATE/claude.script"
}

# ── P4a — la session routée efface les deux verrous ───────────────────────────

@test "P4a une session routée efface les verrous et le drain ne le redemande jamais" {
  use_tickets 09-escalated
  cp "$TRACKER_DIR/09-escalated.md" "$TRACKER_DIR/10-second.md"
  perl -pi -e 's/^# 09 — Escalated/# 10 — Second/' "$TRACKER_DIR/10-second.md"

  script_two_sessions 'rm -rf "$root/.scratch/demo/.run.lock" "$root/.git/ralph.tree.lock"'

  drain <<'ANSWERS'
o
n
o
n
ANSWERS

  printf '=== rc du drain : %s\n' "$status"
  printf '=== ce que la SECONDE session routée a vu, drain encore vivant :\n'
  sed 's/^/    /' "$SHIM_STATE/observed" 2>/dev/null || printf '    <rien>\n'
  printf '=== le drain a-t-il dit un mot ? -------------------\n'
  printf '%s\n' "$output" | grep -i 'lock\|verrou\|stopping' | sed 's/^/  /'
  printf '  (rien au-dessus = rien ne le nomme)\n'
  printf '=== sortie du drain -------------------------------\n%s\n' "$output"

  set -e
  false
}

# ── P4b — le témoin appairé : la même course, sans l'effacement ───────────────

@test "P4b la même paire de sessions, sans l'effacement" {
  use_tickets 09-escalated
  cp "$TRACKER_DIR/09-escalated.md" "$TRACKER_DIR/10-second.md"
  perl -pi -e 's/^# 09 — Escalated/# 10 — Second/' "$TRACKER_DIR/10-second.md"

  script_two_sessions ':'

  drain <<'ANSWERS'
o
n
o
n
ANSWERS

  printf '=== rc du drain : %s\n' "$status"
  printf '=== ce que la SECONDE session routée a vu :\n'
  sed 's/^/    /' "$SHIM_STATE/observed" 2>/dev/null || printf '    <rien>\n'

  set -e
  false
}

# ── P4c — le même effacement sur le chemin AFK, pour comparaison ──────────────

@test "P4c le même effacement depuis une session AFK : ce que loop.sh en dit" {
  use_tickets 01-alpha 02-beta

  cat >"$SHIM_STATE/claude.script" <<'SCRIPT'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
root="$(cat "$state/project-dir")"
rm -rf "$root/.scratch/demo/.run.lock" "$root/.git/ralph.tree.lock"
mkdir -p src
printf 'alpha\n' >src/alpha.txt
printf '{"type":"result","subtype":"success","is_error":false,"duration_ms":10,"num_turns":1,"result":"ok","session_id":"s","total_cost_usd":0.001,"usage":{"input_tokens":10,"output_tokens":10}}\n'
exit 0
SCRIPT
  chmod +x "$SHIM_STATE/claude.script"

  run_loop
  printf '=== rc du run AFK : %s\n' "$status"
  printf '=== ce que loop.sh en dit -------------------------\n'
  printf '%s\n' "$output" | grep -i 'lock' | sed 's/^/  /'
  printf '  (rien au-dessus = rien ne le nomme)\n'

  set -e
  false
}
