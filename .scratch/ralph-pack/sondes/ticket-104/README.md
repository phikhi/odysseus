# Sondes de [104] (06/10/2026)

Des **instruments**, pas des tests : chaque cas finit par un `set -e; false`
volontaire. Aucun ne compte dans le verdict des deux gates.

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-104/g1-qui-tient-encore.bats
    bash test/run.sh .scratch/ralph-pack/sondes/ticket-102/h4-le-hook-configure.bats -f 'C2b|C3|C4'

## h4 rejouée sur la branche (avant la correction du lexeur)

Les 85 appels `git` que le lexeur de [91] voyait passaient déjà par `proc_git` :

    C2b  .git/config, MAX_PARALLEL=2, sœur tenue    14 exécutions, 0 fd ouvert, 0 ligne forgée
    C3   ~/.gitconfig, hook configuré, MP=1          160 exécutions, 0 fd ouvert, 0 ligne forgée
    C4   ~/.gitconfig, core.fsmonitor, MP=1          978 exécutions, **10 fois fds 3 et 5**,
                                                     **4 lignes forgées** dans le reçu de 01

## g1 — qui lance encore git en tenant 3 et 5

Le programme note, à chaque exécution, son propre résultat de forgeur et la chaîne
de ses ancêtres (`ps -o ppid=,command=`). Les dix exécutions qui tenaient 3 et 5
avaient toutes pour parent

    git -c core.quotePath=false diff-tree -r --name-status <base> <now>

lancé par un shell de `loop.sh` — un `git` **nu** que le recensement ne voyait pas,
parce qu'il est dans le corps d'un heredoc non cité : `gate_restore_tree`,
`done <<CHANGED` puis `$(git … diff-tree …)`. Le lexeur de [91] jetait le corps des
heredocs avec leur prose ; un heredoc non cité **exécute** ses `$( … )`. Cinq sites
de cette forme (`failures_make_durable`, `gate_restore_tree`, `lang__expected`,
`lang_check`, `lenses__patch`).

Après la correction du lexeur et la conversion des cinq sites, g1 rejouée :
**958 exécutions, aucun descripteur ouvert**.

## Mesures ponctuelles (hors harnais, scratchpad)

- Coût de `proc_git` (sous-shell + `exec` de 253 fermetures, liste précalculée) :
  +0,3 à +0,7 ms sur un `git rev-parse HEAD` de ~12 ms (300 appels, nu / en
  substitution).
- Un hook configuré et un `core.fsmonitor` global, le shell appelant tenant 5 et 9 :
  sous `git` nu les deux trouvent 5 et 9 ouverts ; sous `proc_git`, rien. Statut,
  stdin, `GIT_INDEX_FILE=… f` (exporté pendant l'appel, absent après) et le jeton de
  [102] passent.
- `reference-transaction` configuré qui sort 1 sur `prepared` : `update-ref` rend
  128 (« update aborted by the reference-transaction hook ») ; un `.lock` posé à
  côté de la ref : `update-ref` rend 128 aussi (« cannot lock ref »).
- `printf -v X '%s>&- ' {3..255}` marche sous `/bin/bash` 3.2.57 (1667 octets).
