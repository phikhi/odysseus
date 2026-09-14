#!/usr/bin/env bats
#
# Passe transversale du 14/09 — Q2.
#
# `test/layering.bats` porte quatre règles sur la **source livrée** — celles
# qu'aucun test fonctionnel ne peut voir. Les quatre ont la même zone :
#
#     for f in "$dir"/lib/*.sh "$dir"/*.sh   # $dir = .claude
#
# Le commentaire de `layering_privates` dit pourquoi le glob est `*.sh` et pas
# `loop.sh` : *« the pack has two entry points since [16], and an entry point
# outside this glob is one where a lib's `__` internals are reachable with
# nothing to say so »*. [19] en a livré un **troisième**, et il est à la racine du
# dépôt, hors de `.claude/**`.
#
# Q2a montre la zone et l'absence. Q2b plante la faute de [61] dans le heredoc de
# prose de `init_claude_block` et mesure les deux choses qui comptent : la règle
# l'attrape quand on l'y pointe, et l'effet sur un vrai projet est un `CLAUDE.md`
# troué déposé par un installeur qui sort en 0.
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

# La règle de layering.bats, extraite telle quelle de la source livrée : rien
# n'est recopié ici, sinon la sonde mesurerait sa propre copie.
q2__rule() {
  local out="$RALPH_TEST_DIR/rule.bash"
  awk '/^layering_heredoc_prose\(\) \{/,/^\}/' "$RALPH_PACK_ROOT/test/layering.bats" >"$out"
  printf 'layering_heredoc_prose "$1"\n' >>"$out"
  printf '%s\n' "$out"
}

@test "Q2a la zone des quatre règles de source, et les points d entrée du pack" {
  printf '=== la zone, lue dans test/layering.bats :\n'
  grep -n 'for f in "\$dir"' "$RALPH_PACK_ROOT/test/layering.bats" | sed 's/^/    /'
  printf '=== ce que les quatre règles reçoivent comme $dir :\n'
  grep -n 'run layering_' "$RALPH_PACK_ROOT/test/layering.bats" | sed 's/^/    /'

  printf '=== les points d entrée du pack, et où ils vivent :\n'
  printf '    .claude/loop.sh          dans la zone\n'
  printf '    .claude/human-loop.sh    dans la zone\n'
  if [ -e "$RALPH_PACK_ROOT/.claude/init.sh" ]; then
    printf '    init.sh                  dans la zone\n'
  else
    printf '    init.sh                  HORS de la zone (racine du dépôt)\n'
  fi

  printf '=== les heredocs non cités de init.sh, qui est ce que la règle vise :\n'
  grep -nE "<<[A-Za-z_]" "$RALPH_PACK_ROOT/init.sh" | sed 's/^/    /'

  set -e
  false
}

@test "Q2b la faute de [61] plantée dans init_claude_block" {
  local rule dir dest
  rule="$(q2__rule)"
  dir="$RALPH_TEST_DIR/src"
  mkdir -p "$dir"

  printf '=== témoin : la règle sur le pack livré, et sur init.sh tel quel\n'
  bash "$rule" "$RALPH_PACK_ROOT/.claude" && printf '    .claude          propre (rc=0)\n'
  cp "$RALPH_PACK_ROOT/init.sh" "$dir/init.sh"
  bash "$rule" "$dir" && printf '    init.sh tel quel propre (rc=0) — les backticks y sont échappés à la main\n'

  printf '=== un seul backtick de prose dé-échappé, dans le paragraphe du tracker :\n'
  sed 's|are in \\`docs/agents/\\`\.|are in `docs/agents/`.|' \
    "$RALPH_PACK_ROOT/init.sh" >"$dir/init.sh"
  printf '    la règle, pointée sur ce fichier :\n'
  bash "$rule" "$dir" | sed 's/^/        /' || true

  printf '=== et ce que ça donne sur un vrai projet :\n'
  dest="$RALPH_TEST_DIR/target"
  mkdir -p "$dest"
  git -c init.defaultBranch=main init -q "$dest"
  git -C "$dest" config user.name "ralph probe"
  git -C "$dest" config user.email "ralph@probe.invalid"
  git -C "$dest" config commit.gpgsign false
  printf 'x\n' >"$dest/README.md"
  git -C "$dest" add -A && git -C "$dest" commit -q -m fixture

  env -u RALPH_CONFIG \
    FEATURE=demo TEST_CMD="bash run-tests.sh" TYPECHECK_CMD=none \
    LANG_ARTIFACT=en LANG_CHECK=on SCHEDULER=none VISUAL_REAL_ASSETS=1 \
    RUN_CMD="echo run" VISUAL_CMD="echo visual" WORKTREE_PROVISION="" \
    bash "$dir/init.sh" --yes --no-sweep --target "$dest" --from "$RALPH_PACK_ROOT" \
    >"$RALPH_TEST_DIR/out" 2>&1
  printf '    code de sortie de l installeur : %s\n' "$?"
  printf '    ce qu il a dit :\n'
  grep -i 'agents/\|not found\|is a directory' "$RALPH_TEST_DIR/out" | sed 's/^/        /'
  printf '    ce que le projet a maintenant dans son CLAUDE.md :\n'
  sed -n '/ralph pack: start/,/ralph pack: end/p' "$dest/CLAUDE.md" |
    sed -n '3,9p' | sed 's/^/        /'

  set -e
  false
}
