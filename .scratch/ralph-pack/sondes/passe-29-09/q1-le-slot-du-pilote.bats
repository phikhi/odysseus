#!/usr/bin/env bats
#
# Passe transversale du 29/09 — Q1.
#
# Une itération est `loop__iterate … &` : un fork. Le seul canal par lequel elle
# rend une réponse au pilote est `$slot`, un `mktemp -d "$TMPDIR/ralph-slot.XXXXXX"`
# créé par le pilote avant le fork (loop.sh:1356) — et `ralph-slot.*` est l'un des
# dix-sept globs que `gate_tmp_names` **publie** (gate.sh:251).
#
# Dix fichiers y passent, et `loop__finish` en tire :
#   outcome           → `sterile` (donc STERILE_K), `tracker_unclaim`, `stop_code=4`
#   posture           → `budget_posture` → `budget_check` → la pause / l'arrêt
#   rollback-failed   → `stop_code=4`
#   drift             → des lignes de journal à sujet **arbitraire**
#   n turns cost tokens action → la ligne du journal du matin
#
# Ce que la ligne 64 de `docs/frontiere-de-confiance.md` écrit de toute cette
# classe de signaux : « ce qu'il coûte au pire est borné par `BUDGET_MAX_PAUSE` et
# `STERILE_K`, que rien de ce répertoire ne déplace ». Les deux bornes sont lues
# ici.
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

plain_ticket() {
  local id="$1" surface="$2"
  {
    printf '# %s\n\n' "$id"
    printf '**What to build:** A ticket written by the 29/09 pass probe.\n\n'
    printf '**Blocked by:** None\n\n'
    printf '**Write-surface:** %s\n\n' "$surface"
    printf '**Status:** ready-for-agent\n\n'
    printf -- '- [ ] The marker file exists.\n'
  } >"$TRACKER_DIR/$id.md"
}

four_tickets() {
  plain_ticket 01-plain 'src/one.txt'
  plain_ticket 02-plain 'src/two.txt'
  plain_ticket 03-plain 'src/three.txt'
  plain_ticket 04-plain 'src/four.txt'
}

# Le survivant. `trap "" TERM` parce que c'est le prix écrit de [92] : un
# survivant qui ignore le signal reste. Il réécrit un fichier du slot en boucle à
# 10 ms — la fenêtre du pilote est la sienne : `loop__reap` dort 0,2 s entre deux
# passes, et l'itération écrit `outcome` puis `done` juste avant.
plant_survivor() {
  local file="$1" content="$2"
  script_claude <<SCRIPT
#!/usr/bin/env bash
state="\$RALPH_SHIM_STATE"
FORGE_FILE='$file' FORGE_BODY='$content' nohup bash -c '
  trap "" TERM
  end=\$((SECONDS + 120))
  while [ "\$SECONDS" -lt "\$end" ]; do
    for d in "\$TMPDIR"/ralph-slot.*; do
      [ -d "\$d" ] || continue
      printf "%s\n" "\$d" >>"\$RALPH_SHIM_STATE/survivor.saw"
      printf "%s\n" "\$FORGE_BODY" >"\$d/\$FORGE_FILE" 2>/dev/null &&
        printf "%s %s\n" "\$d" "\$FORGE_FILE" >>"\$RALPH_SHIM_STATE/survivor.forged"
    done
    sleep 0.01
  done
' >/dev/null 2>&1 &
printf '%s\n' "\$!" >"\$state/survivor.pid"
chmod -x "\$state/claude.script"
exec claude "\$@"
SCRIPT
}

kill_survivor() {
  kill -KILL "$(cat "$SHIM_STATE/survivor.pid" 2>/dev/null)" 2>/dev/null || true
}

survivor_report() {
  printf '=== le survivant a vu %s slot(s), forgé %s fois\n' \
    "$(sort -u "$SHIM_STATE/survivor.saw" 2>/dev/null | grep -c . || echo 0)" \
    "$(grep -c . "$SHIM_STATE/survivor.forged" 2>/dev/null || echo 0)"
  printf '=== une ligne du run nomme-t-elle une forge ?\n'
  printf '%s\n' "$output" | grep -iE 'forged|survivor|tamper|not the copy|appeared in' |
    sed 's/^/    /' || printf '    aucune\n'
}

@test "Q1a témoin appairé — quatre tickets, aucune session ne livre, rien de planté" {
  four_tickets
  session_writes_nothing
  set_config ITER_CAP 8

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== sessions de livraison : %s\n' "$(claude_call_count || true)"
  printf '=== la ligne d arrêt :\n'
  printf '%s\n' "$output" | grep -iE 'sterile|iteration cap|nothing to do|stopping' |
    sed 's/^/    /' || printf '    aucune\n'
  printf '=== journal (run.log) :\n'
  grep -c . "$FEATURE_DIR/run.log" 2>/dev/null |
    sed 's/^/    lignes: /' || printf '    absent\n'

  set -e
  false
}

@test "Q1b le même run, un survivant écrit resolved dans \$slot/outcome" {
  four_tickets
  session_writes_nothing
  set_config ITER_CAP 8
  plant_survivor outcome resolved

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== sessions de livraison : %s\n' "$(claude_call_count || true)"
  printf '=== la ligne d arrêt :\n'
  printf '%s\n' "$output" | grep -iE 'sterile|iteration cap|nothing to do|stopping' |
    sed 's/^/    /' || printf '    aucune\n'
  printf '=== ce que le journal dit des itérations :\n'
  grep -oE '	(resolved|nothing-delivered|gate-red|budget-[a-z]*)	' \
    "$FEATURE_DIR/run.log" 2>/dev/null |
    sort | uniq -c | sed 's/^/    /' || printf '    absent\n'
  survivor_report

  kill_survivor
  set -e
  false
}

@test "Q1c une itération verte, un survivant écrit une posture bloquée dans \$slot/posture" {
  four_tickets
  plant_survivor posture 'blocked weekly 0'

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== sessions de livraison : %s\n' "$(claude_call_count || true)"
  printf '=== tickets : 01=%s 02=%s\n' \
    "$(ticket_field 01-plain Status || true)" \
    "$(ticket_field 02-plain Status || true)"
  printf '=== les 20 dernières lignes du run :\n'
  printf '%s\n' "$output" | tail -20 | sed 's/^/    /'
  survivor_report

  kill_survivor
  set -e
  false
}

@test "Q1d une itération verte, un survivant écrit 1 dans \$slot/rollback-failed" {
  four_tickets
  plant_survivor rollback-failed 1

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== sessions de livraison : %s\n' "$(claude_call_count || true)"
  printf '=== ticket 01 : %s\n' "$(ticket_field 01-plain Status || true)"
  printf '=== les 12 dernières lignes du run :\n'
  printf '%s\n' "$output" | tail -12 | sed 's/^/    /'
  survivor_report

  kill_survivor
  set -e
  false
}

# Q1e isole le second défaut que Q1d a fait apparaître : `loop__finish` finit par
# `rm -rf "$slot"` et le pilote tourne sous `errexit`. Un `rm -rf` dont le
# répertoire se repeuple pendant la marche rend ENOTEMPTY. Le survivant n'écrit
# ici qu'un nom que `loop__finish` ne lit pas : la seule conséquence possible est
# la course du `rm`.
@test "Q1e un survivant écrit un nom que personne ne lit dans \$slot" {
  four_tickets
  plant_survivor noise 'rien du tout'

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== sessions de livraison : %s\n' "$(claude_call_count || true)"
  printf '=== tickets : 01=%s 02=%s 03=%s 04=%s\n' \
    "$(ticket_field 01-plain Status || true)" \
    "$(ticket_field 02-plain Status || true)" \
    "$(ticket_field 03-plain Status || true)" \
    "$(ticket_field 04-plain Status || true)"
  printf '=== les 8 dernières lignes du run :\n'
  printf '%s\n' "$output" | tail -8 | sed 's/^/    /'
  printf '=== la phrase du garde de sortie de [72] est-elle là ?\n'
  printf '%s\n' "$output" | grep -i 'ended in the middle' | sed 's/^/    /' ||
    printf '    non\n'
  survivor_report

  kill_survivor
  set -e
  false
}

# Q1f la même course, sans `sleep` : Q1e la perd la plupart du temps parce que la
# fenêtre est celle entre la marche de `rm -rf` et son `rmdir`. Un survivant qui
# écrit sans relâche la gagne.
@test "Q1f un survivant qui repeuple \$slot sans relâche" {
  four_tickets
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
nohup bash -c '
  trap "" TERM
  end=$((SECONDS + 120))
  while [ "$SECONDS" -lt "$end" ]; do
    for d in "$TMPDIR"/ralph-slot.*; do
      [ -d "$d" ] || continue
      printf x >"$d/noise" 2>/dev/null &&
        printf "%s\n" "$d" >>"$RALPH_SHIM_STATE/survivor.forged"
    done
  done
' >/dev/null 2>&1 &
printf '%s\n' "$!" >"$state/survivor.pid"
chmod -x "$state/claude.script"
exec claude "$@"
SCRIPT

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== tickets : 01=%s 02=%s 03=%s 04=%s\n' \
    "$(ticket_field 01-plain Status || true)" \
    "$(ticket_field 02-plain Status || true)" \
    "$(ticket_field 03-plain Status || true)" \
    "$(ticket_field 04-plain Status || true)"
  printf '=== les 6 dernières lignes du run :\n'
  printf '%s\n' "$output" | tail -6 | sed 's/^/    /'
  printf '=== la phrase du garde de sortie de [72] est-elle là ?\n'
  printf '%s\n' "$output" | grep -i 'ended in the middle' | sed 's/^/    /' ||
    printf '    non\n'
  printf '=== forges : %s\n' "$(grep -c . "$SHIM_STATE/survivor.forged" 2>/dev/null || echo 0)"

  kill_survivor
  set -e
  false
}

# Q1g `$slot/drift` est le seul des sept où il n'y a AUCUNE course : le pack ne
# l'écrit que sur une dérive de capacité, de PATH ou de forensique, et
# `loop__finish` le lit tel quel. Pas de survivant, pas d'attente : la session
# l'écrit elle-même pendant sa fenêtre.
@test "Q1g la session écrit \$slot/drift, sans survivant et sans course" {
  four_tickets
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
state="$RALPH_SHIM_STATE"
tab="$(printf '\t')"
for d in "$TMPDIR"/ralph-slot.*; do
  [ -d "$d" ] || continue
  {
    printf '%s\n' "FORGED-SUBJECT-ONE${tab}capability-drift"
    printf '%s\n' "../../../etc/passwd${tab}forged-outcome"
  } >>"$d/drift"
  printf '%s\n' "$d" >>"$state/drift.written"
done
chmod -x "$state/claude.script"
exec claude "$@"
SCRIPT

  run_loop_own_tmp
  printf '=== statut du run : %s\n' "$status"
  printf '=== la session a écrit drift dans %s slot(s)\n' \
    "$(sort -u "$SHIM_STATE/drift.written" 2>/dev/null | grep -c . || echo 0)"
  printf '=== le journal du matin (run.log) :\n'
  sed 's/^/    /' "$FEATURE_DIR/run.log" 2>/dev/null || printf '    absent\n'
  printf '=== le témoin du journal de [10] a-t-il dit quelque chose ?\n'
  printf '%s\n' "$output" | grep -i 'journal' | sed 's/^/    /' ||
    printf '    rien\n'

  set -e
  false
}
