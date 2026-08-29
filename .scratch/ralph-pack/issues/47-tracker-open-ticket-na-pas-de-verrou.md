# 47 — `tracker_open_ticket` n'a pas de verrou, et ses deux réparations le manquent

**What to build:** Sérialiser l'attribution d'un `NN` par `tracker_open_ticket`, et décider ce qui répare une collision que **la boucle elle-même** a créée. `tracker_local__next_nn` lit le répertoire, prend le max et écrit ; il n'y a aucun verrou, et il y a maintenant trois producteurs (`failures_reslice`, l'escalade de [14], `capability_propose`). Deux ouvertures concurrentes prennent le même numéro — reproduit. La conséquence est celle de [27] et elle est permanente : un bare number cesse de résoudre, et tout ticket portant `Blocked by: NN` quitte la frontière pour de bon. Les deux contrôles qui existent ne peuvent structurellement pas l'attraper : `tracker_preflight` tourne une fois au démarrage du run, et la renumérotation de `failures_quarantine_strays` est désarmée par le registre des écritures de la boucle ([13]/[42]) — précisément parce que c'est la boucle qui a écrit.

**Blocked by:** None

**Write-surface:** `.claude/lib/tracker-local.sh`, `.claude/lib/tracker.sh`, `.claude/lib/capability.sh`, `test/tracker-local.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Deux ouvertures de ticket en vol ne prennent jamais le même `NN`. Le mécanisme existe déjà à côté : `tracker_local_claim` fait sa lecture-écriture sous `state_guard_take` pour exactement cette raison, et l'écrit.
- [x] La dédup de `capability_propose` ne peut plus ouvrir deux fois la même proposition : elle lit `tracker_ids` avant d'écrire, donc elle a la même course par le même bout.
- [x] Une collision qui existerait quand même a un chemin de réparation, ou une phrase qui dit qu'elle n'en a pas. Aujourd'hui elle n'a ni l'un ni l'autre : elle naît après le préflight et le registre exempte celle de la boucle.
- [x] Le tableau de `docs/frontiere-de-confiance.md` dit ce qui tient « un ticket est identifiable par son `NN` » **quand c'est la boucle qui écrit**. La ligne actuelle ([27]) parle du mauvais écrivain.

## Comments

- **Origine : passe transversale du 26/08/2026**, sur `main` à `3d6915b`. Document dans `.scratch/ralph-pack/passe-transversale-26-08.md`, sondes conservées dans `.scratch/ralph-pack/sondes/passe-26-08/` (`p4.bats` P4a, `p5.bats` P5a). L'angle avait été **écrit** par [15] dans [13] et dans [27] ; la passe l'a reproduit, et a trouvé que ces deux tickets-là sont `resolved` — donc qu'aucun ticket ouvert de la file ne le lirait jamais. C'est ce ticket qui leur donne un propriétaire.

- **La fenêtre est plus large qu'on ne la lit.** `tracker_local_open_ticket` calcule `nn` **avant** de lire le corps sur stdin (`body="$(cat)"` vient après). Elle reste donc ouverte aussi longtemps que l'appelant met à produire ce corps — ce qui, pour un re-slice, est le temps d'un plan. La sonde s'en sert : elle tient la première ouverture sur un fifo, fait passer la seconde en entier, puis relâche.

      === second opened: 03-second
      === first opened: 03-first
      === tracker
      01-alpha.md  02-beta.md  03-first.md  03-second.md
      === can a bare number resolve?
      rc=1 out=tracker: "03" matches 2 tickets — an ambiguous id is never safe to resolve

  Et le ticket bloqué sur `03` ne rentre plus dans la frontière : `tracker_local__is_unblocked` rend faux dès que `tracker_local__path` refuse.

- **Les deux réparations, et pourquoi aucune n'agit.**

  *`tracker_preflight`* nomme parfaitement le cas — sondé, il rend `03 ambiguous-id two or more tickets carry the number 03 (03-first, 03-second)`. Il tourne **une fois, au démarrage du run** ([27] : « ce qui reste est un humain éditant le répertoire à la main »). Cette collision-là naît en cours de run, donc il ne la verra qu'à la nuit suivante, quand les tickets qui pointent dessus sont déjà sortis de la frontière.

  *`failures_quarantine_strays`* renumérote — c'est tout le sens de [27] — mais seulement ce qui n'est pas dans le registre des écritures de la boucle ([13], lu par les deux gardes depuis [42]). Sondé côte à côte (`p5` P5a), les deux moitiés du même appel :

      === the loop created them (ids in the register)
      rc=0 tracker: 01-alpha.md 02-first.md 02-second.md
      === a session created them (empty register)
      ralph: … quarantined 03-first 02-second
      ralph: … renumbered 02-first -> 03-first

  **Le registre qui protège les écritures de la boucle est exactement ce qui désarme la réparation quand c'est la boucle qui a écrit la collision.** Deux mécanismes corrects séparément, un trou à leur composition — la question 4 de `CLAUDE.md`. Ne pas « corriger » en faisant lire le registre autrement : l'exemption est juste, et [42] a coûté un ticket pour l'installer. Ce qui manque est en amont.

- **Ce que la sonde ne prouve pas, et qu'il ne faut pas prétendre.** Elle met les deux ouvertures en vol à la main, avec un fifo. Elle ne mesure pas la probabilité de la course en exploitation, et un test qui la mesurerait mesurerait la machine — le harnais a déjà payé cette leçon deux fois. Le test qui tient la garantie doit être au niveau du module, comme celui de la clé du brief de [14] : deux appels sérialisés par le garde, pas deux processus lancés en espérant.

- **Ordre.** Avant [16] et [18] : [16] vide le puits où les doublons de proposition atterrissent, et [18] doit implémenter `open_ticket` sur un backend distant — `tracker.sh` lui dit déjà qu'il doit répondre à « que fait `tracker_ids` quand deux tickets réclament un identifiant », et il vaut mieux qu'il hérite de la réponse que de la redécouvrir.

- **Ce que [37] laisse ici, livré le 27/08/2026.** La liste sur laquelle ce ticket
  va travailler est maintenant sûre à lire : `tracker_ids` voyage à raison d'un id
  par ligne et se compare ligne entière, donc un ticket nommé `99-my ticket.md` n'est
  plus deux ids fantômes au milieu d'une allocation de numéro. Concrètement,
  `tracker__carriers`, `tracker__is_ambiguous`, `tracker__count` et
  `tracker__ambiguous_numbers` ont changé de forme (heredoc + `while IFS= read -r`
  au lieu de `for id in $ids`, comptage de lignes au lieu de `wc -w`) : une
  réparation qui touche `tracker_local__next_nn` ou le préflight doit repartir du
  code tel qu'il est, pas de ce que cette page décrivait avant. La renumérotation et
  `tracker_local__path` n'ont **pas** bougé — tout y était déjà cité, glob compris.

- **Livré le 27/08/2026.** Ce que le code ne dit pas, dans l'ordre où ça a compté.

  **Le garde ne va pas dans `issues/`, et c'est la seule décision de placement qui
  ait un coût.** `tracker_local_claim` met le sien à côté du ticket
  (`$file.guard`), donc le réflexe était d'y mettre celui-ci. `issues/` est
  exactement l'arbre que `failures_protect_tracker` snapshotte en objet git
  autour de chaque session : un répertoire de garde pris là pendant qu'une
  itération voisine compare ses deux snapshots arrive comme un chemin `A`/`D`
  que la restauration tenterait de `checkout-index`. Le claim s'en tire parce
  que sa fenêtre est de l'ordre de la milliseconde et qu'il tombe *avant* le
  spawn ; une ouverture, elle, tombe **dans** la fenêtre d'une sœur, par
  construction (re-slice, escalade du retro, proposition). Le garde vit donc
  dans le répertoire de la feature, à côté du verrou de run, et il en hérite
  l'exposition — une session peut le supprimer ([12]). C'est écrit dans le
  tableau plutôt qu'ici parce que c'est une frontière de confiance et pas un
  détail d'implémentation.

  **`$$` est le pid du pilote dans toutes les itérations**, une itération étant
  un sous-shell (`loop__iterate … &`) et bash ne changeant pas `$$` dans un
  sous-shell. Conséquences, les deux vraies : `state_guard_take` voit toujours
  un propriétaire vivant tant que le pilote vit, donc un garde laissé par une
  itération morte n'est pas récupéré mais attendu (c'est le bon ancrage ici — si
  le pilote est mort, plus rien n'alloue) ; et `state_guard_release` d'une
  itération pourrait relâcher le garde d'une sœur, ce qui ne se produit pas
  parce que chaque relâche suit une prise réussie dans la même fonction. Le
  claim a déjà cette propriété ; personne ne l'avait écrite.

  **L'ordre corps/numéro est la moitié de la trouvaille, pas un détail de
  style.** Déplacer `body="$(cat)"` avant l'allocation était nécessaire *avant*
  de poser le garde : avec l'ordre d'origine, le garde aurait été tenu pendant
  la production du corps par l'appelant, c'est-à-dire que l'espace des numéros
  entier aurait attendu le stdin de quelqu'un — pour un re-slice, le temps d'un
  plan. Le correctif « évident » (envelopper la fonction telle quelle dans un
  garde) transformait une collision en interblocage de fait.

  **`tracker_renumber` est le second écrivain de l'espace des numéros** et il
  n'était pas dans la description du ticket. La quarantaine l'appelle depuis une
  itération pendant qu'une sœur peut ouvrir un enfant de re-slice ; sans le même
  garde, renumérotation et ouverture se distribuent le même `NN`. Le corps est
  passé en `tracker_local__renumber_held` (non gardé) pour que rien n'imbrique
  deux prises du même garde — un garde réentrant aurait été la porte de sortie,
  et il aurait fallu l'écrire.

  **La dédup est devenue une opération de l'adaptateur (`tracker_open_unique`),
  pas un garde exposé.** Trois options ont été pesées. Exposer une paire
  prendre/relâcher publique était layering-légal mais fausse : `open_ticket`
  prend le même garde, donc un appelant qui l'aurait tenu aurait attendu
  lui-même. Un troisième argument optionnel sur `open_ticket` laissait un
  backend distant ignorer le drapeau en silence et rouvrir le doublon. Une
  opération séparée échoue à voix haute (`does not implement open_unique`,
  rc 3) : c'est l'issue à préférer, et c'est écrit dans l'en-tête de
  `tracker.sh` pour [18].

  **Ce que le dispatcher devait apprendre, et pourquoi la première entrée de
  mutation était VACUOUS.** `open_unique` est routé avec `open_ticket` et
  `renumber` : le registre veut l'**id** rendu et jamais le slug reçu, sans quoi
  la proposition que la boucle vient d'ouvrir est mise en quarantaine par la
  sœur comme du travail qu'une session s'est donné ([42]). La première version
  de l'entrée nommait `test/capability.bats` — VACUOUS, et le diagnostic n'est
  pas que le test ment : `capability_propose` est appelé par le retro, donc
  *après* la quarantaine de sa propre itération, et la quarantaine suivante part
  d'un snapshot qui contient déjà la proposition. La garantie n'est observable
  qu'à `MAX_PARALLEL>1`. Le test est descendu au module (registre asserté
  directement), exactement comme `failures.bats` le fait pour `open_ticket`.
  C'est la troisième fois que ce dépôt paie « la garantie est vraie, la sonde
  bout en bout ne peut pas la voir ».

  **Un appelant qui n'obtient pas le garde refuse, il n'alloue pas.** 120 essais
  × 0,05 s = 6 s, le même bornage que le garde de l'index de leçons. Ce que ça
  coûte est nommé : un re-slice rend un split incomplet à un humain, une
  proposition tombe dans la ligne du reçu qui disait déjà « ou le tracker a
  refusé l'écriture » — cette ligne existait avant ce ticket et couvre le cas
  sans un mot de plus.

  **Ce qui n'a pas été construit, et pourquoi.** Une vérification après écriture
  (« le numéro que je viens de prendre est-il porté par mon seul fichier ») a
  été écrite puis retirée : sous le garde elle est du code mort, et aucune sonde
  ne peut l'atteindre — `tracker_local__number_taken` et `tracker_local__path`
  appliquent exactement le même glob, donc il n'existe pas de nom de fichier que
  l'une voie et l'autre pas. Une garantie qu'aucun test ne peut rendre rouge n'a
  pas été livrée ; la réparation manquante est devenue la phrase que l'AC
  autorisait, dans le tableau.

  **Pièges de harnais rencontrés.** Une entrée de mutation qui vise
  `tracker_local__open_guard_take` seul casse *les deux* garanties (ouverture et
  renumérotation) : les deux entrées s'ancrent donc sur les deux lignes de
  `printf` qui diffèrent, pas sur la ligne de prise qui est identique. Et
  l'entrée [14] `an escalation waiting for a human is opened again every night`
  a DÉRIVÉ — attendu, la ligne porteuse a changé de fichier
  (`capability.sh` → `tracker-local.sh`) sans changer de forme ; garantie
  revérifiée, ancre recalée, entrée rejouée `ok`.

  **Ce que ça laisse aux suivants.** [18] hérite d'une clause d'interface de
  plus : un backend distant doit répondre à `open_unique` ou être refusé à voix
  haute, et il doit dire ce que fait sa création concurrente. [16] vide le puits
  où les propositions atterrissent et peut désormais compter sur « une
  proposition par slug » plutôt que sur la chance. Le test de la fenêtre
  corps/numéro (`a body that is slow to arrive does not hold a number`) contient
  un `sleep 0.5` dont le rôle est d'ouvrir la fenêtre côté *muté*, jamais
  d'ordonner une assertion : l'ordre est tenu par un fifo, et le test est vert
  sur du code correct quelle que soit la charge. Si cette entrée de mutation
  revient VACUOUS sous charge un jour, c'est le sleep qu'il faut allonger, pas
  le test qu'il faut réécrire.

- **Ce que la passe transversale du 27/08/2026 a trouvé sur ce ticket, et ce qu'elle a disculpé.** Deux corrections à sa ligne du tableau, portées par [49]. (1) « Le garde vit dans le répertoire de la feature et pas dans `issues/` » est le bon diagnostic, appliqué à un seul garde : celui du **claim** est toujours dans `issues/`, et l'argument « sa fenêtre est de l'ordre de la milliseconde et il tombe avant le spawn » ne vaut que pour le claim de l'itération elle-même — une sœur claime où elle tombe, et le transitoire ressuscité sort son ticket de la frontière pour le reste du run (`q5`). (2) « une session peut le supprimer, et ce que ça lui rachèterait n'est qu'une collision » ne nomme qu'une direction : une session peut aussi le **poser**, depuis une itération verte, et ça éteint les trois producteurs de tickets **plus** `tracker_renumber` — donc la réparation de [27] — pour la nuit et pour les runs suivants (`q2`). Disculpés, à ne pas resonder : `state_guard_release` avec deux sœurs en vol (la sœur refusée ne relâche rien, `q4` Q4c) ; la double reprise d'un garde périmé (barrière d'attente active, `both=0` sur 300 tours — la course est stagée, pas gagnée) ; l'invisibilité du garde aux gates, qui est structurelle (les branches jugent le worktree, `ralph_feature_dir` résout dans l'arbre principal) et le met au même rang que `.run.lock` ; et le refus bout en bout du re-slice, qui marche et se dit sur le reçu (`q3`). Mesures au passage : la borne annoncée à 6 s vaut **8 s**, et `tracker_renumber` la paie par intrus.

- **Complété par [49], livré le 29/08/2026, sur quatre points de ce ticket.**
  (a) Le tableau de confiance ne chiffrait que la **suppression** du garde ; la
  **pose** vaut l'espace des numéros entier — les trois producteurs et
  `tracker_renumber` — pour la nuit et les runs suivants, et c'est écrit là
  maintenant. (b) La cause d'un refus d'allocation atteint le **reçu**
  (`tracker_local__open_refused`, pid détenteur et depuis quand) au lieu de deux
  `printf … >&2` ; les trois producteurs disaient déjà qu'aucun ticket n'avait été
  ouvert, aucun ne pouvait dire pourquoi. (c) Un `.open.guard` laissé par un run tué
  est compté au démarrage du run suivant (`gate_leftovers`, sur la liveness du
  propriétaire) — il traversait un run vert entier en silence, ce garde n'étant
  relâché par aucun trap là où le verrou de run l'est par le sien. (d) L'argument
  écrit ici pour laisser le garde du claim dans `issues/` — « sa fenêtre est de
  l'ordre de la milliseconde et il tombe avant le spawn » — est faux pour une
  **sœur**, et la conclusion tient pour une autre raison : la correction est du côté
  du garde qui compare les arbres. La borne d'attente annoncée à six secondes en vaut
  huit, mesurées.
