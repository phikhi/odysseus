#!/usr/bin/env bats
#
# Passe transversale du 14/09 — Q1.
#
# `init_claude_block` écrit, dans le `CLAUDE.md` du projet cible, la seule phrase
# qui dise à une session de livraison ce qu'aucune write-surface ne peut couvrir.
# `loop_session_prompt` ne nomme aucun chemin scellé : dans un projet installé,
# ce bloc **est** tout ce qu'une session apprend de la liste.
#
# La liste est retapée. `playthrough.sh` fait le même geste trois fichiers plus
# loin et la **dérive** (`$(gate_sealed_paths)` dans son heredoc de prompt), donc
# le précédent existe et il est dans le pack.
#
# Q1a compte les deux côtés. Q1b demande la même chose au paragraphe « The
# tracker », qui décrit un tracker markdown alors que l'installeur vient de lire
# `TRACKER_BACKEND` et d'imprimer la bonne phrase à la console.
#
# Instrument, pas test : chaque cas finit par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

INIT_SH=""

setup() {
  harness_setup
  INIT_SH="$RALPH_PACK_ROOT/init.sh"
}

teardown() {
  harness_teardown
}

# Un projet la minute avant que le pack arrive.
q1__target() {
  local dest="$RALPH_TEST_DIR/$1"
  mkdir -p "$dest"
  git -c init.defaultBranch=main init -q "$dest"
  git -C "$dest" config user.name "ralph probe"
  git -C "$dest" config user.email "ralph@probe.invalid"
  git -C "$dest" config commit.gpgsign false
  printf 'a project that existed first\n' >"$dest/README.md"
  git -C "$dest" add -A
  git -C "$dest" commit -q -m "fixture"
  printf '%s\n' "$dest"
}

q1__install() {
  local dest="$1"
  shift
  env -u RALPH_CONFIG \
    FEATURE=demo TEST_CMD="bash run-tests.sh" TYPECHECK_CMD=none \
    LANG_ARTIFACT=en LANG_CHECK=on SCHEDULER=none VISUAL_REAL_ASSETS=1 \
    RUN_CMD="echo run" VISUAL_CMD="echo visual" WORKTREE_PROVISION="" \
    TMPDIR="$TMPDIR" "$@" \
    bash "$INIT_SH" --yes --no-sweep --target "$dest" --from "$RALPH_PACK_ROOT"
}

@test "Q1a ce que le pack scelle, et ce que la prose déposée en nomme" {
  local dest
  dest="$(q1__target sealed)"
  q1__install "$dest" >/dev/null 2>&1

  printf '=== gate_sealed_paths, demandé au pack livré :\n'
  local sealed
  sealed="$(env -u RALPH_CONFIG RALPH_PROJECT_ROOT="$dest" bash -c '
    . "$1/lib/state.sh"; . "$1/lib/gate.sh"; gate_sealed_paths' _ "$RALPH_PACK_ROOT/.claude")"
  printf '%s\n' "$sealed" | LC_ALL=C sort | sed 's/^/    /'
  printf '    (%s entrées)\n' "$(printf '%s\n' "$sealed" | grep -c .)"

  printf '=== ce que le bloc de init.sh nomme dans le CLAUDE.md du projet :\n'
  local named
  named="$(sed -n '/ralph pack: start/,/ralph pack: end/p' "$dest/CLAUDE.md" |
    grep -o '`[^`]*`' | tr -d '`' | LC_ALL=C sort -u)"
  printf '%s\n' "$named" | sed 's/^/    /'

  printf '=== les scellés que la prose ne nomme pas :\n'
  local path
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    case "
$named
" in
      *"
$path
"*) ;;
      *) printf '    MANQUE  %s\n' "$path" ;;
    esac
  done <<SEALED
$sealed
SEALED

  printf '=== et le précédent, dans le pack, trois fichiers plus loin :\n'
  grep -n 'gate_sealed_paths' "$RALPH_PACK_ROOT/.claude/lib/playthrough.sh" | sed 's/^/    /'
  grep -n 'sealed' "$RALPH_PACK_ROOT/.claude/loop.sh" |
    grep -c 'loop_session_prompt' | sed 's/^/    phrases du prompt de session qui nomment un scellé : /'

  set -e
  false
}

@test "Q1b le paragraphe « The tracker » sur un backend distant" {
  local dest
  dest="$(q1__target remote)"

  printf '=== ce que l installeur dit à la console quand TRACKER_BACKEND=github :\n'
  q1__install "$dest" TRACKER_BACKEND=github TRACKER_REPO=acme/x \
    TRACKER_TOKEN_CMD='echo t' TRACKER_USER=bot 2>&1 |
    grep -i 'TRACKER_BACKEND=github' | cut -c1-160 | sed 's/^/    /'

  printf '=== ce qu il écrit dans le fichier que chaque session lit :\n'
  sed -n '/ralph pack: start/,/ralph pack: end/p' "$dest/CLAUDE.md" |
    sed -n '3,9p' | sed 's/^/    /'

  printf '=== et ce qu il provisionne sur disque :\n'
  find "$dest/.scratch" | sed "s|$dest/||" | sed 's/^/    /'

  printf '=== la signature du bloc, qui ne peut pas varier :\n'
  grep -n 'init_claude_block() {' -A 2 "$INIT_SH" | sed 's/^/    /'
  grep -n 'init_claude_block "' "$INIT_SH" | sed 's/^/    /'

  set -e
  false
}
