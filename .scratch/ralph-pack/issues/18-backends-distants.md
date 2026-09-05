# 18 — Backends distants github + gitlab

**What to build:** Les implémentations distantes de l'adaptateur de tracker, satisfaisant **la même interface** que `local`, avec la forme d'intégration façonnée par le backend (claim = assignee, reçu = PR, `wait_ci`). La boucle reste agnostique.

**Blocked by:** 02, 10

**Write-surface:** `.claude/lib/tracker-github.sh`, `.claude/lib/tracker-gitlab.sh`, `test/tracker-remote.bats`

**Status:** ready-for-agent

- [ ] Les adaptateurs `github` et `gitlab` satisfont l'interface fixe ; la boucle reste agnostique (aucun changement de control-flow).
- [ ] En distant : claim = assignee ; reçu = la PR ; liveness du claim en **sidecar local** (concurrence mono-machine).
- [ ] `wait_ci` est ON par défaut si une CI est détectée (opt-out `WAIT_CI=off`) → intégration PR-par-itération.
- [ ] Le même scénario e2e que `local` (piloté par une API mockée) produit les mêmes transitions d'état observables.
- [ ] `tracker_ids` est implémenté par les deux backends ; un backend qui ne la fournit pas est détecté, pas subi.

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
  propres tickets en lisant le slug dans l'id.** `playthrough__injected` compte les
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
  `playthrough__injected`, `router__tracker_state`, `router_protect_tracker`).
  L'en-tête de contrat de `lib/tracker.sh` ne dit rien de qui parle ; le seul
  endroit que l'interface possède pour un constat de **forme d'id** est
  `tracker_preflight`, explicitement non dispatché, et il ne porte que
  `ambiguous-id`. **Si [64] passe avant, ce ticket implémente contre un logement
  qui existe ; sinon il doit l'inventer, ou réimplémenter huit `printf >&2`.**
  `lib/tracker.sh` était déjà hors write-surface de [48] : c'est toujours ici que
  la décision se prend, [64] ne fait que la préparer.

- **Seconde contrainte de la même passe, sur la borne du gate de valeur.** [11]
  avait déjà écrit ici que `playthrough__injected` lit le slug **dans l'id** et
  qu'un backend numérotant côté serveur casse la borne. La passe a élargi le
  constat : la borne ne lit pas seulement un id, elle lit un espace de noms **à
  deux écrivains** — une session de livraison qui dépose trois fichiers
  `NN-playthrough-wiring-*.md` dans `issues/` est nommée par la quarantaine, garde
  ses noms, et éteint la réinjection de la feature pour toujours (mesuré, `q3`
  Q3e). Ticket [65]. Si [65] passe avant, ce ticket écrit contre un compteur qui
  ne scanne plus le tracker — probablement le registre d'écritures du pilote
  ([13]/[40]) — et la question « un backend qui numérote côté serveur » disparaît
  avec le scan.
