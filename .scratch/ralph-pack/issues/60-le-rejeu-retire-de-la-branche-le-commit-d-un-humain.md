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

**Status:** ready-for-agent

**Tags:** frontiere-de-confiance

- [ ] **Le rejeu pose la seconde question, celle que [50] a dû poser au
      rafraîchissement.** « Absent du commit » ne veut pas dire « supprimé » : ça
      veut dire « supprimé **ou** refusé au staging ». `concurrency_integrate` a
      `$start` sous la main, et un chemin qui n'est ni dans le commit ni dans
      `$start` n'est pas une suppression de cette itération — c'est un chemin dont
      elle n'a rien de vrai à dire, exactement le raisonnement que
      `concurrency__refresh` porte déjà quatre-vingts lignes plus bas.
- [ ] **La ligne de journal cesse d'annoncer son intention.** Mesuré :
      `folded onto the branch over a sibling's commit` s'imprime alors que le fold
      vient de **retirer** un fichier de la branche, et qu'il n'y a **aucun
      frère** — c'est un commit humain qui a déplacé le tip. Deux mensonges dans
      une ligne, et c'est le défaut que [30] a payé sur `core.excludesFile` et [37]
      sur la quarantaine.
- [ ] **La phrase de gravité de [54] est corrigée là où elle est écrite** — dans
      son ticket et au tableau de `docs/frontiere-de-confiance.md`. Elle dit
      « le chemin replay n'est atteint qu'au-dessus de `MAX_PARALLEL=1`, donc
      l'installation par défaut n'y touche pas » : mesuré faux, le rejeu est
      atteint à `MAX_PARALLEL=1` dès que le tip bouge, et le tip bouge dès qu'un
      humain commite.
- [ ] **Le test porte sur le rejeu et pas sur le fast-forward**, comme celui de
      [54] et pour la même raison, avec le témoin appairé : le même montage sans
      le refus de staging doit laisser le fichier sur la branche.
- [ ] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.

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
