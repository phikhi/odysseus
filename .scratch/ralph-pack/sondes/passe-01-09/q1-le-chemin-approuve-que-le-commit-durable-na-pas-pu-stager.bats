#!/usr/bin/env bats
#
# Passe transversale du 01/09 — Q1, la question que [54] a explicitement
# renvoyée à cette passe.
#
# Ce que [54] a écrit :
#   « `concurrency__refresh` a reçu `$tip` parce que « absent de `HEAD` » ne veut
#     pas dire « supprimé » ; le rejeu, lui, pose toujours UNE seule question et
#     lit « absent du commit » comme « supprimé ». Un chemin que le gate approuve
#     et que `git add` REFUSE (le `refused` de `failures_make_durable`) est absent
#     du commit exactement comme un chemin supprimé — et s'il est sur le tip, le
#     rejeu le retire de la branche. Non ouvert en ticket parce qu'aucun cas
#     atteignable n'a été construit. »
#
# Et, dans le même ticket : « Le chemin replay n'est atteint qu'au-dessus de
# `MAX_PARALLEL=1`, donc l'installation par défaut n'y touche pas. »
#
# Les deux moitiés de la question sont donc :
#   Q1a — le rejeu est-il vraiment hors de portée à MAX_PARALLEL=1 ? Un humain
#         qui commite dans un autre terminal pendant qu'un run tourne déplace le
#         tip — et c'est exactement ce que [56] vient de demander aux humains de
#         faire (« un humain qui commite dans un autre terminal et retape `r`
#         passe »).
#   Q1b — le refus de `git add` mesuré par Q2 (`chmod 000`) donne le chemin
#         approuvé absent du commit. Le tip le porte. Que devient-il ?
#
# Le rôle du `TYPECHECK_CMD` ici est celui de l'humain à son second terminal, et
# celui du `TEST_CMD` celui d'une suite de projet qui touche les permissions :
# les deux tournent APRÈS que [29] a figé l'arbre jugé, ce qui est exactement la
# fenêtre que [54] nomme (« entre l'arbre jugé et le commit durable »).
#
# Instrument, pas test : chaque cas finit par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  chmod -R u+rwX "$RALPH_TEST_DIR" 2>/dev/null || true
  harness_teardown
}

mk_ticket() {
  local id="$1" file
  shift
  file="$TRACKER_DIR/$id.md"
  {
    printf '# %s — written by a sonde\n\n' "$id"
    printf '**What to build:** A fixture for the fold.\n\n'
    while [ "$#" -ge 2 ]; do
      printf '**%s:** %s\n\n' "$1" "$2"
      shift 2
    done
    printf -- '- [ ] Something a session delivers.\n'
  } >"$file"
  harness__commit "sonde: $id"
}

# L'humain à son second terminal : il commite un correctif sur la branche
# pendant que l'itération tourne. Monté sur TYPECHECK_CMD, qui tourne dans le
# fan, donc après l'arbre jugé et avant le commit durable.
human_commits() {
  local path="$1" body="$2"
  cat >"$SHIM_BIN/human-commits" <<HUMAN
#!/usr/bin/env bash
root="\$(cat "\$RALPH_SHIM_STATE/project-dir")"
mkdir -p "\$root/\$(dirname "$path")"
printf '%s\n' "$body" >"\$root/$path"
git -C "\$root" add -- "$path"
git -C "\$root" -c user.name=human -c user.email=h@x commit -q -m 'human: a fix committed in another terminal'
exit 0
HUMAN
  chmod +x "$SHIM_BIN/human-commits"
  set_config TYPECHECK_CMD 'human-commits'
}

# ── Q1a — le rejeu est-il hors de portée à MAX_PARALLEL=1 ? ───────────────────

@test "Q1a un commit humain sur la branche pendant l'itération, MAX_PARALLEL=1" {
  mk_ticket 50-fold Status ready-for-agent \
    'Write-surface' '`src/ok.txt`, `src/shared.txt`' 'Blocked by' None
  human_commits 'src/shared.txt' 'written by the human, committed by hand'

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
mkdir -p src
printf 'delivered by the session\n' >src/ok.txt
printf 'also delivered by the session\n' >src/shared.txt
exit 0
SCRIPT

  run_loop
  printf '=== rc du run                    : %s\n' "$status"
  printf '=== Status 50-fold               : %s\n' "$(ticket_status 50-fold)"
  printf '=== ligne fast-forward ?         : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'folded onto the branch$')"
  printf '=== ligne rejeu ?                : %s\n' \
    "$(printf '%s\n' "$output" | grep -c "folded onto the branch over a sibling's commit")"
  printf '=== src/shared.txt sur HEAD      : %s\n' \
    "$(git -C "$PROJECT_DIR" show HEAD:src/shared.txt 2>&1)"
  printf '=== src/ok.txt sur HEAD          : %s\n' \
    "$(git -C "$PROJECT_DIR" show HEAD:src/ok.txt 2>&1)"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}

# ── Q1b — le chemin approuvé que le commit durable n'a pas pu stager ──────────
#
# Même montage, plus la suite du projet qui rend illisible le chemin livré,
# après l'arbre jugé. `git add` le refuse, il est absent du commit de
# l'itération, et le tip le porte parce que l'humain vient de le commiter.

@test "Q1b le même montage, le chemin livré rendu illisible après l'arbre jugé" {
  mk_ticket 50-fold Status ready-for-agent \
    'Write-surface' '`src/ok.txt`, `src/shared.txt`' 'Blocked by' None
  human_commits 'src/shared.txt' 'written by the human, committed by hand'

  cat >"$SHIM_BIN/perm-tests" <<'PERM'
#!/usr/bin/env bash
chmod 000 src/shared.txt 2>/dev/null || true
exit 0
PERM
  chmod +x "$SHIM_BIN/perm-tests"
  set_config TEST_CMD 'perm-tests'

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
mkdir -p src
printf 'delivered by the session\n' >src/ok.txt
printf 'also delivered by the session\n' >src/shared.txt
exit 0
SCRIPT

  run_loop
  printf '=== rc du run                    : %s\n' "$status"
  printf '=== Status 50-fold               : %s\n' "$(ticket_status 50-fold)"
  printf '=== ligne « could not be staged »: %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'could not be staged')"
  printf '=== ligne rejeu ?                : %s\n' \
    "$(printf '%s\n' "$output" | grep -c "folded onto the branch over a sibling's commit")"
  printf '=== src/shared.txt sur HEAD      : %s\n' \
    "$(git -C "$PROJECT_DIR" show HEAD:src/shared.txt 2>&1)"
  printf '=== src/ok.txt sur HEAD          : %s\n' \
    "$(git -C "$PROJECT_DIR" show HEAD:src/ok.txt 2>&1)"
  printf '=== src/shared.txt dans l'\''arbre : %s\n' \
    "$([ -e "$PROJECT_DIR/src/shared.txt" ] && echo present || echo ABSENT)"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}

# ── Q1c — le témoin appairé : le même montage sans le chmod ───────────────────

@test "Q1c témoin appairé : le même montage sans le refus de staging" {
  mk_ticket 50-fold Status ready-for-agent \
    'Write-surface' '`src/ok.txt`, `src/shared.txt`' 'Blocked by' None
  human_commits 'src/shared.txt' 'written by the human, committed by hand'

  cat >"$SHIM_BIN/perm-tests" <<'PERM'
#!/usr/bin/env bash
exit 0
PERM
  chmod +x "$SHIM_BIN/perm-tests"
  set_config TEST_CMD 'perm-tests'

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
mkdir -p src
printf 'delivered by the session\n' >src/ok.txt
printf 'also delivered by the session\n' >src/shared.txt
exit 0
SCRIPT

  run_loop
  printf '=== rc du run                    : %s\n' "$status"
  printf '=== Status 50-fold               : %s\n' "$(ticket_status 50-fold)"
  printf '=== ligne « could not be staged »: %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'could not be staged')"
  printf '=== src/shared.txt sur HEAD      : %s\n' \
    "$(git -C "$PROJECT_DIR" show HEAD:src/shared.txt 2>&1)"
  printf '=== src/ok.txt sur HEAD          : %s\n' \
    "$(git -C "$PROJECT_DIR" show HEAD:src/ok.txt 2>&1)"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}
