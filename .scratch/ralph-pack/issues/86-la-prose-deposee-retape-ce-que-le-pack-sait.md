# 86 — La prose que l'installeur dépose retape ce que le pack sait

**What to build:** Que le bloc `CLAUDE.md` que `init.sh` écrit dans le projet cible demande au pack ce qu'il affirme — la liste scellée à `gate_sealed_paths`, la forme du tracker au backend choisi — au lieu de la retaper.

**Blocked by:** 87

**Write-surface:** `init.sh`, `test/install.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] La phrase du bloc qui énumère les chemins scellés est **dérivée de `gate_sealed_paths`**, avec le même geste que `playthrough.sh` fait déjà dans son heredoc de prompt. Un chemin ajouté à la liste apparaît dans le bloc sans que personne édite `init.sh`.
- [ ] Un test compare les deux ensembles sur un install réel et rougit sur un écart, dans les **deux** directions — un scellé absent du bloc, et un chemin du bloc que le pack ne scelle pas. Une seule direction est la faute que `test/smoke.bats` documente sur la surface de configuration.
- [ ] Le paragraphe « The tracker » dépend du `TRACKER_BACKEND` que l'install vient de retenir : un projet installé sur `github`/`gitlab` ne reçoit pas une description de fichiers markdown sous `.scratch/<feature>/`, et `.scratch/<feature>/issues` n'est pas provisionné pour un backend qui ne l'utilisera jamais.
- [ ] Ce que le bloc dit du tracker est **la même phrase** que celle que `init_preflight` imprime déjà à la console pour ce backend, ou dérivé du même endroit — deux rédactions du même fait dérivent, et celle que personne ne relit est celle qui ment.
- [ ] Une entrée de mutation par garantie livrée, avec le témoin appairé.
- [ ] La ligne du tableau de `docs/frontiere-de-confiance.md` — « Ce que l'installeur déposera dans le **prochain** projet » — dit ce que le bloc affirme, ce qui le tient, et ce qui reste seulement dit.

## Comments

- **Ordre validé par Philippe le 14/09/2026** : **[87] → [86] → [88] → [89]**.
  Le critère est celui d'habitude — minimiser la reprise, jamais l'urgence. [87]
  devant parce qu'il ne touche que `test/` et qu'il pose le filet de source sous
  le heredoc de prose que [86] va réécrire ; [88] derrière [86] parce qu'il
  généralise une forme dont [86] livre le précédent ; [89] en dernier, sans arête.

- **Ouvert par la passe transversale du 14/09/2026** (`../passe-transversale-14-09.md`,
  §1 et §2). Sonde : `../sondes/passe-14-09/q1-la-prose-deposee-retape-la-liste-scellee.bats`.

- **Le fait qui rend ce ticket non cosmétique, et il est mesuré :**
  `loop_session_prompt` ne nomme **aucun** chemin scellé. Dans un projet installé,
  le bloc que `init_claude_block` écrit est *tout* ce qu'une session de livraison
  apprend de ce qu'aucune write-surface ne peut couvrir.

- **L'écart, mesuré sur un install réel dans un dépôt git neuf.**
  `gate_sealed_paths` rend douze chemins ; le bloc en nomme cinq tels quels,
  trois par leur basename nu (`commands`, `skills`, `hooks`) et quatre pas du tout :
  `.claude/settings.local.json`, `CLAUDE.local.md`, `LEARNINGS.md`,
  `learning-records`. Les deux derniers sont scellés par [14] **précisément parce
  qu'ils sont inlinés dans le prompt de chaque session suivante** — une session qui
  écrirait l'index écrirait le prompt de toutes celles d'après — et rien ne le dit
  à la session à qui on le demande.

- **La liste bouge, et c'est ce qui fait la dérive.** Trois entrées à [24], douze
  à [31]. Le bloc est *managed* (`init__merge_block` le remplace à chaque
  réinstallation), donc le logement de la réparation existe déjà.

- **Le précédent est dans le pack, trois fichiers plus loin.** `playthrough.sh`
  met `$(gate_sealed_paths)` dans son heredoc de prompt. Rien à inventer.

- **§2 : l'installeur *sait* et le dit au mauvais endroit.** Au même run,
  `init_preflight` lit `TRACKER_BACKEND`, reconnaît un backend distant et imprime
  la phrase juste — `TRACKER_REPO`, `TRACKER_TOKEN_CMD`, `WAIT_CI`, et ce que le
  backend distant n'achète pas. Il le dit **une fois, à l'humain qui regarde**, et
  écrit l'autre version **dans le fichier que chaque session lira toutes les
  nuits**. C'est la forme du constat de [64] prise par l'autre bout : huit fois sur
  une console, zéro fois là où ça compte. Mesuré avec `TRACKER_BACKEND=github` :
  le paragraphe markdown est identique, et `.scratch/demo/issues` est provisionné.
  `init_claude_block` ne prend que `$feature`, donc la phrase **ne peut pas**
  varier.

- **Ce que ce ticket ne répare pas, et pourquoi il faut l'écrire.** Ce n'est pas
  une garantie qui manque : le scellement tient quoi qu'on dise à la session. Ce
  qui manque est l'autre moitié de la doctrine de ce dépôt — *dire, puis tenir* —
  et son coût est une itération rouge sur un chemin dont la session avait lu la
  liste et où ce chemin n'était pas. L'AC est donc sur la **dérivation**, pas sur
  un contrôle nouveau.

- **Contrainte de forme, et elle est en tension avec la précédente.** Le bloc est
  de la **prose en anglais** déposée chez quelqu'un d'autre, pas un listing. Une
  dérivation qui cracherait douze lignes de chemins à la place d'une phrase serait
  juste et illisible. La bonne forme est probablement une phrase qui introduit une
  liste dérivée, comme `playthrough.sh` le fait ; ce qui compte est qu'aucun
  **nom de chemin** ne soit tapé dans `init.sh`.

- **Piège de heredoc, et c'est pour ça que [87] passe devant.** Le bloc est un
  `cat <<BLOCK` **non cité** : y injecter `$(gate_sealed_paths)` marche, et un
  backtick de prose ajouté au même endroit est une substitution de commande
  silencieuse — mesuré par la passe, l'installeur sort en 0 et le projet garde
  « The conventions are in . » pour toujours. [87] pose les quatre règles de source
  sur `init.sh` ; livré devant, il est le filet sous cette réécriture.

- **Ce que le paragraphe du tracker doit continuer de dire, quel que soit le
  backend.** Les deux phrases suivantes du bloc sont vraies des trois backends et
  n'ont rien à voir avec le format de stockage : « **The loop marks tickets, never
  the session** » et la restauration depuis l'instantané pris avant la session.
  Depuis [73] le transport de cet instantané est celui du backend — un tree object
  sur `local`, un listing d'issues sur une forge — donc la phrase tient. Ne pas la
  faire varier en même temps que le reste.

- **Piège de mise en scène.** `test/install.bats` installe dans un dépôt neuf avec
  toutes les confirmations forcées passées par l'environnement (`run_init`). Un
  test qui ajoute `TRACKER_BACKEND=github` doit aussi donner `TRACKER_REPO` et
  `TRACKER_TOKEN_CMD`, sans quoi il mesure le refus de préflight et pas le bloc.
  Et `init_preflight` **n'est pas fatal** sur une configuration douteuse : le pack
  est installé de toute façon, ce qui est délibéré ([19]) — donc asserter sur le
  contenu du `CLAUDE.md` déposé, jamais sur le seul code de sortie.

- **Angle voisin, nommé ici plutôt que laissé à trouver** : `.claude/skills` est
  scellé et il est, dans ce dépôt, un jeu de liens symboliques vers `.agents/skills/`
  — le commentaire de `gate_sealed_paths` porte déjà la réserve (*« a write
  **through** a link lands outside the sealed path »*). Ce que [19] a changé est la
  portée : `.agents/skills/` est maintenant ce qui part dans le prochain projet
  (`cp -RL` au dépôt, `.agents/skills/` dans le `files` de `package.json`). Une
  phrase dans la ligne du tableau, pas un ticket.

- **Ce que [87] laisse sous ce ticket, livré le 15/09/2026.** Le filet existe : les
  quatre règles de source de `test/layering.bats` lisent `init.sh` comme elles
  lisent `loop.sh`, sur une zone dérivée et plus sur un glob. Trois conséquences
  concrètes pour la réécriture, et les trois sont des rougeurs à `bash test/run.sh`
  et pas des conseils :
  - `layering_heredoc_prose` couvre maintenant le `cat <<BLOCK` de
    `init_claude_block`. Une backtick de prose non échappée y est **rouge** — c'est
    le filet que ce ticket attendait.
  - `layering_privates` donne à `init.sh` le préfixe `init_`. La dérivation doit
    donc passer par un nom **public** du pack : `gate_sealed_paths`, jamais
    `gate__sealed_config`. Ce n'est pas une privation — les douze chemins sortent
    du public, qui appelle le privé pour le nom réel de `RALPH_CONFIG`.
  - `layering_masked_status` lit `init.sh` aussi. `local paths="$(gate_sealed_paths)"`
    est **rouge** : deux instructions, `local paths` puis `paths="$(…)" || …`, comme
    partout ailleurs dans le pack. C'est exactement la forme qu'une dérivation
    appelle, donc elle se rencontre au premier essai.
- **Et ce que [87] ne couvre pas, alors que ce ticket va y toucher.** La règle
  s'arrête au **corps d'un heredoc**. L'AC 4 demande que le paragraphe du tracker
  soit la même phrase que celle que `init_preflight` imprime à la console — or
  cette phrase-là vit dans un `init__note "…"`, une chaîne entre **guillemets
  doubles**, où une backtick non échappée est une substitution de commande que rien
  ne voit : mesuré sur un vrai run, l'installeur sort en 0 et l'opérateur lit une
  phrase trouée. Propriétaire : **[90]**. En attendant, une phrase partagée entre
  le heredoc et la console est gardée d'un côté seulement, et le côté non gardé est
  celui où le pack a le plus de backticks (30 sites dans `init.sh`).
- **Rien à maintenir dans `test/layering.bats` en réécrivant le bloc.** Les
  violations plantées dans la copie d'`init.sh` sont **ajoutées en fin de fichier**
  et non éditées dans la prose de `init_claude_block`, précisément pour que cette
  réécriture-ci ne les fasse pas dériver.
