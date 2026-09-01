#!/usr/bin/env bats
#
# Passe transversale du 01/09 — Q2.
#
# `gate_tree_snapshot` documente son refus en toutes lettres (l. 2131-2136) :
# « No `|| true`, unlike the branch below … `set -e` takes the function down, the
# caller gets no tree, and that is the refusal it needs — a tracker guard handed
# an empty tree instead would read it as "the session changed nothing" ».
#
# Deux faits mesurés hors du pack avant d'écrire cette sonde :
#   1. `git add -A` échoue **WHOLE** sur un fichier illisible et laisse l'index
#      VIDE — `write-tree` rend 4b825dc642cb6eb9a060e54bf8d69288fbee4904, l'arbre
#      vide, et pas un arbre partiel ;
#   2. `x="$(f)" || x=""` **suspend errexit** sur toute l'extension dynamique de
#      `f` (mesuré : un `false` au milieu de `f` ne la tue pas).
#
# Or les onze appelants de `gate_tree_snapshot` sont tous de cette forme. La
# question de cette sonde : le refus documenté existe-t-il en vol, et si non, que
# fait un run réel.
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
    printf '**What to build:** A fixture for the frontier.\n\n'
    while [ "$#" -ge 2 ]; do
      printf '**%s:** %s\n\n' "$1" "$2"
      shift 2
    done
    printf -- '- [ ] Something a session delivers.\n'
  } >"$file"
  harness__commit "sonde: $id"
}

# ── Q2a — au module : que rend la fonction, et avec quel code ─────────────────

@test "Q2a gate_tree_snapshot sur un arbre portant un fichier illisible" {
  pack_run 'printf hello >"$PWD/readable.txt"
    chmod 000 CONTEXT.md
    tree="$(gate_tree_snapshot)" || tree="REFUSED"
    printf "tree=%s rc=%s\n" "$tree" "$?"
    printf "empty-tree=%s\n" "$(git hash-object -t tree /dev/null)"
    printf "entries=%s\n" "$(git ls-tree -r "$tree" 2>/dev/null | wc -l | tr -d " ")"
    printf "top-level=%s\n" "$(git ls-tree --name-only "$tree" 2>/dev/null | tr "\n" " ")"
    printf "HEAD-entries=%s\n" "$(git ls-tree -r --name-only HEAD | wc -l | tr -d " ")"
    printf "HEAD-top-level=%s\n" "$(git ls-tree --name-only HEAD | tr "\n" " ")"
    chmod 644 CONTEXT.md'
  printf '=== rc pack_run : %s\n' "$status"
  printf '%s\n' "$output"

  set -e
  false
}

@test "Q2b témoin appairé : le même appel, tous les fichiers lisibles" {
  pack_run 'printf hello >"$PWD/readable.txt"
    tree="$(gate_tree_snapshot)" || tree="REFUSED"
    printf "tree=%s\n" "$tree"
    printf "empty-tree=%s\n" "$(git hash-object -t tree /dev/null)"
    printf "entries=%s\n" "$(git ls-tree -r "$tree" 2>/dev/null | wc -l | tr -d " ")"'
  printf '=== rc pack_run : %s\n' "$status"
  printf '%s\n' "$output"

  set -e
  false
}

# ── Q2f — la branche à pathspec, celle dont le commentaire décrit le refus ────
#
# « No `|| true`, unlike the branch below … `set -e` takes the function down, the
# caller gets no tree, and that is the refusal it needs — a tracker guard handed
# an empty tree instead would read it as "the session changed nothing" ».
# La question est posée à la lettre : un pathspec qui ne matche rien.

@test "Q2f gate_tree_snapshot avec un pathspec qui ne matche rien" {
  pack_run 'tree="$(gate_tree_snapshot "no/such/path")" || tree="REFUSED"
    printf "tree=%s\n" "$tree"
    printf "empty-tree=%s\n" "$(git hash-object -t tree /dev/null)"'
  printf '=== rc pack_run : %s\n' "$status"
  printf '%s\n' "$output"

  set -e
  false
}

# ── Q2g — le garde du tracker, avec un ticket illisible ───────────────────────

@test "Q2g failures_tracker_tree quand un fichier de ticket est illisible" {
  mk_ticket 40-one Status ready-for-agent 'Write-surface' '`src/one.txt`'
  mk_ticket 41-two Status ready-for-agent 'Write-surface' '`src/two.txt`'

  pack_run 'before="$(failures_tracker_tree)" || before="REFUSED"
    printf "before=%s entries=%s\n" "$before" \
      "$(git ls-tree -r "$before" 2>/dev/null | wc -l | tr -d " ")"
    chmod 000 .scratch/demo/issues/41-two.md
    after="$(failures_tracker_tree)" || after="REFUSED"
    printf "after=%s entries=%s\n" "$after" \
      "$(git ls-tree -r "$after" 2>/dev/null | wc -l | tr -d " ")"
    printf "empty-tree=%s\n" "$(git hash-object -t tree /dev/null)"
    printf "diff-tree-name-status:\n%s\n" \
      "$(git diff-tree -r --name-status "$before" "$after" 2>/dev/null)"
    chmod 644 .scratch/demo/issues/41-two.md'
  printf '=== rc pack_run : %s\n' "$status"
  printf '%s\n' "$output"

  set -e
  false
}

# ── Q2c — le run réel : une session laisse un fichier illisible ───────────────
#
# Rien d'hostile n'est requis pour produire ça : un outil qui écrit un fichier en
# mode 000, un `chmod` dans un script de build, un montage qui rend un chemin
# illisible. Le fichier rendu illisible ici est un fichier **committé** que la
# session ne prétend pas livrer, et qui n'est pas dans sa write-surface.

@test "Q2c un run réel dont la session laisse un fichier illisible dans l'arbre" {
  mk_ticket 30-narrow Status ready-for-agent 'Write-surface' '`src/one.txt`' \
    'Blocked by' None

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
mkdir -p src
printf 'delivered by the session\n' >src/one.txt
chmod 000 CONTEXT.md
exit 0
SCRIPT

  local head_before
  head_before="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
  run_loop
  chmod 644 "$PROJECT_DIR/CONTEXT.md" 2>/dev/null || true

  printf '=== rc du run                : %s\n' "$status"
  printf '=== Status 30-narrow         : %s\n' "$(ticket_status 30-narrow)"
  printf '=== Failures 30-narrow       : %s\n' "$(ticket_field 30-narrow Failures)"
  printf '=== Escalation 30-narrow     : %s\n' "$(ticket_field 30-narrow Escalation)"
  printf '=== HEAD a bougé ?           : %s\n' \
    "$([ "$head_before" = "$(git -C "$PROJECT_DIR" rev-parse HEAD)" ] && echo non || echo OUI)"
  printf '=== src/one.txt sur HEAD ?   : %s\n' \
    "$(git -C "$PROJECT_DIR" ls-tree -r --name-only HEAD | grep -c '^src/one.txt$')"
  printf '=== une ligne nomme CONTEXT ?: %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'CONTEXT')"
  printf '=== une ligne dit illisible ?: %s\n' \
    "$(printf '%s\n' "$output" | grep -ci 'unreadable\|permission')"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}

@test "Q2d témoin appairé : la même session sans le chmod" {
  mk_ticket 30-narrow Status ready-for-agent 'Write-surface' '`src/one.txt`' \
    'Blocked by' None

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
mkdir -p src
printf 'delivered by the session\n' >src/one.txt
exit 0
SCRIPT

  local head_before
  head_before="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
  run_loop

  printf '=== rc du run                : %s\n' "$status"
  printf '=== Status 30-narrow         : %s\n' "$(ticket_status 30-narrow)"
  printf '=== HEAD a bougé ?           : %s\n' \
    "$([ "$head_before" = "$(git -C "$PROJECT_DIR" rev-parse HEAD)" ] && echo non || echo OUI)"
  printf '=== src/one.txt sur HEAD ?   : %s\n' \
    "$(git -C "$PROJECT_DIR" ls-tree -r --name-only HEAD | grep -c '^src/one.txt$')"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}

# ── Q2e — la write-surface large, qui est l'autre sortie ──────────────────────
#
# Si le scope-guard rougit en Q2c parce que tout l'arbre a l'air supprimé, la
# question suivante est celle d'un ticket dont la surface couvre ce que le faux
# arbre prétend supprimé. Ce que la question 5 demande : y a-t-il un chemin où le
# ticket sort **resolved** avec zéro commit — le faux livré de [35] par une autre
# porte.

@test "Q2e le même défaut sous une write-surface qui couvre tout" {
  mk_ticket 31-wide Status ready-for-agent \
    'Write-surface' '`src/one.txt`, `CONTEXT.md`, `.scratch/**`, `.claude/**`, `*`' \
    'Blocked by' None

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
mkdir -p src
printf 'delivered by the session\n' >src/one.txt
chmod 000 CONTEXT.md
exit 0
SCRIPT

  local head_before
  head_before="$(git -C "$PROJECT_DIR" rev-parse HEAD)"
  run_loop
  chmod 644 "$PROJECT_DIR/CONTEXT.md" 2>/dev/null || true

  printf '=== rc du run                : %s\n' "$status"
  printf '=== Status 31-wide           : %s\n' "$(ticket_status 31-wide)"
  printf '=== HEAD a bougé ?           : %s\n' \
    "$([ "$head_before" = "$(git -C "$PROJECT_DIR" rev-parse HEAD)" ] && echo non || echo OUI)"
  printf '=== src/one.txt sur HEAD ?   : %s\n' \
    "$(git -C "$PROJECT_DIR" ls-tree -r --name-only HEAD | grep -c '^src/one.txt$')"
  printf '=== fichiers sur HEAD        : %s\n' \
    "$(git -C "$PROJECT_DIR" ls-tree -r --name-only HEAD | wc -l | tr -d ' ')"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}
