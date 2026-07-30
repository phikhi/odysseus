# 31 — Le scellement est plus étroit que le critère qu'il énonce

**What to build:** Aligner `gate_sealed_paths` sur le critère que [24] a écrit à côté : **« un `claude` frais le lit au démarrage, ou le run suivant le source »**. La liste implémente trois fichiers ; le critère en couvre davantage. `CLAUDE.md` et `.mcp.json` sont lus par chaque spawn, ne sont couverts par aucun scellement, et un ticket peut les déclarer dans sa write-surface — ce qui rachète exactement le trou que `gate_is_sealed` a été placé avant la question de la surface pour refuser. Et un `RALPH_CONFIG` sous un autre nom n'est pas scellé du tout, alors que c'est le fichier que le run suivant source.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/lenses.sh`, `.claude/ralph.config.sh.example`, `test/gate.bats`, `test/lenses.bats`, `test/contract-claude.bats`, `test/helpers/claude-contract.bash`, `test/helpers/harness.bash`, `test/helpers/shims/claude`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`, `CONTEXT.md`, `README.md`

**Status:** resolved

- [x] Le scellement est dérivé du critère, pas d'une liste de cas : ce qu'un `claude` frais lit au démarrage du projet (au minimum `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.claude/settings*.json`, et ce qui vit sous `.claude/` et prend effet au spawn — `agents/`, `commands/`, `skills/`, les scripts de hook référencés) plus ce que le run suivant source.
- [x] Le fichier que le run suivant source est scellé **sous le nom qu'il porte réellement**, pas sous `.claude/ralph.config.sh` en dur : `RALPH_CONFIG` est une variable d'environnement, et un run lancé avec une autre valeur laisse sa vraie configuration ouverte à une write-surface.
- [x] Le coût est mesuré et écrit avant d'élargir : un chemin scellé est un chemin qu'**aucun ticket ne peut plus livrer**. Sondé : un ticket qui déclare `.claude/settings.json` est rouge à chaque tentative, pour toujours. Élargir sans trancher ce point livre un blocage, pas une garantie.
- [x] La distinction détecter/empêcher est écrite là où elle compte : le scellement rougit l'itération **après** que les branches du gate ont tourné dans l'arbre où le fichier était. Sondé.
- [x] La ligne correspondante de `docs/frontiere-de-confiance.md` dit ce que le scellement tient, et à quel moment il tombe.

## Comments

- **Origine : passe transversale 24→26, le 30/07/2026.** Trouvé en relisant la liste de [24] contre le critère de [24], plutôt que contre les cas qui l'avaient fait écrire. Quatre sondes.

  *Sonde 3 — `.mcp.json` et `CLAUDE.md`, déclarés par le ticket, hérités par la session suivante, et commités.* Surface `src/alpha.txt`, `.mcp.json`, `CLAUDE.md` ; la première session dépose un serveur MCP (`command: sh -c …`) et un `CLAUDE.md` qui dit d'ignorer la règle de write-surface ; le fake enregistre à chaque spawn ce qu'il voit. Deux tickets :

  ```
  exit=0   01-alpha=resolved   02-beta=resolved
  inherited: session 2 saw .mcp.json | session 2 read the injected CLAUDE.md
  commit: 01-alpha: iteration delivered (gate green)   .mcp.json  CLAUDE.md  src/alpha.txt
  ```

  Aucune plainte de scellement. La session suivante lit les deux fichiers, et la boucle les a **commités** — donc tous les runs suivants les héritent aussi. C'est le cas armé de [24] à un chemin près, en pire sur un point : `settings.local.json` était ignoré et transitoire, ceux-là entrent dans l'historique du projet.

  Ce que ça permet n'est pas le même dans les deux cas, et il faut le dire pour ne pas surestimer : un `CLAUDE.md` hostile est une instruction, donc il ne peut pas battre un contrôle qui est du code — c'est la doctrine de ce dépôt, une règle de prompt n'est pas une garantie. Un `.mcp.json` hostile est autre chose : un serveur MCP est une **commande** que le spawn lance. **Non vérifié contre le vrai binaire** : `claude -p` en `bypassPermissions` charge-t-il les serveurs de projet sans approbation (`enableAllProjectMcpServers`, ou l'approbation stockée) ? C'est la question à sonder sous `RALPH_REAL_CLAUDE=1` avant de décider si ce chemin est une exécution de commande à chaque itération ou seulement un fichier inerte. La réponse change la gravité, pas le fait.

  *Sonde 3b — le même fichier quand le projet l'ignore.* `.mcp.json` dans le `.gitignore`, la session l'écrit hors de sa surface :

  ```
  exit=0  status=resolved   .mcp.json exists: yes
  ralph: gate: 01-alpha: nothing in this gate judged 1 ignored path(s): .mcp.json
  ```

  Invisible au scope-guard, invisible au rollback, seulement nommé par la ligne de zone de [24]. Un `.mcp.json` gitignoré est une configuration courante (serveurs locaux à la machine), donc ce n'est pas un cas de laboratoire.

  *Sonde 4 — le fichier que le run suivant source, sous un autre nom.* `RALPH_CONFIG=.claude/ralph.prod.sh`, ticket déclarant `.claude/ralph.prod.sh`, session qui y ajoute `TEST_CMD='true'` :

  ```
  exit=0  status=resolved
  sealed complaint: 0
  le run suivant sourcerait TEST_CMD='true'
  ```

  C'est le trou de [24] rouvert par une clé d'environnement. `gate_sealed_paths` nomme `.claude/ralph.config.sh` en dur ; `loop.sh` lit `RALPH_CONFIG="${RALPH_CONFIG:-$RALPH_DIR/ralph.config.sh}"`. Le préflight refuse un `TEST_CMD` vide ; `TEST_CMD=true` passe tous les contrôles du pack, et la seule chose qui l'attraperait est la confirmation forcée de l'installeur ([19]) — qui ne tourne pas au démarrage d'un run.

  *Sonde 9r — le scellement détecte, il n'empêche pas.* Un `TEST_CMD` qui rapporte ce qu'il voit, une session qui dépose `.claude/settings.local.json` :

  ```
  la branche du gate a vu : settings.local.json
  ralph: gate: 01-alpha: tests=green typecheck=green scope=red
  ```

  L'ordre est celui-là et il ne peut pas être autre : les branches tournent dans l'arbre que la session a laissé, le scellement ne rougit qu'à l'agrégation, le rollback n'efface qu'après. Aujourd'hui la branche est du bash et ça ne coûte rien. Le jour où une branche est une lentille [06], c'est un `claude` qui démarre dans cet arbre — sondé pour `CLAUDE.md` et `.mcp.json`, verdict vert de bout en bout :

  ```
  la branche du gate a vu : CLAUDE.md  .mcp.json
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green
  ```

  Le juge configuré par le jugé. Le test de [24] (« a session cannot configure the harness that judges the next one ») prouve l'absence d'héritage vers la session de l'**itération suivante** ; il ne dit rien d'une session spawnée **dans** le gate, qui n'existait pas encore quand il a été écrit.

- **Le coût d'élargir, sondé, et c'est la vraie difficulté du ticket.** Le scellement est inconditionnel : aucune write-surface ne peut le couvrir, quoi que dise `GUARDED_PATHS`. Donc un chemin scellé est un chemin que la boucle ne peut plus livrer. Sondé sur `.claude/settings.json`, qui est du **code du pack** (déclaré dans la write-surface de [01], déposé dans les projets cibles) :

  ```
  exit=4  status=ready-for-agent  failures=[1]
    wrote .claude/settings.json, which configures the harness itself — no write-surface may cover it
  ```

  Rouge à chaque tentative, définitivement. Aucun ticket de ce dépôt ne pourra plus toucher la posture headless du pack par la boucle. C'est déjà vrai et assumé pour ces trois fichiers ; ça devient une décision à prendre pour chaque chemin ajouté. Deux exemples qui font mal :

  - **`CLAUDE.md` de ce dépôt est la definition of done.** La sceller interdit à la boucle de modifier ses propres règles de livraison — ce qui est peut-être exactement ce qu'on veut, et qui doit être écrit comme un choix.
  - **`.claude/skills/`** est ici un jeu de liens symboliques vers `.agents/`. Écrire *à travers* un lien atterrit dans `.agents/`, qui n'est ni gardé ni scellé : sceller la cible et pas le lien ne prouve rien. À vérifier avant d'annoncer la couverture.

  La piste qui évite l'impasse : distinguer **scellé** (aucune surface ne peut le couvrir) de **neutralisé au spawn** (le pack impose sa valeur, comme `DISABLE_AUTO_COMPACT`). [24] a déroulé puis écarté la neutralisation pour de bonnes raisons — elle déplace le poison au lieu de l'effacer, et son placement était un piège (une restauration après le snapshot `base` devient un delta imputé à la session). Ces raisons valent pour la configuration du harnais ; elles ne valent pas forcément pour un `--mcp-config` explicite au spawn, qui est de l'argv et non un fichier. À trancher dans le ticket, pas ici.

- **Contrainte pour [06], et c'est un ordre de livraison.** Une lentille est un `claude` spawné dans l'arbre du jugé. Tant que ce ticket n'est pas livré, une session peut écrire, **dans sa propre write-surface déclarée**, un fichier que le `claude` de la lentille lira au démarrage. Le scellement ne l'attrape pas, et même quand il l'attrapera, il l'attrapera après. Ce n'est pas la même remarque que celle que [25] avait posée à [06] (la fenêtre du gate s'allonge) : celle-là dit que la fenêtre du gate est un endroit où le jugé écrit pour son juge.

- **Ce que [29] (livré le 30/07/2026) ajoute à l'enjeu de ce ticket : le scellement de `ralph.config.sh` est ce qui rend les écritures du gate acceptables.** L'arbre jugé est maintenant pris avant le fan, donc ce que `TEST_CMD` et `TYPECHECK_CMD` écrivent pendant qu'ils tournent n'est plus imputé à la session — mais n'est plus jugé du tout, ni défait par le rollback : la boucle se contente de le nommer, et l'artefact entre dans le `base` de l'itération suivante. L'argument qui rend ça tenable est exactement une ligne de ce ticket : ces deux commandes viennent d'un fichier **scellé**, donc ce qu'elles écrivent est aussi digne de confiance que la configuration du harnais. Un `RALPH_CONFIG` sous un autre nom casse la chaîne des deux côtés à la fois : une session y pose le `TEST_CMD` du run suivant, et ce que ce `TEST_CMD` écrira ne sera ni jugé ni défait par personne. À citer dans les critères d'acceptation : ce n'est plus seulement « une session peut choisir le gate du run suivant », c'est « une session peut choisir une commande dont les écritures sont structurellement hors de portée de tous les contrôles ».

- **Contrainte pour [19].** L'installeur écrit la configuration du projet cible et ne peut donc pas déclarer les chemins scellés dans sa write-surface — sondé ci-dessus. Il devra soit passer par un chemin non scellé (`ralph.config.sh.example`, puis une copie faite par un humain), soit être le seul composant qui tourne hors de la boucle. À écrire dans son ticket dans les deux cas.

- **Contrainte pour [18].** Un backend distant peut vouloir sa propre configuration (jeton, endpoint). Tout fichier de ce genre que le run suivant source tombe sous ce ticket, et pas sous le sien.

- **[06] est livré (30/07/2026) : la contrainte écrite plus haut n'est plus un ordre de livraison, c'est une situation en cours.** Une branche du gate **est** maintenant un `claude`. Ce que ça change pour ce ticket, en trois points :

  - **Le scénario sondé ici est armé.** Une session dont la write-surface déclare `CLAUDE.md` ou `.mcp.json` obtient un vert de bout en bout, et la lentille démarre dans cet arbre. Ce que [06] a construit borne les **dégâts** (jeu d'outils en lecture seule, et ce que la lentille écrit est mesuré puis remis) mais ne borne pas l'**influence** : un `CLAUDE.md` déposé par le jugé est lu par le juge au démarrage, et rien ne l'en empêche ni ne le détecte. C'est la même famille que l'injection par le diff, qui est désormais une ligne du tableau de frontière.
  - **La question précise qui attend le vrai binaire, et pourquoi elle décide de la forme du correctif.** `--tools` est documenté comme portant sur « the built-in set ». Un serveur MCP de projet n'est pas built-in. Donc : **`claude -p --dangerously-skip-permissions --tools Read,Grep,Glob` charge-t-il les serveurs d'un `.mcp.json` de projet, et si oui, leurs outils survivent-ils à `--tools` ?** Si la réponse est oui, le jeu d'outils en lecture seule d'une lentille est contournable par un fichier qu'une session peut déclarer dans sa surface, et la moitié *empêcher* de [06] tombe — le confinement (mesurer + défaire) tient toujours, mais il devient le seul rempart. Le fake ne peut pas répondre : il rend `mcp_servers: []`. Ça coûte du quota, donc c'est un opt-in humain.
  - **Ce que la réponse implique pour le périmètre de ce ticket.** Si les outils MCP survivent, sceller `.mcp.json` ne suffit pas non plus : le scellement détecte à l'agrégation, donc *après* que la lentille a tourné. Il faudrait la piste déjà notée ici — **neutraliser au spawn** plutôt que sceller — et pour un `claude` de lentille c'est de l'argv, pas un fichier : `--strict-mcp-config` ou un `--mcp-config` vide explicite. C'est le cas où la distinction *scellé / neutralisé au spawn* cesse d'être une élégance et devient la seule option qui tombe avant ce qu'elle protège. À trancher ici avec la réponse en main, pas avant.

## Ce que la livraison a trouvé — 30/07/2026

**La question MCP a reçu sa réponse, et elle est mauvaise.** Opt-in `RALPH_REAL_CLAUDE=1` joué le 30/07/2026. Trois sondes, parce que les deux premières n'étaient pas concluantes et qu'il fallait le voir :

- *v1/v2 — session à un tour.* `mcp_servers: [{"name":"probe","status":"pending"}]`, aucun outil `mcp__` dans le flux, le modèle répond `MCP-TOOL-ABSENT`. **Non concluant** : le témoin en posture nue disait exactement pareil, avec `num_turns: 1`. `system/init` est un instantané à t=0 et une session `-p` qui répond tout de suite part avant la fin du handshake. Une sonde à un tour aurait rendu un faux vert, et c'est la leçon la plus transférable du ticket.
- *v3 — cinq tours, comme une lentille qui lit un diff.* En posture lentille (`--tools Read,Grep,Glob`) :

  ```
  "type":"tool_use","name":"mcp__probe__rogue_write"
  verdict du modèle : VERDICT MCP-TOOL-PRESENT
  ```

  Donc **`--tools` ne retire pas les outils d'un serveur MCP de projet**. Et dans *toutes* les sondes, y compris à un tour et y compris sous `--tools`, la **commande du serveur est lancée** — marqueur écrit par le process. Un `.mcp.json` n'est pas un fichier inerte, c'est une exécution de commande à chaque spawn.
- *v4 — le correctif.* Même fixture, `--strict-mcp-config` en plus : serveur **pas lancé**, zéro `mcp__`, `ABSENT`.

**Et une sonde que le ticket n'avait pas prévue, qui est le vrai trou.** Un `.claude/settings.json` de projet peut déclarer un **hook**, et un hook est une *commande*. Sondé avec un `PreToolUse` sur `Read` : sous la posture de lentille de [06], le marqueur est écrit — le hook tourne dans le process du juge, au premier appel d'outil. `--tools` ne l'a jamais couvert : un hook n'est pas un outil. `--setting-sources user` le referme (marqueur absent, `Read` appelé dans les deux cas, donc le témoin est valide). Le même flag referme le canal `CLAUDE.md` : une lentille obéissait à une instruction marqueur déposée dans l'arbre du jugé (3 mentions → 0).

**Le cas courant n'était pas une attaque, et c'est ce qui a élargi le ticket.** Un projet qui commite son propre `.mcp.json` et ses propres hooks — un projet ordinaire — faisait exécuter ses commandes dans chaque session de lentille, sans qu'aucune session ait rien fait de mal. Le test livré est monté comme ça, pas comme une session hostile.

**Décisions prises, avec leur coût.**

1. **Deux mécanismes pour les mêmes fichiers, et ils couvrent deux fenêtres différentes.** Le scellement pour la durabilité (fenêtre « session suivante » : détecter suffit, le rollback efface avant tout nouveau spawn) ; la **posture de spawn** (`lenses_posture`) pour la fenêtre du gate, où détecter est trop tard. Ce n'est pas une ceinture et des bretelles : aucun des deux ne couvre la fenêtre de l'autre.
2. **`CLAUDE.md` et `CLAUDE.local.md` sont scellés**, décision humaine prise en connaissance du coût : la boucle n'éditera plus jamais les règles qui la jugent, definition of done de ce dépôt comprise. **Contrainte écrite dans [14]** : sa promotion autonome de leçon en guidance `CLAUDE.md` doit passer par `LEARNINGS.md` ou escalader.
3. **`.claude/agents`, `commands`, `skills`, `hooks` sont scellés** — coût nul, l'AC de [15] refusant déjà toute création de capacité en AFK. Réserve écrite et non refermée : ici `.claude/skills` est un jeu de liens symboliques, donc écrire *à travers* un lien atterrit hors du chemin scellé. Le scope-guard voit cette écriture, le scellement non.
4. **Le `RALPH_CONFIG` réel est scellé sous son nom**, et le défaut reste dans la liste : un `RALPH_CONFIG` pointant hors de l'arbre ne doit pas déceller l'ordinaire.

**Deux pièges rencontrés, qui valent pour le prochain.**

- **Le trap `ERR` du runner voit un `cat` échouer avant le `return 0` qui suit.** Un helper de test dont la réponse *attendue* est « le fichier n'existe pas » doit écrire `|| true`, pas `; return 0` : sinon la ligne d'échec du trap atterrit dans le `$output` que l'appelant est en train d'asserter, et le test rougit en accusant la mauvaise chose.
- **Une mutation VACUOUS a révélé un test qui passait pour la mauvaise raison.** La normalisation de chemin (`pwd -P`) n'était pas exercée : le harnais résout déjà son tmpdir, donc le `RALPH_CONFIG` du test était physique et la ligne ne portait rien. Corrigé en faisant passer le run par un **lien symbolique** — un projet sous un chemin symlinké est le cas ordinaire sur un mac, et sans ça le scellement du config aurait échoué **ouvert** en production tout en paraissant couvert. Au passage, la normalisation côté racine a été **retirée** plutôt que documentée : `git rev-parse --show-toplevel` répond déjà un chemin physique, donc c'était une ligne qu'aucune mutation ne pouvait faire rougir.

**Ce qui reste ouvert après ce ticket, et n'a pas de propriétaire.** La posture ferme ce qui s'*exécute* ou se lit *au démarrage*. Elle ne ferme rien de ce que la lentille va lire elle-même : les rubriques l'envoient dans `CONTEXT.md`, `docs/adr/` et le code autour du diff avec ses propres `Read`/`Grep`. C'est le canal d'influence que [06] a déclaré sans propriétaire, et il est inchangé.
