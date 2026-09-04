# 60 — Le rejeu retire de la branche le commit d'un humain, et le fait à MAX_PARALLEL=1

**What to build:** Fermer la question que [54] a explicitement renvoyée à la
passe transversale, avec le cas atteignable qu'il n'avait pas construit — et
corriger la phrase de gravité qu'il a écrite, qui est fausse.

[54] écrivait :

> `concurrency__refresh` a reçu `$tip` parce que « absent de `HEAD` » ne veut pas
> dire « supprimé » ; le rejeu, lui, pose toujours **une seule** question et lit
> « absent du commit » comme « supprimé ». Un chemin que le gate approuve et que
> `git add` **refuse** (le `refused` de `failures_make_durable`) est absent du
> commit exactement comme un chemin supprimé — et s'il est sur le tip, le rejeu le
> retire de la branche. **Non ouvert en ticket parce qu'aucun cas atteignable n'a
> été construit.**

Le cas est construit, et il tient en une phrase : **un humain qui commite dans un
autre terminal pendant qu'un run tourne**. C'est-à-dire exactement ce que [56]
vient de demander aux humains de faire — « un humain qui commite dans un autre
terminal et retape `r` passe ».

**Blocked by:** 59

**Write-surface:** `.claude/lib/concurrency.sh`, `test/concurrency.bats`,
`test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** frontiere-de-confiance

- [x] **Le rejeu pose la seconde question, celle que [50] a dû poser au
      rafraîchissement.** « Absent du commit » ne veut pas dire « supprimé » : ça
      veut dire « supprimé **ou** refusé au staging ». `concurrency_integrate` a
      `$start` sous la main, et un chemin qui n'est ni dans le commit ni dans
      `$start` n'est pas une suppression de cette itération — c'est un chemin dont
      elle n'a rien de vrai à dire, exactement le raisonnement que
      `concurrency__refresh` porte déjà quatre-vingts lignes plus bas.
      *`concurrency__replay` prend `$start` en cinquième argument ; un chemin
      absent des deux est compté `kept` et laissé où il est.*
- [x] **La ligne de journal cesse d'annoncer son intention.** Mesuré :
      `folded onto the branch over a sibling's commit` s'imprime alors que le fold
      vient de **retirer** un fichier de la branche, et qu'il n'y a **aucun
      frère** — c'est un commit humain qui a déplacé le tip. Deux mensonges dans
      une ligne, et c'est le défaut que [30] a payé sur `core.excludesFile` et [37]
      sur la quarantaine. *Deux lignes : une par chemin laissé (`is not in this
      iteration's commit and was not on the branch it started from`) et le résumé
      `folded onto the branch over a commit that moved the tip — N path(s)
      written, M removed, K left alone`.*
- [x] **La phrase de gravité de [54] est corrigée là où elle est écrite** — dans
      son ticket et au tableau de `docs/frontiere-de-confiance.md`. Elle dit
      « le chemin replay n'est atteint qu'au-dessus de `MAX_PARALLEL=1`, donc
      l'installation par défaut n'y touche pas » : mesuré faux, le rejeu est
      atteint à `MAX_PARALLEL=1` dès que le tip bouge, et le tip bouge dès qu'un
      humain commite. *Barrée dans [54], retirée du tableau, et la clause
      « quand un frère est passé avant » de la même ligne du tableau réécrite —
      elle portait la même hypothèse.*
- [x] **Le test porte sur le rejeu et pas sur le fast-forward**, comme celui de
      [54] et pour la même raison, avec le témoin appairé : le même montage sans
      le refus de staging doit laisser le fichier sur la branche. *Trois tests :
      le module avec quatre réponses dans un seul appel, la discipline de code de
      retour des deux `ls-tree`, et le run réel de bout en bout à `MAX_PARALLEL=1`
      (humain sur `TYPECHECK_CMD`, `chmod 000` sur `TEST_CMD`).*
- [x] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.
      *Sept entrées `60 …` → sept `ok`.*

## Comments

- **Origine : passe transversale du 01/09/2026.** Sonde conservée :
  `.scratch/ralph-pack/sondes/passe-01-09/q1-le-chemin-approuve-que-le-commit-durable-na-pas-pu-stager.bats`
  (Q1a, Q1b, Q1c).

- **Ce qui a été mesuré, dans l'ordre.**

  - **Q1a — le rejeu est atteint à `MAX_PARALLEL=1`.** Un `TYPECHECK_CMD` qui
    commite dans l'arbre principal (le second terminal de l'humain, monté sur une
    branche du fan, donc après l'arbre jugé de [29] et avant le commit durable)
    suffit : `folded onto the branch over a sibling's commit`, un frère,
    zéro. Le témoin est la ligne `folded onto the branch` du fast-forward, qui
    n'apparaît pas.
  - **Q1b — le chemin approuvé que `git add` a refusé.** Même montage, plus un
    `TEST_CMD` qui rend le chemin livré illisible après l'arbre jugé (la fenêtre
    que [54] nomme). Résultat :

        ralph: 50-fold: src/shared.txt was approved by the gate and could not be
               staged — it is not in this commit
        ralph: 50-fold: committed 2 path(s)
        ralph: 50-fold: folded onto the branch over a sibling's commit
        ralph: iteration 1: 50-fold -> resolved

    et après le run : `src/shared.txt` **n'existe pas dans `HEAD`**, et il est
    **absent de l'arbre de travail** — `concurrency__refresh` le `rm -f` ensuite,
    correctement de son point de vue puisque le fold l'a bien retiré. Le commit
    d'un humain est donc détruit sur la branche *et* sur le disque par un run qui
    vient de dire à voix haute qu'il n'a pas pu stager ce chemin. C'est le
    symptôme de [50], une fonction plus loin.
  - **Q1c — témoin appairé.** Le même montage sans le `chmod` : `src/shared.txt`
    survit sur `HEAD` (avec le contenu de la session — le conflit sémantique que
    [13] documente comme le prix du rejeu, pas ce ticket).

- **`Blocked by: 59` et pas l'inverse.** Le refus de `git add` que ce ticket lit
  comme un fait est le même que [59] lit comme un arbre. [59] décide de ce que le
  pack fait d'un refus de git ; ce ticket décide de ce que le **fold** en fait.
  Livrer celui-ci d'abord ferait écrire deux fois la même question.

- **Ce que [59] a décidé, livré le 03/09/2026 — le blocage est levé et voici ce
  qu'il laisse.** Trois choses, et la troisième change le montage de la sonde.

  - **La règle tranchée** : un refus de git voyage par le **code de retour**, et
    l'appelant qui le reçoit refuse de conclure plutôt que de conclure sur du
    partiel. Ce ticket applique la même règle un cran plus loin : « absent du
    commit » n'est pas une réponse, c'est deux réponses (supprimé, ou refusé au
    staging), et le rejeu doit poser la seconde question au lieu d'en déduire une.
  - **Ce qui n'a pas changé, et c'est le cœur de ce ticket** :
    `failures_make_durable` **dit déjà** qu'il n'a pas pu stager un chemin
    approuvé (`was approved by the gate and could not be staged`) et commite
    quand même le reste. [59] n'y a pas touché — c'est un commit forensique de
    l'itération, pas un arbre jugé —, donc la ligne Q1b reste reproductible telle
    quelle.
  - **Le montage de la sonde, en revanche, se relit.** Q1b rend le chemin livré
    illisible depuis `TEST_CMD`, c'est-à-dire **après** l'arbre jugé. Si la sonde
    est réécrite pour rendre le fichier illisible *avant* le snapshot du gate,
    elle ne mesure plus rien de ce ticket : depuis [59] le snapshot refuse et
    l'itération n'atteint jamais le fold. La fenêtre qui compte ici est celle qui
    s'ouvre **entre l'arbre jugé et le commit durable**, et `TEST_CMD` /
    `TYPECHECK_CMD` en sont les deux seuls crochets.

- **Ce qui n'est pas ce ticket.** Le rejeu écrase ce qu'un frère — ou un humain —
  a posé sur un chemin que l'itération livre aussi. C'est le conflit sémantique
  déjà écrit au tableau comme un prix assumé, et il ne se referme pas par un
  contrôle borné. Ce ticket ne parle que du chemin **retiré**.

- **LIVRÉ le 04/09/2026.** `.claude/lib/concurrency.sh` : `concurrency__replay`
  prend `$start` en cinquième argument, `concurrency_integrate` le lui passe.

  - **La seconde question, et son sens exact.** « Absent du commit de l'itération »
    est **deux** réponses. Si le chemin est dans `$start` : la session l'a
    supprimé, `--force-remove` comme avant. S'il n'y est pas non plus : rien de
    cette itération ne l'a mis sur la branche et rien ne l'en a retiré, donc ce
    qui est au tip a été posé par quelqu'un d'autre pendant qu'elle tournait, et
    le fold n'a aucun verdict à rendre — `kept`, laissé en place. C'est mot pour
    mot le raisonnement que [50] a donné à `concurrency__refresh`.
  - **Les deux `ls-tree` sont lus par leur code de retour, ce que le ticket ne
    demandait pas.** Ajouté quand même, parce que la garantie livrée est
    « un vide n'est pas une réponse » et qu'écrire une nouvelle question dont le
    vide décide entre *retirer* et *garder* aurait remis la ligne de [34] dans la
    fonction qu'on venait de la lui retirer. `git ls-tree` rend vide + `rc=0` pour
    un chemin qu'un arbre ne porte pas et vide + `rc=128` pour un arbre qu'il ne
    peut pas lire : discriminateur identique à celui de [59], même famille, coût
    quatre lignes. Un repli qui ne peut pas lire ce que son propre commit contient
    refuse la branche (l'itération repart `not-integrated`, sans retry, et le run
    s'arrête) au lieu de conclure « supprimé » et de retirer.
  - **Deux lignes de journal et pas une.** Le résumé (`over a commit that moved
    the tip — N written, M removed, K left alone`) rend compte du **résultat**, et
    une ligne **par chemin laissé** dit lequel et pourquoi. Sans la seconde, un
    chemin que le gate a approuvé et qui n'est pas sur la branche ne serait
    lisible dans le journal du matin que comme un écart entre deux nombres.

- **Ce que la suite complète a attrapé et qu'aucun test ciblé ne voyait — la
  leçon de [59], vérifiée une seconde fois.** La mutation
  `13 every fold rebuilds the commit instead of fast-forwarding` (`if false` sur
  le choix des deux formes) ne rougissait **que** par le
  `refute_output_contains "over a sibling's commit"` du test de fast-forward :
  avec `if false`, le rejeu produit le même message de commit, le même compte de
  commits et zéro merge, donc la ligne de journal était le seul témoin. Renommer
  cette ligne rendait l'entrée **VACUOUS** en silence. Le test porte maintenant
  `refute_output_contains "over a commit that moved the tip"` en premier, et garde
  la réfutation de l'ancienne formulation en dessous pour qu'elle ne revienne pas.
  Une réécriture de ligne de journal peut donc décrocher une mutation qui ne parle
  pas d'elle : **rejouer les familles voisines, pas seulement ses propres
  entrées** — `13 `, `39 `, `44 `, `50 `, `54 ` rejouées ici, toutes `ok`.

- **Ce que le ticket suivant hérite.**

  - **Le chemin livré *et* écrasé reste ouvert**, et c'est un prix, pas un défaut :
    `src/witness.txt` du test de module documente le cas — approuvé, stagé,
    replayé par-dessus ce qu'un humain venait de commiter au même nom. Le tableau
    le dit depuis [13].
  - **`concurrency__replay` écrit encore un blob périmé sans le dire.** Un chemin
    qui était dans `$start`, que la session a **modifié**, et dont le `git add` a
    été refusé, reste dans le commit de l'itération **avec son ancien contenu** :
    `ls-tree` répond une ligne, le rejeu la pose sur le tip, et l'édition qu'un
    humain venait d'y commiter est remplacée par la version d'avant. Ce ticket ne
    parle que du chemin *retiré* et le laisse ; c'est la même famille, un cran
    plus fin (comparer le blob à celui de `$start` le rendrait détectable).
  - **`concurrency__refresh` agit encore sur un chemin `kept`, et [50] avait fermé
    la forme voisine.** Un chemin laissé en place est *dans* `HEAD` (c'est le
    commit de l'humain), donc le rafraîchissement prend sa branche `else` :
    `checkout-index -f` écrit le blob de `HEAD` dans l'arbre principal et
    `git reset -- <path>` remet l'entrée d'index à `HEAD`. Sur un chemin que ce
    run vient explicitement de déclarer hors de son verdict, ça écrase une
    **édition non commitée** et défait un **staging** de l'humain. C'est plus
    étroit qu'avant ce ticket — le repli retirait le chemin et le rafraîchissement
    le `rm -f`, donc l'humain perdait tout —, et c'est déjà le prix écrit au
    tableau pour les chemins livrés ; mais sur un chemin *non* livré, c'est
    exactement la règle que [50] a posée à l'autre bout de la même fonction. Le
    fermer demanderait de faire voyager l'ensemble `kept` du rejeu au
    rafraîchissement : hors surface ici, ticket propre si quelqu'un le prend.
  - **La ligne de journal est un témoin de mutation.** Voir ci-dessus : avant de
    reformuler une ligne de `concurrency__log`, chercher qui la réfute.
