# 17 — Langues (consigne + gate de langue + interact)

**What to build:** Le découplage `LANG_INTERACT` (parole à l'humain, HITL) / `LANG_ARTIFACT` (prose durable rédigée) : injection de la consigne dans les sessions fraîches, langue d'interaction côté HITL, et **gate de langue objectif** ajouté comme lentille (la consigne molle est doublée d'un check).

**Blocked by:** 05, 03

**Write-surface:** `.claude/lib/lang.sh`, `test/lang.bats`

**Status:** resolved

- [x] La consigne `LANG_ARTIFACT` est injectée dans le prompt de chaque session fraîche ; le code/identifiants (Standards) et les fichiers du pack en sont exclus.
- [x] Un gate de langue objectif (détection post-hoc, par-fichier, tolérant — langue dominante, termes étrangers cités OK) vérifie la prose rédigée ; échec → retry (patron scope-guard).
- [x] Une édition de fichier existant matche la **langue du fichier** plutôt que `LANG_ARTIFACT`.
- [x] `LANG_INTERACT` n'est utilisé que sur les surfaces HITL ; une session AFK ne l'emploie pas.

- **Contrainte posée par [06], livré le 30/07/2026 : la lentille Standards n'est pas le gate de langue, et il ne faut pas se laisser croire l'inverse.** Le registre de lentilles ajoute un regard *jugement* qui relit le diff et peut parfaitement remarquer qu'un commentaire est dans la mauvaise langue. Ça ne coche pas une seule ligne de ce ticket : une lentille est un modèle dont le verdict n'est vérifié par rien, un gate de langue est un check déterministe. La ligne « Prose durable en `LANG_ARTIFACT` » du tableau de frontière dit maintenant explicitement que ce ticket reste le propriétaire, précisément pour empêcher cette confusion — c'est la même erreur, un cran plus bas, que celle de lire une consigne du prompt comme une contrainte.

- **Ce que [06] offre en revanche, gratuitement : le patron.** Le gate de langue est un check objectif, donc une branche de la **phase objective** et pas une lentille — même patron que le scope-guard, code de retour dans un fichier. Si un jour il fallait qu'il soit configurable par lentille, `lenses_want_<nom>` / `lenses_rubric_<nom>` est le point d'extension et `gate_run` n'a pas à changer.

## Livré le 05/08/2026

`.claude/lib/lang.sh` : les listes de mots, le scoreur, le préflight, la consigne du prompt et `lang_check` — la quatrième branche de la phase objective, démarrée par `gate_run` après le scope-guard. `test/lang.bats` : 20 tests. 24 entrées dans `test/mutate.sh`. Un ticket ouvert en sondant : [39].

Sondes de run réel, dans un dépôt jetable, le 05/08/2026 : **1,2 Go de prose sur 201 fichiers** → 5 min, verdict juste, aucune explosion mémoire (le contenu est tubé dans le scoreur, jamais mis dans une variable — c'est ce que la sonde a fait corriger) ; un chemin portant **deux espaces** est jugé sous son vrai nom ; un `.md` **binaire** tombe dans « trop peu de prose » et pas dans un rouge ; une session qui **commite son propre travail** est jugée pareil, l'arbre venant de `gate_tree_snapshot` et pas de `HEAD`.

### Ce que le gate juge, et comment

**Des fichiers de prose, lus dans l'arbre que le gate juge.** `LANG_PROSE_PATHS` (globs, famille markdown par défaut) décide ce qui est de la prose : un `.md` est de la prose, un `.py` est du code qui en contient. Le contenu vient de `git cat-file -p "$tree:$file"` et jamais du disque — `TEST_CMD` écrit pendant que cette branche tourne, donc lire le fichier rendrait un tirage et pas un verdict ([29], une branche plus loin). Sondé : un `TEST_CMD` qui réécrit le fichier en anglais pendant le gate ne rachète pas une itération qui a livré du français.

**Un score de mots outils, avec une règle qui porte tout le reste : un mot revendiqué par deux langues ne vote pour personne.** `de`, `la`, `in` ne disent rien de la langue d'un texte ; une liste qui prétend le contraire fausse le score dans les deux sens. C'est cette règle qui permet d'écrire les listes généreusement au lieu de les rendre disjointes à la main — et c'est elle qui a son propre test, piloté par une table de test et non par les listes livrées.

**Le verdict est une part, pas une correspondance.** `hits(langue attendue) / mots reconnus ≥ LANG_CHECK_THRESHOLD` (0.80). C'est ce qui rend le ticket tenable : une doc anglaise qui cite `chien de garde` et une ligne de commande reste anglaise. Un gate qui exigerait l'inverse apprendrait à un projet à écrire de la documentation qui ne nomme rien.

**Sous `LANG_CHECK_MIN_HITS` (12) mots reconnus, le fichier n'est pas jugé — et il est compté.** Un stub, une table d'identifiants, une note de deux lignes ne sont la preuve d'aucune langue. Rougir là-dessus est le chemin le plus court vers un projet qui met `LANG_CHECK=off`.

**Une édition matche le fichier.** La langue attendue d'un fichier qui existait est la langue dominante de sa version dans l'arbre **de base**. Si cette version est elle-même indécidable, on retombe sur `LANG_ARTIFACT` — c'est la bonne réponse pour un stub qu'on remplit.

### Écarts de write-surface

Le ticket déclarait `.claude/lib/lang.sh` et `test/lang.bats`. Cinq fichiers de plus, chacun pour une raison :

- `.claude/lib/gate.sh` : la branche doit être démarrée par quelqu'un, et `gate_run` est ce quelqu'un. Plus `gate__report_lang`, plus l'appel à `lang_preflight` dans `gate_preflight`, plus **le renommage de `gate__under_path` en `gate_under_path`** (voir ci-dessous).
- `.claude/loop.sh` : la ligne de consigne en dur est remplacée par `$(lang_session_rules)`.
- `.claude/ralph.config.sh.example` : trois clés de plus (`LANG_CHECK_MIN_HITS`, `LANG_PROSE_PATHS`, `LANG_EXEMPT_PATHS`) et la réécriture des quatre existantes.
- `test/mutate.sh` : les entrées du ticket, plus le retour des trois entrées qui ancraient sur `gate__under_path`.
- `test/gate.bats` : « a branch of this gate can read the tree it is being judged on » comptait trois branches. Il y en a quatre.

Hors pack : `docs/frontiere-de-confiance.md`, `CONTEXT.md`, `README.md`.

### Décisions, et ce qu'elles coûtent

**Une branche objective, pas une lentille, et démarrée en dernier dans le fan.** Le dernier n'est pas cosmétique : `RALPH_GATE_VERDICTS` se lit toujours `tests=… typecheck=… scope=…`, donc les deux tests qui ancraient sur cette séquence exacte ne bougent pas.

**`gate__under_path` devient `gate_under_path`.** `LANG_EXEMPT_PATHS` nomme des chemins et pas des globs, exactement comme `GUARDED_PATHS`, donc il lui faut la lecture littérale de [33]. Un second appelant rend une fonction publique — c'est la règle du dépôt, et une copie de ces douze lignes dans `lang.sh` aurait été la deuxième définition d'une convention de découpage qui a déjà coûté un faux vert silencieux.

**Cinq refus au préflight, tous de la forme « la valeur qui éteint le contrôle sans le dire ».** La liste est écrite contre ce critère et pas contre les cas qui l'ont fait écrire — c'est la leçon de [31], et les deux derniers ne sont apparus que comme ça. Un `LANG_CHECK` qui n'est ni `on` ni `off` serait lu comme `off` ; un seuil qui n'est pas une fraction serait lu comme zéro et passerait tout ; un `LANG_PROSE_PATHS` vide ne laisserait rien à juger ; un `LANG_CHECK_MIN_HITS` à zéro diviserait par zéro sur le premier fichier sans un mot reconnaissable, donc une branche qui meurt sans verdict au lieu de juger ; un `LANG_ARTIFACT` sans liste de mots ne jugerait rien en rendant vert. Le dernier est le vrai piège de ce ticket : le pack a six langues et il y en a davantage, donc un projet japonais doit **déclarer** `LANG_CHECK=off` au lieu d'hériter d'un gate qui ne juge rien. Le prix est écrit : ce projet-là n'a pas de gate de langue, et la boucle le dit à chaque itération.

**Deux clés que le projet possède, et les deux s'annoncent.** `LANG_CHECK=off` par une ligne à chaque itération, sur le modèle de `no review lens ran (LENSES is empty)`. `LANG_EXEMPT_PATHS` par le **compte** de ce qu'elle a retiré, sur la même ligne que la couverture : c'est l'interrupteur qui pourrait tout éteindre (`.` suffirait), et l'interdire n'était pas une option — le pack lui-même est en anglais dans un projet de n'importe quelle langue, et un projet a le droit d'exempter la doc d'un vendor.

**La consigne du prompt sort du même module que le check.** `lang_session_rules` est appelé par `loop.sh`, et la phrase « c'est vérifié et pas seulement demandé » n'apparaît que si `LANG_CHECK` est `on`. C'est la correction structurelle du défaut que ce ticket referme : la consigne vivait dans `loop.sh` et le tableau de frontière disait « Rien », deux endroits sans raison de bouger ensemble.

### Ce que rien ne tient — écrit comme des choix

- **Les commentaires dans le code ne sont jugés par rien.** Il faudrait une syntaxe de commentaire par langage, et un extracteur qui se trompe rougit du code honnête. Aucun propriétaire ; la limite est dans `docs/frontiere-de-confiance.md` et dans le README, pas dans un silence.
- **Le détecteur est tolérant par construction**, donc une session qui saupoudre des mots outils passe. C'est un contrôle contre la **dérive** — une session fraîche qui rédige dans la langue par défaut du modèle, ce qui est le cas qui arrive — et pas contre un adversaire.
- **La prose tombée dans la zone ignorée** n'est pas jugée, comme tout le reste de cette zone.
- **Le code du pack n'est pas scellé** : un ticket peut réécrire `lang.sh` comme il peut réécrire `gate.sh`. À dessein, et déjà dans le tableau.
- **Un nom de fichier non-ASCII n'est pas jugé — et ce n'est pas le défaut de ce gate.** Sondé en le lançant sur des noms réels : `git diff-tree --name-only` C-quote tout ce qui sort de l'ASCII, donc `docs/spécification.md` arrive sous la forme `"docs/sp\303\251cification.md"`, que `git cat-file`, `git add` et `rm` refusent tous les trois. `lang_check` reconnaît la forme, ne juge pas, et **compte**. Le reste de la trouvaille — le scope-guard qui rougit pour une raison inactionnable, le commit durable qui laisse tomber le fichier en silence, le rollback qui annonce avoir retiré un fichier toujours là — est [39].
- Une dérive en deux temps a été regardée et ne marche pas : passer un fichier de `fr` à `en` demande de garder ≥ 80 % de `fr` à chaque itération, ce qui ne converge pas. Dans l'autre sens — vider un fichier jusqu'à l'indécidable puis le réécrire — la langue attendue retombe sur `LANG_ARTIFACT`, c'est-à-dire sur ce que le projet a déclaré : la seule direction où « blanchir » mène là où la règle voulait aller de toute façon.

### Le piège, pour qui écrira une mutation de cette forme

La première entrée pour « la langue attendue vient de l'arbre *d'avant* la session » remplaçait `$base:$file` par `HEAD:$file`. Elle est revenue `VACUOUS`, et le test était bon : **une session ne commite pas**, donc au moment du gate `HEAD` porte exactement ce que l'arbre de base porte. Les deux sources ne diffèrent que dans la tête de qui écrit la mutation. Ce que le contrôlé écrit, c'est l'arbre de travail — `cat "$file"` — et c'est la seule substitution qui retire quelque chose. La leçon est dans `docs/frontiere-de-confiance.md`.

### Contraintes posées ailleurs

- **[16] — la boucle humaine hérite `LANG_INTERACT`.** Aucun fichier du chemin AFK ne lit la clé, et ce qui le vérifie est le prompt réellement envoyé (`test/lang.bats`, « an AFK session is never told LANG_INTERACT »), plus un test structurel sur `loop.sh`. `human-loop.sh` est l'autre point d'entrée et la clé lui appartient : un lib *partagé* qui la lirait remettrait la langue d'un humain dans une session que personne ne regarde. Le test structurel ne nomme que `loop.sh` exprès, pour ne pas interdire un lib HITL à [16].
- **[19] — l'installeur.** `LANG_CHECK` est marqué FORCED CONFIRMATION dans `ralph.config.sh.example` : c'est l'installeur qui doit faire trancher un humain, et lui faire écrire `off` en connaissance de cause pour un projet dont la langue n'est pas dans les six. Même famille que la confirmation forcée sur `TEST_CMD`.
- **[10] — le reçu d'audit** a une quatrième branche à lire dans `RALPH_GATE_VERDICTS` (`lang=green|red`) et une ligne de couverture de plus à garder (`the language gate checked N …`).
- **Ajouter une langue** au pack, si le besoin vient : `lang_words_<code>` plus le code dans `lang_codes`, mots ASCII sans accent (le tokeniseur travaille en octets sous `LC_ALL=C`).
