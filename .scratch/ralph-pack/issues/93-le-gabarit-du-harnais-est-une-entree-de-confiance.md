# 93 — Le gabarit du harnais est une entrée de confiance de la suite qui juge

**What to build:** Que le gabarit de projet gardé sous `$TMPDIR` cesse d'être cru sur parole par la suite qui décide si une itération est verte — et que ce qu'aucun pack ne peut tenir sur le cache de la commande de test d'un projet soit nommé dans le tableau.

**Blocked by:** 92

**Write-surface:** `test/helpers/harness.bash`, `test/smoke.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Le gabarit est **validé contre sa source** au moment où il est estampé, ou la suite cesse de le partager entre runs. C'est le cache d'une fonction pure du pack : comparer la sortie à l'entrée est ce qu'un cache doit faire, et l'empreinte lit déjà tout le pack à chaque `harness_setup`, donc le prix est connu et mesurable.
- [ ] Le geste couvre les **deux** objets de ce préfixe : `ralph-harness.<empreinte>/project` et `ralph-harness.globals.<empreinte>`. Le second est sans conséquence pris seul ([89]), mais il vit sous la même clé et se répare du même geste.
- [ ] Les deux décisions existantes sont **préservées ou retranchées explicitement** : les sept jours de conservation, défendus par un test de `init.sh sweep` (*« the suite's template cache is kept seven days on purpose »*), et le refus du motif `ralph-*` par [62] pour cette raison exacte. Réduire la durée ne répare rien — l'adressage est par contenu.
- [ ] Le tableau porte la ligne générique : **ce que la commande de test d'un projet lit hors du dépôt n'est tenu par rien**, et ne peut pas l'être par un pack qui diffe des trees git. Posture de [39] — nommer ce qu'on ne sait pas adresser plutôt que faire semblant.
- [ ] Le test qui tient tout ça met en scène la chaîne complète (pack cassé + gabarit forgé) et asserte **ce qui a changé**, avec son témoin appairé.
- [ ] Une entrée de mutation par garantie livrée, avec le témoin appairé.

## Comments

- **Ordre validé par Philippe le 22/09/2026** : **[91] → [92] → [93]**.
  Le critère est celui d'habitude — minimiser la reprise, jamais l'urgence. [91]
  devant parce qu'un `bash` planté possède l'interpréteur des quatre commandes du
  projet et rendrait inutile toute réparation faite à l'intérieur du gate ; [92]
  ensuite, seul ticket qui touche le cycle de vie d'une session, et il réécrit la
  borne de la ligne 35 du tableau ; [93] en dernier, purement dans `test/`, sa
  ligne de tableau étant l'aveu générique dont les deux autres sont les cas
  adressables.

- **Ouvert par la passe transversale du 22/09/2026** (`../passe-transversale-22-09.md`,
  §3). Sonde : `../sondes/passe-22-09/q1-le-cache-du-harnais.sh`.
  C'est la question que **[89] a explicitement laissée à cette passe**, et elle est
  plus large que son ticket ne la décrivait.

- **Mesuré de bout en bout.** `A` run propre → gabarit sous `fp0 = 3290877307`.
  `B` une garantie du pack retirée (`state.sh`, entrée existante de `mutate.sh`)
  → `fp1 = 1448025410`. `C` une copie du gabarit **propre** déposée sous `fp1`.
  `D` `TEST_CMD` relancé → **vert**, `1 tests, 0 failures`. `E` témoin appairé,
  dépôt retiré → **rouge**, `test/state.bats:94: failed`. `F` contre-témoin, pack
  restauré → vert. Le pack de l'arbre est cassé et la suite dit vert.

- **Pourquoi le gabarit et pas le cache des globals.**
  `harness__install_pack` copie `loop.sh`, `human-loop.sh`, `settings.json` et
  les vingt-quatre libs dans `$TMPDIR/ralph-harness.<empreinte>/project/.claude`,
  et chaque test fait `cp -R "$template/project" "$PROJECT_DIR"` : **le pack que
  la suite teste est cette copie, pas celle du dépôt**.

- **L'adressage par le contenu est ce qui le rend accidentellement sûr, et
  délibérément atteignable.** Un gabarit périmé ne peut pas produire un faux vert :
  la clé change dès que le pack change — c'est aussi ce qui protège
  `test/mutate.sh`. Le canal exige qu'une session calcule l'empreinte de l'arbre
  qu'elle s'apprête à rendre au gate, avec la fonction qui est dans l'arbre.

- **La portée, à lire avant de dimensionner.** Ce dépôt n'est **pas** installé sur
  lui-même — pas de `.claude/ralph.config.sh`, les deux gates sont lancés à la
  main. Ce n'est donc pas un faux vert livré ici ; c'est le canal que reçoit tout
  projet dont la commande de test garde un cache hors du dépôt (`jest`, `pytest`,
  `gradle`, `ccache`, `node_modules/.cache`). Le pack ne peut pas le fermer : ce
  qui est hors de l'arbre lui est structurellement invisible (ligne 57 du tableau).
  Ce dépôt peut fermer le sien.

- **Hérité de [92]** : la ligne de tableau écrite ici est l'aveu générique dont
  [91] et [92] sont les deux cas adressables. Elle se lit après la borne que [92]
  réécrit, pas avant.
