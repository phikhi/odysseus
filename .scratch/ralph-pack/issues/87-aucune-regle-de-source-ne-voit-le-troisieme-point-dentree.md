# 87 — Aucune des quatre règles de source ne voit le troisième point d'entrée

**What to build:** Que les quatre règles de `test/layering.bats` jugent `init.sh` comme elles jugent `loop.sh` et `human-loop.sh`, et que leur zone soit dérivée des points d'entrée du pack au lieu d'être un glob écrit à la main.

**Blocked by:** None

**Write-surface:** `test/layering.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Les quatre règles (`layering_privates`, `layering_upward`, `layering_masked_status`, `layering_heredoc_prose`) sont exécutées sur `init.sh` comme sur les deux autres points d'entrée, et chacune rougit sur une violation plantée dans une **copie** de `init.sh` (le pack planté de `layering__planted_pack` est le logement existant : il copie déjà `lib/`, `loop.sh` et `human-loop.sh`).
- [x] La zone n'est plus « `.claude/lib/*.sh` plus `.claude/*.sh` » écrit à la main : elle est **dérivée**, de sorte qu'un quatrième point d'entrée livré demain soit jugé le jour où il arrive, ou refusé bruyamment s'il n'est pas dérivable. Un point d'entrée est un fichier exécutable du pack qui n'est pas un lib — le critère est à écrire dans le test, pas à deviner.
- [x] `layering_privates` reçoit le bon `own` pour `init.sh` : le préfixe est `init_`, ce que `basename … .sh | tr '-' '_'` donne déjà, donc la règle marche telle quelle — le vérifier plutôt que le supposer, avec un `gate__quelque_chose` planté dans la copie.
- [x] `layering_upward` sur `init.sh` : la règle actuelle ne boucle que sur `lib/`, et elle n'a pas de sens pour un point d'entrée. Décider et **écrire** lequel des deux : soit elle reste sur `lib/` et le test dit pourquoi, soit `init.sh` gagne sa propre règle (un installeur n'a pas le droit d'appeler `loop_`, il n'y a pas de boucle).
- [x] Une entrée de mutation par garantie livrée, avec le témoin appairé qui distingue « le test ment » de « la ligne porteuse a bougé ».

## Comments

- **Ordre validé par Philippe le 14/09/2026** : **[87] → [86] → [88] → [89]**.
  Le critère est celui d'habitude — minimiser la reprise, jamais l'urgence. [87]
  devant parce qu'il ne touche que `test/` et qu'il pose le filet de source sous
  le heredoc de prose que [86] va réécrire ; [88] derrière [86] parce qu'il
  généralise une forme dont [86] livre le précédent ; [89] en dernier, sans arête.

- **Ouvert par la passe transversale du 14/09/2026** (`../passe-transversale-14-09.md`,
  §3). Sonde : `../sondes/passe-14-09/q2-aucune-regle-de-source-ne-voit-linstalleur.bats`.

- **Ce qui est mesuré, et dans les deux sens.** Les quatre règles bouclent sur
  `"$dir"/lib/*.sh "$dir"/*.sh` avec `$dir="$RALPH_PACK_ROOT/.claude"` ; `init.sh`
  est à la racine du dépôt, donc hors des quatre. Un seul backtick dé-échappé
  planté dans le heredoc de `init_claude_block` (sur une **copie**) donne :
  - la règle `layering_heredoc_prose`, extraite de `test/layering.bats` sans être
    recopiée, l'attrape dès qu'on l'y pointe — `init.sh:834` ;
  - l'installeur sort en **0**, avec une ligne `docs/agents/: is a directory`
    perdue dans un rapport de quarante lignes ;
  - et le projet cible garde un `CLAUDE.md` qui dit « The conventions are in . ».

  Témoin appairé : le pack livré **et** `init.sh` tel quel rendent tous deux
  `rc=0`. Les backticks de `init.sh` sont échappés à la main aujourd'hui — c'est
  une propriété de l'auteur, pas du dépôt.

- **Pourquoi la règle du heredoc est celle qui coûte le plus cher ici.** `init.sh`
  est le fichier du pack qui a la plus forte densité de prose non citée : neuf
  heredocs, dont deux — `init_gitignore_block` et `init_claude_block` — écrivent
  dans le projet cible. Le second écrit dans `CLAUDE.md`, qui est **scellé** ([31])
  et que chaque `claude` frais lit au démarrage. [61] a payé un ticket pour la même
  faute dans le prompt d'**une** session ; ici elle atteint toutes les sessions
  d'un projet, pour toute sa vie, et l'installeur ne tourne qu'une fois.

- **Le commentaire de `layering_privates` dit déjà pourquoi ce ticket existe** :
  *« `"$dir"/*.sh` and not `"$dir"/loop.sh`: the pack has two entry points since
  [16], and an entry point outside this glob is one where a lib's `__` internals
  are reachable with nothing to say so. »* [19] en a livré un troisième. Le glob a
  été élargi une fois à la main quand [16] est arrivé ; le livrer dérivé est ce
  qui empêche de le refaire.

- **Contrainte de forme, héritée de [62] et [85].** La dérivation vit **dans le
  test**, jamais dans le pack : la source du pack est dans un arbre qu'une session
  écrit, donc un pack qui publierait la liste de ses propres points d'entrée
  publierait une liste qu'une session peut réduire. Et une dérivation qui ne sait
  pas ce qu'elle ne voit pas ne prouve rien : le test doit refuser un point
  d'entrée que son critère ne classe ni comme lib ni comme entrée, plutôt que de
  le laisser tomber en silence.

- **Piège de mise en scène.** `layering__planted_pack` construit une copie du pack
  et y plante une violation de chaque genre. `init.sh` n'est pas dans cette copie
  aujourd'hui ; l'y ajouter est la moitié facile. La moitié qui compte est que le
  fichier planté soit **une copie** — planter dans `init.sh` lui-même laisse le
  dépôt avec un installeur cassé si le run est interrompu, et c'est précisément ce
  que le commentaire de `layering__planted_pack` dit déjà (*« a run interrupted
  halfway must not leave the repository holding a bogus function »*).

- **Ce que le ticket suivant hérite.** [86] réécrit un heredoc de prose de
  `init.sh` (le bloc `CLAUDE.md`). Livré devant, ce ticket-ci est le filet sous
  cette réécriture ; livré derrière, il constate après coup. C'est la seule arête
  de la file proposée par la passe.

- **Ce que ce ticket ne fait pas, et qui reste écrit ailleurs.** `init.sh`,
  `bin/**` et `package.json` ne sont pas scellés et ne peuvent pas l'être — la
  ligne du tableau de [19] le dit et l'assume. Ce ticket ne change pas ça : il
  ajoute un contrôle de **source**, du même genre que les trois autres, pas une
  garde d'exécution.

- **Livré le 15/09/2026.** Ce que le code ne dit pas :

- **Le critère n'est pas celui que le ticket proposait, et c'est mesuré.** Le ticket
  écrivait « un point d'entrée est un fichier **exécutable** du pack qui n'est pas
  un lib ». `.claude/human-loop.sh` est `100644` dans l'index et se lance par
  `bash .claude/human-loop.sh` : un test sur `-x` aurait classé le **deuxième**
  point d'entrée comme un lib, c'est-à-dire une zone fausse dans la même direction
  que le glob qu'elle remplace. Le critère livré est la **première ligne** — un
  shebang bash pour un point d'entrée, `# shellcheck shell=bash` pour un module
  sourcé — parce que c'est ce que le fichier *est fait pour* et pas ce qu'un mode
  dit de lui. Vingt-quatre libs, trois points d'entrée, aucun fichier ambigu.

- **La position est un contre-contrôle, jamais le critère.** Où un fichier est posé
  est exactement la connaissance écrite à la main que ce ticket retire, donc elle ne
  décide rien ; mais un fichier de `lib/` qui porte un shebang, ou un point d'entrée
  qui porte la directive shellcheck, est un pack dont les deux signaux se
  contredisent et la réponse honnête y est un refus, pas une supposition. Les deux
  formes sont plantées dans la copie (`.claude/stray.sh`, `.claude/lib/misplaced.sh`).

- **`layering_upward` reste sur les libs, et la décision est assertée et pas
  décrite.** Mesuré avant de trancher : étendre la règle aux points d'entrée
  demanderait **deux** dérogations sur le pack livré — `loop.sh` *est* la boucle et
  nomme `loop_*` une ligne sur deux, et `init.sh` nomme `loop_preflight` à dessein,
  dans le `grep -v` de `init_refusals`, parce que [19] dérive de `loop.sh` la liste
  des refus au lieu de la retaper. Une règle à dérogation est une règle qu'on
  contourne. Le test asserte les deux moitiés : `init.sh` est bien dans la zone
  dérivée (les trois autres règles le rapportent), il porte bien le nom, et cette
  règle-là ne le rapporte pas.

- **Le piège qui a coûté un VACUOUS, et il est dans l'outillage, pas dans la
  règle.** Le refus d'un fichier inclassable voyage vers les quatre règles préfixé
  d'un `!` (un chemin commence par `/`, donc aucun constat n'est pris pour un
  fichier). L'entrée de mutation qui retire ce préfixe a d'abord rendu **VACUOUS**
  contre un test qui avait l'air juste : sans le préfixe, la ligne part dans
  `grep -v … "$f"`, et `grep: <la phrase entière>: No such file or directory` revient
  sur stderr, que `run` fusionne — donc `assert_output_contains` sur un morceau de
  la phrase passait **sur le message d'erreur**. Les deux assertions sont maintenant
  ancrées en début de ligne (`grep -c '^\.claude/stray\.sh …'`). Règle générale à
  retenir : sur un constat dont le texte est un chemin, une assertion par sous-chaîne
  ne distingue pas le constat de l'erreur que le chemin provoque.

- **Les plants dans `init.sh` sont ajoutés en fin de fichier, pas édités dans la
  prose.** [86] réécrit `init_claude_block` juste après ; une mutation ancrée sur une
  phrase de ce bloc aurait dérivé vers un vert le jour de sa livraison.

- **Ce que la zone dérivée coûte, assumé.** Un fichier `*.sh` qui apparaît dans le
  dépôt hors des quatre zones élaguées (`.git`, `.scratch`, `test`, `.agents`, plus
  `node_modules` où qu'il soit) et qui ne porte ni shebang ni directive shellcheck
  fait **rougir les quatre règles**. C'est la clause « refusé bruyamment s'il n'est
  pas dérivable » de l'AC 2, et donc aussi : une session qui laisse un script de
  brouillon à la racine du dépôt rend l'itération rouge. `docs/` n'est pas élagué à
  dessein — `docs/agents/` part dans le prochain projet, donc du shell qui
  atterrirait là partirait aussi. `bin/` non plus : `bin/ralph-init.js` n'est pas
  walké parce qu'il est en node, mais du shell sous `bin/` le serait, et c'est
  précisément ce que le glob ne savait pas faire.

- **La dérivation vit dans le test et nulle part ailleurs** ([62], [85]) : la source
  du pack est dans un arbre qu'une session jugée écrit, donc un pack qui publierait
  la liste de ses propres points d'entrée publierait une liste qu'une session peut
  raccourcir. Rien ici ne lit `init_payload` ni le `files` de `package.json`.

- **Write-surface débordée, et pourquoi.** Le ticket déclarait `test/layering.bats`
  et `test/mutate.sh`. `docs/frontiere-de-confiance.md` s'y ajoute : l'étape 5 de la
  definition of done demande de vérifier le tableau plutôt que de le supposer, et la
  vérification a trouvé une ligne **surévaluée**. « Une règle écrite dans un prompt
  arrive au modèle telle qu'elle est écrite » disait « une règle sur la source pour
  tout le reste » alors que `init.sh` était dehors depuis [19]. La ligne dit
  maintenant ce que la zone dérivée couvre, ce qu'elle ne couvre toujours pas, et
  corrige au passage deux faits qui y étaient faux : il y a **trois** points d'entrée
  et non deux, et le troisième porte `set -uo pipefail` **sans `-e`**, à dessein
  (`init.sh:39`). Aucune ligne nouvelle : [87] n'ajoute aucune règle au prompt d'une
  session.

- **Ce qui reste à faire ailleurs : [90], ouvert par la sonde de frontière de ce
  ticket.** La règle de [61], même élargie à `init.sh`, ne lit que le **corps d'un
  heredoc**. Le pack écrit sa prose surtout dans des chaînes entre guillemets
  doubles : 52 sites où l'échappement `\`` est porteur, dont 30 dans `init.sh`.
  Mesuré sur un vrai run de l'installeur, avec un seul backtick dé-échappé dans un
  `init__note` : l'opérateur lit « ·  is not on this PATH », l'installeur sort en
  **0**, un seul `command not found` se perd dans un rapport de quarante lignes, et
  `layering_heredoc_prose` est **vert** sur ce fichier. Disculpé dans l'autre sens :
  un scanner qui suit l'état de citation ne trouve **aucune** backtick non échappée
  en contexte double dans le pack livré — c'est une règle à écrire, pas une
  migration à faire.

- **Contrainte écrite par [89], livré le 22/09/2026.** La zone que ce ticket a
  dérivée a **déménagé** : `layering__shell_files` est devenue `harness_pack_sources`
  dans `test/helpers/harness.bash`. [89] en fait un second appelant — il dérive le
  recensement des globals du pack de la même marche — et la règle 6 du `CLAUDE.md`
  dit qu'un `__` à deux appelants est public. `test/layering.bats` la consomme,
  le commentaire de zone a suivi la fonction, et **l'entrée de mutation
  « 87 the derived zone stops at .claude, as the glob did » vise maintenant
  `$HARNESS` et non plus `$LAYERING`** — son témoin, `test/layering.bats "derived
  from the pack"`, n'a pas changé. Une seconde entrée, `89 the zone of the census
  stops at .claude`, vise la même ligne avec le témoin de `smoke.bats` : la ligne
  porte deux garanties depuis [89], et une édition qui la déplace en casse deux.
