# Sondes de la passe transversale du 08/09/2026

Des **instruments**, pas des tests. Chacune se termine par un `set -e; false`
volontaire : elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant.
Elles ne sont pas dans `test/` et `test/run.sh` sans argument ne les ramasse pas —
elles ne doivent jamais compter dans le verdict des deux gates.

Les faire tourner, une par une ou par nom :

    bash test/run.sh .scratch/ralph-pack/sondes/passe-08-09/q1-un-tracker-de-plus-dune-page-nest-pas-le-tracker.bats
    bash test/run.sh -f Q2d .scratch/ralph-pack/sondes/passe-08-09/q2-le-sidecar-est-un-fichier-que-la-session-ecrit.bats

Elles pilotent le pack tel qu'il est livré ; aucune n'édite `.claude/` ni `test/`,
et aucune n'a besoin d'une mutation appliquée à la main. La passe qui les a
écrites est dans `../../passe-transversale-08-09.md`.

| Sonde | Ce qu'elle demande | Verdict, mesuré le 08/09/2026 |
|---|---|---|
| `q1` Q1a | une forge de quatre issues servie **deux par page**, `FORGE_PAGE=2` | `tracker_ids` rend **2** ids sur 4 ; la frontière aussi ; `3-gamma`, ouverte et `ready-for-agent`, se lit **« pas de ticket »** (rc=1). **Une seule page demandée**, trois fois. La borne compte **1** sur une page de deux enregistrements et **99** sur une page pleine de cent |
| `q1` Q1b | témoin appairé : les mêmes quatre sur **une** page | **4** ids, une requête |
| `q1` Q1c | la borne desserrée (`FORGE_PAGE=1`), qui met la pagination en marche | pages 1, 2 et 3 demandées — et `tracker_ids` rend **`3-gamma`, `4-delta`** : la page deux a **écrasé** la page une, `1-alpha` se lit « pas de ticket » |
| `q1` Q1d | ce que la disparition coûte au scope-guard | `src/beta.txt` (page une) → `2-beta` revendique ; `src/delta.txt` (page deux) → **personne** (rc=1), donc un drift contractuel classé débordement interne, donc retry au lieu d'escalade |
| `q2` Q2a | une itération **verte** dont la session appende `1-decision\treceipt\thttps://forge.invalid/pull/9999` à `.scratch/<feature>/.forge-claims` de l'arbre principal | run **rc=0**, ticket travaillé `resolved`/`closed`, **0** mot du sidecar. Le dossier du drain montre `receipt https://forge.invalid/pull/9999 — verdicts, findings, and the zones nothing judged`, sous la réserve écrite pour **le réseau** |
| `q2` Q2b | témoin appairé : le même run vert, sans la ligne | « receipt none was kept for this ticket » |
| `q2` Q2c | un claim de run **mort** sur un backend distant, tel quel | `Claimed=[owner=pid:999999 …]`, `claim_reclaim_stale` rend `2-alpha retry`, la forge repasse à `ready-for-agent` |
| `q2` Q2d | le même, avec **une ligne** appendue derrière par une session (pid vivant de cet utilisateur) | `Claimed=[owner=pid:<vivant> at=<maintenant>]`, reclaim **silencieux**, ticket toujours `claimed`, **frontière vide** |
| `q2` Q2e | une session pose `.scratch/<feature>/.forge.guard/pid` avec un pid vivant | le run **s'arrête** (`rc=4`, sterile) après deux itérations qui n'ont rien réclamé, et la phrase qu'il imprime est **fausse** : « the tracker refused the write: nobody is named as holding it » |
| `q2` Q2f | le même geste sur le backend **local**, `issues/01-alpha.md.guard/pid` | identique : `rc=4`, deux fois la même phrase fausse, ticket toujours `ready-for-agent`. Le défaut est du pack, pas de [18] |
| `q3` Q3a | une session **routée** met le voisin `2-alpha` à `resolved`, backend distant | le drain le **remet** — par le réseau, `tracker_mark_ready` — le nomme, et redit la réserve de [61] sur les trois champs qu'il ne remet pas |
| `q3` Q3b | une session d'**itération** met `1-decision` (le puits humain) à `resolved`, backend distant | run **rc=0**, itération **verte**, `1-decision` reste **`resolved`** : un ticket qui attendait un humain est sorti du puits par une session, et le run ne dit que sa phrase générique de démarrage |
| `q3` Q3c | témoin appairé : le même geste sur le backend **local** | « the session edited the tracker — restored 1 ticket file(s), the iteration cannot be green », outcome `tracker-write`, `20-decision` toujours `ready-for-human` |

## Rejeu des sondes de vérification des tickets livrés

`ticket-64`, `ticket-65`, `ticket-66`, `ticket-67`, `ticket-68`, `ticket-69`,
`ticket-70` rejouées à l'identique le 08/09/2026 : **aucune régression**, chaque
verdict est celui que son ticket a consigné (deux constats une fois chacun et
repli à 13 pour [64] ; borne non mordue puis phrase nommant les trois intrus pour
[65] ; 2/0/1 lignes `ref-drift` et guichets `admit`/`arbitrate` pour [66] ; zéro
auto-accusation pour [67] ; `spec-drift` une fois pour [68] ; résidus nommés pour
[69] ; 1/0/1 lignes `forensic-drift` et la réserve imprimée dans les trois cas
pour [70]). [71] et [72] n'ont pas laissé de répertoire de sondes : leurs témoins
sont `passe-07-09/q2` et `passe-07-09/q4`.

## Pièges rencontrés en les écrivant

**Le faux `curl` du harnais ne peut pas servir une seconde page**, et il le dit :
« Page two and beyond are empty: this fake holds fewer tickets than a page. »
Une sonde qui veut mesurer la pagination écrase `$SHIM_BIN/curl` — la **copie**
que le harnais a posée dans le PATH du test, jamais `test/helpers/shims/curl`.
Le faux doit rendre le corps, puis `\n200` : `forge__http` lit le statut comme
**dernière ligne** (`-w '\n%{http_code}'`).

**`kill -0 1` ne prouve pas qu'un pid est vivant.** Un pid qu'on n'a pas le droit
de signaler rend EPERM, donc non zéro, donc `state_guard_take` le lit comme mort
et prend le garde. Une sonde qui veut un propriétaire vivant fork son propre
`sleep` et écrit `$!`.

**Le menu du drain répond à `o`, pas à `y`** — et un ticket de guichet `admit`
en offre autant qu'un autre. `printf "o\no\nn\nq\n"` ouvre deux sessions puis
laisse le ticket où il est.

**`awk` compare un *strnum* à une variable non initialisée numériquement.**
`f[1]` sorti de `split()` sur « 0.number » vaut « 0 », et `last` non affectée vaut
à la fois « » et `0` : `f[1] != last` est **faux** au premier enregistrement de
chaque document. C'est la racine de Q1a, et c'est une forme qu'on ne voit pas en
relisant — elle se mesure (`awk 'BEGIN{for(i=0;i<100;i++)…}'` en trois lignes).

**Une session d'itération atteint l'arbre principal** par `git worktree list
--porcelain`, et le nom de la feature par `basename "$(ls -d "$main"/.scratch/*/
| head -1)"` — `$FEATURE` n'est pas dans son environnement (piège de [70]).

**Un `pack_run` mute la forge du mock.** Deux mesures dans le même test partagent
l'état : un premier appel à `claim_reclaim_stale` **rend** le ticket, donc le
second ne mesure plus le claim mais un `Status:` déjà changé. Les deux moitiés
d'un témoin appairé veulent deux `@test`.
