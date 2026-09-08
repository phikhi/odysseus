# Sondes de vérification du ticket [70]

Des **instruments**, pas des tests : `verification.bats` finit chaque cas par un
`set -e; false` volontaire, il rougit toujours, et ce qu'on lit est ce qu'il
imprime avant. Il n'est pas dans `test/` et `test/run.sh` sans argument ne le
ramasse pas.

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-70/verification.bats
    bash test/run.sh -f V2 .scratch/ralph-pack/sondes/ticket-70/verification.bats

Ce qu'il demande, et que `test/forensic.bats` ne demande pas : une session qui
écrit **vraiment** et qui **commite**, un run qui va au bout de sa frontière, et
**le drain qui vient après** — les deux moitiés du correctif dans un seul
scénario. La suite mesure les deux séparément.

| Cas | Ce qu'il demande | Verdict, mesuré le 08/09/2026 |
|---|---|---|
| V1 | une itération **verte** qui commite dix lignes de vrai travail *et* écrit `refs/heads/failed/20-decision` | ticket `resolved`, run **rc=0**, travail sur la branche (`iteration delivered (gate green)`), **1** ligne `forensic-drift` au journal nommant la ref, **1** aveu sur le reçu de l'itération. Le drain suivant : desk **`arbitrate`** — la contrefaçon survit, c'est le prix écrit — mais le dossier la montre **avec la réserve** |
| V2 | un run **réellement rouge** : vraie ref `failed/01-alpha` écrite par `failures_preserve_attempt`, vrai reçu écrit par `receipt_emit`, puis un drain | **0** ligne `forensic-drift`, **0** aveu sur le reçu — et la réserve imprimée quand même, elle ne dépend d'aucune dérive |
| V3 | une itération **verte** qui commite *et* forge `receipts/<feature>/20-decision.md` dans l'arbre principal | ticket `resolved`, travail sur la branche, **1** ligne `forensic-drift` nommant le chemin, **1** aveu sur le reçu. Le drain montre le reçu forgé sous une ligne `branch there is none`, **avec** la réserve |

## Pièges rencontrés en les écrivant

**`$FEATURE` n'est pas dans l'environnement d'une session.** Un faux `claude` qui
écrit `"$main/receipts/$FEATURE/…"` écrit dans `receipts/` tout court, hors de la
zone témoin, et la sonde mesure alors un silence qu'elle a fabriqué elle-même.
Le nom se retrouve par `basename "$(ls -d "$main"/.scratch/*/ | head -1)"`, comme
dans `passe-07-09/q3`.

**Un `sed -n '/What there is to read/,/^$/p'` ne rend rien du dossier** : la
section commence par une ligne vide, donc la plage se ferme immédiatement. Les
lignes se prennent au `grep`.

**Le fake `claude` doit commiter avec `-c user.name` / `-c user.email`** : le
worktree d'itération hérite de la config du dépôt de test, et un commit sans
identité fait échouer la session pour une raison qui n'est pas celle qu'on sonde.

**Un `mutate.sh` a trouvé ce qu'une relecture n'avait pas vu.** L'entrée « the
receipt this iteration is about to write is never registered » est sortie
**VACUOUS** : le témoin appairé visé était un run à **un** ticket, qui écrit son
reçu sur la **dernière** itération qu'il fera — donc aucune comparaison ne tourne
après cette écriture et le registre n'était jamais exercé. Le test a été réécrit à
deux tickets (`test/forensic.bats`, « a receipt this run emitted is not drift for
the iteration that comes after it »).
