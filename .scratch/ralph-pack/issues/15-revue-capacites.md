# 15 — Revue de capacités au fil de l'eau

**What to build:** Le pas qui **repère sans créer** une capacité manquante (lentille / agent / skill) en delivery : le retro propose et escalade, jamais d'auto-création — une capacité change le contrat, donc toujours HITL.

**Blocked by:** 14

**Write-surface:** `.claude/lib/capability.sh`, `test/capability.bats`, `.claude/lib/retro.sh`, `.claude/loop.sh`, `.claude/ralph.config.sh.example`, `test/mutate.sh` — plus les artefacts du dépôt (`CONTEXT.md`, `docs/frontiere-de-confiance.md`, les tickets)

**Status:** resolved

- [x] Détecter ≠ créer : le retro qui repère une lentille/agent/skill manquant ouvre une proposition `ready-for-human`, sans jamais créer la capacité en AFK.
- [x] La barre de déclenchement est respectée : récurrence **ou** classe non couverte.
- [x] Réutiliser-avant-créer : la proposition privilégie étendre un brief > réutiliser un skill du substrat > créer neuf.
- [x] Aucune capacité n'est créée automatiquement pendant un run AFK.

## Comments

- **Contrainte tenue par [31], livré le 30/07/2026 : la dernière AC n'est plus seulement une consigne.** `.claude/agents`, `.claude/commands`, `.claude/skills` et `.claude/hooks` sont scellés — ils entrent dans le snapshot quoi que dise `GUARDED_PATHS`, et **aucune write-surface ne peut les couvrir**. Une session qui créerait une capacité en AFK rougit donc l'itération et se fait rollbacker, au lieu de dépendre de la bonne volonté du modèle. C'était le coût nul de l'élargissement : ce ticket refusait déjà la création autonome, donc sceller ces chemins n'enlève rien à personne.

  Ce que ça change ici : l'AC devient **vérifiée** plutôt que demandée, et la ligne du tableau de `docs/frontiere-de-confiance.md` peut le dire. Ce que ça ne change pas : la *proposition* est un ticket `ready-for-human`, donc elle n'écrit rien sous ces chemins de toute façon.

  Une réserve à connaître, héritée telle quelle : ici `.claude/skills` est un jeu de liens symboliques vers `.agents/`. Écrire *à travers* un lien atterrit hors du chemin scellé — le scope-guard voit bien cette écriture pour ce qu'elle est, le scellement ne la voit pas du tout. Si ce ticket touche aux skills, c'est la distinction à garder en tête.

- **Contrainte posée par [14], livré le 24/08/2026 : le canal d'escalade existe déjà, ne pas en bâtir un second.** Le subagent retro peut répondre `RALPH-RETRO-ESCALATE: <règle>` quand ce qu'il a vu demanderait un gate, un lint ou un hook. Le pack ouvre alors, **par l'adaptateur de tracker** (donc noté au registre de [13], donc à l'abri des deux gardes de [42]), un ticket `retro-<slug>` en `ready-for-human`, avec la règle demandée, la raison pour laquelle elle n'est pas une leçon, et le ticket d'où elle vient. Dédupliqué contre le tracker : une escalade qui attend déjà un humain n'est pas rouverte chaque nuit.

  Ce que ce ticket hérite : la frontière « détecter ≠ créer » est **tenue** de ce côté-là — la seule chose que la boucle écrit d'elle-même est une observation dans son propre index, jamais une capacité. Ce que ce ticket doit décider : si sa revue de capacités produit ses propres propositions, elle passe par le même canal (même forme de ticket, même dédup) ou elle dit pourquoi elle en veut un autre. Deux producteurs de propositions avec deux formats est exactement le genre de chose qu'un humain qui vide le puits ne voit qu'une fois qu'elle est là.

---

### Ce qui a été livré, le 25/08/2026

- **La décision que le commentaire de [14] demandait : un seul écrivain, deux producteurs.** `capability_propose SLUG TITRE` (dans `capability.sh`) possède la *forme* du ticket de puits humain — le `**Status:** ready-for-human`, le passage par `tracker_open_ticket` donc par le registre de [13], et la dédup contre `tracker_ids`. `retro__escalate` a été réécrit pour passer par lui : ce qui reste dans `retro.sh` est le préfixe de slug (`retro-`) et le corps qui dit pourquoi une règle n'est pas une leçon. Une capacité prend le préfixe `capability-<kind>-<nom>` et son propre corps. Un humain qui vide le puits lit donc **une** forme et distingue les deux par le titre, ce qui était le risque nommé.

  Conséquence dans `test/mutate.sh` : les deux entrées de [14] qui ancraient sur `**Status:** ready-for-human` et sur la ligne de dédup ont changé de **fichier** et pas de **test** — elles pointent maintenant `$CAPABILITY` et nomment toujours `test/retro.bats`. Rejouées, `ok` toutes les deux.

- **La barre est calculée, jamais demandée.** `capability_bar` rend `uncovered`, `recurrent` ou `below-bar n/at`. `uncovered` veut dire que **rien** dans l'inventaire ne répond à ce nom — ni lentille de `LENSES`, ni skill, ni agent, ni commande — et une seule occurrence suffit alors : un trou structurel ne se confirme pas par une deuxième nuit. `recurrent` est l'autre moitié : quelque chose répond déjà à ce nom, donc ce qui est demandé est un élargissement, donc il faut `CAPABILITY_RECUR_AT` occurrences **dans un run**.

  Le point de conception est là et pas ailleurs : demander au modèle « est-ce récurrent ? » est une garantie posée sur une phrase de prompt, et c'est précisément ce que `docs/frontiere-de-confiance.md` existe pour refuser. Le compteur est un fichier **append-only** (une ligne par observation, compté par `grep -c`) dans le répertoire secret de [14] — jamais un read-modify-write, parce que deux itérations partagent ce répertoire au-dessus de `MAX_PARALLEL=1` et qu'une observation perdue serait perdue exactement dans le cas dont la barre parle.

- **Réutiliser-avant-créer est une fonction, pas une consigne.** `capability_route NOM` parcourt l'inventaire dans l'ordre **lentille → skill → agent → commande → neuf** et **ne consulte pas le `kind` demandé**. C'est le cas qui fait la différence : un retro qui réclame une lentille `migrations` alors que le substrat livre un skill `migrations` demande quelque chose qui est déjà dans la maison, et répondre « créer une lentille » parce que le mot *lens* était dans la question est l'erreur que l'ordre existe pour empêcher. Le ticket porte le verdict en toutes lettres (« Extend what exists », « Reuse what exists », « Nothing here answers for »).

  L'inventaire est aussi mis **dans le prompt** du retro, et les deux moitiés ne sont pas redondantes : le prompt est l'atténuation (un modèle qui ne voit pas ce qui existe propose ce qui existe, chaque nuit), la route est la mesure.

- **Un `ready-for-human` ne se fait pas ramasser comme du travail.** Vérifié plutôt que supposé : `tracker_local_frontier` ne rend que des tickets `ready-for-agent`. Une proposition ne peut donc pas revenir en livraison la nuit suivante — ce qui serait l'auto-création par la porte d'à côté, avec un jour de décalage.

### La trouvaille : l'AC 4 était vraie pour l'arbre et fausse pour deux racines

Le commentaire de [31] dit que l'AC 4 est **vérifiée**. Elle l'est — *pour l'arbre dans lequel une itération est jugée*. Posée contre son critère plutôt que contre les cas qui l'ont écrite ([31] lui-même, [45] une deuxième fois), la question est « qu'est-ce qu'un `claude` frais charge comme capacité, et où ça vit ». Deux racines répondent oui et n'entrent dans aucun arbre que le scope-guard compare :

- **l'arbre principal.** Depuis [13] une itération est jugée dans un worktree jetable ; l'arbre principal n'y est pas, et une session déterminée le retrouve — `git worktree list` le nomme. C'est exactement la route que [14] avait trouvée pour `LEARNINGS.md`, sauf que **sa parade n'est pas disponible ici** : un index se sert depuis une copie que le pilote a prise avant toute session, une capacité est chargée par le binaire et il n'y a pas de copie à servir.
- **le `$HOME` de l'opérateur.** Atteignable *par conception* : `lenses_posture` passe `--setting-sources user` à dessein ([06]) — la direction de confiance est qu'une lentille hérite de qui a lancé le run et jamais de l'arbre jugé. Cette direction suppose que le `$HOME` de l'opérateur n'est pas écrivable par la session jugée. Il l'est. Et un hook dans `~/.claude/settings.json` est une **commande** qui tourne dans le process de la session suivante, ce qui est précisément le mode de panne que [31] avait sondé pour la version *dans l'arbre*.

Ce que ce ticket y met est un **témoin et pas un contrôle**, le même que [10] a posé sur `run.log` : `capability_witness` prend la ligne de base par le pilote avant qu'aucune session du run n'existe, `capability_drift` recompare à chaque itération, et une surface qui a bougé sort en `receipt_gap` sur le reçu **et** en ligne de journal. `find -L` et pas `find` : c'est la réserve que [31] avait laissée à ce ticket, et un témoin qui ne suivrait pas les liens serait aveugle à exactement ce cas-là.

Sondes (25/08/2026, dans `test/capability.bats`) : une session qui écrit `$HOME/.claude/agents/backdoor.md` finit `resolved` **et** le reçu nomme la surface ; la même chose dans le `.claude/agents` de l'arbre principal aussi ; une écriture à travers un skill lié est vue au niveau du module ; un run où rien n'a bougé ne dit rien du tout (c'est un canal d'événements, pas de couverture — la distinction que [45] a tracée entre `receipt_note` et `receipt_gap`).

**Les limites, écrites comme des choix et pas découvertes ensuite :**

1. Ça ne défait rien. Rien dans ce pack n'atteint hors du dépôt, et ce n'est pas ce ticket qui va commencer.
2. Ça ne **rougit** jamais. Un faux rouge sur le `$HOME` de l'opérateur arrêterait une nuit pour un fichier que l'opérateur a écrit lui-même.
3. La mesure tombe **après** le gate, donc la phase de lentilles de la *même* itération a déjà démarré un `claude` qui charge ce que la session vient d'écrire. C'est la limite jumelle de celle du scellement (« il détecte, il n'empêche pas ») et là où [06] avait une réponse en argv, il n'y en a pas ici : cette réponse serait de retirer `--setting-sources user`, c'est-à-dire de rendre la lentille aveugle à l'opérateur, ce que [06] a refusé exprès. Aucun propriétaire ; la limite est écrite.
4. `~/.claude.json` est **hors de la liste, exprès** : le binaire le réécrit à chaque démarrage, donc le surveiller signalerait une dérive à chaque itération, ce qui revient à n'en signaler aucune.
5. Le témoin est **par run** — une capacité installée entre deux runs est la ligne de base du suivant. Même asymétrie que `LEARNINGS.md` et `receipts/`, par le même bout.

### Ce que le ticket suivant hérite

- **`tracker_open_ticket` a un troisième producteur et toujours pas de verrou.** `tracker_local__next_nn` lit le répertoire, prend le max et écrit ; deux ouvertures concurrentes peuvent donc choisir le même `NN`. C'était déjà vrai avec `failures_reslice` et l'escalade de [14] — [42] a sondé deux re-slices voisins créant quatre tickets — et ce ticket ajoute un producteur de plus. La dédup de `capability_propose` a la même course : deux itérations peuvent lire `tracker_ids` avant que l'une des deux n'écrive, et ouvrir deux fois la même proposition. Rien ici ne l'aggrave au-delà de ça et rien ici ne le referme : le propriétaire naturel est [27] pour l'ambiguïté d'id et [13] pour la sérialisation. Noté dans les deux.
- **Une session hostile peut faire apparaître un ticket `ready-for-human` dans le tracker du projet cible.** Le texte du reçu passe par le retro, et le retro peut nommer une capacité ; le nom est réduit à `[a-z0-9-]{1,32}` et le `WHY` est ramené à une ligne et cité `> `, donc l'injection de bloc est neutralisée comme partout ailleurs et l'injection de prose ne l'est pas (même famille que [14] et [06]). Le plafond est borné par trois choses et il faut les dire : une proposition par itération, la dédup contre le tracker, et le fait qu'un `ready-for-human` n'entre pas dans la frontière. Le coût maximal est donc du bruit dans un puits humain, jamais du travail exécuté.
- **`CAPABILITY=off` n'éteint pas le témoin**, et c'est écrit dans `ralph.config.sh.example` : la clé décide si une capacité manquante devient un ticket, pas si l'apparition d'une capacité est dite. Un ticket qui voudrait un jour rendre le témoin optionnel doit répondre à « qu'est-ce qui reste pour tenir l'AC 4 hors de l'arbre » avant d'ajouter la clé.

### La seconde trouvaille, sortie d'une relecture et pas d'un test

**Le `kind` que le modèle répond était lu comme une *regex*.** `capability_kinds | grep -qx "$kind"` : sans `-F`, un `kind` de `.*` matche `lens`, passe le contrôle, et voyage dans le slug — donc la boucle écrit elle-même `issues/NN-capability-.*-sql.md`, un nom de fichier portant un métacaractère de glob, **choisi par une session** (le texte du reçu atteint le retro) et écrit par le seul canal que ni la restauration ni la quarantaine de `issues/` ne toucheront, puisque c'est la boucle qui l'a écrit. C'est la famille de défaut à laquelle [33] a consacré un ticket, atteinte par une porte neuve. Sondé le 25/08/2026 : `.*` et `s.ill` passaient tous les deux.

Correctif : une seule fonction, `capability_is_kind`, avec `grep -qxF`. Le test qui le tient est « a kind that is a pattern is not a kind », et il asserte deux choses — aucun ticket ouvert, **et** aucun nom de fichier du tracker ne porte de `*` : « aucun ticket ne matche ce préfixe » serait vrai aussi d'un ticket dont le nom est un motif qui ne matche rien.

### Pièges de harnais rencontrés

- **Un `$` non échappé dans la moitié droite d'une entrée de mutation reste `BROKEN` même sous `-Mstrict`** quand il est écrit dans une chaîne perl : `"$dir\/capability.seen"` a fait échouer la compilation avec `Global symbol "$dir" requires explicit package name`. Réponse : ancrer la mutation sur un fragment court (`grep -c "^$kind/$name\$"` → `grep -c "^"`) plutôt que réécrire une ligne entière.
- **`\\n` et `\\\\n` dans une moitié gauche perl ne matchent pas la même chose.** Le fichier contient `printf '%s\n'` — un backslash et un `n` — donc le motif perl doit porter `\\n` (deux caractères dans la chaîne bash entre apostrophes). Écrire `\\\\n` cherche *deux* backslashes et rend `DRIFTED` sans que rien n'ait bougé. C'est le jumeau du piège `$\n` que [14] avait consigné, par l'autre bout.
- **`$1` dans la moitié droite d'une mutation est le groupe de capture de perl, et ça sort en `VACUOUS` sur un test sain.** L'avertissement en tête de `test/mutate.sh` nomme `$1` à côté de `$(` et `$&`, et c'est exactement ce qui est arrivé : `grep -qx "$1"` non échappé devient `grep -qx ""`, qui refuse **tous** les kinds — donc la mutation « lit le kind comme un motif » rendait le contrôle plus strict au lieu de le retirer, le test restait vert, et le verdict accusait un test qui faisait son travail. Ni `-Mstrict` ni `bash -n` ne peuvent le voir : les deux moitiés sont légales. C'est le jumeau du `$\n` de [14] avec un symptôme inversé — `DRIFTED` là-bas, `VACUOUS` ici. La règle pratique : après avoir écrit une entrée, relire la moitié **droite** en se demandant ce que perl y voit, pas seulement ce que bash y verra.
- **Une sonde de témoin doit partir d'un état propre.** Le premier rejeu de la sonde de dérive est resté silencieux : la passe précédente avait laissé le fichier planté, donc la ligne de base l'incluait déjà. Un témoin qui compare deux instants ne peut pas être sondé deux fois de suite dans le même répertoire.

### Ce que la passe transversale du 26/08/2026 a fait de ce ticket

- **La contrainte laissée à [13]/[27] a maintenant un propriétaire : [47].** Elle avait été
  écrite dans les deux, et les deux sont `resolved` — donc aucun ticket ouvert de la file ne
  l'aurait lue. La passe a reproduit la course (`sondes/passe-26-08/p4.bats`) et a trouvé
  que les deux réparations existantes la manquent structurellement : le préflight tourne au
  démarrage du run, et la renumérotation de la quarantaine est désarmée par le registre de
  [13] précisément parce que c'est la boucle qui a écrit.

- **Les limites 3 et 5 se composent en un silence définitif, et c'est [46].** Le témoin
  tourne bien à chaque itération, mais son seul canal durable est le `receipt_gap`, et le
  reçu n'est émis que sur les quatre routes de [45] ; `capability__log` n'écrit que stdout.
  Sur un run qui s'arrête *sur* une itération retryée (`ITER_CAP`, `STERILE_K`, arrêt
  demandé, mur budget), la dérive n'atteint ni reçu ni journal — et comme le témoin est par
  run, le run suivant la reprend comme ligne de base. Sondé : `p2.bats` P2c, `p3.bats` P3b.
  `ralph.config.sh.example` dit de ce témoin qu'« il est sur chaque reçu » ; c'est la moitié
  documentaire du même écart.

- **Ce que la passe a confirmé conforme, et qu'il ne faut pas resonder** : l'AC 4 tient —
  `CAPABILITY=off` n'éteint pas le témoin (`p5.bats` P5c) — et la limite 3 est exacte : la
  lentille de la *même* itération voit bien le `$HOME/.claude/settings.json` que la session
  qu'elle juge vient d'écrire (`p5.bats` P5b).

- **Et la porte de `$HOME` mène plus loin que la moitié « capacité ».** `~/.gitconfig` porte
  `core.fsmonitor`, qui est un chemin de programme que git lance à chaque rafraîchissement
  d'index : 248 exécutions sur un run de deux itérations, dans l'arbre de processus du pack,
  run vert et silence complet. `capability_surfaces` ne le regarde pas, et c'est la bonne
  décision — ce n'est pas ce qu'un `claude` frais charge comme capacité. Le critère est
  autre et le propriétaire est [46].
- **[46], le 29/08/2026 : le témoin a maintenant un canal durable, et la limite 5 est refermée à moitié.** Ce ticket annonçait la dérive « sur le reçu et en ligne de journal » ; la seconde moitié était fausse (`capability__log` n'écrivait que stdout, et `run.log` n'est écrit que par le pilote), donc sur un run qui s'arrête **sur** une itération retryée la dérive n'atteignait aucun document — et le témoin étant par run, le run suivant la reprenait comme ligne de base. `capability_drift` **rend** maintenant ses lignes (`sujet<TAB>outcome<TAB>message`), l'itération les passe au pilote par son slot, et `loop__finish` en fait une ligne de `run.log` par surface, le sujet portant la surface. Le `receipt_gap` est inchangé. Ce que ça ne change pas : ça ne rougit rien et ça ne défait rien.

- **Et la porte que ce ticket a ouverte sans la mesurer entièrement a maintenant son propriétaire livré.** `--setting-sources user` suppose un `$HOME` que la session ne peut pas écrire ; ce ticket a montré qu'elle le peut, pour une *capacité*. [46] a mesuré l'autre moitié : un `core.fsmonitor` dans `~/.gitconfig` est une commande qui tourne dans le process **du pack** (252 exécutions sur un run de deux itérations). Celle-là **rougit** l'itération, contrairement à la capacité — la différence est ce que la clé décide, et elle est écrite au tableau de confiance.
