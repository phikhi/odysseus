# 27 — Un ticket renommé laisse deux fois le même NN, et la frontière ne s'en remet pas

**What to build:** Refermer la combinaison que la protection du tracker de [21] ne couvre pas. Un renommage de fichier de ticket est un `D` plus un `A` : la protection **restaure** le supprimé et **laisse** le créé, par deux décisions correctes prises séparément. Résultat, deux fichiers portent le même `NN`, `tracker_local__path` refuse à juste titre de résoudre un numéro nu ambigu, et tout ticket portant `Blocked by: NN` quitte la frontière — définitivement.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/tracker-local.sh`, `.claude/lib/tracker.sh`, `.claude/loop.sh`, `test/failures.bats`, `test/tracker-local.bats`, `test/loop-happy-path.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Un `NN` en double ne peut pas naître d'une session : soit le renommage est restauré des deux côtés, soit le fichier créé est mis en quarantaine sous un identifiant qui ne collisionne pas.
- [x] Un `NN` en double déjà présent — un humain peut en créer un à la main — est signalé au préflight du run, pas découvert ticket par ticket en cours de route.
- [x] Un ticket dont le blocage pointe vers un `NN` ambigu ne disparaît pas en silence : la boucle dit lequel et pourquoi, dans `run.log` et non seulement sur stderr.
- [x] Le test crée la collision par un renommage de session, pas en déposant deux fichiers à la main : c'est le chemin qui l'a produite.

## Comments

- **Origine : passe transversale 01→22, le 29/07/2026.** Sondé avec une session qui fait `mv .scratch/demo/issues/01-alpha.md .scratch/demo/issues/01-alpha-v2.md`, tracker seedé avec `01-alpha` et `03-blocked` (`Blocked by: 01`). Le pack se comporte comme prévu à chaque étape, et le résultat est cassé :

  ```
  ralph: 01-alpha: the session edited the tracker — restored 1 ticket file(s)
  ralph: 01-alpha: the session wrote the tracker itself — quarantined 01-alpha-v2
  ...
  tracker: "01" matches 2 tickets — an ambiguous id is never safe to resolve
  ```

  Tracker après le run : `01-alpha.md`, `01-alpha-v2.md`, `03-blocked.md`. `tracker_field 01` est illisible, `tracker_frontier` ne rend plus rien d'exploitable, et `03-blocked` est hors frontière pour toujours — son blocage ne pourra plus jamais être évalué comme satisfait. Le run a bouclé trois fois sur `01-alpha`, l'a escaladé en `failed-impl`, puis est sorti en « sterile run ». Dans un tracker plus grand il serait sorti en `exit 0` — « ce run a broyé tout ce qu'il pouvait » — avec un ticket silencieusement perdu.

- **Aucun des deux comportements n'est faux tout seul, et c'est ça la trouvaille.** [21] a raison de restaurer un ticket modifié ou supprimé : c'est ce qui empêche une session de réécrire la write-surface sur laquelle elle va être jugée. [21] a aussi raison de **ne pas** supprimer un ticket créé : « le rendre au snapshot aurait effacé la seule copie de ce qu'il demandait », donc quarantaine et un humain tranche. Le troisième corollaire de `docs/frontiere-de-confiance.md` — « un contrôle qui restaure doit dire ce qu'il ne restaure pas » — a été posé en livrant [21] et il pointait déjà ici : ce que la protection ne restaure pas, c'est un `A`, et un renommage est le cas où un `A` et un `D` décrivent le **même** ticket.

- **Ce qui aggrave : l'itération suivante hérite du désordre.** Aux itérations 2 et 3 la sonde lit « restored **2** ticket file(s) » : le snapshot pré-session contient désormais le fichier mis en quarantaine, la session le réécrase, et la protection restaure les deux. Le ticket accumule ses trois `Failures:` sur un défaut que la boucle a elle-même stabilisé dans le tracker.

- **Priorité honnête : c'est le moins probable des quatre trous trouvés par cette passe.** Une session à qui l'on dit « ne touche à aucun ticket » ne renomme pas un fichier de ticket par accident. Ce qui le rend digne d'un ticket plutôt que d'un commentaire, c'est qu'il est **permanent** quand il arrive — rien dans le pack ne sort le tracker de cet état — et qu'il casse la frontière entière, pas seulement le ticket touché. Le contrôle de préflight de l'AC 2 est peut-être la moitié qui vaut le plus cher pour le moins d'effort.

- **Livré le 03/08/2026. Ce qui a été choisi, et pourquoi ce n'est pas l'autre branche de l'AC 1.** Les deux issues offertes par l'AC étaient « restaurer le renommage des deux côtés » et « quarantaine sous un identifiant qui ne collisionne pas ». La seconde a été retenue, et pas par goût :

  - Restaurer les deux côtés suppose de **reconnaître** un renommage, c'est-à-dire `git diff-tree -M`, dont la détection est une heuristique de similarité. Une session qui renomme *et* réécrit produit un `D` + un `A` sous le seuil : la collision revient, et le correctif ne couvre que le cas poli.
  - Surtout, le renommage n'est pas le seul chemin, ni le plus probable. Rien n'empêche une session d'écrire `01-autre-chose.md` de sa propre initiative — aucun `mv`, même dégât. Un correctif indexé sur « git a appelé ça un renommage » n'aurait rien vu de celui-là. La clé est le **numéro**, pas le mouvement.
  - Et elle préserve [21] intacte : rien de ce que la session a écrit n'est détruit, le fichier part au puits humain sous un nom qui résout. C'était la raison même de la quarantaine.

  Deux tests portent les deux chemins (`test/failures.bats` : « does not leave two tickets carrying one number », par un `mv` de session ; « on a number already taken », par une création). Aucun des deux ne dépose deux fichiers à la main.

- **Ce que ça a coûté à l'interface, et ce que ça n'a pas coûté.** Une opération de plus, `tracker_renumber ID` (14ᵉ), dispatchée : renommer est du travail de backend. En face, le préflight de l'AC 2 n'en est **pas** une — `tracker_preflight` vit dans `tracker.sh` et se déduit de `tracker_ids` + `tracker_field`, parce que la question porte sur la *forme* des ids (« deux tickets portent-ils `NN` ») et que cette forme appartient à l'interface, pas au stockage. Un backend numéroté côté serveur n'y trouve rien, ce qui est la bonne réponse et non une opération non implémentée.

- **Décision sur l'AC 2 : signaler, pas refuser.** Un `NN` en double posé à la main ne casse pas le ticket qui le porte — il casse ceux qui le **désignent**. Le reste de la frontière est parfaitement broyable, donc refuser le run échangerait une nuit de travail contre un avertissement qui se lit pareil le matin. Le préflight nomme le numéro, ses porteurs, et chaque ticket dont le `Blocked by:` pointe dessus. Le prix assumé : un ticket bloqué sur un numéro ambigu reste hors frontière pour tout le run, nommé une fois au départ au lieu d'être redécouvert à chaque scan.

- **AC 3 : pourquoi `run.log` et pas seulement la console.** `loop_log` écrit sur stdout, et `run.log` ne reçoit que le journal — donc « la boucle le dit » ne voulait rien dire pour un humain qui lit le matin, ni pour le reçu de [10]. Les findings passent par `loop_journal_append` avec deux outcomes neufs, `ambiguous-id` (sujet = le numéro) et `blocked-on-ambiguous-id` (sujet = le ticket qui le désigne), sur le modèle des lignes `reclaimed-*` de [12]. Ils sont écrits **avant les verrous** : un run refusé par le verrou d'un autre laisse donc sa ligne, un doublon honnête plutôt qu'un silence.

- **La sonde de frontière de confiance sur le correctif lui-même, et c'est la trouvaille de ce ticket.** Question 5 posée sur ma propre réparation : *qu'est-ce qu'une session peut écrire que ce mécanisme-là ne verra pas ?* La renumérotation s'appuie sur `tracker_local__next_nn`, dont la borne se déduit des **noms de fichiers du répertoire** — que la session écrit. Un ticket nommé `1000000000000000000000000000000-x.md` fait rendre à awk `1e+30`, dont `$(( ))` dit `value too great for base` : la fonction rend zéro, et le repli de la quarantaine était `|| final="$stray"`, c'est-à-dire *garde la collision*. Le correctif se désarmait par un nom de fichier. Deux changements : `next_nn` ignore les numéros trop larges pour être de l'arithmétique et **vérifie** son résultat contre le répertoire au lieu de le déduire ; et un refus de renumérotation est désormais journalisé au lieu d'être avalé. Les deux ont leur test (`too wide to be arithmetic`, `checked against the directory`) et leur mutation.

  Effet de bord, hors du champ initial et assumé : `tracker_open_ticket` — donc le re-slice de [07] — avait la même faille par la même fonction. Elle est refermée du même coup, et le second test (`10.md` déjà présent) porte précisément ce cas-là.

- **Écart de write-surface, à lire comme tel.** Le ticket déclarait quatre fichiers ; il en a fallu quatre de plus. `.claude/lib/tracker.sh` pour la 14ᵉ opération et le préflight générique, `.claude/loop.sh` pour l'appeler et journaliser (AC 2 et AC 3 sont inatteignables sans lui : le préflight *est* dans `loop.sh`), `test/loop-happy-path.bats` parce que c'est là que vivent les tests de préflight, et `docs/frontiere-de-confiance.md` parce que la ligne « Un ticket est identifiable par son `NN` » nommait ce ticket comme propriétaire.

- **Huit mutations ajoutées** (`27 …`), toutes rouges. Deux méritent d'être connues : « a ticket named after the number alone counts as a collision » a d'abord été `VACUOUS` — le test ne créait qu'un seul `02-*`, donc la garde `NN.md` n'était pas ce qui le tenait ; il a fallu deux porteurs pour que la règle d'exactitude soit la seule chose qui décide. Et « the next number is never checked against the directory » l'a été aussi, pour la même raison : un fichier `10-already-here.md` est compté par `next_nn`, donc la boucle de vérification ne servait pas — c'est `10.md` (sans slug, invisible du `sed`) qui la rend nécessaire.

- **Et une mutation d'un autre ticket a dérivé, ce qui est le rappel que `mutate.sh` existe pour ça.** L'entrée « 07 a quarantined ticket is only logged, not taken off the frontier » visait `tracker_mark_escalated "$stray"` ; la renumérotation escalade `"$final"`, donc l'ancre ne matchait plus. `DRIFTED` et non `VACUOUS` : la garantie de [07] est intacte, c'est la ligne qui la porte qui a bougé sous elle. Vérifié puis réancrée — et c'est exactement le cas que la note en tête de `mutate.sh` décrit, un ticket qui déplace la ligne d'un autre sans qu'aucun test ne rougisse. Total : 229 mutations, 0 not ok.

- **Ce qui reste ouvert ici, dit franchement.** `failures_tracker_snapshot` joint les ids par des espaces et `failures__strays` les compare mot à mot : un ticket dont le nom de fichier contient une **espace** est mal vu par ce chemin. Même famille que [33], autre liste. La boucle de quarantaine, elle, lit ligne par ligne. Non traité ici parce que réparer le lecteur sans réparer le format ne gagne rien ; à poser dans [33] si son correctif touche au format des listes du pack. **Décidé le 04/08/2026, en livrant [33]** : il y a touché — toute liste que le pack se passe à lui-même voyage un élément par ligne — et la décision est *même convention, ticket séparé*, parce que ce n'est pas le même espace de noms. C'est **[37]**, qui prend les sept `for id in $(tracker_ids)` du pack, le format de `failures_tracker_snapshot`, et la question que ce ticket-ci n'a pas posée : jusqu'où un id à espace survit ailleurs que dans ces boucles.

- **Contrainte pour [18], deux points.** D'abord une opération de plus à implémenter : `tracker_renumber ID`, qui rend l'id que le ticket porte après coup. Un backend numéroté côté serveur le rend inchangé — c'est légitime — mais il doit **le dire dans son ticket** plutôt que le laisser deviner. Ensuite `tracker_preflight` n'est pas dispatché : il lit `tracker_ids` et `tracker_field`, donc il tournera tel quel sur un backend distant et n'y trouvera rien. Si un backend distant peut rendre deux tickets pour un identifiant (une migration, un miroir), c'est à lui d'ajouter sa propre question au préflight.

- **Contrainte pour [10].** Deux outcomes neufs dans `run.log`, `ambiguous-id` et `blocked-on-ambiguous-id`, et ils ne ressemblent à aucun autre : ce ne sont pas des itérations. Ils n'ont ni ticket claimé, ni verdict, ni tours, ni coût, et le sujet de la première n'est pas un ticket mais un **numéro**. Ils sont aussi écrits avant les verrous, donc un run refusé au démarrage en laisse un jeu complet — le reçu doit les traiter comme des faits de démarrage, pas comme du travail.

- **Contrainte pour [13].** `tracker_renumber` renomme un fichier dans le répertoire de tickets **partagé**, et son choix de numéro est un « lis le répertoire puis écris » non atomique : deux itérations concurrentes qui quarantainent chacune un intrus peuvent viser le même numéro libre. `tracker_local_claim` a déjà eu ce problème et l'a réglé par `state_guard_take` ; la renumérotation n'a pas de garde. À décider là-bas : garde partagée, ou renumérotation sous le verrou du tracker.

- **Contrainte pour [16].** Un ticket au puits humain peut désormais porter un id qui ne correspond pas à son titre `# NN — …` : le corps est laissé exactement tel que la session l'a écrit, et c'est la note appendue qui dit le nom d'origine. C'est délibéré — réécrire le corps serait la suppression que la quarantaine existe pour éviter — mais le puits humain doit l'afficher pour ce que c'est plutôt que le présenter comme une incohérence.

- **Contrainte pour [18] : ce trou est propre au backend local.** La collision naît de la convention « le nom de fichier porte le `NN` » et du glob `NN-*.md` de `tracker_local__path`. Un backend distant numérote côté serveur et n'a pas ce chemin — mais il devra dire, dans son propre ticket, comment il rend `tracker_ids` stable quand deux tickets prétendent au même identifiant.

- **Contrainte posée par [15], livré le 25/08/2026 : un troisième producteur d'ids, toujours sans verrou.** `tracker_local__next_nn` lit le répertoire, prend le max et écrit ; deux ouvertures concurrentes peuvent choisir le même `NN`, et c'est exactement la collision que ce ticket sait diagnostiquer et renuméroter. Les producteurs étaient `failures_reslice` et l'escalade de [14] — [42] a sondé deux re-slices voisins créant quatre tickets — et [15] ajoute `capability_propose`. Ce ticket n'a rien à corriger dans ce qu'il a livré ; ce qui manque est en amont, la sérialisation de l'ouverture, et le propriétaire naturel est [13].

- **Passe transversale du 26/08/2026 : la contrainte que [15] a écrite ici a maintenant un
  ticket, [47].** Ce ticket-ci est `resolved`, donc la contrainte n'avait aucun lecteur dans
  la file ouverte. La passe a reproduit la course de `tracker_open_ticket`
  (`.scratch/ralph-pack/sondes/passe-26-08/p4.bats` : deux ouvertures en vol, même `NN`, bare
  number irrésolvable, ticket bloqué sorti de la frontière pour de bon) et a montré que les
  deux réparations existantes la manquent structurellement — `tracker_preflight` tourne au
  démarrage du run, et la renumérotation de `failures_quarantine_strays` est désarmée par le
  registre des écritures de la boucle, précisément parce que c'est la boucle qui a écrit
  (`p5.bats` P5a, les deux moitiés côte à côte). Le détail de fenêtre qui compte pour qui
  écrira le correctif : `nn` est calculé **avant** que le corps ne soit lu sur stdin.

- **Ce que [49] mesure sur la réparation de ce ticket, le 29/08/2026.**
  `tracker_renumber` passe par le garde d'ouverture de [47], et il le prend **une
  fois par intrus** : la borne d'attente est de huit secondes mesurées (cent-vingt
  essais de 0,05 s plus le coût de la boucle) et non les six annoncées, donc dix
  fichiers déposés par une session dans `issues/` coûtent quatre-vingts secondes
  d'itération immobile avant que la quarantaine ne renonce. Et une session qui
  **pose** ce garde éteint `tracker_renumber` pour toute la durée où son propriétaire
  vit, c'est-à-dire la réparation de ce ticket : ligne au tableau de confiance.
