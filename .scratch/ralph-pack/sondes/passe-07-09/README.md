# Sondes de la passe transversale du 07/09/2026

Des **instruments**, pas des tests. Chacune se termine par un `set -e; false`
volontaire : elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant.
Elles ne sont pas dans `test/` et `test/run.sh` sans argument ne les ramasse pas —
elles ne doivent jamais compter dans le verdict des deux gates.

Les faire tourner, une par une ou par nom :

    bash test/run.sh .scratch/ralph-pack/sondes/passe-07-09/q1-une-session-jugee-ecrit-la-ref-forensique-que-le-drain-lit.bats
    bash test/run.sh -f Q2c .scratch/ralph-pack/sondes/passe-07-09/q2-le-drain-accuse-la-seconde-session-de-ce-que-sa-propre-remise-a-ecrit.bats

Elles pilotent le pack tel qu'il est livré ; aucune n'édite `.claude/` ni `test/`,
et aucune n'a besoin d'une mutation appliquée à la main. La passe qui les a
écrites est dans `../../passe-transversale-07-09.md`.

| Sonde | Ce qu'elle demande | Verdict, mesuré le 07/09/2026 |
|---|---|---|
| `q1` Q1a | une itération **verte** dont la session fait `git update-ref refs/heads/failed/20-decision` | gate vert sur les quatre axes, ticket `resolved`, run **rc=0**, **0** mot d'une ref au run comme au reçu. Le drain suivant : desk **`admit` → `arbitrate`**, dossier « `git log -p failed/20-decision` » |
| `q1` Q1b | témoin appairé : le même run vert, sans la ref | desk **`admit`**, « there is none. nothing ever ran on this ticket » |
| `q1` Q1c | l'autre sens : l'itération verte **efface** une ref écrite par un run précédent | la ref est partie, **0** mot, et le drain affirme « nothing ever ran on this ticket » sur un ticket réellement jugé |
| `q2` Q2c | une session routée met à `resolved` un voisin du puits **sans** `**Escalation:**` | le drain **meurt** dans `router__put_back` (`${2:?}` de `tracker_local_mark_escalated`). **rc = 0** — « the sink is empty: everything in it was drained ». Le voisin reste `resolved`, le ticket du puits reste dedans, `run.log` est **vide** |
| `q2` Q2d | témoin appairé : le même voisin **portant** `**Escalation:** decision` | remis, nommé, `tracker-drift restored` journalisé, rc=3 |
| `q2` Q2b | témoin appairé : deux sessions, aucune n'écrit le voisin | silence, **0** ligne de dérive, rc=3 |
| `q2` Q2a | le même que Q2c, avec un second `o` derrière | le second `o` n'arrive jamais : une seule session ouverte, le drain est déjà mort |
| `q3` Q3a | une itération **verte** dont la session écrit `receipts/<feature>/20-decision.md` dans l'arbre principal | run **rc=0**, **0** mot. Le dossier le présente comme le reçu d'audit, avec **0** réserve, et ajoute « `failed/20-decision` is a ref and survives » |
| `q3` Q3b | témoin appairé : le même run vert, sans le reçu forgé | « receipt none was kept for this ticket » |
| `q4` Q4a | un run AFK tourne, un humain lance un drainage | le drain journalise `20 ambiguous-id … action=drain` **puis** refuse (`rc=1`). Le run finit en accusant : « the run journal does not hold exactly the 3 line(s) this run wrote … do not believe it about this run » |
| `q4` Q4b | témoin appairé : le même run, sans drainage à côté | **0** accusation |
| `q4` Q4c | l'autre sens : un drainage tient les verrous, un run AFK démarre | le run journalise **puis** refuse (`rc=1`) ; c'est le témoin du **drain** qui accuse, même phrase |

## Pièges rencontrés en les écrivant

**Mesurer le code de sortie du drain hors d'un pipeline.** `printf … | bash
human-loop.sh` rend bien le statut du drain, mais une sonde qui veut *asserter*
dessus doit le prendre sans intermédiaire (`bash human-loop.sh <fichier ;
rc=$?`) — c'est ce qui a établi que le drain mort de Q2c rend `0` et non `1`.
Un `${:?}` sort du shell avec le statut de la dernière commande exécutée, pas
avec `1` : le `0` est le fait mesuré, pas une déduction.

**Un `${:?}` dans une substitution de commande ne tue que le sous-shell.**
Vérifié à part (`x="$(f a)" || true` : la substitution rend le vide, l'appelant
survit, rc 0). C'est la différence entre le pack d'avant [67] et celui
d'aujourd'hui, et c'est ce qui rend le défaut de `q2` invisible à toute lecture
de `router.sh` seul.

**Un voisin du puits qui porte une `Escalation:` ne reproduit rien** (Q2d) : le
cas est *l'absence du champ*, et c'est la forme que `capability_propose` écrit —
le producteur unique du palier capacité, du palier rétro et de
`playthrough__escalate`.

**Une session d'itération atteint l'arbre principal** par
`git worktree list --porcelain | awk '/^worktree /{print $2; exit}'`, et les
refs `refs/heads/*` sans rien faire du tout : elles vivent dans le répertoire git
commun, qu'un worktree partage.

**Il faut un ticket `ready-for-agent` pour qu'un run AFK fasse quoi que ce soit**
(piège déjà connu de la passe du 06/09) : toutes les sondes qui mesurent une
itération sèment `01-alpha` en plus du ticket du puits.

**Faire attendre une session pour tenir les verrous.** `q4` a besoin d'un run
vivant : le faux `claude` touche `$RALPH_SHIM_STATE/in-session` puis attend
`$RALPH_SHIM_STATE/go`. Pour l'autre sens, le drain est tenu vivant par un
**fifo** sur son stdin (`mkfifo` + `exec 9>`), sans quoi il sort tout de suite
sur « stdin ended ».

**`tracker_preflight` a besoin de deux tickets portant le même `NN`** pour
produire le constat `ambiguous-id` que `q4` fait journaliser. Deux fichiers
`20-a.md` et `20-b.md` suffisent, et les mettre en `ready-for-human` les garde
hors de la frontière.
