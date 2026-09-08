# 76 — La première page est tout le tracker d'un backend distant

**What to build:** Une lecture de tracker distant qui rend le tracker entier, et un faux de suite capable de servir plus d'une page — sans quoi rien de tout ça n'est mesuré.

**Blocked by:** None

**Write-surface:** `.claude/lib/forge.sh`, `test/tracker-remote.bats`, `test/helpers/shims/forge-api`, `test/helpers/harness.bash`, `test/mutate.sh` — plus `.claude/lib/tracker-github.sh`, `.claude/lib/tracker-gitlab.sh`, `.claude/ralph.config.sh.example`, `test/smoke.bats` et `docs/frontiere-de-confiance.md`, **écart déclaré** (voir les commentaires de livraison).

**Status:** resolved

- [x] `tracker_ids`, `tracker_frontier`, `read_ticket` et `field` rendent le tracker **entier** quand il tient sur plusieurs pages.
- [x] Deux pages ne se recouvrent pas : un enregistrement est identifié par ce que la forge lui donne, jamais par sa place dans un tableau.
- [x] Le faux de la suite sert plus d'une page pleine, et un test lit un tracker de plus de cent tickets.
- [x] Une lecture qui s'arrête sur une borne du pack (le plafond de pages) le **dit** au lieu de rendre une liste courte.
- [x] `per_page` et la borne à laquelle le compte est comparé sont un seul nombre, écrit une fois.

## Comments

### Livré le 08/09/2026 — ce que le code ne dit pas

- **Deux défauts, quatre mécanismes, cinq mutations.** Le ticket en annonçait
  deux ; la livraison en porte cinq, parce que deux ACs (la borne du plafond et
  « un seul nombre ») sont des garanties à part entière et qu'une garantie
  qu'aucune mutation ne vise n'est pas couverte.

  1. **La borne compte l'ensemble et non une suite.** `if (f[1] ~ /^[0-9]+$/ &&
     !(f[1] in seen))` : un indice de tableau awk est une **chaîne**, donc il n'y
     a plus de comparaison à fausser — c'est la réparation, pas le `!=` corrigé en
     comparaison de chaînes. Bonus non cherché : un document qui n'est pas un
     tableau (un objet d'erreur) compte zéro et arrête la pagination au lieu de
     compter ses clés.
  2. **Les pages sont un seul document.** `forge__listing` renumérote les feuilles
     de chaque page avec un offset avant de les concaténer. C'était la seule
     position possible : `forge__records` ne peut pas lire le numéro d'une issue
     avant d'avoir un identifiant qui distingue les pages, donc il faut désambiguïser
     par la position *avant* de pouvoir identifier par le numéro.
  3. **Un enregistrement est le numéro que la forge a donné.** Le garde `emitted`
     dans le `END` de `forge__records` : première occurrence gardée. Ce que ça
     couvre en plus de l'AC 2 : la **fenêtre qui glisse** — une issue ouverte entre
     la requête de la page une et celle de la page deux décale tout, et la dernière
     issue de la page une revient en tête de la page deux. Sans ce garde, un ticket
     y a deux ids.
  4. **Le plafond refuse.** `FORGE_PAGES` (20) atteint sans qu'une page soit venue
     courte est un `return 1` avec sa phrase, qui nomme les deux clés à lever. La
     décision — refuser plutôt que servir court — est celle de [59] : un appelant
     ne peut pas distinguer une liste courte d'un tracker plus petit, et les quatre
     conséquences sont écrites dans le tableau de confiance.
  5. **`per_page` est la borne.** `forge__path` substitue `{size}` par
     `forge__page_size`, donc les deux tables de backend ne portent plus de nombre.
     Un `arg` ne peut pas injecter `{size}` : `forge__urlenc` échappe `{` et `}`.

- **Écart de write-surface, déclaré.** Le ticket ne nommait que cinq chemins. Cinq
  autres ont été touchés, chacun pour une raison qui n'est pas un débordement de
  confort :
  - `tracker-github.sh` et `tracker-gitlab.sh` : l'AC 5 **est** l'effacement du
    `100` de leurs deux tables. Il n'y avait pas de version de cette AC qui ne les
    touche pas.
  - `ralph.config.sh.example` : la phrase du refus nomme `FORGE_PAGES` et
    `FORGE_PAGE`, et une clé qu'un message d'erreur nomme sans que la config la
    déclare est un cul-de-sac. **Effet de bord utile, non cherché** :
    `harness__clear_env` nettoie l'environnement à partir des clés déclarées dans
    l'exemple, donc `FORGE_PAGE` exporté dans le shell d'un développeur ne pouvait
    pas être neutralisé par le harnais — c'était un faux vert latent, il est fermé.
  - `test/smoke.bats` : sa liste et l'exemple sont une **égalité** dans les deux
    sens depuis [17], donc ajouter une clé sans l'ajouter là est un test rouge.
  - `docs/frontiere-de-confiance.md` : la ligne existait déjà, ouverte par la
    passe, avec `Propriétaire : [76]`.

- **La première AC était le faux, et elle a été livrée d'abord.**
  `test/helpers/shims/forge-api` lit `page` et `per_page` **dans l'URL** et
  découpe `order` comme une forge. Le `case` qu'il remplace matchait des
  sous-chaînes : `*"page=1"*` matche aussi `page=10`, et `per_page=100` porte les
  lettres de `page=`. Les paramètres sont maintenant pelés sur le dernier `?` ou
  `&` qui précède le nom.

- **Ce qu'a coûté la vérification côté consommateurs**, rejouée sur la sonde de la
  passe (`sondes/passe-08-09/q1-*.bats`, les quatre cas, qui finissent toujours par
  un `false` volontaire) : Q1a rend les quatre ids et la frontière complète, Q1c lit
  `1-alpha` servi par la page une pendant qu'il y a une page deux, et **Q1d — le
  scope-guard — rend `4-delta` pour `src/delta.txt`**, c'est-à-dire l'AC 5 de [18]
  atteinte par l'autre bout : un débordement dans la surface d'un ticket de la page
  deux est de nouveau un drift contractuel, donc une escalade et pas un retry en
  boucle.

- **Le sondage du run réel, et le prix qu'il chiffre.** Le défaut vivait dans
  l'écart entre le faux et le réel ; ce qui reste de cet écart après la livraison :
  - un tracker de **plus de `FORGE_PAGE` × `FORGE_PAGES` issues (2 000 par défaut)**
    ne se lit plus du tout — c'est le choix du ticket, mais il est plus dur qu'une
    troncature silencieuse et il faut le savoir : la boucle s'arrête au lieu de
    broyer la moitié d'un tracker ;
  - le refus **n'est pas mémoïsé** (`FORGE__CACHE` n'est posé qu'en cas de succès),
    donc chaque appelant repaie les 20 requêtes avant de se faire refuser. Sur le
    chemin AFK c'est un run qui s'arrête, pas une nuit ;
  - une lecture de tracker coûte maintenant **une requête par page** au lieu d'une :
    `forge__api` réessaie trois fois une lecture, donc un tracker de 21 pages fait
    jusqu'à 63 requêtes dans le pire cas, contre 3 avant. C'est le prix de lire le
    tracker, et c'est le budget que [75] devra chiffrer pour son cache.

- **Pièges rencontrés, pour la mémoire du harnais.**
  - Le témoin de l'AC 5 ne peut pas être asserté sur des ids : une table qui dirait
    encore `per_page=100` avec `FORGE_PAGE=2` rendrait le tracker **entier et juste**
    (page pleine de 100 = les 4 tickets, puis une page vide). Seule l'URL le voit,
    et elle se lit dans `forge_calls` — pas dans `$output`, que le `run` de la
    ligne précédente possède.
  - `forge_serve_twice` ne touche pas le faux : la liste **est** le fichier `order`,
    donc un numéro écrit deux fois dedans est la même issue servie sur deux pages.
  - Les deux moitiés du témoin du plafond sont deux `@test` (un `pack_run` fait
    tourner le faux), conformément au piège de harnais déjà écrit.


- **Ouvert par la passe transversale du 08/09/2026** (`../passe-transversale-08-09.md`,
  §1 ; sondes `../sondes/passe-08-09/q1-*.bats`). Deux défauts empilés, et le
  second est caché par le premier.

- **Le premier : la borne ne compte jamais le premier enregistrement d'une page.**

  ```sh
  count="$(printf '%s' "$body" | LC_ALL=C awk -F'\t' '
    { split($1, f, "."); if (f[1] != last) { n++; last = f[1] } }
    END { print n + 0 }')"
  [ "${count:-0}" -ge "${FORGE_PAGE:-100}" ] || break
  ```

  `f[1]` sorti de `split()` est un **strnum** (« 0 » ressemble à un nombre) et
  `last` n'est pas initialisée, donc awk compare **numériquement** : `0 == 0` est
  vrai, le premier enregistrement n'est pas compté, et `last` n'est même pas
  affectée. **Mesuré** : `1` sur une page de deux enregistrements, `99` sur une
  page pleine de cent. `99 >= 100` est faux. **La page deux n'est donc jamais
  demandée, sur aucun tracker.**

  Ce n'est pas une hypothèse de laboratoire : `state=all` est la bonne décision
  de [18] — un ticket résolu revendique sa write-surface autant qu'un ouvert —
  et elle garantit que n'importe quel dépôt un peu vécu dépasse cent issues.

- **Le second : deux pages se recouvrent.** `forge__records` reconstruit un
  enregistrement par **indice de tableau** (`rec = substr(p, 1, dot - 1)`), et
  `forge_json` numérote les éléments de **chaque document**. La première issue de
  la page deux est `0.number` comme celle de la page une : elle l'écrase.
  **Mesuré** (Q1c, avec `FORGE_PAGE=1` pour franchir la borne faussée) : un
  tracker de quatre issues servi deux par page rend `3-gamma` et `4-delta`, et
  `1-alpha` se lit « pas de ticket ». Réparer la borne seule échangerait un
  tracker tronqué contre un tracker **faux** : les deux moitiés se livrent
  ensemble.

  Attention à la variante silencieuse : une clé absente d'un enregistrement de la
  page deux ne remplace pas celle de la page une (`who[rec]`, l'assignee, est la
  seule qui manque en pratique), donc un enregistrement peut aussi être un
  **mélange** de deux issues.

- **Ce que la troncature coûte, en descendant les consommateurs.** À vérifier en
  livrant, parce que c'est ce qui dit si le correctif suffit :
  - le **scope-guard** — c'est l'AC 5 de [18] atteinte par l'autre bout : un
    débordement dans la write-surface d'un ticket perdu par le listing est classé
    débordement interne, donc **retry au lieu d'escalade**, en boucle (mesuré,
    Q1d) ;
  - la **frontière** — les tickets de la page deux ne sont jamais travaillés, et
    une frontière vide est ce qui déclenche le gate de valeur terminal ;
  - **`Blocked by:`** — `forge__is_unblocked` fait bloquer un id qui ne pointe sur
    rien, et c'est le bon fail-safe : tout ticket bloqué par un ticket de la page
    deux quitte la frontière **pour de bon** ;
  - **`claim_reclaim_stale`** et **`failures_quarantine_strays`** — un claim de
    run mort posé sur un ticket de la page deux n'est jamais balayé ;
  - le **drain** — `router__tracker_state` et `router_unblocks` lisent la même
    liste.

- **Le piège qui explique pourquoi personne ne l'a vu, et il est à réparer ici.**
  Le faux `curl` de la suite le dit lui-même : « Page two and beyond are empty:
  this fake holds fewer tickets than a page. » Aucun test de ce dépôt n'a jamais
  fait tourner la boucle de pagination, et `FORGE_PAGE` n'apparaît dans aucun
  test. Un correctif livré contre ce faux-là serait vert sans rien prouver : la
  première AC de ce ticket est le faux, pas le pack. La sonde `q1` montre la
  forme minimale — un `curl` qui lit `page=` dans l'URL, rend un tableau par page
  et `[]` ensuite, en terminant par `\n200` parce que `forge__http` lit le statut
  comme dernière ligne.

- **Et la mutation qui doit rougir** (obligation 1 de la definition of done) : la
  garantie n'est pas « le compte est juste », c'est « le tracker rendu est le
  tracker ». Une entrée qui remet le `!=` numérique doit faire rougir un test qui
  lit un tracker de **plus d'une page pleine** ; une entrée qui remet
  l'identification par indice doit faire rougir un test qui lit un ticket de la
  **première** page alors qu'il y en a deux. Deux entrées, deux témoins, parce
  qu'un seul test verrait les deux défauts comme une seule absence de ticket.

- **Question transversale à poser en le livrant** : ce que ce ticket répare est
  une lecture qui rend **moins** que ce qu'on lui demande sans le dire. Le pack a
  la même forme ailleurs — le plafond de vingt pages, et `FORGE_PAGE` comparé à un
  `per_page=100` écrit dans un autre fichier. Une lecture bornée qui se tait est
  exactement ce que [59] a fermé pour les refus de git ; ici la valeur n'est pas
  un refus, c'est une liste courte, et aucun appelant ne peut faire la différence.

## Place dans la file

Ordre validé par Philippe le 08/09/2026, après la passe transversale du même
jour : **[76] → [74] → [77] → [75] → [73] → [19]**. Critère du dépôt —
minimiser la reprise, jamais l'urgence.

1. **[76]** — le seul faux vert livré des six, la plus petite surface, et sa
   première AC est **le faux du harnais** : tout ticket distant qui suit mesure
   contre lui. Le précédent est [59], premier pour la même raison.
2. **[74]** — même famille que [76] (« une lecture qui rend moins qu'on lui
   demande, sans le dire »), deux lignes de `loop.sh`, et il tranche comment la
   boucle lit un refus d'adaptateur — ce que [73] ajoutera.
3. **[77]** — tranche **où vit l'état local** d'un backend distant. [75] loge un
   cache : livré derrière, il hérite du logement ; livré devant, il le choisit
   deux fois.
4. **[75]** — le cache, qui donne son budget à la remise de [73] (cinq champs
   plus le corps par ticket, par fenêtre).
5. **[73]** — la remise, avec le mécanisme que `router.sh` porte déjà et le
   budget que [75] vient de payer.
6. **[19]** — l'installeur lit ce que les cinq autres décident : le `.gitignore`
   de la zone comptable ([77]), les clés de config de [76] et [75].

`Blocked by:` écrit en conséquence : `[76] None`, `[74] None`, `[77] None`,
`[75] 77`, `[73] 74, 75, 77`, et `[19]` gagne `73, 74, 75, 76, 77`.

### Ce qui reste à faire ailleurs — trouvé en livrant, pas réparé ici

`forge__slug_taken` lit le listing dans un heredoc avec `|| printf ''` : **un
listing refusé s'y lit « ce slug n'est pas pris »**, donc `forge_open_unique` ouvre
un doublon au lieu de ne rien faire. C'est la forme exacte de [59] à l'intérieur de
l'adaptateur, et ce n'est pas nouveau — mais ce ticket la rend atteignable **sans
panne réseau** : sur un dépôt de plus de 2 000 issues, le plafond refuse à tous les
coups, donc chaque `retro-*` ou `capability-*` que la boucle veut ouvrir « une
seule fois » est rouvert à chaque run. Non réparé ici : c'est une autre garantie
(« un refus n'est pas une réponse »), elle veut son test et sa mutation, et elle
est de la famille que [74] possède. Écrit dans [74] aussi.


### Contrainte écrite dans [74]

Ce ticket ajoute **une source de refus** au listing distant : le plafond de pages.
Elle emprunte exactement le chemin que [74] possède — `forge_ids` et
`forge_frontier` rendent non zéro, et `loop__next_ticket` lit la frontière dans une
substitution de commande en heredoc qui avale le statut. Conséquence à traiter
là-bas : un dépôt de plus de 2 000 issues arrive au pilote comme une **frontière
vide**, donc comme un gate de valeur terminal, alors que le backend a dit à voix
haute qu'il ne pouvait pas lire le tracker. C'est le même défaut que [74] traite
déjà pour un 404 ; ce ticket lui donne un second cas, atteignable sans aucune panne
réseau.

### Contrainte écrite dans [75]

Le budget du cache change de forme : une lecture de tracker n'est plus une requête
mais **une par page**, `forge__api` en réessayant trois en cas de refus. La
mémoïsation de `forge__listing` reste une variable de shell, posée **seulement en
cas de succès** — un refus de plafond ou de page n'est pas mis en cache et sera
repayé intégralement par l'appelant suivant. Un cache qui voudrait survivre à un
shell doit donc décider ce qu'il fait d'un tracker partiellement lu : la réponse
de ce ticket-ci est « rien, on refuse », et elle est plus facile à tenir qu'à
raffiner.

### Contrainte écrite dans [19]

Deux clés de configuration neuves à installer, déjà déclarées dans
`.claude/ralph.config.sh.example` et dans la liste de `test/smoke.bats` (les deux
sont une égalité dans les deux sens) : **`FORGE_PAGE`** (100 — la taille de page
demandée à la forge *et* la borne à laquelle une page est comparée, un seul nombre)
et **`FORGE_PAGES`** (20 — le nombre de pages qu'un listing peut demander avant de
**refuser**). Elles ne sont lues que par un backend distant, comme `TRACKER_REPO`
et les siennes.
