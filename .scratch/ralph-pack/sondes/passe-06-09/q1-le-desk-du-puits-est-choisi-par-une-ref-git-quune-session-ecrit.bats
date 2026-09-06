#!/usr/bin/env bats
#
# Passe transversale du 06/09 — Q1.
#
# `router_desk` distingue les trois arrivées de `decision` par les preuves :
# l'existence de `failed/<id>` et la valeur de `Failures:`. [55] a pinné
# `Escalation:` ; [61] a pinné `Failures:` après avoir mesuré qu'une session
# routée choisissait le desk de la session suivante sur le même ticket. La ref,
# elle, est lue telle quelle, et le commentaire de `router_desk` dit pourquoi :
#
#   « The `failed/<id>` ref is still read as it stands, and that is the boundary:
#     pinning a git ref is a different mechanism, a routed session that writes one
#     has left a branch behind it in the repository, and `router_tree_note` is
#     what looks at what a session left outside `issues/`. »
#
# Or `router__tree_dirt` est `git diff --name-only HEAD` + `git ls-files --others` :
# il mesure l'arbre de travail. Une ref n'est pas un chemin de l'arbre de travail.
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

# Un ticket `decision` sans branche et sans retries : le desk `admit`, c'est-à-dire
# « aucun run n'a jamais jugé ceci ».
sonde__ticket() {
  local file="$TRACKER_DIR/20-decision.md"
  {
    printf '# 20-decision — arrivé par la quarantaine\n\n'
    printf '**What to build:** Something a human has to arbitrate.\n\n'
    printf '**Status:** ready-for-human\n\n'
    printf '**Escalation:** decision\n\n'
    printf '**Write-surface:** `src/one.txt`\n\n'
    printf '**Blocked by:** None\n'
  } >"$file"
  harness__commit "sonde: 20-decision"
}

sonde__state() {
  printf '=== %s\n' "$1"
  pack_run 'router_desk 20-decision'
  printf '    desk                     : %s\n' "$output"
  pack_run 'router_has_branch 20-decision && echo oui || echo non'
  printf '    failed/20-decision       : %s\n' "$output"
  printf '    refs présentes           : %s\n' \
    "$(git for-each-ref --format='%(refname)' refs/heads 2>/dev/null | tr '\n' ' ')"
}

@test "Q1a une session routée écrit refs/heads/failed/<id> : le desk du drain suivant" {
  sonde__ticket
  sonde__state 'avant la session'

  # La session routée : elle tourne dans l'arbre principal, sans worktree, sans
  # scope-guard, sans gate, sans rollback. Elle écrit une ref et rien d'autre.
  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
git -C "$root" update-ref refs/heads/failed/20-decision HEAD
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  # Drain n°1 : on ouvre une session sur le ticket, puis on passe au suivant.
  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n1 rc=%s\n' "$status"
  printf '    ce que le drain a dit de ce que la session a laissé :\n'
  printf '%s\n' "$output" | grep -n 'left .* path(s)\|already uncommitted\|failed/' |
    sed 's/^/      /' || printf '      (rien)\n'

  sonde__state 'après la session'

  # Drain n°2 : le dossier que lit l'humain.
  run bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n2 — dossier :\n'
  printf '%s\n' "$output" | sed -n '/── 20-decision ──/,/The question/p' | sed 's/^/    /'
  printf '=== drain n2 — ce qu il y a à lire :\n'
  printf '%s\n' "$output" | sed -n '/What there is to read/,/journal/p' | sed 's/^/    /'

  set -e
  false
}

@test "Q1b témoin appairé : la même session, sans la ref" {
  sonde__ticket
  script_claude <<'FAKE'
#!/usr/bin/env bash
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n1 rc=%s\n' "$status"
  sonde__state 'après une session qui n écrit rien'

  run bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n2 — dossier :\n'
  printf '%s\n' "$output" | sed -n '/── 20-decision ──/,/The question/p' | sed 's/^/    /'
  printf '=== drain n2 — ce qu il y a à lire :\n'
  printf '%s\n' "$output" | sed -n '/What there is to read/,/journal/p' | sed 's/^/    /'

  set -e
  false
}

@test "Q1c l autre sens : une session routée efface la ref d une tentative réellement jugée" {
  sonde__ticket
  # Une branche forensique comme un run en écrit une.
  git update-ref refs/heads/failed/20-decision HEAD
  sonde__state 'avant la session — une vraie tentative jugée'

  script_claude <<'FAKE'
#!/usr/bin/env bash
root="$(cat "$RALPH_SHIM_STATE/project-dir")"
git -C "$root" update-ref -d refs/heads/failed/20-decision
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":1,"total_cost_usd":0.01}'
FAKE

  run bash -c 'printf "o\nn\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n1 rc=%s\n' "$status"
  printf '    ce que le drain a dit de la suppression :\n'
  printf '%s\n' "$output" | grep -n 'left .* path(s)\|already uncommitted\|failed/' |
    sed 's/^/      /' || printf '      (rien)\n'

  sonde__state 'après la session'

  run bash -c 'printf "n\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== drain n2 — dossier :\n'
  printf '%s\n' "$output" | sed -n '/── 20-decision ──/,/The question/p' | sed 's/^/    /'
  printf '=== drain n2 — ce qu il y a à lire :\n'
  printf '%s\n' "$output" | sed -n '/What there is to read/,/journal/p' | sed 's/^/    /'

  set -e
  false
}
