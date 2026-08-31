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
`test/mutate.sh`

**Status:** ready-for-agent

- [ ] Un chemin livré dont le nom porte un métacaractère de glob (`[`, `]`, `*`, `?`)
      arrive sur la branche par le chemin **replay** comme par le chemin
      fast-forward — ou bien le fold refuse et le dit, plutôt que de supprimer.
- [ ] Le test est écrit sur le **replay** et pas sur le fast-forward : à
      `MAX_PARALLEL=1` la branche n'a pas bougé, `concurrency__replay` n'est jamais
      appelé, et un test de bout en bout passerait des deux côtés du correctif. Voir
      comment [50] a dû descendre au module pour `concurrency__refresh`, pour la même
      raison.
- [ ] `test/mutate.sh` porte l'entrée qui retire le `:(literal)`, et elle rougit.

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

- **Ce qui borne la gravité, et ce qui ne la borne pas.** Le chemin replay n'est
  atteint qu'au-dessus de `MAX_PARALLEL=1`, donc l'installation par défaut n'y touche
  pas. Mais quand il est atteint, ce n'est pas une perte de travail non commité : le
  fold construit un arbre où le fichier est **absent** et le pose sur la branche, donc
  une livraison verte est activement **retirée** de la branche par le run lui-même, et
  la ligne de journal dit `folded onto the branch over a sibling's commit` — un
  contrôle qui rend compte de son intention et non de son résultat, exactement ce que
  [30] a payé sur `core.excludesFile` et [37] sur la quarantaine.
