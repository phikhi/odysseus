# 31 — Le scellement est plus étroit que le critère qu'il énonce

**What to build:** Aligner `gate_sealed_paths` sur le critère que [24] a écrit à côté : **« un `claude` frais le lit au démarrage, ou le run suivant le source »**. La liste implémente trois fichiers ; le critère en couvre davantage. `CLAUDE.md` et `.mcp.json` sont lus par chaque spawn, ne sont couverts par aucun scellement, et un ticket peut les déclarer dans sa write-surface — ce qui rachète exactement le trou que `gate_is_sealed` a été placé avant la question de la surface pour refuser. Et un `RALPH_CONFIG` sous un autre nom n'est pas scellé du tout, alors que c'est le fichier que le run suivant source.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/ralph.config.sh.example`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`, `CONTEXT.md`, `README.md`

**Status:** ready-for-agent

- [ ] Le scellement est dérivé du critère, pas d'une liste de cas : ce qu'un `claude` frais lit au démarrage du projet (au minimum `CLAUDE.md`, `CLAUDE.local.md`, `.mcp.json`, `.claude/settings*.json`, et ce qui vit sous `.claude/` et prend effet au spawn — `agents/`, `commands/`, `skills/`, les scripts de hook référencés) plus ce que le run suivant source.
- [ ] Le fichier que le run suivant source est scellé **sous le nom qu'il porte réellement**, pas sous `.claude/ralph.config.sh` en dur : `RALPH_CONFIG` est une variable d'environnement, et un run lancé avec une autre valeur laisse sa vraie configuration ouverte à une write-surface.
- [ ] Le coût est mesuré et écrit avant d'élargir : un chemin scellé est un chemin qu'**aucun ticket ne peut plus livrer**. Sondé : un ticket qui déclare `.claude/settings.json` est rouge à chaque tentative, pour toujours. Élargir sans trancher ce point livre un blocage, pas une garantie.
- [ ] La distinction détecter/empêcher est écrite là où elle compte : le scellement rougit l'itération **après** que les branches du gate ont tourné dans l'arbre où le fichier était. Sondé.
- [ ] La ligne correspondante de `docs/frontiere-de-confiance.md` dit ce que le scellement tient, et à quel moment il tombe.

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
