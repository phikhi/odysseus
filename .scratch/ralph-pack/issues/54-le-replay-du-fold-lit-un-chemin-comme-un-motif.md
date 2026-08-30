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

- **Ce qui borne la gravité, et ce qui ne la borne pas.** Le chemin replay n'est
  atteint qu'au-dessus de `MAX_PARALLEL=1`, donc l'installation par défaut n'y touche
  pas. Mais quand il est atteint, ce n'est pas une perte de travail non commité : le
  fold construit un arbre où le fichier est **absent** et le pose sur la branche, donc
  une livraison verte est activement **retirée** de la branche par le run lui-même, et
  la ligne de journal dit `folded onto the branch over a sibling's commit` — un
  contrôle qui rend compte de son intention et non de son résultat, exactement ce que
  [30] a payé sur `core.excludesFile` et [37] sur la quarantaine.
