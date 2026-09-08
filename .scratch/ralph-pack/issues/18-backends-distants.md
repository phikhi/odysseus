# 18 — Backends distants github + gitlab

**What to build:** Les implémentations distantes de l'adaptateur de tracker, satisfaisant **la même interface** que `local`, avec la forme d'intégration façonnée par le backend (claim = assignee, reçu = PR, `wait_ci`). La boucle reste agnostique.

**Blocked by:** 02, 10, 64, 65, 66, 70, 71

**Write-surface:** `.claude/lib/tracker-github.sh`, `.claude/lib/tracker-gitlab.sh`, `test/tracker-remote.bats`

**Status:** resolved

- [x] Les adaptateurs `github` et `gitlab` satisfont l'interface fixe ; la boucle reste agnostique (aucun changement de control-flow).
- [x] En distant : claim = assignee ; reçu = la PR ; liveness du claim en **sidecar local** (concurrence mono-machine).
- [x] `wait_ci` est ON par défaut si une CI est détectée (opt-out `WAIT_CI=off`) → intégration PR-par-itération.
- [x] Le même scénario e2e que `local` (piloté par une API mockée) produit les mêmes transitions d'état observables.
- [x] `tracker_ids` est implémenté par les deux backends ; un backend qui ne la fournit pas est détecté, pas subi.

## Comments

- **Contrainte posée par [05] : l'interface a une 8ᵉ opération, `tracker_ids`** (tous les tickets, quel que soit leur état, min-NN d'abord). Le scope-guard s'en sert pour distinguer un débordement dans un fichier neutre d'un débordement dans la write-surface d'un **autre** ticket. Attention au mode de panne : `tracker__dispatch` renvoie 3 pour une opération non implémentée, mais l'appelant (`gate__surface_owner`) itère sur une liste vide et conclut simplement que personne ne revendique le chemin. Un backend distant qui oublie `tracker_ids` **dégrade donc en silence** — tout drift contractuel devient un débordement interne, donc retry au lieu d'escalade. À traiter ici : implémenter l'opération, et/ou durcir le gate pour qu'une classification impossible escalade au lieu de se taire.
- Coût à surveiller : `gate__surface_owner` appelle `tracker_ids` puis lit un champ par ticket, pour chaque fichier hors surface. Bénin sur des fichiers markdown, à revoir si chaque lecture devient un appel réseau (cache par itération).
- **Contrainte posée par [07] : une 9ᵉ opération, `tracker_block_on ID DEPS`** (retenir un ticket jusqu'à ce que les tickets listés soient `resolved`, en conservant les blocages déjà présents). Le re-slice s'en sert : le ticket trop gros est bloqué sur les tickets plus petits qu'il a produits, puis revient en frontière. Même mode de panne silencieux que `tracker_ids` : un backend qui ne l'implémente pas renvoie 3, et l'appelant continue — le parent repartirait alors en frontière **sans être bloqué**, donc serait re-tenté immédiatement et re-slicé en boucle. À implémenter, ou à faire échouer bruyamment.
- **Contrainte posée par [21] : le backend distant n'a aucune protection du tracker, et le silence est le mode de panne.** `failures_protect_tracker` compare deux tree objects de `.scratch/<FEATURE>/issues` autour du spawn et restaure ce qu'une session y a édité — un chemin de fichiers plus git, donc intrinsèquement le backend `local`. Sur un backend distant, le répertoire n'existe pas : les deux snapshots sont le tree vide, le delta est nul, et la protection **rend 0 sans un mot**. Pas d'erreur, pas de log, pas de garde. Or ce que la protection tient est ce qui rend le scope-guard fiable : sans elle, une session distante qui édite l'issue qu'elle est en train de livrer élargit sa write-surface, et le gate la juge sur la surface élargie. À traiter ici, et le choix doit être explicite plutôt qu'hérité : soit une opération d'adaptateur (snapshot/restore de l'état des tickets, ce que l'API permet de faire autrement), soit un refus bruyant tant que rien ne garde la zone. Un `return 0` silencieux est la forme exacte du faux vert que [21] vient de refermer.
- **Contraintes posées par [12] (liveness du claim), livré le 29/07/2026.** La liveness est **toujours locale** (spec §152) et la politique est backend-agnostique, donc elle impose deux choses au backend distant.

  1. **La forme du champ `Claimed:` est de l'interface, pas un détail du backend `local`.** `tracker_field ID Claimed` doit rendre `owner=<qui> at=<iso8601>` — la politique a besoin de savoir *qui* pinger et *quand* le claim a été pris. Documenté au-dessus de `tracker_field` dans `lib/tracker.sh`. Un backend qui rend autre chose ne casse rien de visible : la politique est fail-open, donc elle réclamera **tout**, ticket par ticket, en boucle. Le symptôme sera dans le tracker, pas dans une erreur.
  2. **Un owner qui n'a pas la forme `pid:<n>` est jugé par `CLAIM_TTL` seul** — pas réclamé à vue. C'est délibéré : `kill -0` n'a aucun sens sur un assignee, et voler le ticket d'un humain serait pire qu'attendre le backstop. Conséquence à traiter ici : avec un backend distant **et** `CLAIM_TTL=0` (« pas de backstop », la même lecture que `GATE_TIMEOUT`), plus rien ne réclame jamais un claim. C'est exactement le wedge illimité que la liveness en sidecar de ce ticket doit refermer — le prévoir, ou refuser `CLAIM_TTL=0` au préflight quand le backend est distant.

- **Fragilité à connaître, mesurée par la passe transversale du 29/07/2026 : `awk -v` interprète les échappements de la valeur qu'on lui passe.** `tracker_local__patch_field` écrit un champ via `awk -v v="$value"`, et awk traite `\n`, `\t`, `\\` dans une assignation `-v` comme des séquences d'échappement. Vérifié : `v='a\nb'` produit une **vraie** newline dans le fichier, ce qui coupe le ticket en deux — le champ suivant tombe dans le corps et `tracker_local__field_of_file` ne lit plus que `a`. Aucune valeur n'est aujourd'hui d'origine hostile (les raisons d'escalade sont des littéraux du pack, `owner` est `pid:$$`, les blocages sont des chiffres), donc ce n'est pas une faille — c'est une fragilité qui devient exploitable **ici** : ce ticket doit rendre le champ `Claimed` (`owner=<who> at=<iso8601>`) depuis des données serveur, et un nom d'assignee est une chaîne que le pack ne choisit pas. Assainir la valeur, ou cesser de la passer par `-v`, fait partie de ce que ce ticket doit décider.

- **Contrainte posée par [26], livré le 29/07/2026 : deux obligations de plus sur l'interface, dont une invisible si elle est manquée.**

  1. **`mark_resolved` doit lâcher `Failures:` en même temps que le claim.** Un backend qui garde le champ recrée le défaut que [26] vient de fermer : un compteur cumulatif sur toute la vie du ticket, donc un ticket escaladé `failed-impl` **après** avoir été livré vert deux fois. Rien ne rougit : le compteur est une entrée du tracker, pas un code de retour. Écrit au-dessus de `tracker_field` dans `lib/tracker.sh`, et testé au niveau de l'adaptateur dans `test/tracker-local.bats` — un backend distant devra porter le même test.
  2. **Un `owner` que le pack ne pingue pas ne fait plus seulement « attendre le TTL », il ne fait plus payer l'attente.** Le point 2 ci-dessus reste vrai et se complète : rendre un assignee (`owner=assignee:<nom>`) dit maintenant deux choses à la boucle — ne le pingue pas, et ne facture pas de retry au ticket quand le backstop le reprend. Seul `owner=pid:<n>` est facturé. Un backend qui rendrait un assignee **sous** la forme `pid:<n>` pour « simplifier » ferait payer aux humains le budget de retry du ticket, sans autre symptôme qu'une escalade prématurée.

- **Une contrainte de plus, de la passe du 30/07/2026 : tout fichier de configuration qu'un backend distant ferait sourcer par le run suivant (jeton, endpoint) tombe sous [31], pas sous ce ticket.** Le critère est celui de [24] — « un `claude` frais le lit au démarrage, ou le run suivant le source » — et [31] existe parce que la liste qui l'implémente était plus étroite que lui, y compris pour `RALPH_CONFIG` sous un autre nom.

- **Contrainte posée par [27], livré le 03/08/2026 : une 14ᵉ opération, et une question à trancher dans ce ticket.** `tracker_renumber ID` rend l'id que le ticket porte après l'appel, et sert à un seul endroit — la quarantaine, sur ce qu'une session a ajouté au tracker. Sur le backend local elle défait une collision de `NN` qu'un renommage de session produit à partir de deux décisions correctes de [21]. Un backend qui numérote côté serveur ne peut pas avoir cette collision : il rend l'id inchangé, ce qui est une réponse légitime — mais qui doit être **écrite ici** et non déduite du fait que ça marche. Corollaire : `tracker_preflight` n'est pas dispatché, il se déduit de `tracker_ids` et `tracker_field` parce que la question porte sur la forme des ids. Il tournera donc tel quel sur ce backend et n'y trouvera rien. Si un identifiant distant peut se retrouver porté par deux tickets — une migration, un miroir, un import — c'est à ce ticket d'ajouter sa propre question au préflight plutôt que de laisser un scan générique répondre « rien à signaler » sur un cas qu'il ne connaît pas.

- **Contrainte posée par [10], livré le 07/08/2026 : deux choses sur `emit_receipt`, dont une qui ne se voit pas.**

  1. **`emit_receipt` ne compte pas comme une écriture de ticket.** Le dispatcher notait toute opération hors des quatre lectures dans le registre de [13] ; `emit_receipt` en est désormais exempté, et le critère de la liste est redit dans le code : la question est « la boucle a-t-elle écrit le ticket qu'un garde d'`issues/` va comparer », pas « est-ce que ça touche le disque ». Un adaptateur distant qui rendrait le reçu comme une PR répond non à cette question et l'exemption tient. Un adaptateur qui, en émettant le reçu, **écrirait aussi le ticket** (un commentaire, un label, un lien) y répond oui : il doit alors noter l'id lui-même, sans quoi la restauration et la quarantaine d'une itération sœur défont son écriture — en silence et seulement au-dessus de `MAX_PARALLEL=1`.
  2. **Le reçu arrive par stdin et le backend rend un emplacement sur stdout.** Le contenu est du markdown assemblé par la boucle : titre, verdicts, findings des branches rouges, zones non jugées, méta, et le travail **par référence** (`git show <sha>`, `git diff-tree -r <base> <tree>`, `git log -p failed/<ticket>`). Ces références sont des objets du dépôt local. Un backend distant qui rend le reçu comme une PR doit décider ce qu'elles deviennent chez lui — une PR qui dit « lisez `git show 4f2ab9c` » à quelqu'un qui n'a pas le dépôt ne référence rien. Ne pas régler ça en inlinant le diff : c'est l'AC que [10] a refusée, et pour la raison qu'un reçu n'est pas une seconde copie du dépôt.

- **Contrainte posée par [14], livré le 24/08/2026 : la quatrième couche ne passe pas par l'adaptateur, et c'est une décision.** `LEARNINGS.md`, `learning-records/` et `docs/adr/` sont écrits **directement dans l'arbre du projet**, jamais par `tracker_emit_receipt` ni par aucune opération dispatchée. Un backend distant reçoit donc son reçu en PR et garde ses leçons en local. La raison est celle du scellement : l'index est inliné dans le prompt de chaque session fraîche, donc c'est le prompt — et un prompt servi depuis un service distant serait un prompt que ce pack ne peut ni sceller, ni comparer à une copie qu'il a prise lui-même. Si ce ticket veut publier les leçons ailleurs, la direction qui reste honnête est **sortante seulement** : le pack écrit son index, un adaptateur peut le recopier vers un service, et rien de ce qui revient d'un service n'entre dans un prompt.

  Le canal de reprise entre deux tentatives ([14] sur [10]) est dans le même cas et pour une raison de plus : il vit dans `$TMPDIR` sous un nom que le pilote n'exporte pas, donc il n'a pas d'existence hors du run et il n'y a rien à publier.

- **Contrainte posée par la passe transversale du 26/08/2026 : `open_ticket` doit répondre à
  la question de [47] avant d'exister.** `tracker.sh` dit déjà qu'un backend dont les ids ne
  peuvent pas entrer en collision « doit encore à son propre ticket une réponse à la question
  en dessous ([27]) : que fait `tracker_ids` quand deux tickets réclament un identifiant ».
  La passe a montré que le backend `local` y répond mal : `tracker_local__next_nn` n'a aucun
  verrou, trois producteurs, et les deux réparations existantes manquent la collision que la
  boucle crée elle-même. Un backend distant qui numérote côté serveur hérite gratuitement de
  la moitié « id », **pas** de la moitié « dédup » : `capability_propose` déduplique en
  lisant `tracker_ids` avant d'écrire, ce qui est une course quel que soit le backend. Livrer
  après [47] et hériter de ce qu'il aura décidé, plutôt que le redécouvrir sur une API.

- **Contrainte posée par [47], livré le 27/08/2026 : une 15ᵉ opération, `tracker_open_unique
  SLUG TITLE`, et c'est un refus bruyant qu'elle achète.** « N'ouvre pas si un ticket porte
  déjà ce slug » est devenu une **opération de l'adaptateur** au lieu d'une lecture que
  l'appelant fait avant d'écrire : `capability_propose` lisait `tracker_ids`, ne trouvait
  rien et ouvrait, donc deux propositions en vol n'en trouvaient aucune et en ouvraient deux.
  La question et l'écriture doivent tomber du même côté de ce qui sérialise la création, quel
  que soit le backend — un backend qui numérote côté serveur hérite de la moitié « id » et
  **pas** de celle-ci. Trois choses à écrire ici plutôt qu'à déduire. *(1)* Ne pas
  l'implémenter n'est pas un dégradé silencieux : `tracker__dispatch` rend 3 avec
  `does not implement open_unique`, ce qui a été **préféré** à un drapeau optionnel sur
  `open_ticket` qu'un backend pourrait ignorer sans un mot. *(2)* La sémantique du retour est
  « rien sur stdout et succès » quand la proposition existait déjà — l'appelant lit le vide,
  jamais un code de sortie, parce que « déjà en attente d'un humain » est une réussite.
  *(3)* Le dispatcher note dans le registre de [13] l'**id rendu** et non le slug reçu, et
  n'écrit **aucune ligne** quand rien n'a été ouvert : une création qui n'a pas eu lieu n'est
  pas une écriture à exempter, et une ligne de trop donnerait aux deux gardes de [42] un id à
  sauter pour un ticket que ce run n'a pas touché. Le backend local sérialise par un garde
  (`state_guard_take`) dans le répertoire de la feature ; un backend distant doit dire ce qui
  tient l'équivalent chez lui, ou dire que rien ne le tient.

- **Contrainte posée par [37], livré le 27/08/2026 — une clause d'interface, pas un
  détail du backend local.** `tracker_ids` et `tracker_frontier` doivent rendre **un
  id par ligne** ; c'est écrit dans l'en-tête de `lib/tracker.sh` et tous les
  consommateurs du pack lisent ligne par ligne et comparent des **lignes entières**
  (`failures__in_list`, `claim__among`, `tracker__holds_exactly`). Un adaptateur qui
  rendrait une ligne de mots rouvre quatre pannes d'un coup, et aucune n'est
  cosmétique : une quarantaine qui annonce avoir escaladé un ticket resté sur la
  frontière, un registre ([13]/[42]) qui exempte chaque *mot* d'un id, un
  débordement de surface classé retryable au lieu de `contract`, et un claim de run
  mort jamais balayé. Les sondes sont dans `.scratch/ralph-pack/sondes/37/`. La
  limite de cette convention est nommée et ouverte comme [48] : un nom de fichier
  peut contenir un saut de ligne, qu'un heredoc ne peut pas porter — si [48] change
  le transport, c'est cette clause-là qu'il faut relire ici.

- **Seconde clause d'interface, posée par la passe transversale du 27/08/2026.** Le répertoire du tracker ne contient pas que des tickets : le backend local y écrit trois sortes de transitoires (`<id>.md.guard/` du claim, `<id>.md.tmp.XXXXXX` de `state_atomic_write`, `<id>.md.work.XXXXXX` et `.work.XXXXXX.p` de `set_fields`), et `failures_protect_tracker` les prend pour des éditions de ticket — il les restaure, accuse la session, et refuse le vert. Un backend distant a le même problème sous une autre forme : tout ce que son *stockage* montre au garde et qui n'est pas un ticket. Ce qu'il doit dire est donc « ce que `read_ticket`/`ids`/le snapshot rendent est un ticket, et rien d'autre n'y transite », ou bien fournir sa propre borne. Le correctif et la décision appartiennent à [49] ; cette clause rejoint « un id par ligne » ([37]) dans l'en-tête de `lib/tracker.sh`.

- **Troisième clause d'interface, posée par [39], livré le 27/08/2026.** La convention
  « un id par ligne » ([37]) et « un chemin par ligne » ([33]) ont toutes deux une
  frontière qui n'était écrite nulle part : ce que le producteur fait d'un nom qu'il
  ne peut pas imprimer tel quel. Pour le backend local la réponse vient de git, et
  elle est *bonne* — `core.quotePath=false` rend les noms hors ASCII tels quels, et
  git cite encore, **sur une seule ligne**, les noms portant un caractère de contrôle.
  C'est ce qui rend la convention sûre : un nom à saut de ligne ne coupe jamais une
  liste en silence, il arrive comme quelque chose d'inadressable que chaque
  consommateur refuse à voix haute (`gate_unaddressable`). **Un backend distant n'a
  pas cette propriété gratuitement.** Un adaptateur qui rendrait un id ou un chemin
  brut, saut de ligne compris, casserait la convention exactement là où le backend
  local ne la casse pas — et sans bruit. Ce qu'il doit dire : soit son transport ne
  peut pas produire une entrée multiligne, soit il cite lui-même ce qu'il ne peut
  pas rendre tel quel. L'argument complet et le prix de l'alternative (`-z`, neuf
  lecteurs) sont dans la ligne « Un fichier dont le nom n'est pas de l'ASCII pur est
  adressable par le pack » de `docs/frontiere-de-confiance.md`.

- **Clause héritée de [49], livré le 29/08/2026.** Le répertoire du tracker ne
  contient pas que des tickets : le backend local y pose un garde de claim, le
  temporaire de chaque écriture atomique et la copie de travail de `set_fields`. Un
  garde pris autour d'une session — la restauration de [21] ici, l'équivalent
  ailleurs — ne doit pas prendre ces objets pour une édition de la session, et le
  registre des écritures de la boucle ne peut pas les exempter parce qu'il est indexé
  par **id**. Ce backend-ci répond par un prédicat (`failures__is_ticket_path` :
  directement dans `issues/`, suffixe `.md`) ; un backend distant doit répondre à la
  même question pour la forme qu'il stocke, et dire ce qu'il fait de ce qui n'est pas
  un ticket. Corollaire déjà écrit ailleurs : un garde qui vit sur un ticket voyage
  avec ce ticket, celui qui sérialise l'espace des numéros vit à côté du verrou de run.

- **Contrainte posée par [16], livré le 31/08/2026 : l'interface a trois opérations de
  plus, et chacune pose une question qu'un backend distant doit répondre pour lui-même.**
  Elles sont documentées dans l'en-tête de `lib/tracker.sh` avec le reste ; ce qui suit
  est ce qu'un backend distant ne peut pas hériter du local sans se tromper.

  1. **`tracker_clear_failures ID`** — rendre au ticket tout son budget de retries, sans
     passer par `resolved`. Le backend local *retire* le champ. Un backend qui range le
     compteur ailleurs qu'en champ de ticket (un label, un champ personnalisé, un
     sidecar) doit répondre lui-même : `mark_resolved` doit le vider aussi, sinon c'est
     le compteur cumulatif que [26] a retiré, reconstruit sous un autre nom.
  2. **`tracker_mark_wontfix ID`** — fermé par un humain. Un état que le backend local
     nommait déjà et qu'aucun producteur n'écrivait ; c'est le drainage qui l'écrit
     maintenant. Il lâche `Escalation:` **et** `Failures:` : un ticket fermé qui porte
     encore une raison d'escalade se lit, au prochain grep, comme un ticket qui attend
     toujours un humain.
  3. **`tracker_receipt_path ID`** — où le reçu de ce ticket se lit, non-zéro et
     silencieux quand il n'y en a plus. C'est une **lecture**, donc elle ne passe pas au
     registre de [13]/[42]. Elle existe parce que le puits humain est le lecteur du reçu
     ([10]) et n'a pas le droit de savoir comment un backend en range un : sur le local
     c'est un fichier sous `receipts/<feature>/`, **sur toi c'est la pull request**. Un
     drainage qui construirait le chemin lui-même répondrait « aucun reçu » sur tout
     backend qui n'utilise pas de fichiers, ce qui se lit comme « rien n'a été écrit sur
     ce ticket ». Et `RECEIPTS_RETENTION_DAYS` balaye le local : « non-zéro quand il n'y
     en a plus » est le contrat, pas « le fichier existe ».
- **Et ce que le puits humain lit sur tes tickets** : `router_desk` distingue les trois
  arrivées de `decision` par les preuves — l'existence de `failed/<id>` et la valeur de
  `Failures:`. La branche est une **ref git locale** ; sur un backend distant elle peut
  vivre ailleurs, et un ticket dont l'arbre de tentative est une PR fermée sera routé sur
  le guichet `admit` (« aucun run n'a jamais jugé ceci »), ce qui est faux. Si ce ticket
  déplace la trace forensique, il possède la question de savoir comment le routeur la
  trouve.

- **Contrainte posée par [11], livré le 04/09/2026 : le gate de valeur compte ses
  propres tickets en lisant le slug dans l'id. PÉRIMÉE — remplacée par [65],
  livré le 05/09/2026 ; la version vivante est plus bas, « Seconde contrainte de
  la même passe ». Gardée telle quelle pour que le remplacement se lise.**
  `playthrough__injected` compte les
  tickets `*-playthrough-wiring-*` que la feature porte déjà, et c'est **ce compte**
  que `PLAYTHROUGH_REINJECT_MAX` borne — délibérément lu dans le tracker plutôt que
  gardé dans une variable du run, parce qu'un compteur en mémoire se remet à zéro
  au redémarrage et ne bornerait plus rien sur une nuit qui a planté. Un backend
  qui numérote **côté serveur** rend des ids qui ne portent pas le slug : le compte
  resterait à zéro pour toujours, la borne ne bornerait plus rien, et un run
  pourrait réinjecter à chaque tour. Deux réponses possibles et c'est à ce
  ticket-là de choisir — rendre un id qui porte le slug, ou ajouter à l'interface
  d'adaptateur une opération « combien de tickets portent ce préfixe de slug » que
  le backend local implémente en lisant ses noms de fichiers. Et
  `tracker_open_unique` est l'autre moitié de la terminaison de ce chemin (le même
  trou nommé deux fois n'ouvre qu'un ticket, le second tour demande un humain) : un
  backend qui ne l'implémente pas refuse bruyamment, ce qui est le bon échec, mais
  il doit répondre à la question plutôt que d'hériter d'une réponse qui marche sur
  du markdown.

- **Corollaire additif de « un id par ligne », posé par [48], livré le
  05/09/2026 : un backend ne rend jamais un id qui contient un saut de ligne, et
  il refuse à voix haute.** La clause d'interface de [37] **ne change pas** —
  l'en-tête de `lib/tracker.sh` la dit toujours, et le fichier est resté hors
  write-surface. Ce que [48] y ajoute est ce qui s'ensuit : un transport une
  entrée par ligne ne peut pas porter un nom qui contient une fin de ligne, et
  unix autorise ce nom. Le backend local le refusait de fait en le rendant en
  **deux** ids que le tracker ne porte pas — dont la frontière était polluée, dont
  aucun n'était réclamable, et sur lesquels `failures_quarantine_strays` écrivait
  `quarantined 99-a, b` sans avoir escaladé quoi que ce soit. Il le refuse
  maintenant explicitement, dans les six scans du backend, et le dit.

  Ce qu'un adaptateur distant doit répondre, et pourquoi ce n'est pas gratuit chez
  lui : un titre d'issue GitHub ou Jira peut parfaitement contenir un saut de ligne
  et rien n'oblige un serveur à le refuser. Trois choses en découlent. (1) Ce que
  `frontier`/`ids` rendent doit être une ligne ou rien — un id dérivé d'un titre
  doit être normalisé avant d'être rendu, jamais après avoir été lu. (2) Le refus
  doit être **dit**, pas silencieux : un ticket qui n'apparaît sur aucune frontière
  et dont rien ne nomme le fichier est pire qu'un ticket inadressable. (3) La
  question du numéro nu vaut aussi là-bas : `tracker_local__path` ne compte plus un
  nom inadressable parmi les porteurs d'un `NN`, sans quoi un seul fichier fantôme
  rendait un numéro ambigu et sortait de la frontière tout ticket portant
  `Blocked by: NN` ([27]). Un backend qui résout des ids côté serveur doit dire ce
  qu'il fait quand deux objets prétendent au même identifiant.

  L'arbitrage sous-jacent est celui de [39] et il est identique ici : le transport
  reste une ligne par entrée, et ce que ça exclut est refusé à voix haute par
  chaque consommateur, plutôt que de rendre NUL-séparée chaque liste du pack pour
  un nom qu'aucun projet n'a. La ligne complète est dans le tableau de
  `docs/frontiere-de-confiance.md`, rangée « Un ticket est identifiable par son
  `NN` ».

- **Contrainte posée par la passe transversale du 05/09/2026 : la clause « à voix
  haute » n'a aujourd'hui aucun logement dans l'interface, et [64] est ouvert pour
  lui en donner un.** Mesuré (`../sondes/passe-05-09/q3-*.bats`) : la voix est un
  `printf … >&2` dans `tracker_local__refuse_name`, donc dans un `__` du **backend
  local** ; elle est dite huit fois sur la console d'un run AFK, zéro fois dans
  `run.log`, zéro dans le reçu, zéro dans `docs/playthroughs/` — et quatre
  consommateurs la jettent (`$(tracker_ids 2>/dev/null)` dans
  `playthrough__injected`, `router__tracker_state`, `router_protect_tracker` —
  depuis [65], celui de `playthrough.sh` s'appelle `playthrough__strangers`, et
  il y en a un second dans le repli de `playthrough__opened`).
  L'en-tête de contrat de `lib/tracker.sh` ne dit rien de qui parle ; le seul
  endroit que l'interface possède pour un constat de **forme d'id** est
  `tracker_preflight`, explicitement non dispatché, et il ne porte que
  `ambiguous-id`. **Si [64] passe avant, ce ticket implémente contre un logement
  qui existe ; sinon il doit l'inventer, ou réimplémenter huit `printf >&2`.**
  `lib/tracker.sh` était déjà hors write-surface de [48] : c'est toujours ici que
  la décision se prend, [64] ne fait que la préparer.

  **RÉSOLUE PAR [64], LIVRÉ LE 06/09/2026. Ce que ce ticket implémente contre,
  et il n'y a rien à inventer :**

  - **`tracker_refuse_name NOM`** — publique, dans `lib/tracker.sh`. Un backend
    qui rencontre un nom qu'il ne peut pas rendre comme id l'appelle **avec le nom
    tel que le tracker le porte**, et n'imprime **aucune phrase à lui**.
    L'interface échappe le saut de ligne *et* la tabulation, en fait un constat
    `unaddressable-name` de `tracker_preflight` (une ligne `loop_log` + une ligne
    de journal, une fois au démarrage du run **et** du drain), et garde la phrase
    sur stderr en repli pour les appelants qu'aucun préflight ne couvre. Un
    backend distant qui numérote côté serveur n'appelle jamais cette fonction et
    ne trouve rien au préflight : c'est la bonne réponse, pas une réponse
    manquante — même arbitrage que pour `ambiguous-id`.
  - **La clause est dans l'en-tête de contrat de `lib/tracker.sh`**, avec
    l'endroit où passe la voix. C'est là qu'il faut la lire, plus dans [48] ni
    seulement dans le tableau.
  - **`tracker_finding_said SUJET ISSUE`** — appelée par `loop.sh` et par
    `human-loop.sh` après avoir journalisé un constat, pour que le repli cesse de
    répéter ce qu'un lecteur a déjà reçu. Un backend n'a rien à en faire ; un
    **troisième point d'entrée** en aurait, et c'est la famille [55]/[56]/[57].
  - `tracker_local__refuse_name` **n'existe plus** : ne pas le chercher comme
    modèle.

- **Seconde contrainte de la même passe, sur la borne du gate de valeur —
  RÉSOLUE PAR [65], LIVRÉ LE 05/09/2026, ET REMPLACÉE PAR UNE AUTRE.** Lire les
  deux paragraphes qui suivent ensemble : le premier est mort, le second est la
  contrainte vivante.

  *Ce qui est mort.* [11] avait écrit ici que `playthrough__injected` lit le slug
  **dans l'id** et qu'un backend numérotant côté serveur laisse le compte à zéro
  pour toujours. **Ce scan n'existe plus** : `playthrough__injected` a disparu, la
  borne est comptée sur le registre d'écritures du pilote ([13]/[40]) via
  `playthrough__opened`. Les deux réponses que [11] laissait à choisir — « rendre
  un id qui porte le slug » ou « ajouter une opération *combien de tickets portent
  ce préfixe* » — **ne sont plus à choisir** : la seconde est devenue sans objet,
  et la première n'est plus une obligation *pour la borne* (elle le reste pour la
  dédup, voir ci-dessous).

  *Ce qui la remplace, plus étroit qu'avant.* `playthrough__opened` est la liste
  que **le run tient lui-même** : `playthrough_close` y ajoute l'id que
  `tracker_open_unique` vient de rendre, quel qu'il soit. Le compte ne lit donc
  **plus du tout** la forme d'un id, et un backend numérotant côté serveur ne
  casse plus la borne. Restent deux lecteurs qui, eux, lisent encore le texte de
  l'id, et ce sont ceux-là que ce ticket doit traiter :

  - `playthrough__opened_slug` compare `*-<slug>` sur les ids que **ce run** a
    ouverts, pour distinguer « un doublon que j'ai ouvert » de « un nom que je
    n'ai jamais vu ». Sur un id qui ne dérive pas du slug, la réponse est
    **toujours non** : chaque doublon est rapporté à un humain comme un ticket
    que ce run n'a pas ouvert. Phrase fausse, à chaque tour.
  - `playthrough__strangers` filtre `tracker_ids` sur `-playthrough-wiring-` pour
    **nommer** les tickets de câblage que ce run n'a pas ouverts. Sur des ids
    numérotés côté serveur il ne trouve jamais rien : la phrase que lit l'humain
    quand la borne mord redevient muette sur ce qu'elle n'a pas compté — le
    silence exact que [65] a fermé.

  Une seule réparation pour les deux, et c'est la même qu'avant en plus étroit :
  **l'id que le backend rend porte le slug qu'on lui a passé**, ou l'interface
  gagne la question « cet id porte-t-il ce slug », posée *au backend* au lieu
  d'être déduite du texte. `tracker_open_unique` reste l'autre moitié de la
  terminaison de ce chemin (le même trou nommé deux fois n'ouvre qu'un ticket, le
  second tour demande un humain) : un backend qui ne l'implémente pas refuse
  bruyamment, ce qui est le bon échec, mais il doit répondre à la question plutôt
  que d'hériter d'une réponse qui marche sur du markdown.

  *Et une contrainte de fond, qui n'est pas une affaire d'id :* la source du
  compte doit rester **hors d'atteinte d'une session**. Un backend qui tiendrait
  sa propre trace de « ce que la boucle a ouvert » — un label, un champ, une
  requête — ne doit pas la substituer ici : tout ce qu'un backend expose est
  écrit par ce qu'une session peut appeler. Le registre d'écritures du pilote
  ([13]/[40]) a d'ailleurs été essayé et **refusé** en livrant [65], pour une
  raison qui vaut aussi pour un backend : il répond « quels tickets la boucle
  a **écrits** », et une mise en quarantaine est une écriture — les trois tickets
  contrefaits revenaient dans le compte par `failures_quarantine_strays`.

- **Contrainte posée par [62], livré le 05/09/2026 : tout `mktemp` que ces
  adaptateurs poseront au premier niveau de `$TMPDIR` doit avoir sa ligne dans
  `gate_tmp_names`.** Un backend distant qui cache des réponses HTTP est le
  candidat évident (`ralph-github.*`, `ralph-gitlab.*`, un sidecar de claim), et
  c'est précisément le producteur pour lequel ce ticket a été mis avant les
  quatre suivants dans la file. Ce n'est pas une consigne à retenir : le test
  `every name the pack puts at the top of TMPDIR is counted by the sweep list`
  (`test/gate.bats`) lit les `mktemp` du pack livré, les fait résoudre par le
  pack et rougit sur un producteur non couvert. Deux formes échappent quand même
  à la dérivation, et ce ticket est en position de les écrire toutes les deux :
  un chemin composé en **deux temps** (le répertoire dans une variable sur une
  ligne, le nom sur la variable à la suivante) et un fichier **hors de
  `.claude/**`**. Le sidecar de liveness du claim, s'il vit hors de
  `.scratch/<feature>/`, tombe dans la même question — et la réponse « il est
  compté » ou « il est ailleurs et voici qui le garde » va dans
  `docs/frontiere-de-confiance.md`, pas seulement ici.

- **`Blocked by:` élargi le 05/09/2026, ordre validé par Philippe.** `64, 65`
  s'ajoutent à `02, 10`. [64] est l'arête **dure** (le logement d'interface de la
  clause « à voix haute ») ; [65] est l'arête d'opportunité — s'il livre en
  cessant de scanner le tracker, la contrainte que [11] avait écrite ici (« un
  backend qui numérote côté serveur casse la borne ») **disparaît avec le scan**
  au lieu d'être une obligation de plus pour ce ticket. Ordre complet retenu :
  [63] → [62] → [65] → [64] → passe transversale → [18] → [19].

- **Contrainte posée par la passe transversale du 06/09/2026 : la trace forensique
  que le routeur lit n'est épinglée par rien, et [66] est ouvert pour ça.** Ce
  ticket porte déjà, plus haut, la remarque « la branche est une **ref git
  locale** ; sur un backend distant elle peut vivre ailleurs […] Si ce ticket
  déplace la trace forensique, il possède la question de savoir comment le routeur
  la trouve. » La passe ajoute la moitié qui manquait : **et qui l'épingle**.

  Mesuré (`../sondes/passe-06-09/q1-*.bats`) : une session routée qui n'écrit *que*
  `refs/heads/failed/<id>` fait passer le desk de `admit` à `arbitrate` ; une qui
  l'efface fait passer `arbitrate` à `admit`, et le dossier affirme alors à
  l'humain « there is none. nothing ever ran on this ticket » à propos d'une
  tentative réellement jugée. `router_pin` épingle `Escalation:`,
  `Write-surface:`, `Failures:`, l'arbre de travail et l'état du tracker — pas la
  ref.

  Ce que ça impose ici, quelle que soit la forme que prendra [66] : **la trace
  forensique d'un backend distant est une preuve, donc elle doit être lue par le
  routeur à travers un épinglage pris avant la session routée, pas au moment du
  dossier.** Une PR, un label, une requête : tout ce qu'un backend expose est
  écrit par ce qu'une session peut appeler — c'est le même arbitrage que celui que
  [65] a écrit pour la borne du gate de valeur. Livrer après [66] et hériter du
  mécanisme, plutôt que d'inventer un second épinglage sur une API.

- **[66] est livré le 07/09/2026, et voici le mécanisme dont hériter, avec ses
  trois prix.** `router_pin` prend, au même appel que les trois champs, un
  instantané de **tout** `refs/heads/failed/*` — `<objectname><TAB><refname>`,
  produit par `router__failed_refs` — et `router_has_branch` répond dessus pour le
  ticket épinglé, donc `router_desk` **et** `router_dossier` décident et racontent
  sur la même valeur. `router_branch_note` compare l'instantané au retour de
  chaque session routée et nomme trois arrivées : créée, effacée, déplacée. Ce que
  ce ticket doit reproduire pour une trace distante, sans le réinventer :

  1. **La preuve est lue à travers un épinglage pris par `router_pin`**, pas au
     moment du dossier. Si la trace est une PR, l'état de cette PR est un
     `ROUTER__PINNED_*` de plus, pris au même appel — et `router_has_branch` est
     le point d'extension, parce que c'est la seule fonction que `router_desk` et
     `router_dossier` interrogent.
  2. **Nommer ne rend rien, et la phrase doit dire lequel des deux cas on est
     dans.** Une preuve *créée* est une fausse route réparable par l'épinglage ;
     une preuve *détruite* est perdue, et la sentence de `router_branch_note` le
     dit en toutes lettres (« The evidence is lost, not moved »). Sur un backend
     distant, « détruite » a une forme de plus — une PR fermée, un dépôt privé
     devenu inaccessible, un token révoqué — et un **refus de l'API n'est pas une
     absence de preuve** : `router_branch_note` refuse et ne nomme rien quand
     `git` ne répond pas ([59]), et une requête réseau a besoin de la même
     distinction, avec plus de raisons de tomber.
  3. **Rien n'est remis et rien ne refuse.** Ce drain n'est pas l'auteur de ces
     preuves et un garde qui refuserait le drainage donnerait à une session
     routée une ligne pour renvoyer chez lui l'humain venu vider le puits
     (posture de [69], tenue par [67]). Un backend distant ne doit pas
     « réparer » une PR.

  Et les deux résidus mesurés (`../sondes/ticket-66/verification.bats`), qui sont
  des contraintes et pas des anecdotes : la preuve forgée **survit au drainage**,
  donc le drainage suivant l'épingle et route dessus (V1) ; et l'épinglage est
  **par ticket**, donc une preuve écrite sur un **voisin** re-guichette ce voisin
  dans le même drainage — nommée à l'écran et dans `run.log` (`ref-drift
  created`), jamais défaite (V5). Un backend qui rend la trace par une requête a
  exactement le même résidu, et il coûte un appel réseau par ticket drainé au lieu
  d'un `for-each-ref`.

- **Et une clause de plus, du même endroit, sur ce que le drain *raconte*.**
  `router_run_notes` tire quatre conclusions de `run.log`, un fichier local que
  rien ne garde ([67]). Un backend distant ne change rien à cette ligne — le
  journal reste local ([16] : « le drain journalise dans le même fichier, parce que
  c'est celui qu'un humain ouvre au matin ») — mais `tracker_receipt_path` rend
  chez toi une PR, et le dossier met les deux côte à côte. Si ce ticket ajoute une
  source de preuve, elle a la même obligation que la ref.

- **Deux clauses d'interface de plus, posées par la passe transversale du
  07/09/2026** (`../passe-transversale-07-09.md`).

  1. **Ce qu'une opération de l'adaptateur a le droit de refuser, et sous quelle
     forme.** L'en-tête de `lib/tracker.sh` documente les opérations et leurs
     valeurs de retour, jamais leurs refus — alors que le dispatcher en émet déjà
     un (`3`, « does not implement <op> »), donc la forme existait sans être un
     contrat. Mesuré sur le backend **local** : `tracker_local_mark_escalated` est
     écrite `${2:?tracker: an escalation needs a reason}`, ce qui est une **sortie
     du shell** ; appelée par `router__put_back` avec une valeur de champ vide,
     elle tue le drain, qui rend `0`. Un refus doit être un code de retour. Un
     backend distant qui refuserait par un `exit`, un `${:?}` ou un `set -e` non
     rattrapé tuerait ses **deux** appelants, et celui qui coûte le plus cher est
     le drain : depuis [67] il n'y a plus de sous-shell entre lui et ses libs.
     Le correctif et la clause appartiennent à **[71]**, à livrer avant ce ticket.
  2. **Le reçu distant est une preuve que le dossier montre, et sa provenance doit
     être dite.** [66] avait déjà écrit ici la moitié « ref » de cette arête : une
     trace forensique déplacée hors d'une ref locale doit être lue à travers un
     épinglage pris avant la session routée. La moitié « reçu » est mesurée depuis
     le 07/09 : sur le backend local, `tracker_local_receipt_path` est un `[ -f ]`
     sur un chemin de l'**arbre principal** qu'une session d'itération atteint, et
     le dossier le présente sans réserve. Sur un backend distant le reçu est une
     **PR**, c'est-à-dire un objet qu'une session peut atteindre par le réseau : ce
     ticket doit dire ce qui atteste la provenance d'un reçu distant, ou dire que
     rien ne l'atteste. Propriétaire du travail préparatoire : **[70]**, collé à ce
     ticket.

- **Coût du drain sur un backend distant, chiffré ici parce que personne ne l'avait
  écrit.** La note ci-dessus sur `gate__surface_owner` ne couvre que le chemin AFK.
  Depuis [58]/[61], `router__tracker_state` lit **cinq champs plus le ticket
  entier** pour **chaque** ticket du tracker, **à chaque** ticket drainé ; et
  `router_sink` appelle `router_unblocks`, qui relit `Blocked by:` sur tous les
  tickets, pour chaque candidat du puits. Sur un tracker de quarante tickets avec
  trois tickets dans le puits, c'est de l'ordre de sept cents lectures là où le
  backend local fait des `sed`. Un cache par ticket drainé est la parade évidente
  et elle a un piège nommé ailleurs dans ce dépôt ([08], [40]) : il ne doit pas
  vivre dans un fichier qu'une session routée peut écrire.

- **`Blocked by:` élargi le 07/09/2026** après la passe du même jour et la
  validation de la file par Philippe : `70` et `71` s'ajoutent aux cinq
  existantes. `71` parce que la clause *ce qu'une opération de l'adaptateur a le
  droit de refuser, et sous quelle forme* n'existe pas encore et qu'un backend
  distant l'inventerait ; `70` parce que la preuve que le dossier montre doit
  savoir dire sa provenance avant qu'un backend la déplace vers une PR. File
  retenue : **[71] → [72] → [70] → [18] → [19]**.

- **La clause que [71] a écrite, livrée le 07/09/2026, et c'est une contrainte
  sur chaque opération écrite ici.** L'en-tête de contrat de `lib/tracker.sh` dit
  maintenant *comment* une opération refuse : un **code de retour** non nul —
  `3` est pris par le dispatcher pour une opération non implémentée, donc un
  backend commence à `1` ou `2` — et **jamais** une sortie de shell : ni
  `${N:?word}`, ni `exit`, ni un errexit laissé filer. La raison n'est pas
  stylistique : cette interface a **deux appelants**, et celui qui paie est le
  drain — depuis [67] il n'a ni sous-shell d'itération ni `proc_collect` entre
  lui et ses libs. Mesuré sur le backend local avant [71] : un `${2:?}` a tué le
  drain en pleine remise, qui est sorti `0`, le code que son propre en-tête
  documente comme « the sink is empty ». Troisième moitié de la clause : une
  **valeur vide est une valeur**, pas un refus — `mark_escalated ID ""` est le
  ticket du guichet `request`, sans `Escalation:`, et un backend distant doit
  pouvoir l'écrire.

- **Et ce qui ne tient pas cette clause, à savoir tout ce qui est ici.** Aucun
  test de ce dépôt ne peut lire un backend qui n'existe pas encore : la ligne du
  tableau de confiance le dit en toutes lettres. Ce qui tient est l'autre bout —
  `human-loop.sh` refuse désormais de sortir `0` ailleurs qu'à sa dernière ligne
  (code **6** sinon), donc un backend qui casse la clause coûte un mauvais
  diagnostic et jamais un faux « everything was drained ». Un backend écrit ici
  qui refuserait en tuant le shell serait donc **vert sur toute la suite** et
  visible seulement à ce code de sortie : à couvrir par un test de ce ticket, pas
  à supposer.

- **Ce que [70] laisse à ce ticket, livré le 08/09/2026 — et c'est plus étroit et
  plus concret que la moitié écrite par [66].**

  1. **Une opération d'adaptateur de plus existe : `tracker_receipt_dir`.** Elle
     rend le répertoire dans lequel le backend garde ses reçus, ou **refuse**
     quand il n'en garde pas dans un répertoire — ce qui est le cas d'un backend
     distant, où le reçu est une PR ([10]). Elle a été ajoutée parce que
     `tracker_receipt_path` ne pouvait pas servir : elle répond pour un reçu qui
     existe déjà, et le témoin de [70] est pris **avant la première session**, sur
     un répertoire entier et pas sur un id. Un backend distant doit répondre à
     cette opération, et « refuser » est une réponse valide et prévue.

  2. **Le prix de ce refus est déjà écrit et il est à vous.** Quand
     `tracker_receipt_dir` refuse, **rien dans le pack ne témoigne des reçus** :
     le run le dit une fois au démarrage (`forensic_uncovered`), et
     `router_dossier` continue d'envoyer un humain lire un reçu dont plus rien
     n'atteste la provenance. Ce ticket doit dire **ce qui atteste la provenance
     d'un reçu distant, ou dire que rien ne l'atteste** — et la seconde réponse
     est acceptable, à condition qu'elle soit écrite dans
     `docs/frontiere-de-confiance.md` et que le dossier la porte. Une PR est un
     objet qu'une session atteint **par le réseau**, ce qu'aucun scope-guard,
     aucun rollback et aucun témoin de fichier local ne voit.

  3. **La réserve du dossier est déjà là, et elle est écrite pour un reçu
     local.** `router_dossier` imprime maintenant, sous la ref et sous le reçu :
     « written by a run, into zones the sessions that run judges can reach: a ref
     is a path in no working tree, and a receipt lives in the main tree, which is
     not the worktree a scope-guard compares. » **Cette phrase devient fausse sur
     un backend distant** — un reçu n'y est pas dans l'arbre principal. La relire
     fait partie de ce ticket.

  4. Et la moitié de [66] reste : un backend distant qui déplace la trace
     forensique déplace une preuve, qui doit être lue à travers un épinglage pris
     avant la session routée. `forensic_failed_refs` est publique et vit dans
     `.claude/lib/forensic.sh` depuis [70] ; c'est elle qu'un backend distant
     remplace ou double.

## Livraison (08/09/2026)

**Écart de write-surface, déclaré.** La surface annoncée était
`.claude/lib/tracker-github.sh`, `.claude/lib/tracker-gitlab.sh`,
`test/tracker-remote.bats`. Ce qui a été écrit en plus, et pourquoi chaque
fichier :

- **`.claude/lib/forge.sh` (neuf)** — le noyau partagé des deux backends. Deux
  adaptateurs de vingt opérations chacun, écrits deux fois, sont deux endroits
  où la prochaine correction sera faite une fois. Le préfixe est `forge_` et
  **pas** `tracker_remote_` : `tracker__dispatch` route
  `TRACKER_BACKEND=<nom>` vers `tracker_<nom>_<op>`, donc un noyau nommé d'après
  un backend ferait de `TRACKER_BACKEND=remote` un backend qui répond à
  certaines opérations et se trompe silencieusement sur les autres. Le
  découpage tient aussi la règle de couches : les adaptateurs appellent des
  `forge_*` **publiques**, jamais un `forge__` — `test/layering.bats` refuserait
  l'inverse.
- **`.claude/lib/tracker.sh`** — une 21ᵉ opération, `tracker_tickets_dir` (voir
  plus bas).
- **`.claude/lib/tracker-local.sh`** — son implémentation locale.
- **`.claude/lib/failures.sh`** — `failures__issues_path` demande le chemin à
  l'adaptateur au lieu de le composer, et `failures_protect_tracker` gagne la
  branche explicite d'un backend qui ne garde pas ses tickets ici.
- **`.claude/lib/forensic.sh`** — `forensic_uncovered` gagne la deuxième zone.
- **`.claude/lib/gate.sh`** — `gate__surface_owner` rend `2` sur un `ids` refusé,
  et le scope-guard escalade au lieu de retenter (AC 5).
- **`.claude/lib/router.sh`** — la réserve du dossier, qui était **fausse** pour
  un reçu distant ([70] avait laissé sa relecture ici).
- **`.claude/ralph.config.sh.example`** — les cinq clés qu'un backend distant lit
  et qu'aucun autre ne lit.
- **`test/helpers/harness.bash`, `test/helpers/shims/curl`,
  `test/helpers/shims/forge-api` (neuf)** — la forge mockée, avec état.
- **`test/tracker-local.bats`** — un test nommait `github` comme « un backend qui
  n'existe pas » ; il nomme maintenant `jira`.
- **`test/mutate.sh`, `docs/frontiere-de-confiance.md`, `CONTEXT.md`** — les
  obligations 1, 5 et 8 de la definition of done.

### Ce qui a été décidé, et qui ne se déduit pas du code

1. **L'état vit dans le corps de l'issue, pas dans des labels.** C'est ce qui
   rend « le même scénario produit les mêmes transitions » une mesure et pas une
   affirmation : le modèle d'état est celui du backend local, lu avec la même
   tolérance (`**Nom:** v` ou `Nom: v`, blancs de fin coupés, `[[:space:]]` pour
   un CRLF). Ce que le vocabulaire de la forge porte **en plus**, pour l'humain
   et jamais pour une lecture du pack : l'assignee (le claim) et la fermeture
   (`resolved`, `wontfix`). Un champ et un état de forge qui se contredisent
   donneraient deux autorités pour un fait.
2. **Un id est `<numéro>-<slug>`, ou le numéro nu.** Le slug est un champ du
   corps (`Slug:`), donc il revient dans **le listing** — une requête pour tout
   le tracker — et c'est ce qui fait que `frontier`, `ids`, `read_ticket` et
   chaque `field` de chaque ticket sont servis par une seule requête. Le slug
   n'est pas décoratif : `playthrough__opened_slug` et `playthrough__strangers`
   le lisent dans le **texte** de l'id ([65]).
3. **Il n'y a rien à refuser, et c'est la réponse que `lib/tracker.sh` prévoyait
   déjà.** Un id est un entier plus un slug dans le rendu que le transport
   utilise déjà (`\n`, `\t`, `\\`), donc il est d'une ligne par construction
   quoi qu'un humain tape dans un `Slug:`. `tracker_refuse_name` n'est jamais
   appelée et le préflight ne trouve rien : c'est la bonne réponse et pas une
   réponse manquante, exactement comme pour `ambiguous-id`. Ce que ça coûte est
   écrit dans `forge__record_id` : l'id d'une issue dont le slug porte une
   tabulation se lit `12-a\tb`.
4. **`renumber` rend l'id qu'on lui donne** ([27]), et la question du dessous a
   une réponse : `forge__record` résout sur le numéro, unique dans un dépôt.
5. **`open_unique` est sérialisé par un garde local**, dans le répertoire de la
   feature, à côté du verrou de run ([49] : un garde sur l'espace des ids vit là,
   un garde sur un ticket voyage avec lui). Ce qui le tient : cette machine, et
   rien de plus — aucune des deux forges n'offre de compare-and-swap sur une
   issue. C'est spec §213 (« liveness mono-machine, pas d'orchestration
   distribuée ») dit à l'endroit où on supposerait sinon que la forge s'en
   charge. Le claim est dans le même cas.
6. **Le reçu est la requête, et la branche est poussée dedans.** C'est la réponse
   à ce que [10] avait laissé ouvert : les `git show <sha>` du reçu résolvent
   pour qui a récupéré la branche, sans inliner le diff que [10] a refusé. Une
   requête par ticket, ouverte par `mark_resolved` — qui en a besoin avant de
   pouvoir attendre un pipeline — et réécrite par `emit_receipt`. Ce que la
   machine retient d'elle est dans le sidecar, jamais sur le ticket : un
   adaptateur qui écrirait un lien, un label ou un commentaire en émettant un
   reçu devrait noter l'id dans le registre de [13] lui-même, or c'est le
   dispatcher qui le tient et il exempte `emit_receipt`. Le lien entre les deux
   est fait par la forge, à partir du `#<numéro>` que porte la description.
7. **Ce qui atteste la provenance d'un reçu distant : rien ici.** [70] avait posé
   la question et accepté cette réponse à condition qu'elle soit écrite et portée
   par le dossier. Elle l'est : `tracker_receipt_dir` refuse,
   `forensic_uncovered` le dit une fois au démarrage du run, `router_dossier`
   imprime la réserve écrite pour un objet qui n'est pas dans cet arbre — et dit
   que ce qui l'atteste vraiment est le registre d'auteurs de la forge, que ce
   pack ne lit pas. La phrase de [70] (« a receipt lives in the main tree ») est
   **fausse** ici et a été relue, comme le ticket le demandait.
8. **La trace forensique ne bouge pas.** `failures_preserve_attempt` écrit
   `refs/heads/failed/<id>` quel que soit le backend, donc la moitié de [66]
   qui portait sur « un backend qui déplace la preuve » ne s'applique pas :
   celui-ci ne la déplace pas. Ce qu'il déplace est le **reçu**, et c'est le
   point 7.
9. **`wait_ci`** : `auto` (défaut) attend quand la forge rend un pipeline et
   laisse passer un projet qui n'en a pas — c'est toute la détection ; `on` est
   un projet qui a dit en avoir une, donc une requête sans pipeline est un fait
   pour un humain. Rouge, délai, statut inconnu ou requête impossible à ouvrir :
   le ticket est escaladé (`ci-red`, `ci-timeout`, `ci-unreachable`,
   `ci-absent`) et l'opération refuse. Un statut qu'aucune des deux forges ne
   documente est `unknown` et **jamais** `none` — [59] appliqué à un mot.
10. **Le coût du drain, chiffré et PAS réglé — et c'est écrit comme tel.** Le
    listing est mémoïsé dans une **variable du shell appelant**, ce qui replie
    les lectures d'un **même appel** sur une requête : un scan de frontière de
    quarante tickets portant chacun un blocage coûte une requête et non quarante
    et une. Ce que ça n'achète pas était la phrase évidente et elle est fausse :
    une variable de shell meurt à la première substitution de commande, et une
    substitution est **la** façon dont ce pack lit le tracker. Ordres de grandeur
    sur un tracker de quarante : 1 requête pour un scan de frontière, 41 pour un
    débordement de surface, **240 pour un ticket drainé**. Les deux durées de vie
    plus longues sont refusées ici plutôt que mal choisies — un fichier dans
    `.scratch/<feature>/` est un fichier qu'une session routée écrit ([40], et le
    corollaire de [21] : ce cache décide de ce que le tracker *dit*), et un
    fichier dans le répertoire témoin du run serait juste mais `human-loop.sh`
    n'en fabrique pas, donc le donner au drain est une modification du point
    d'entrée. Propriétaire : **[75]**. Ce qui est réglé sans discussion : ces
    adaptateurs ne posent **aucun** `mktemp`, donc `gate_tmp_names` n'a pas
    bougé.
11. **Le sidecar** vit dans `.scratch/<feature>/.forge-claims`, à côté du verrou
    de run, en append-only avec la dernière ligne qui gagne. Il porte trois
    sortes de faits locaux : le claim (`owner=pid:<n> at=<iso>`), la requête
    ouverte, et l'URL du reçu. Il a exactement l'exposition du verrou de run —
    une session peut l'écrire — et c'est déjà la ligne « Le reste de
    `.scratch/<feature>/` » du tableau de confiance.
12. **JSON en awk, strict.** Délibérément pas jq (le pack promet de tourner sans
    rien d'installé), et délibérément **strict** là où `budget__window` est
    tolérant : celui-là lit un chiffre sur un endpoint non documenté et n'imprime
    rien quand il ne peut pas, celui-ci porte le **texte d'un ticket** — une
    valeur devinée ici est un ticket réécrit. Un `\uXXXX` au-dessus de l'ASCII
    refuse au lieu de deviner : `%c` d'awk est un octet sur une implémentation et
    un caractère sur une autre.
13. **`ENVIRON` et jamais `awk -v`** pour toute valeur qui n'est pas un littéral
    du pack. C'est la fragilité que la passe du 29/07/2026 avait mesurée sur le
    backend local et léguée à ce ticket : awk interprète les échappements d'une
    assignation `-v`, donc une raison d'escalade portant `\n` arrive en vraie
    newline et coupe le ticket en deux.

### Pièges rencontrés, à ne pas redécouvrir

- **`IFS=<TAB> read -r a b c` avale les champs vides.** La tabulation est un
  caractère blanc d'IFS, donc une suite de tabulations se replie et une
  tabulation de tête saute : un enregistrement dont l'assignee est vide — tout
  ticket non réclamé — arrivait avec un champ de moins et la frontière lisait le
  `open` de la forge comme le slug du ticket. Épluché à l'expansion de paramètre
  (`forge__field_at`), qui ne découpe et ne replie rien. **Le pack a d'autres
  `IFS="$(printf '\t')" read` ; ils ne sont sûrs que tant que leurs champs sont
  non vides.**
- **Le corps échappé se scanne en tenant compte de `\\`.** Un champ dont la
  valeur finit par une contre-oblique met un `\` juste avant le `n` du séparateur
  suivant : un scan qui cherche les deux caractères `\n` coupe la valeur un
  caractère trop tôt, sur un ticket parfaitement bien formé. Les paires sont
  repliées sur un octet sentinelle avant la recherche.
- **`printf "$tmpl" a b` réutilise le format tant qu'il reste des arguments**,
  donc un gabarit d'URL qui nomme le dépôt et pas l'argument imprimait le chemin
  **deux fois**. Les gabarits sont `{repo}` / `{arg}` et la substitution est de
  l'expansion de paramètre.
- **`sub` est une fonction interne d'awk** : la nommer en paramètre local d'une
  fonction awk est une erreur de compilation.
- **`\u0000` n'existe pas dans une chaîne awk** : la table d'ordinaux de
  `forge__urlenc` part de 1.
- **`mutate.sh` : un `$#` dans un `s#...#...#` termine le délimiteur.** Utiliser
  `s@...@...@` pour toute ancre qui contient `#`.
- **`bash test/mutate.sh -n` édite `.claude/` et le restaure**, donc il rebâtit
  l'empreinte du template du harnais : une suite lancée **pendant** ce dry-run
  peut bâtir son projet à partir d'un pack muté. Un run de suite a été jeté pour
  ça pendant ce ticket.

### Ce que le gate de mutation a attrapé, et qui était vert avant lui

Trois entrées sur trente-huit sont sorties **VACUOUS** au premier passage. Deux
étaient des tests qui mentaient, une était une mutation qui n'en était pas une —
et aucune des trois n'était visible dans une suite verte.

1. **« un backslash dans un slug n'est pas la fin de la ligne ».** Le test
   nommait un backslash *ailleurs* dans le corps, et le défaut est ailleurs : le
   séparateur d'un corps échappé est la paire `\n`, et une valeur qui porte
   elle-même un backslash suivi de la **lettre** `n` porte exactement cette
   paire. Sans le repli des backslashes échappés, le scan s'arrêtait **dans** la
   valeur et le slug sortait tronqué (`a\`) : le ticket recevait un id
   qu'aucun lecteur de ce tracker ne rencontrera jamais, et rien ne rougissait —
   le numéro est toujours là, donc le tracker répond simplement sur un nom que
   personne ne porte. Le test réécrit met le backslash **dans le slug** et vérifie
   les deux moitiés : l'id rendu, et que le ticket reste joignable dessous.
2. **« une raison d'escalade vide est une valeur ».** Le test lisait le champ
   `Escalation` et le comparait au vide. Or un ticket portant `**Escalation:**`
   suivi de rien et un ticket ne portant pas cette ligne **se lisent
   identiquement** à travers une lecture de champ — le backend local le dit dans
   son propre commentaire, et je l'ai lu en écrivant celui-ci sans en tirer la
   conséquence pour mon assertion. La garantie est l'**absence de la ligne**,
   parce que ce que `router__put_back` doit pouvoir écrire est la forme que le
   puits a vraiment, octet pour octet. Le test réécrit regarde le corps.
3. **La mutation du lecteur JSON n'en était pas une.** Neutraliser un `fail`
   ne prouvait rien : la chose suivante que l'analyseur rencontrait refusait pour
   sa propre raison, et le document était rejeté quand même — vert pour une autre
   cause que celle qu'on croyait mesurer. La forme qui fait vraiment **passer** un
   document cassé est de lire un mot nu comme un nombre, et il faut élargir les
   *deux* classes de caractères (celle qui reconnaît le début d'un nombre et celle
   qui le consomme) : élargir seulement la première laisse l'analyseur sur place
   et le refus arrive de l'accolade suivante.

La leçon transversale des trois, parce qu'elle n'est pas propre à ce ticket :
**une assertion sur une valeur lue à travers le même lecteur que le code écrit ne
peut pas voir une différence que ce lecteur normalise.** Les points 2 et 3 sont
la même erreur à deux étages.

### Ce qui reste, et où

Trois tickets ouverts. Les deux premiers ont leur ligne dans
`docs/frontiere-de-confiance.md` ; le troisième est un coût et pas une garantie,
donc il n'en a pas :

- **[73] — rien ne restaure le tracker d'un backend distant.**
  `failures_protect_tracker` ne peut pas comparer deux arbres git d'un répertoire
  qui n'existe pas. Ce ticket a livré la **détection** — le chemin est demandé à
  l'adaptateur, le refus est une branche explicite, le run le dit une fois — et
  pas la remise. Un refus à chaque fenêtre rendrait rouge toute itération d'un
  backend distant, ce qui échange un faux vert contre pas de vert ; la remise
  demande de rendre `failures_protect_tracker` agnostique du transport, ce qui
  est une réécriture de ce garde et pas un ajout de backend.
- **[74] — la boucle avale les refus de l'adaptateur.** `loop.sh` ne lit pas le
  code de retour de `tracker_mark_resolved`, donc sur un pipeline rouge `run.log`
  dit `resolved` pendant que le tracker dit `ready-for-human` ; et
  `loop__next_ticket` lit la frontière dans une substitution de commande, donc
  un listing refusé arrive comme une frontière vide, ce qui déclenche le gate de
  valeur terminal. Les deux sont des changements de control-flow que l'AC 1
  interdit ici. Ce qui a été fait de ce côté-ci : les deux opérations refusent
  correctement, et `forge__api` redemande une **lecture** (trois essais) et
  jamais une écriture.
- **[75] — le drain d'un backend distant relit le tracker par ticket.** Le point
  10 ci-dessus, avec ses deux durées de vie refusées et le piège d'invalidation
  qui attend celui qui le livrera.

### Contraintes créées ailleurs

- **[19] (installeur)** : il balaye ce que `gate_tmp_names` nomme, et ce ticket
  n'ajoute **aucun** nom — les adaptateurs distants ne posent pas un `mktemp`.
  Ce qu'il ajoute hors du dépôt est le sidecar
  `.scratch/<feature>/.forge-claims`, qui est **dans** le dépôt, dans la zone que
  `gate_is_bookkeeping` exclut déjà. Un installeur qui propose `github` ou
  `gitlab` doit demander `TRACKER_REPO`, `TRACKER_TOKEN_CMD` et `TRACKER_USER` :
  sans le premier, chaque opération refuse au premier appel.
- **[73]** : le registre de [13] est indexé par **id**, et l'id d'un backend
  distant contient le slug lu dans le corps — donc une session qui change le
  slug change l'id du ticket sans changer le ticket. Personne n'a mesuré ce que
  ça fait aux deux gardes de [42].
