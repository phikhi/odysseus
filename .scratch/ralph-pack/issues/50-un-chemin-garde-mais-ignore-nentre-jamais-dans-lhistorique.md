# 50 — Un chemin gardé qu'un projet ignore est approuvé, puis jamais commité

**What to build:** Décider ce que le pack fait d'un chemin que le gate **approuve** et
que `git add` **refuse**, et le tenir. Le cas armé n'a rien d'exotique : un projet qui
`gitignore` un répertoire que son propre `GUARDED_PATHS` nomme. `gate_tree_snapshot`
le force dans l'arbre jugé — c'est le contrat de [24] — le scope-guard le juge et
l'approuve, puis `failures_make_durable` fait `git add` sans `-f`, que git refuse pour
un chemin ignoré. L'itération est **verte**, le ticket `resolved`, et le fichier
n'est pas dans l'historique. Le défaut par défaut du pack sur lui-même : un projet
qui ignore `.claude/` — la convention de tous les projets Claude Code — ne reçoit
jamais le code que la boucle lui livre.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/gate.sh`,
`test/failures.bats`, `test/gate.bats`, `test/mutate.sh`,
`docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Un chemin gardé qu'un projet ignore, écrit par une itération verte et approuvé
      par le scope-guard, **arrive dans l'historique** — ou bien l'itération n'est pas
      verte. Pas les deux moitiés actuelles : approuvé *et* absent.
- [ ] La décision est écrite avec son prix, pas seulement le correctif. `--force` sur
      les seuls chemins approuvés est la réponse courte, et il faut dire ce qu'elle
      engage : le commit durable se met à écrire dans l'historique du projet cible
      des chemins que ce projet a explicitement dits hors de son historique, sur la
      foi d'un `GUARDED_PATHS` qui est une clé du projet lui-même. Refuser le vert
      est la réponse symétrique, et elle refuse indéfiniment le seul ticket honnête
      dont la surface tombe dans la zone ignorée — la même impasse que [35] a déjà
      nommée pour `gate__nothing_delivered`.
- [ ] Le `git reset` du même bloc et celui de `concurrency__refresh` sont relus sous
      la même question : ce qui n'a pas pu être stagé n'a pas non plus à être
      désindexé, et l'arbre principal doit refléter ce qui a réellement été commité.
- [ ] La ligne « Ce que le commit durable d'une itération verte contient vraiment »
      de `docs/frontiere-de-confiance.md` est réécrite avec ce qui tient réellement.
      Elle a été posée par [39] et dit aujourd'hui *nommé, pas commité*.

## Comments

- **Origine : livraison de [39], le 27/08/2026.** Trouvé en cherchant une observation
  pour la vérification que [39] venait d'ajouter (« ce que le gate a approuvé et qui
  n'est pas dans ce commit »), pas en cherchant ce défaut-ci. Le test qui le stage est
  dans le dépôt : `test/failures.bats`, « a path the gate approved and git would not
  stage is named, not dropped » — `GUARDED_PATHS=vendor`, `.gitignore` porte
  `vendor/`, la surface du ticket porte `vendor/*`. Résultat asserté aujourd'hui :
  `run_loop` réussit, `01-alpha` est `resolved`, la ligne de gap nomme
  `vendor/thing`, et `git ls-tree HEAD` ne le contient pas.

- **Ce que [39] a livré et ce qu'il a refusé de livrer.** Livré : la **vérification de
  résultat**. `failures_make_durable` ne se contente plus de lancer `git add` sous un
  `|| true` — il compare l'arbre qu'il s'apprête à commiter à l'arbre que le gate a
  jugé, netté contre la liste approuvée, et **nomme** chaque chemin manquant. Refusé :
  forcer. Ajouter `--force` change ce qu'une itération verte commite dans *tout*
  projet à `.gitignore` fourni, ce qui est une décision à prendre pour elle-même et
  pas en passant dans un ticket sur les noms de fichiers non-ASCII.

- **Pourquoi ce n'est pas seulement `vendor/`.** `GUARDED_PATHS` vaut `.claude` par
  défaut, et `.claude/settings.local.json` est ignoré par convention dans tous les
  projets Claude Code — c'est le cas armé de [24], mot pour mot. Un projet qui ignore
  `.claude/` en entier (ce que font des projets réels pour ne pas versionner leur
  configuration locale) reçoit donc une boucle qui juge le pack, approuve les
  éditions du pack, et ne les commite jamais. Sonder ce cas-là avant d'écrire : c'est
  lui qui décide si `--force` est un élargissement ou une réparation.

- **Le troisième forçage à ne pas oublier.** Ce que `gate_tree_snapshot` force dans
  l'arbre jugé n'est pas seulement `GUARDED_PATHS` : c'est aussi tout ce qu'une règle
  d'ignore écrite **pendant** l'itération vient de cacher ([30], `gate_newly_hidden`).
  Un fichier que la session a écrit puis caché par un `.gitignore` de son cru est donc
  jugé, potentiellement approuvé — et tombe exactement dans le même trou. Celui-là est
  moins innocent, et il vaut la peine de demander si le forcer dans l'historique est
  bien ce qu'on veut : la réponse peut différer des deux autres.
