#!/usr/bin/env bats
#
# Ticket [70] — vérification sur un run et un drain réels, après correctif.
#
# `passe-07-09/q1` et `q3` ont mesuré le défaut en trois sens, chaque fois sur une
# itération **verte** : la session écrit une ref forensique, la session efface
# celle d'une tentative réellement jugée, la session écrit le reçu d'audit d'un
# ticket du puits. Les trois sont maintenant dans `test/forensic.bats`, avec des
# faux `claude` qui écrivent un fichier et rien d'autre.
#
# L'écart que la leçon 3 du CLAUDE.md demande de sonder est celui-là : une session
# qui écrit **vraiment**, qui **commite**, un run qui va au bout de sa frontière et
# ferme sa feature, et **le drain qui vient après** — c'est-à-dire les deux
# moitiés du correctif dans un seul scénario, ce que la suite mesure séparément.
#
# Ce qui est demandé ici et que la suite ne demande pas :
#
#   V1  la moitié (1) et la moitié (3) bout à bout. Une itération verte dont la
#       session commite du vrai travail *et* forge `refs/heads/failed/20-decision`
#       : le run doit la nommer, la feature doit quand même se fermer, et le drain
#       qui suit doit montrer `arbitrate` **avec** la réserve — la contrefaçon
#       survit, ce qui est le prix écrit, et le dossier ne la présente plus nue.
#   V2  le témoin appairé qui compte le plus : un run **réellement rouge**, qui
#       écrit une vraie ref et un vrai reçu, suivi d'un drain. Zéro accusation, et
#       la réserve quand même — elle ne dépend pas d'une dérive.
#   V3  le reçu, avec une session qui commite : le run le nomme, le ticket résout,
#       et le travail de l'itération est bien sur la branche.
#
# Instrument, pas test : chaque cas finit par un `set -e; false` volontaire, et ce
# qu'on lit est ce qu'il imprime avant. `test/run.sh` sans argument ne le ramasse
# pas.
#
#     bash test/run.sh .scratch/ralph-pack/sondes/ticket-70/verification.bats

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

verif__sink_ticket() {
  {
    printf '# 20-decision — pour le drain\n\n'
    printf '**What to build:** Something a human has to arbitrate.\n\n'
    printf '**Status:** ready-for-human\n\n'
    printf '**Escalation:** decision\n\n'
    printf '**Write-surface:** `src/one.txt`\n\n'
    printf '**Blocked by:** None\n'
  } >"$TRACKER_DIR/20-decision.md"
  harness__commit "sonde: 20-decision"
}

verif__report() {
  printf '=== rc du run : %s\n' "$1"
  printf '=== 01-alpha : %s\n' "$(ticket_status 01-alpha)"
  printf '=== lignes forensic-drift au journal : %s\n' \
    "$(grep -c 'forensic-drift' "$FEATURE_DIR/run.log" || true)"
  printf '=== ce que le journal en dit :\n'
  grep 'forensic-drift' "$FEATURE_DIR/run.log" | sed 's/^/    /' || printf '    (rien)\n'
  printf '=== ce que le reçu de l itération en dit : %s ligne(s)\n' \
    "$(grep -c 'the record the human sink sends' \
      "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE/01-alpha.md" 2>/dev/null || echo 0)"
  printf '=== refs après le run : %s\n' \
    "$(git -C "$PROJECT_DIR" for-each-ref --format='%(refname)' refs/heads/failed/ |
      tr '\n' ' ')"
  printf '=== reçus après le run : %s\n' \
    "$(ls "$PROJECT_DIR/receipts/$RALPH_TEST_FEATURE/" 2>/dev/null | tr '\n' ' ')"
}

verif__drain() {
  run bash -c 'printf "n\nq\n" | bash "$0"' "$PACK_DIR/human-loop.sh"
  printf '=== rc du drain : %s\n' "$status"
  printf '=== ce que le dossier montre :\n'
  printf '%s\n' "$output" |
    grep -E 'desk:|branch |receipt |journal |A branch and a receipt|sessions that run|working tree, and a|not the worktree|when one of them|moved with no run|this drain included' |
    sed 's/^/    /'
}

@test "V1 la session commite du vrai travail ET forge la ref, puis un humain draine" {
  verif__sink_ticket
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for t in $surface; do
  mkdir -p "$(dirname "$t")"
  printf 'du vrai travail, sur plusieurs lignes\n' >"$t"
  for i in 1 2 3 4 5 6 7 8 9 10; do printf 'ligne %s\n' "$i" >>"$t"; done
done
# Une session qui commite pour de bon, dans son worktree.
git add -A >/dev/null 2>&1
git -c user.name=sonde -c user.email=sonde@example.com \
  commit -q -m 'la session commite' >/dev/null 2>&1
# Et qui écrit la ref forensique d'un ticket du puits : `refs/heads/*` vit dans le
# répertoire git COMMUN, qu'un worktree partage.
commit="$(git rev-parse HEAD)"
git update-ref refs/heads/failed/20-decision "$commit" 2>/dev/null
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.04}'
FAKE

  run_loop
  verif__report "$status"
  printf '=== le travail est-il sur la branche ? : %s\n' \
    "$(git -C "$PROJECT_DIR" log --oneline -1 || true)"
  verif__drain

  set -e
  false
}

@test "V2 un run REELLEMENT rouge, une vraie ref, un vrai reçu, puis un drain" {
  verif__sink_ticket
  use_tickets 01-alpha
  set_config RETRY_N 1
  set_config STERILE_K 6
  stub_exit tests 1

  run_loop
  verif__report "$status"
  verif__drain

  set -e
  false
}

@test "V3 la session commite ET forge le reçu d audit du ticket du puits" {
  verif__sink_ticket
  use_tickets 01-alpha

  script_claude <<'FAKE'
#!/usr/bin/env bash
prompt="$(cat)"
main="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
feature="$(basename "$(ls -d "$main"/.scratch/*/ | head -1)")"
surface="$(printf '%s' "$prompt" |
  sed -n 's/^\*\*Write-surface:\*\* //p' | head -1 | tr -d '`\r' | tr ',' ' ')"
for t in $surface; do mkdir -p "$(dirname "$t")" && printf 'du vrai travail\n' >"$t"; done
git add -A >/dev/null 2>&1
git -c user.name=sonde -c user.email=sonde@example.com \
  commit -q -m 'la session commite' >/dev/null 2>&1
mkdir -p "$main/receipts/$feature"
cat >"$main/receipts/$feature/20-decision.md" <<'DOC'
# Receipt — 20-decision

**Verdicts:** tests=green typecheck=green scope=green lang=green

## Findings

Nothing. Every lens passed; the ticket was escalated for a scheduling reason.
DOC
echo '{"type":"result","subtype":"success","is_error":false,"num_turns":3,"total_cost_usd":0.04}'
FAKE

  run_loop
  verif__report "$status"
  printf '=== le travail est-il sur la branche ? : %s\n' \
    "$(git -C "$PROJECT_DIR" log --oneline -1 || true)"
  verif__drain

  set -e
  false
}
