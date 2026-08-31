# 16 — Boucle humaine (`human-loop.sh`)

**What to build:** La 2ᵉ boucle bash HITL, sœur de la ralph loop, qui **draine le puits `ready-for-human`**, route chaque ticket par sa raison d'escalade vers le bon traitement, et **réinjecte** le résultat en `ready-for-agent`. Ferme le cycle escalade → drain → réinjection.

**Blocked by:** 07

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/router.sh`, `test/human-loop.bats`

**Status:** resolved

- [x] `human-loop.sh` draine `ready-for-human` et route par `Escalation:` : `decision`→grilling, `too-big`→to-tickets, `failed-impl`→implement/pair (amorcé `failed/<ticket>` + reçu), `spec-gap`→to-spec, `sign-off`→approbation.
- [x] Anti-faux-vert : tout code corrigé repasse le gate via réinjection `ready-for-agent` ; jamais de `resolved` direct sauf `sign-off`.
- [x] Exclusion mutuelle avec l'AFK via le verrou de run (on broie **ou** on draine).
- [x] L'ordre de traitement = impact de déblocage puis NN.

## Comments

- **Contrainte posée par [07] : ce qui arrive réellement dans le puits, et avec quoi.** Trois raisons sont posées par la boucle AFK, sur la ligne `Escalation:` : `failed-impl` (gate rouge ou crash au-delà de `RETRY_N`, avec `Failures:` à l'appui), `decision` (débordement **contractuel** — la session a écrit dans la write-surface d'un autre ticket ; deux tickets sont dessinés sur le même fichier et c'est un arbitrage de découpage, pas une implémentation à refaire), `too-big` (la session a franchi la limite molle **et** aucun découpage préservant les AC n'a pu être produit). `spec-gap` et `sign-off` ne sont posées par personne aujourd'hui.
- **Chaque escalade est accompagnée d'une branche `failed/<ticket>`** qui contient l'arbre exact de la tentative, tracker retiré, commitée sur le `HEAD` pré-session. C'est l'amorce prévue par l'AC `failed-impl` — elle existe pour les trois raisons, pas seulement celle-là. Elles ne sont jamais nettoyées : les recycler ou les supprimer à la réinjection est du ressort de cette boucle.
- **Remettre `Failures:` à zéro en réinjectant.** Le compteur est porté par le ticket et n'est pas remis à zéro par [07] (c'est la mémoire de ce qui s'est passé). Un ticket réinjecté en `ready-for-agent` avec `Failures: 3` et `RETRY_N=2` sera donc **réescaladé à sa première tentative**, sans retry. `tracker_mark_ready` efface `Escalation:` mais pas `Failures:` — à faire ici, explicitement.
- **`to-tickets` est utilisable ici, et nulle part ailleurs dans le pack.** Le skill existe (`.agents/skills/to-tickets/`), mais son frontmatter porte `disable-model-invocation: true` — seul un humain le déclenche — et son étape 5 **publie directement** dans `.scratch/<feature>/issues/`. Les deux sont disqualifiants pour la boucle AFK ([07] explique pourquoi et implémente le contrat en ligne) et parfaitement légitimes ici : un humain invoque, relit, publie. Attention tout de même à un point : ce que le skill publie n'a **pas** traversé la validation de découpage de [07] (write-surface incluse dans celle du parent, AC préservées). C'est la relecture humaine qui en tient lieu.

- **`too-big` → to-tickets : la boucle AFK a déjà essayé.** Le re-slice autonome de [07] tourne avant l'escalade ; un ticket arrivant ici en `too-big` est un ticket qu'une session fraîche n'a pas su découper en préservant les AC, ou dont le plan élargissait la write-surface. Le format de plan attendu par la boucle (`--- ticket: <slug> | <title> ---`, write-surface incluse dans celle du parent) est dans `failures__reslice_prompt` — le même contrat vaut pour un découpage humain.
- **Contrainte posée par [12], livré le 29/07/2026 : `failed-impl` peut arriver sans qu'aucune implémentation ait échoué.** Un claim dont le propriétaire est mort est compté comme le crash qu'il est (personne n'était vivant pour le classer), donc il consomme un retry et escalade en `failed-impl` au plafond. La raison est réutilisée exprès — « implement/pair amorcé » est le bon guichet pour un ticket qui tue son run à répétition — mais l'humain qui draine doit savoir que dans ce cas **il n'y a pas de branche `failed/<ticket>`** : `failures_preserve_attempt` n'a pas tourné, le run qui l'aurait appelée est celui qui est mort. Le compteur `Failures:` est la seule trace. Si le routage veut distinguer les deux, la matière est dans `run.log` (`reclaimed-escalated`), pas dans le ticket.

- **Complément de la passe transversale du 29/07/2026 : le trou du compteur est plus large que la réinjection.** La note ci-dessus ne vise que `tracker_mark_ready`, donc le chemin de cette boucle. Sondé : `tracker_mark_resolved` ne remet pas `Failures:` à zéro non plus, donc le compteur est cumulatif sur toute la vie du ticket, dans la boucle AFK, aujourd'hui. Un ticket peut arriver dans ce puits avec `failed-impl` après avoir été livré vert. La moitié AFK est ouverte en [26] ; ce qui reste à faire ici, c'est le zéro à la réinjection — et savoir que le compteur qu'on lit en drainant ne dit pas seulement « des implémentations ont échoué ».

- **Contrainte posée par [26], livré le 29/07/2026 : la moitié AFK est faite, la moitié réinjection reste ici, et une des raisons de routage a changé.** Trois choses à savoir avant d'écrire le routeur :

  1. **`tracker_mark_resolved` remet `Failures:` à zéro ; `tracker_mark_ready` non.** Le compteur n'est donc plus cumulatif sur toute la vie du ticket, mais il l'est encore d'un passage dans ce puits au suivant : un ticket réinjecté avec `Failures: 3` et `RETRY_N=2` sera réescaladé à sa première tentative, sans retry. C'est le zéro à la réinjection déjà noté plus haut — il n'a pas été livré par [26], délibérément (voir le piège du re-broyage : le seul point sûr côté AFK est `resolved`). **Ce ticket doit le décider explicitement et le dire**, et l'obligation est écrite au-dessus de `tracker_field` dans `lib/tracker.sh`.
  2. **`failed-impl` implique désormais qu'une session a réellement été jugée.** La note de [12] ci-dessus est périmée sur ce point : le plafond atteint par un **reclaim** escalade en **`decision`**, pas en `failed-impl`. La raison : personne n'avait jugé, donc envoyer l'humain chez implement/pair le faisait chercher une branche `failed/<ticket>` et une suite rouge inexistantes. Conséquence pour le routeur : **`decision` a maintenant deux formes d'arrivée** — le débordement contractuel (avec une branche `failed/<ticket>` à lire) et le run qui meurt à répétition (sans branche ; les lignes `reclaimed-*` de `run.log` sont la seule trace). La note posée sur le ticket dit laquelle. Si ce ticket veut deux guichets distincts, **c'est lui qui ouvre une sixième raison** dans le jeu fermé, avec `CONTEXT.md`.
  3. **Un claim qu'aucun run du pack n'a pris ne coûte plus rien.** Un ticket qu'un humain s'était assigné revient en frontière quand `CLAIM_TTL` tombe — le vol reste, c'est le fail-open de [12] — mais sans `Failures:`, et avec une note sur le ticket qui recopie le record et dit que rien n'a été facturé. Un humain qui drainait un ticket et le retrouve broyé le lira là.

- **Contrainte posée par [23], livré le 31/07/2026 : une sixième raison d'escalade existe déjà, et elle n'est pas `failed-impl`.** Un ticket dont les sessions dépassent le délai de silence ou le mur est retryé en session fraîche jusqu'à `RETRY_N`, puis escaladé `Escalation: session-timeout`. Le routeur doit la traiter, et le point 2 ci-dessus explique pourquoi elle n'a pas été rangée sous `failed-impl` : **rien n'a jugé ces sessions**, le gate n'a pas tourné une seule fois, donc envoyer l'humain chez implement/pair avec « la suite est rouge, va voir » serait faux. Ce qu'il y a à lire est réel mais différent : la branche `failed/<ticket>` porte ce que la session avait eu le temps d'écrire, et `run.log` dit lequel des deux délais est tombé et combien de fois. La question à poser à l'humain n'est pas « pourquoi le code est-il faux » mais « est-ce que ce ticket bloque toutes les sessions qui le prennent, ou est-ce que la machine avait un problème » — la même question que `decision` sur un reclaim, avec en plus un artefact à lire. Si ce ticket décide de fusionner les deux guichets, qu'il le dise ; la raison, elle, reste distincte dans le tracker.

- **Contrainte posée par la passe transversale du 03/08/2026 : une septième raison arrive, et c'est celle qui pose la question la plus embarrassante au routeur.** [35] refuse une itération qui n'a changé aucun fichier — aujourd'hui elle est `resolved`, ce qui est un faux livré. Le ticket tranche ce que ça vaut dans `failures_classify` ; ce que ce ticket-ci doit décider est ce qu'un humain fait avec. Rien n'a été jugé (comme `session-timeout`), la session a répondu normalement (contrairement à `session-timeout`), et il n'y a **aucun artefact** : pas de suite rouge, pas de verdict de lentille, et une branche `failed/<ticket>` qui ne contiendrait rien, puisque la session n'a rien écrit — c'est la première route où le seul document est le flux de la session, que la boucle supprime en fin d'itération. La question à poser à l'humain n'est ni « pourquoi le code est-il faux » ni « la machine avait-elle un problème » mais « pourquoi ce ticket ne fait-il rien faire à la session » : un ticket illisible, une tâche déjà accomplie, un prompt tronqué. Si le guichet manque, c'est ici qu'il s'ouvre.

- **Contrainte posée par [27], livré le 03/08/2026 : un ticket du puits peut porter un id qui contredit son titre.** Ce qu'une session ajoute au tracker sur un numéro déjà pris est renuméroté avant d'être escaladé, et son **corps est laissé exactement tel que la session l'a écrit**, titre `# NN — …` compris : le réécrire serait la suppression que la quarantaine existe pour éviter. Le nom d'origine est dans une note appendue au ticket. Le puits doit donc l'afficher pour ce que c'est — « ce ticket est arrivé sous un autre nom, en voici l'histoire » — plutôt que le présenter comme un tracker incohérent, ou pire, le corriger d'office.

- **[35] livré le 04/08/2026 : la septième raison s'appelle `nothing-delivered`, et le guichet est bien ici.** Ce que le pack a tranché de son côté : rien n'est jugé, la session a répondu normalement, la branche `failed/<ticket>` n'est **pas** écrite (elle porterait l'arbre que la session a reçu — l'anticipation de ce ticket était juste), et une note est posée sur le ticket au plafond, qui pose la question au lieu d'un diagnostic : « pourquoi ce ticket ne fait-il rien faire à une session », avec ses trois réponses probables — un critère sur lequel rien n'est actionnable, un travail déjà fait, un prompt tronqué. Deux routes y arrivent, et la seconde n'était pas prévue : une session qui n'écrit rien, **et le parent d'un re-slice** dont les enfants ont tout livré (ses critères leur ont été distribués par construction, donc il ne lui reste rien à écrire — voir [07]). Sur cette seconde route, la bonne question humaine est « ce split vaut-il le ticket d'origine ? », que rien dans le pack ne vérifie.

- **[17] livré le 05/08/2026 : `LANG_INTERACT` est à vous, et personne d'autre ne doit le lire.** Le découplage est fait côté AFK : la boucle ne parle à personne, donc aucune session qu'elle lance n'est mise en langue d'interaction — c'est un test sur le prompt réellement envoyé, plus un test structurel qui refuse que `loop.sh` nomme la clé. `human-loop.sh` est l'autre point d'entrée et c'est lui qui la lit. Deux choses à savoir en l'écrivant. Le test structurel ne nomme **que** `loop.sh`, exprès, pour ne pas vous interdire un lib HITL ; mais un lib **partagé** avec la boucle AFK qui lirait `LANG_INTERACT` remettrait la langue d'un humain dans une session que personne ne regarde, et c'est le test comportemental qui le rattraperait, avec un message qui parlera de prompt et pas de layering. Et la prose que vos skills font écrire à un humain n'est jugée par rien : le gate de langue est une branche de `gate_run`, il ne tourne pas ici.

- **Contrainte posée par [13], livré le 06/08/2026.** La boucle AFK ne travaille plus dans l'arbre où on la lance : chaque itération a son worktree jetable, et l'arbre principal ne bouge que sur les chemins qu'un gate a approuvés, au moment du repli. Deux conséquences pour la boucle humaine, qui elle vit dans l'arbre principal : ce qu'un humain a de non commité n'est plus jamais jugé, rollbacké ni commité par la boucle AFK (avant, un run démarré sur un arbre sale le prenait comme base) ; et le verrou d'arbre du pilote continue de refuser un second run dans cet arbre, ce qui reste voulu — les deux boucles écrivent le même tracker. Ce qu'une boucle humaine doit décider en plus : un humain qui lance `loop.sh` à la main **dans un worktree d'itération** n'est refusé par rien, le verrou étant par arbre.

- **Contrainte de la passe transversale du 06/08/2026.** La boucle humaine écrit dans `issues/` **hors d'une itération**. Depuis [13] deux gardes décident de ce qui est « l'œuvre du jugé » à partir d'un registre alimenté par `tracker__dispatch` : ce qui ne passe pas par le dispatcher est indiscernable d'une écriture de session, donc restauré ou mis en quarantaine si un run broie en même temps ([42]). Ce ticket doit dire lequel des deux il fait — passer par le dispatcher, ou refuser de tourner pendant un run — et pas laisser la question au hasard du verrou de feature.

- **Contrainte écrite par [41], livré le 07/08/2026 — le puits humain reçoit des `failed-impl` qui ne sont l'échec d'aucune implémentation.** `.git/info/exclude` et `core.excludesFile` vivent dans le répertoire git commun ; quand une session en déplace un, le pack ne peut pas savoir *quel worktree* a écrit, donc **toute itération en vol est facturée** — la sortie retenue, et la seule honnête. Un frère qui n'a rien écrit consomme donc un retry, et s'il était à sa dernière tentative il arrive ici en `failed-impl`, c'est-à-dire avec l'affirmation qu'une implémentation a été jugée et trouvée fausse. Le finding porte sa propre ligne d'explication (« nothing here can tell which session wrote them and every iteration in flight is charged »), donc l'information est dans le ticket — mais **la classe, elle, ment**. Ce ticket possède ce que l'humain lit : soit la boucle humaine sait afficher cette ligne à côté de la classe, soit c'est ici qu'on décide qu'une facture non imputable mérite une classe à elle. [41] a délibérément refusé d'en créer une, pour ne pas décider à la place de ce ticket-ci.

- **Contrainte posée par [10], livré le 07/08/2026 : le puits humain a désormais un document par ticket, et il faut décider s'il en est le lecteur.** Toute escalade finale écrit un reçu sous `receipts/<feature>/<id>.md` : le résumé qui dit pourquoi (et qui distingue « rien n'a été jugé » d'un gate rouge), les verdicts, les findings complets de chaque branche rouge, les zones que rien n'a jugées, et les références à lire (`git show`, `git diff-tree`, `git log -p failed/<ticket>`). C'est exactement la matière que ce ticket veut mettre sous les yeux d'un humain — la note du tracker en dit beaucoup moins. À trancher ici : la boucle humaine pointe le reçu depuis le ticket, ou elle en recopie une partie. Recopier est le piège habituel de ce dépôt : deux auteurs pour une affirmation, et le reçu porte des phrases écrites là où le fait est connu.

- **Et une limite de rétention à connaître.** `RECEIPTS_RETENTION_DAYS` vaut 30, et le reçu référence des **objets** git (le commit d'itération, les deux trees) qu'un `gc` peut collecter dès que la branche est passée devant — plus court que 30 jours. Un ticket qui dort longtemps dans le puits humain peut donc arriver avec un reçu dont les références ne résolvent plus. La branche `failed/<ticket>` est une ref, elle, et survit ; c'est celle sur laquelle s'appuyer si ce ticket veut une garantie de durée.

- **Contrainte posée par [14], livré le 24/08/2026 : le puits humain reçoit des tickets qu'aucune discovery n'a écrits.** Le subagent retro ouvre des `NN-retro-<slug>` en `ready-for-human` quand une leçon récurrente demanderait un gate, un lint ou un hook — c'est-à-dire une capacité, que la boucle ne crée pas d'elle-même ([15]). Ils n'ont ni `What to build` rédigé par un humain, ni write-surface, ni critères d'acceptation : ce sont des **demandes**, pas des tickets prêts à broyer. Deux conséquences pour ce ticket : la boucle humaine doit les distinguer d'un `failed-impl` (ce n'est l'échec de rien), et le geste attendu n'est pas « corriger et remettre `ready-for-agent` » mais « décider, puis écrire le vrai ticket ou fermer ». Un `retro-*` remis tel quel sur la frontière serait un ticket qu'aucun scope-guard ne peut juger, faute de surface déclarée.

- **Contrainte posée par la passe transversale du 26/08/2026 — deux, et la seconde est un
  droit plus qu'une contrainte.** *(a)* Tant que [47] n'est pas livré, le puits peut recevoir
  **deux fois la même proposition** : la dédup de `capability_propose` lit `tracker_ids`
  avant d'écrire, donc deux itérations en vol peuvent la franchir toutes les deux. Un humain
  qui vide le puits verra donc parfois deux `capability-<kind>-<nom>` identiques, et ce n'est
  pas une erreur de saisie. *(b)* Deux tickets peuvent aussi porter le **même `NN`** — la
  même course, par `tracker_open_ticket` — et ce cas-là est pire : un bare number cesse de
  résoudre et tout ticket portant `Blocked by: NN` quitte la frontière définitivement. La
  boucle humaine est le seul composant qui puisse renommer l'un des deux sans être une
  session ; si elle le fait, `tracker_preflight` produit déjà la phrase exacte à afficher.

- **Mise à jour par [47], livré le 27/08/2026 : (a) est fermé, (b) ne l'est qu'aux trois
  quarts.** La dédup de `capability_propose` est passée dans l'adaptateur
  (`tracker_open_unique`), du même côté du garde que l'écriture, donc le puits ne reçoit plus
  deux fois la même proposition : un `capability-<kind>-<nom>` en double n'est plus un
  effet de course connu, et si un humain en voit un, c'est une trouvaille. Pour (b),
  l'allocation d'un `NN` et l'écriture qui la réserve tiennent maintenant sous un garde, et
  `tracker_renumber` passe par le même — la boucle ne peut plus produire la collision. **Ce
  qui reste et arrive donc encore ici** : un doublon posé par un humain éditant `issues/` à
  la main pendant un run, et la fenêtre sans compare-and-swap de `state_guard_take`. Ni l'un
  ni l'autre n'a de réparation automatique — c'est écrit comme tel dans
  `docs/frontiere-de-confiance.md` — et cette boucle reste le seul composant qui puisse
  renommer l'un des deux sans être une session. La phrase à afficher est toujours celle que
  `tracker_preflight` produit, au démarrage du run suivant.

- **Contrainte posée par la passe transversale du 27/08/2026, et elle vise exactement ce que cette boucle affiche.** Un ticket peut lire `ready-for-agent`, être **sur la frontière**, et n'être réclamable par aucune itération du run — un garde de claim ressuscité par la restauration de [21] porte le pid du pilote et rien ne le relâche jamais. Aucune ligne de `run.log` ne le nomme (le journal n'écrit que ce qu'une itération a livré), donc une boucle humaine qui lit le tracker et le journal ne peut pas distinguer ce ticket d'un ticket que le run n'a simplement pas eu le temps d'atteindre. C'est [49] qui répare ; si [49] est livré avant, cette note n'a plus d'objet — s'il ne l'est pas, cette boucle est le dernier endroit où un humain pouvait s'en apercevoir.

- **Ce que [39] ajoute à afficher, livré le 27/08/2026.** Deux nouvelles familles de
  `gap` — c'est-à-dire de promesses revenues courtes, pas de zones jamais regardées —
  arrivent dans le reçu d'audit et dans la console, et un humain les lit
  différemment : `could not put back <chemin>` (un nom que le rollback n'a pas su
  adresser, ou un `rm` qui n'a rien retiré) et `<chemin> was approved by the gate and
  could not be staged` (un chemin approuvé absent du commit durable). Le second a un
  cas armé qui n'a rien à voir avec les noms bizarres et qu'il faut savoir présenter :
  un projet qui `gitignore` un répertoire que son propre `GUARDED_PATHS` nomme voit
  **chaque** itération verte livrer sans commiter, avec un ticket `resolved` — la
  boucle humaine est le seul endroit d'où quelqu'un peut décider de forcer, de
  changer `GUARDED_PATHS`, ou de retirer la règle d'ignore. Avant [39] c'était
  silencieux ; c'est désormais dit, et dire ne suffit pas si personne ne le range.

- **Ce que [49] laisse à lire ici, livré le 29/08/2026.** Un ticket qu'aucune
  itération n'a pu réclamer a désormais une ligne `claim-refused` dans `run.log`
  (sujet = l'id du ticket), et la phrase de la console dit ce qu'elle a observé : le
  statut a bougé, avec son propriétaire, ou il n'a pas bougé et **personne** ne tient
  le ticket. C'était le trou : la boucle humaine est le lecteur d'une frontière dont
  un ticket a disparu, et le seul trace qu'il en existait était une console disant
  « someone else has it » en désignant personne.

- **Contrainte posée par [09], livré le 29/08/2026 : la boucle humaine ne doit jamais armer de successeur.** `SCHEDULER` et `WEEKLY_RESUME` appartiennent au chemin AFK et à lui seul. Un successeur programmé pendant qu'un humain draine réveillerait un run sur un arbre qu'un humain est en train de travailler — la destruction mutuelle que [22] refuse, obtenue par une porte que personne ne regarde. Ce qui le tient aujourd'hui est un fait de structure et non un contrôle : `loop__arm_successor` vit dans `loop.sh` et rien d'autre ne l'appelle. Si `human-loop.sh` finit par partager un lib avec la boucle AFK, c'est ici qu'il faut refuser explicitement, pas dans `scheduler.sh` — la question est « qui a le droit d'armer », pas « comment on arme ». Deux objets neufs qu'un humain peut rencontrer et qu'il faut savoir expliquer : `<gitdir>/ralph.successor` (marqueur singleton, écrit par un run AFK, jamais effacé — un successeur qui se réveille écrit par-dessus) et `.scratch/<feature>/successor.log` (la sortie du job programmé, à côté de `run.log`).

## Note de la passe transversale du 30/08/2026

Deux choses de plus à lire dans `run.log`, et une à ne jamais faire.

- **`weekly-pause` est ambigu et le restera jusqu'à [53].** Mesuré
  (`sondes/passe-30-08/r2`) : le journal écrit `weekly-pause` aussi bien pour un
  projet ayant choisi `WEEKLY_RESUME=human` que pour un run à qui un **marqueur
  forgé** a interdit d'armer — la phrase qui nomme le marqueur est un
  `scheduler__log`, donc stdout, donc morte avec le process. Une boucle humaine qui
  présenterait `weekly-pause` comme « ce projet reprend à la main » se tromperait
  dans le second cas.
- **Un mur budget peut laisser `budget-wall` seul**, sans `successor-armed` ni
  `weekly-pause` : c'est un run tué pendant le drainage. Trois fins, trois formes ;
  la troisième n'est écrite nulle part comme un état ([53]).
- **Rappel de [09], et la passe le confirme** : cette boucle ne doit **jamais**
  armer. Le marqueur est par arbre et le verrou d'arbre refuse un second run
  (`R4b`) — un successeur programmé pendant qu'un humain draine remettrait deux
  runs sur un arbre, et c'est le second qui sortirait en 1.
- **Contrainte posée par [52], livré le 30/08/2026 : `human-loop.sh` est un second
  point d'entrée, donc un second endroit où la question du `PATH` se pose.**
  `loop.sh` refuse maintenant de démarrer (`exit 2`) sur une entrée de `PATH` vide,
  relative, ou portant une tabulation — `gate_path_preflight`, appelé en
  **première ligne** de `loop_main`, avant `cd "$(ralph_project_root)"` qui est
  déjà un `git`. Ce n'est pas une convention de style : la garantie est que le
  refus arrive *avant* que le pack n'exécute un programme par son nom, et c'est
  pour ça que `loop.sh` calcule `RALPH_DIR` par expansion de paramètre au lieu de
  `dirname`. Deux choses à faire ici : appeler `gate_path_preflight` avant tout
  appel externe, et ne pas réintroduire un `dirname`, un `basename` ou un
  `git` au-dessus de cet appel dans le bootstrap. La mutation « 52 the refusal
  arrives after this pack has run a program » mesure exactement ce point sur
  `loop.sh` ; une entrée jumelle sera à écrire pour celui-ci.
- **Et un mot de journal de plus à savoir lire** ([52]) :
  `successor-blocked-path`, un run qui finit en tenant un `git`, un `claude` ou un
  `at` qu'il n'avait pas au démarrage. Comme les quatre autres
  `successor-blocked-*`, ce n'est pas `weekly-pause` et une boucle humaine qui les
  confondrait présenterait « ce projet reprend à la main » à un opérateur dont la
  machine porte une plante.

## Livraison — 31/08/2026

Deux fichiers neufs (`.claude/human-loop.sh`, `.claude/lib/router.sh`), un fichier de
test neuf (`test/human-loop.bats`, 27 tests), 20 entrées de mutation, toutes `ok`.

### Ce que la forme a été, et pourquoi

**Drainage interactif qui lance des sessions** — tranché avec Philippe avant d'écrire.
La boucle prend les deux verrous, parcourt le puits dans l'ordre, imprime un dossier
par ticket, lit la décision d'un humain sur stdin, et ouvre à la demande une session
`claude` **interactive** avec le skill routé. Cinq réponses : `o` (ouvrir), `r`
(réinjecter), `s` (sign-off), `c` (fermer), `n` (suivant), `q` (quitter).

Deux axes séparés, et c'est la décision structurante :

- **la raison** est ce que la boucle AFK a pu savoir au moment où elle a renoncé ;
- **le guichet** est la question qu'un humain doit trancher, dérivé de la raison **et
  des preuves qui existent**.

C'est ce qui répond à la question du « sixième guichet » que [26] et [23] posaient
chacun de leur côté : **aucune sixième raison n'est ouverte**. Une raison est un mot
que la *boucle AFK* écrit — l'ajouter veut dire changer ce qu'un run enregistre en
renonçant, ce qui est le ticket de [26] et se déciderait depuis le mauvais bout. Un
guichet, lui, ne coûte rien côté écriture. Huit guichets, cinq traitements (les cinq
que le critère nomme) : `grilling` en sert quatre.

### Trouvaille : `decision` a TROIS formes d'arrivée, pas deux

Le ticket en listait deux (débordement contractuel ; run mort à répétition).
`failures_quarantine_strays` (`failures.sh:594`) escalade **aussi** en `decision`
tout ticket qu'une session a écrit dans le tracker. C'est la forme la plus fréquente
en pratique, et c'est celle où il n'y a *rien* à lire : pas de branche, pas de
`Failures:`, aucun run n'a jamais tourné dessus.

Le routeur les distingue **par les preuves** et jamais par le mot :

| preuve | guichet | ce qu'on demande à l'humain |
|---|---|---|
| `failed/<id>` existe | `arbitrate` | deux tickets sur un fichier : lequel le possède ? |
| pas de branche, `Failures:` > 0 | `triage-host` | ce ticket tue-t-il son run, ou la machine avait-elle un problème ? |
| pas de branche, pas de `Failures:` | `admit` | ce ticket est-il légitime ? qui l'a écrit ? |

**`session-timeout` est fusionné dans `triage-host`, et [23] demandait que ce soit dit
à voix haute.** La question humaine est mot pour mot la même ; ce qui diffère est la
preuve, qui est déjà un axe séparé (un timeout a une branche, un plafond de reclaim
n'a que le journal). Deux guichets posant une question identique seraient deux noms
pour une décision.

`nothing-delivered` ([35]) a son guichet à lui (`readable`) et sa question porte les
**deux** routes : « pourquoi ce ticket ne fait-il rien faire à une session » et, quand
le ticket est bloqué sur des enfants tous résolus, « ce split vaut-il le ticket
d'origine ». La seconde est dérivée du tracker seul (`Blocked by:` non vide, tous
résolus) et non d'un texte de note, qui serait fragile.

`spec-gap` et `sign-off` restent dans le jeu fermé bien que **personne ne les écrive** :
un ticket qui en porte une a été posé à la main, et le drainage le dit — le lire comme
« pas une raison du tout » enverrait une demande de sign-off délibérée au guichet des
tickets que personne n'a validés.

Toute autre `Escalation:` (le retro et `capability_propose` écrivent une **phrase**,
pas un mot) tombe sur le guichet `request` : ce n'est l'échec de rien, le geste attendu
est « décider puis écrire le vrai ticket ou fermer », et la réinjection est refusée.

### Les décisions que le ticket demandait explicitement

1. **Le zéro de `Failures:` à la réinjection : oui, et dans le chemin de réinjection,
   pas dans `tracker_mark_ready`.** `mark_ready` a un second appelant (`failures_reslice`,
   qui marque un parent en attente de ses enfants) ; le vider dans l'opération prendrait
   la décision pour [11] et pour le re-slice depuis ce ticket-ci. Nouvelle opération
   d'adaptateur `tracker_clear_failures`. **La décision est prise *par chemin de
   réinjection* : [11] doit prendre la sienne** (contrainte écrite dans son ticket).
2. **Sixième guichet pour `decision` : non — voir ci-dessus.** Guichets oui, raison non.
3. **`session-timeout` et `nothing-delivered` :** chacune a sa question, et elles ne
   disent jamais « pourquoi le code est-il faux » (test dédié, `refute_output_contains`).

### Le refus qui ferme le trou de [14]

`router_may_reinject` **refuse** un ticket sans `Write-surface:`. Ce n'est pas un
avertissement : `gate_in_surface` lit une surface vide comme « rien n'est dans le
périmètre », donc une itération dépenserait une session, déborderait une surface qui
n'existe pas, et reviendrait au puits classée `decision` — c'est-à-dire en affirmant
que deux tickets sont dessinés sur un même fichier. Une session brûlée et un mot faux
dans le tracker, pour un ticket que personne n'avait encore écrit.

### Le critère anti-faux-vert, sous la forme qu'un contrôle tient

`router_sign_off` est le **seul appelant de `tracker_mark_resolved`** côté humain, et il
refuse toute raison autre que `sign-off`. Le refus est **à côté de la transition et non
dans le menu** : un point d'entrée qui oublierait de demander serait un faux vert sans
rien pour le remarquer, et il y aura un second point d'entrée ([11]).

### Les verrous : les deux, l'arbre d'abord

Le critère ne demande que le verrou de run. Le verrou d'arbre est pris quand même parce
que la forme retenue met un `claude` **non jugé** dans l'arbre principal : le verrou de
run est *par feature*, et un run qui broie une **autre** feature replie ses commits ici,
déplace HEAD ici, stage et dé-stage des chemins ici — la destruction mutuelle de [22]
par la porte que le verrou de feature n'a jamais fermée. Prix voulu par [09] : un
successeur qui se réveille pendant un drainage sort en `1`.

Le verrou de run porte désormais une **note libre** (défaut `another run`, donc message
inchangé pour l'AFK), et un run refusé par un humain lit « a human draining this
feature's sink already holds … ». **Le verrou d'arbre n'a pas été touché** : sa note
*est* le nom de la feature et une mutation de [22] s'ancre sur cet appel exact — le
message reste « another run already holds this working tree (pid N, feature X) » même
quand le détenteur est un humain. Imprécision connue, écrite au tableau de frontière.

Ça règle aussi la question de la passe du 06/08 : cette boucle écrit dans `issues/` hors
de toute itération, et **refuser de tourner pendant un run** est la réponse — le registre
de [13] n'a rien à exempter puisqu'il n'y a aucun run.

### Le défaut que les tests ont trouvé

Première version : `while IFS= read -r id; do … done <<SINK`. Un `while read` alimenté
par un heredoc sur stdin **donne ce stdin à tout ce qu'il appelle** — la première
question posée à un humain était donc répondue par la fin de la liste de travail : un
dossier imprimé, EOF, et un arrêt dont le code de sortie se lit exactement comme un
humain qui quitte. La liste voyage maintenant sur **fd 3**, stdin reste celui de
l'humain, et la session routée reçoit le terminal de la même façon.

Et le test qui l'a caché une itération : « next marks nothing at all » passait
**vacuously** — `n` et EOF laissent le même tracker et le même code de sortie. Il
refute maintenant `stdin ended`.

### Écarts de write-surface, tous délibérés

La surface déclarée était `.claude/human-loop.sh`, `.claude/lib/router.sh`,
`test/human-loop.bats`. Ont aussi été touchés :

| fichier | pourquoi |
|---|---|
| `.claude/lib/session.sh` | `session_spawn_interactive`. Mis là pour que « le seul endroit du pack qui lance `claude` » reste vrai — c'est ce qui rend les deux invocations vérifiables au même endroit ([20]). |
| `.claude/lib/tracker.sh` + `tracker-local.sh` | trois opérations neuves : `clear_failures`, `mark_wontfix`, `receipt_path`. Chacune est une décision que l'interface doit exposer, pas un champ qu'un appelant écrit. |
| `.claude/lib/state.sh` | note optionnelle sur `run_lock_acquire` (défaut conservant le message mot pour mot). |
| `test/layering.bats` | le glob lit `.claude/*.sh` et non `.claude/loop.sh` : un second point d'entrée hors du glob est un endroit où les `__` d'un lib sont atteignables sans rien pour le dire. Témoin appairé étendu. |
| `test/helpers/harness.bash` | `gate_path_recorders` déplacé en `harness_path_recorders` : deux points d'entrée doivent la même garantie de [52], et une seconde copie serait un second endroit où la mise en scène dérive. |
| `test/helpers/shims/claude` | le faux ne lit stdin que sous `-p`. Plus fidèle (un `claude` interactif ne lit pas le tube du parent) **et** nécessaire : sinon il mange les réponses du drainage. Tous les appelants AFK passent `-p`, rien d'autre ne change. |
| `test/gate.bats` | l'appel au témoin déplacé. |
| `test/mutate.sh`, `docs/frontiere-de-confiance.md` | imposés par la definition of done. |

### Ce qui n'est tenu par rien, et ce qui n'est pas sous contrat

- **Une session HITL n'est jugée par rien.** Pas de worktree, pas de scope-guard, pas de
  gate, pas de rollback, pas de scellement. Elle peut écrire tout ce que le scellement
  interdit ailleurs. Ce qui la tient est **l'absence de `--dangerously-skip-permissions`**,
  donc un humain qui approuve chaque appel d'outil. Ligne écrite au tableau de frontière,
  et c'est la plus large du document. La mutation qui ajoute ce drapeau existe.
- **Le ticket est cité comme donnée** dans le prompt (le guichet `admit` sert des tickets
  au corps tapé par une session). Atténuation, pas garantie.
- **`claude "<prompt>"` démarre une conversation amorcée par ce prompt** est une
  *hypothèse* de ce pack et pas une assertion sur lui : `test/contract-claude.bats` ne
  peut pas la vérifier — une session interactive veut un terminal et un humain. Dette [20].
- **Le comportement de Ctrl-C n'est pas testé.** Le drainage échange son handler contre
  `:` autour d'une session — `:` et non `''`, parce que bash remet un signal *traité* à
  son défaut chez l'enfant et laisse un signal *ignoré* ignoré : `trap '' INT` aurait rendu
  `claude` sourd au Ctrl-C. Raisonné et documenté, non mesuré.
- **Le gate de langue ne tourne pas ici** ([17]) : la prose qu'un humain fait écrire n'est
  jugée par rien.
- **« Ce ticket est arrivé sous un autre nom » est reconnu en grepant la phrase que
  `failures_quarantine_strays` écrit.** Rien ne marque un ticket renuméroté dans un
  champ, donc le dossier lit de la prose : deux auteurs pour une affirmation, et
  reformuler cette note éteint la ligne en silence. Ce qui borne le dégât est que ça
  ne décide qu'une phrase de contexte — jamais un routage, jamais une transition. La
  sortie propre (un champ posé par la quarantaine) appartient à [27], qui possède la
  renumérotation.

### Baseline

`bash test/run.sh` = **632 tests, 0 failures, 6 skips** (605 + 27 neufs).
`bash test/mutate.sh` = **606 mutations, 0 not ok** (586 + 20 neuves).

Une seule ancre a dérivé, et c'était le résultat attendu : `10 writing a receipt
counts as writing the ticket` s'ancrait sur la liste des lectures du dispatcheur, où
[16] a inséré `receipt_path`. Garantie revérifiée avant de recaler — `emit_receipt`
est toujours du côté lecture, donc il ne remet toujours aucun id au registre de
[13]/[42] — puis rejouée `ok`.

### Passe transversale du 31/08/2026 : trois trouvailles sur ce ticket

Sondes conservées sous `.scratch/ralph-pack/sondes/passe-31-08/`, détail dans
`.scratch/ralph-pack/passe-transversale-31-08.md`. La racine : **toutes les
garanties du pack sont des propriétés de `loop.sh`, pas du pack**, et ce ticket a
ajouté un second appelant sans en hériter aucune.

- **[55] — les deux refus lisent un champ que la session routée écrit.** La
  section « Le critère anti-faux-vert, sous la forme qu'un contrôle tient » de ce
  ticket dit vrai sur *où* la question est posée et faux sur *à quoi* :
  `router_may_sign_off` lit `Escalation:` et `router_may_reinject` lit
  `Write-surface:`, sur le ticket, dans l'arbre principal, après la session que
  ce même ticket déclare non jugée. Sondé (P1a) : `Escalation: sign-off` écrit par
  la session, `o` puis `s`, et le ticket sort **`resolved`** sans qu'aucun gate
  ait lu ce code. Témoin appairé refusé. Même trou sur la réinjection (P1c), et
  chaîne complète par le guichet `admit` (P1d).
- **[56] — une contrainte reçue et jamais dépensée.** [13] avait écrit ici, dans
  la liste des contraintes : « ce qu'un humain a de non commité n'est plus jamais
  jugé, rollbacké ni commité par la boucle AFK ». Elle n'est passée ni dans les
  décisions, ni dans le code, ni au tableau — pendant que la ligne imprimée à la
  touche `r` dit « a fresh session and the whole gate decide now ». Sondé (P2a) :
  trois itérations `tests=red`, budget brûlé, retour au puits en `Failures: 3` et
  `failed-impl`, correctif toujours dans l'arbre et jamais nommé ; commité à la
  main (P2b), vert et `resolved` du premier coup. **La liste des contraintes d'un
  ticket n'est pas une liste de choses faites.**
- **[57] — les verrous ne sont jamais redemandés.** `loop.sh` repose
  `run_lock_is_ours` et `tree_lock_is_ours` à chaque itération ; ce fichier ne les
  appelle pas. Sondé (P4a) : la session routée efface les deux verrous, la
  suivante les trouve absents, le drain ouvre ce second `claude` non jugé et finit
  le puits **sans une ligne** — là où le chemin AFK s'arrête bruyamment (P4c).

### Deux notes de plus, sans ticket

- **`human_loop__report_tracker_findings` alimente son `while read` par un heredoc
  sur stdin**, c'est-à-dire la forme exacte du défaut que ce ticket a réparé dans
  sa boucle principale (« Le défaut que les tests ont trouvé »). Rien de ce qu'il
  appelle ne lit stdin aujourd'hui — `human_loop_log` est un `printf`,
  `router_journal` écrit un fichier — donc pas de défaut, mais c'est un piège posé
  pour [11] et pour quiconque ajoutera un appel dans cette boucle. La liste
  devrait voyager sur un descripteur comme l'autre.
- **Un écart de formulation qui compte.** Ce ticket écrit, dans « Ce qui n'est
  tenu par rien » : « l'absence de `--dangerously-skip-permissions`, donc **un
  humain qui approuve chaque appel d'outil** ». Le tableau de frontière et
  `session.sh` disent la chose juste : ce n'est pas « chaque écriture est
  approuvée », c'est « le mode de permission par défaut s'applique » — un projet
  dont les `settings.json` pré-autorisent les outils d'écriture les a
  pré-autorisés ici aussi. C'est la formulation du ticket qui est trop forte.
