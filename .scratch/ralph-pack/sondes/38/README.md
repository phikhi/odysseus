# Sondes de [38] — pourquoi le faux `claude` mourait à ~1 s

Des **instruments**, pas des tests. Chacune se termine par un `false` volontaire : elle
rougit toujours, et ce qu'on lit est ce qu'elle imprime avant. Elles ne sont pas dans
`test/` et `test/run.sh` sans argument ne les ramasse pas — elles ne doivent jamais
compter dans le verdict des deux gates.

Les trois demandent que la mutation du reaper soit appliquée **à la main** avant de
tourner, sinon elles mesurent le pack sain :

    perl -Mstrict -0pi -e 's/  monitor__reaper "\$pid" "\$grace" &\n  MONITOR_REAPER=\$!\n//' \
      .claude/lib/monitor.sh
    bash test/run.sh .scratch/ralph-pack/sondes/38/a-le-sort-du-faux.bats
    git checkout .claude/lib/monitor.sh    # ← ne pas oublier

**Ne pas oublier ce `git checkout`.** Une mutation laissée dans l'arbre est la garantie
de [23] retirée dans un dépôt qui a l'air propre partout sauf dans `git diff`. C'est
arrivé en livrant ce ticket, en tuant `mutate.sh` en vol.

| Sonde | Ce qu'elle demande | Ce qu'elle a rendu |
|---|---|---|
| `a-le-sort-du-faux.bats` | Qui tue le faux, avec battement de cœur et journal de tous les signaux attrapables | 3 passes sur 8 rendent `heartbeats: 0` et un `fake.log` **vide** : le faux n'a jamais démarré. Les 5 autres vont au bout (34 s) et écrivent leur marqueur |
| `b-ou-le-shim-sest-arrete.bats` | Jusqu'où le shim est allé, en listant les artefacts qu'il écrit dans l'ordre (`argv`, `env`, `stdin`) | Dans le cas court : `(no slot 1)`. Le répertoire de slot que le shim réserve **en premier** n'existe pas — mort avant tout |
| `c-la-prediction.bats` | La prédiction de la cause : un stall de 3 au lieu de 1 doit supprimer le cas court | **8/8** scénario entré, 8/8 arrivé au bout. Contre 3/8 manqués à 1 |

La cause, et la mesure qui la tient hors du pack :

    $ bash -c 'hit=0; n=0; while [ $n -lt 120 ]; do idle=$SECONDS; sleep 0.3;
        [ $((SECONDS-idle)) -ge 1 ] && hit=$((hit+1)); n=$((n+1)); done; echo $hit/120'
    38/120

`SESSION_STALL_TIMEOUT 1` n'est pas un délai d'une seconde : `idle` est `$SECONDS` pris au
spawn, `SECONDS` est un entier, donc le premier tick qui franchit une frontière de seconde
suffit. Le TERM tombe alors sur le **shim**, qui n'ignore rien — le `trap '' TERM`
appartient au scénario qu'il n'a pas encore `exec`é — et le KILL testé n'a rien à faire.

Le dossier complet est dans `../../issues/38-une-entree-de-mutation-qui-ment-un-tour-sur-quatre.md`.
