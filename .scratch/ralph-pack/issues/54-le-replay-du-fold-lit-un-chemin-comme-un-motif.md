# 54 — Le replay du fold lit un chemin livré comme un motif, et le retire de la branche

**What to build:** Faire lire `concurrency__replay` un chemin **littéralement**, comme
les huit autres lecteurs de listes de chemins du pack depuis [33]. La ligne :

    line="$(cd "$root" && git ls-tree "$commit^{tree}" -- "$path" 2>/dev/null)" || line=""

Un pathspec git est un **motif**. Un chemin livré nommé `src/zone[1].txt` est donc
demandé comme une classe de caractères, ne matche rien, `line` est vide — et la branche
qui suit lit ce vide comme « la session a supprimé ce fichier » et fait
`git update-index --force-remove`. L'itération est verte, son commit contient le
fichier, et le fold **le retire** de la branche. Les deux lignes voisines
(`--force-remove`, `--cacheinfo`) prennent bien un nom de fichier et non un pathspec :
c'est la seule des trois qui interroge.

**Blocked by:** None

**Write-surface:** `.claude/lib/concurrency.sh`, `test/concurrency.bats`,
`test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Un chemin livré **que git lit comme une magie de pathspec** (déclencheur
      corrigé : le deux-points initial, pas le métacaractère de glob) arrive sur la
      branche par le chemin **replay** comme par le chemin fast-forward. *`:(literal)`
      sur la seule ligne qui interroge, et sur elle seule.*
- [x] Le test est écrit sur le **replay** et pas sur le fast-forward : à
      `MAX_PARALLEL=1` la branche n'a pas bougé, `concurrency__replay` n'est jamais
      appelé, et un test de bout en bout passerait des deux côtés du correctif. Voir
      comment [50] a dû descendre au module pour `concurrency__refresh`, pour la même
      raison. *`pack_run` appelant `concurrency__replay` directement, avec les trois
      réponses dans un seul appel.*
- [x] `test/mutate.sh` porte l'entrée qui retire le `:(literal)`, et elle rougit.
      *`54 the replay asks about a delivered path as a pattern` → `ok`.*

## Comments

- **Origine : livraison de [50], le 30/08/2026.** Trouvé en lisant
  `concurrency__replay` pour répondre au troisième AC de [50], qui portait sur
  `concurrency__refresh` — la fonction d'à côté. Non réparé là : hors de la
  write-surface de ce ticket, et la réparation demande son propre test.

- **Famille de [33], et le dernier de ses lecteurs qui n'a jamais été recalé.** [33] a
  fait voyager toute liste de chemins un chemin par ligne et lire ces chemins
  littéralement ; [39] a repris chaque appelant un par un (`failures_make_durable`, le
  rollback, `concurrency__refresh`, le snapshot). Celui-ci a été manqué parce que le
  `ls-tree` **n'écrit pas** : il pose une question, et la mauvaise réponse est
  silencieuse. `concurrency__refresh`, dans la même famille, a bien reçu son
  `:(literal)` avec le commentaire qui l'explique — quatre lignes plus haut dans le
  même fichier.

- **CORRECTION DU DIAGNOSTIC — sondé le 31/08/2026 pendant la livraison de [51], qui
  a dû mesurer la même famille.** Le déclencheur écrit ci-dessus (`[`, `]`, `*`, `?`)
  est **faux**, et un test écrit dessus serait vert des deux côtés du correctif. Deux
  faits mesurés sur `git version 2.50.1 (Apple Git-155)`, dépôt jetable, deux fichiers
  `src/zone[1].txt` et `src/zone1.txt` commités :

      git ls-tree "$c^{tree}" -- 'src/zone[1].txt'   → l'entrée src/zone[1].txt, seule
      git ls-tree "$c^{tree}" -- 'src/zone*.txt'     → RIEN
      git ls-tree -r "$c^{tree}" -- 'src/zone*.txt'  → RIEN
      git ls-tree "$c^{tree}" -- ':(glob)src/zone*.txt'
        → fatal: pathspec magic not supported by this command: 'glob'

  **`git ls-tree` ne wildmatche pas du tout.** Il refuse même la magie `glob`, et un
  motif à étoile ne lui rend rien. Donc sur cette ligne un nom à métacaractère de glob
  revient **littéralement**, `line` n'est pas vide, et le `--force-remove` n'est jamais
  atteint. Le mécanisme décrit en tête de ticket ne se produit pas pour cette famille
  de caractères. Vérifié aussi que les deux lignes voisines sont bien littérales :
  `git update-index --force-remove -- 'src/zone[1].txt'` retire `src/zone[1].txt` et
  laisse `src/zone1.txt` en place.

- **Le défaut existe quand même, et son déclencheur est le DEUX-POINTS INITIAL.** Même
  sonde, fichier `:odd.txt` à la racine du dépôt :

      git ls-tree "$c^{tree}" -- ':odd.txt'            → RIEN            (rc=0)
      git ls-tree "$c^{tree}" -- ':(literal):odd.txt'  → l'entrée :odd.txt

  `:` ouvre la magie de pathspec ; git lit la magie courte, ne reconnaît pas `o`, et le
  chemin devient `odd.txt` — qui n'existe pas. `line` est **vide**, et la branche qui
  suit lit ce vide comme « la session a supprimé ce fichier » : `--force-remove`. C'est
  exactement la cascade que ce ticket décrit, avec le bon caractère. `:(literal)` la
  ferme. **Conséquences pour les AC** :
  - l'AC 1 doit dire « un chemin livré que git lit comme une magie de pathspec » et le
    test doit porter sur un nom à **deux-points initial**, pas sur `zone[1]` ;
  - le `rc=0` compte autant que la sortie vide : rien ne distingue « aucune entrée » de
    « je n'ai pas compris le chemin », ce qui est la ligne de [34] et vaut peut-être
    mieux qu'un `:(literal)` seul — un `ls-tree` qui ne rend rien pour un chemin que la
    liste approuvée nomme est une **contradiction**, pas une suppression, et le fold
    pourrait refuser en le disant plutôt que retirer ;
  - le témoin appairé se fait avec un nom ordinaire **et** avec un nom à métacaractère
    de glob : ce dernier reste vert des deux côtés, et c'est ce qui documente que la
    famille n'est pas celle qu'on croyait.

- **LIVRÉ le 31/08/2026.** `:(literal)` sur la ligne 529 de
  `.claude/lib/concurrency.sh`, et sur elle seule. Test
  `test/concurrency.bats` : « a delivered path git reads as pathspec magic is
  replayed, not removed ». Entrée de mutation `54 the replay asks about a delivered
  path as a pattern` → `ok`. Ligne du tableau de `docs/frontiere-de-confiance.md`
  (« Le travail d'une itération verte arrive sur la branche ») mise à jour avec ce qui
  la tient et ce qui reste ouvert.

- **Les deux lignes voisines sont disculpées par la mesure, et `:(literal)` les
  casserait.** Sondé le 31/08 sur `git 2.50.1`, index jetable monté sur un arbre
  portant `:odd.txt` :

      git update-index --force-remove -- ':odd.txt'            → retire :odd.txt
      git update-index --force-remove -- ':(literal):odd.txt'  → ne retire RIEN
      git checkout-index -f -- ':odd.txt'                      → restaure :odd.txt

  `update-index` et `checkout-index` prennent un **nom de fichier** et pas un
  pathspec : leur ajouter la magie fait passer `:(literal):odd.txt` pour un nom, qui
  n'existe pas. C'est l'inverse de la règle de [33], sur les deux lignes qui
  l'encadrent. La famille se sonde donc **par verbe** et jamais par voisinage, ce que
  [51] avait déjà mesuré autrement (`diff-tree` sur-matche, `ls-tree` ne wildmatche
  pas, `checkout-index` refuse `:(literal)`).

- **Le témoin appairé a été vérifié à la main, et l'ordre des assertions est
  porteur.** bats s'arrête à la première assertion rouge : avec `:odd.txt` asserté en
  premier, rien ne disait si le nom à métacaractère de glob survivait à la mutation.
  Réordonné (glob, ordinaire, supprimé, frère, **puis** deux-points), la mutation
  appliquée à la main fait rougir la ligne 814 et **elle seule** — c'est la mesure qui
  dit que la famille est la magie de pathspec et pas le glob. Un test qui n'aurait
  asserté que le nom à crochets aurait été vert des deux côtés, exactement ce que la
  correction du diagnostic annonçait.

- **Ce que le ticket suivant hérite, et qui n'est pas réparé ici.** `rc=0` ne
  distingue toujours pas « aucune entrée » de « je n'ai pas compris le chemin » — la
  ligne de [34]. Avec `:(literal)` il n'y a plus de chemin que git puisse mal lire,
  donc le vide redevient univoque **pour cette cause-là**. Il en reste une autre, et
  c'est la moitié de [50] qui n'a pas été faite ici : `concurrency__refresh` a reçu
  `$tip` parce que « absent de `HEAD` » ne veut pas dire « supprimé » ; le rejeu, lui,
  pose toujours **une seule** question et lit « absent du commit » comme « supprimé ».
  Un chemin que le gate approuve et que `git add` **refuse** (le `refused` de
  `failures_make_durable`) est absent du commit exactement comme un chemin supprimé —
  et s'il est sur le tip, le rejeu le retire de la branche. La question symétrique
  serait « était-il dans `$start` ? », et `concurrency_integrate` a la valeur sous la
  main. **Non ouvert en ticket parce qu'aucun cas atteignable n'a été construit** : il
  faut un refus de `git add` sur un chemin que le tip porte, dans la fenêtre entre
  l'arbre jugé et le commit durable — et une suppression, qui est le cas ordinaire, ne
  le produit pas (le chemin est dans l'index lu depuis `head`, `git add -A` stage la
  suppression et rend 0). Laissé à la prochaine passe transversale, comme [51] avait
  laissé `lenses_has_tag`, et écrit au tableau.

  **FERMÉ par [60], livré le 04/09/2026.** La passe du 01/09 a construit le cas
  atteignable — un humain qui commite dans un autre terminal déplace le tip, un
  `TEST_CMD` qui rend le chemin illisible après l'arbre jugé produit le refus de
  `git add` — et le rejeu pose maintenant la seconde question (`$start`), par le
  **code de retour** des deux `ls-tree` et non par leur vide ([59]). La ligne de
  [34] est donc fermée ici aussi, pour les deux causes : plus de chemin que git
  puisse mal lire (`:(literal)`), et plus de refus lu comme un vide.

- **Ce qui borne la gravité, et ce qui ne la borne pas.** ~~Le chemin replay n'est
  atteint qu'au-dessus de `MAX_PARALLEL=1`, donc l'installation par défaut n'y touche
  pas.~~ **FAUX — corrigé par [60], mesuré le 01/09/2026 et livré le 04/09/2026** :
  le rejeu est atteint dès que le **tip bouge**, et le tip bouge dès qu'un humain
  commite dans un autre terminal — ce que [56] demande explicitement aux humains de
  faire. L'installation par défaut y touche. La phrase avait été écrite sans sonde,
  comme celle que [41] a dû corriger dans le tableau et pour la même raison.
  Mais quand il est atteint, ce n'est pas une perte de travail non commité : le
  fold construit un arbre où le fichier est **absent** et le pose sur la branche, donc
  une livraison verte est activement **retirée** de la branche par le run lui-même, et
  la ligne de journal dit `folded onto the branch over a sibling's commit` — un
  contrôle qui rend compte de son intention et non de son résultat, exactement ce que
  [30] a payé sur `core.excludesFile` et [37] sur la quarantaine.
