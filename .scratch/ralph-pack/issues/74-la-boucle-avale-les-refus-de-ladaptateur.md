# 74 — La boucle avale les refus de l'adaptateur

**What to build:** Faire lire à `loop.sh` les deux refus de l'adaptateur qu'il jette aujourd'hui — celui de `tracker_mark_resolved` et celui de `tracker_frontier` — sans que la boucle apprenne quoi que ce soit d'un backend.

**Blocked by:** None

**Write-surface:** `.claude/loop.sh`, `.claude/lib/select.sh`, `test/loop-happy-path.bats`, `test/tracker-remote.bats` — plus `.claude/lib/receipt.sh`, `.claude/lib/retro.sh`, `test/retro.bats`, `test/mutate.sh` et `docs/frontiere-de-confiance.md`, **écart déclaré** (voir les commentaires de livraison).

**Status:** resolved

- [x] Un `tracker_mark_resolved` refusé ne produit pas une ligne de journal `resolved`.
- [x] Une frontière que l'adaptateur a **refusé** de lire ne déclenche pas le gate de valeur terminal.
- [x] Aucune des deux corrections n'apprend à la boucle ce qu'est un backend : ce sont deux codes de retour de l'interface, lus.
- [x] Le chemin `local` garde exactement le comportement qu'il a aujourd'hui, `run.log` compris.

## Comments

### Livré le 09/09/2026 — ce que le code ne dit pas

- **Ce qui a été livré, dans l'ordre des deux endroits.** *(1)* `loop.sh` teste
  `tracker_mark_resolved` : vrai → `outcome=resolved`, faux → `outcome=not-marked`
  et une ligne de run qui dit ce que le tracker répond **après** l'appel
  (`tracker_field ID Status`), donc laquelle des deux formes de refus c'était — un
  pipeline rouge laisse `ready-for-human`, un refus d'écriture laisse le ticket où
  il était. *(2)* `loop__next_ticket` lit la frontière sur une ligne à elle
  (`frontier="$(select_frontier)" || return 1`) au lieu de la lire dans le heredoc,
  et rend `1` ; le pilote lit ce refus, attend tant qu'une itération est en vol,
  puis journalise `frontier-refused`, imprime la phrase et sort en **4**. Rien
  dans les deux ne sait ce qu'est un backend.

- **La décision qui a coûté le plus de réflexion : un mot, et pas un état.** Le
  commentaire d'ouverture prévenait qu'une valeur d'`outcome` de plus touche la
  politique d'échec, le reçu et le compteur de stérilité. Ce qui a été fait :
  `not-marked` est exempté de `failures_handle` **à côté de `resolved`** (l'itération
  a livré ce qu'on lui demandait ; le budget de reprise du ticket n'a pas à payer le
  refus d'un autre), il émet le reçu d'audit comme avant, et il reste demandé par le
  rétro. Les deux dernières ne sont pas des ajouts : cette route produisait déjà un
  document **et** une leçon, sous un mot qui était faux. Les enlever aurait été un
  changement de comportement caché dans un renommage. `retro_wanted` a donc été
  relu contre son critère et non contre ses mots ([31], [45]) : « qu'est-ce qui a
  jugé le code » répond la même chose pour `not-marked` que pour `resolved`, le
  gate ayant tourné, été vert, et le travail ayant atteint la branche.

- **Ce qui change vraiment de comportement, et c'est assumé : le compteur de
  stérilité.** Seul `resolved` le remet à zéro, donc une itération `not-marked` en
  compte une. Conséquence sur un backend distant avec `WAIT_CI` : `STERILE_K`
  pipelines rouges d'affilée arrêtent la nuit (exit 4) au lieu de la laisser
  tourner. C'est cohérent avec la seule chose que le compteur mesure — « ce run n'a
  rien résolu » — et avec le fait qu'une escalade le compte déjà. Avant [74] la
  même nuit sortait en 0 après avoir mis chaque ticket dans le puits humain.

- **Ce que la boucle ne fait pas, volontairement** : elle ne touche pas au claim
  après un refus de marquage. Il est là où l'adaptateur l'a laissé — déposé sur
  `ci-red` (la voie ordinaire), gardé sur un refus d'écriture, et la liveness de
  [12] le récupère alors quand ce run est mort. Un `tracker_unclaim` ajouté ici
  serait la boucle en train de décider à la place de l'adaptateur sur un tracker
  qu'elle vient de ne pas pouvoir écrire.

- **Le pilote attend, puis s'arrête.** Attendre tant qu'une itération est en vol :
  celles-là vont écrire le tracker et un aléa peut avoir guéri d'ici là. S'arrêter
  ensuite : `forge__api` a déjà redemandé la lecture trois fois, et depuis [76] le
  refus le plus probable n'est pas un aléa mais un **état** — un dépôt au-delà du
  plafond de pages refuse tous les listings, à tous les passages. Boucler dessus
  serait une nuit à interroger une forge qui répond toujours la même chose.

- **`select_frontier_count` a été corrigé aussi, bien que personne ne l'appelle.**
  Même forme un cran plus bas : un pipeline répond pour son **dernier** maillon,
  donc `awk` imprimait `0` pour un listing qui n'a pas eu lieu. Piège trouvé en
  l'écrivant : `printf '%s\n' "$frontier"` sur une frontière vide donne une ligne
  vide, donc `NR = 1` — le compte d'une frontière vide serait passé de `0` à `1`,
  ce qu'un test existant de `test/tracker-local.bats` attrape. C'est `printf '%s'`.

- **Sondes du run réel** (les deux scénarios ont été exécutés avec un dump avant
  d'écrire les assertions, pas devinés) :
  1. *Marquage refusé* — `WAIT_CI auto` + `forge_ci failure` : le ticket finit
     `ready-for-human` / `ci-red`, `run.log` porte `1-alpha<TAB>not-marked`, la
     requête ouverte porte le reçu d'audit complet avec la phrase de `not-marked`
     et `outcome: not-marked`, `Failures:` est vide. C'est le run entier, pas
     l'adaptateur seul.
  2. *Listing refusé* — le plafond de pages atteint **pendant** que la session
     travaille : une session (`claude=1`), **zéro** gate de valeur, sortie 4,
     `frontier-refused` au journal. Ce que la sonde a montré et que rien ne
     laissait prévoir : le plafond refuse aussi **à l'intérieur** de l'itération,
     donc le scope-guard ne peut pas dire à qui appartient `src/alpha.txt` (il le
     dit, [76]), et l'itération meurt sans verdict — `iteration-lost`, ticket rendu
     à la frontière. Pas de faux vert au bout, et le test le dit au lieu de
     raconter un run qu'il ne fait pas.

- **Trois choses vues et non prises**, écrites ici et au tableau plutôt que
  laissées à retrouver :
  1. `forge__slug_taken` lit le listing dans un heredoc avec `|| printf ''` : un
     refus s'y lit « ce slug est libre » et `forge_open_unique` ouvre un doublon.
     C'est dans l'adaptateur, hors write-surface de ce ticket → **ticket [78]**
     ouvert le 09/09/2026.
  2. `claim_reclaim_stale` lit `tracker_ids` dans un heredoc de la même façon. Un
     listing refusé y devient « aucun ticket », donc la balayeuse **n'agit pas**
     au lieu d'agir à tort : le refus échoue du côté sûr, et c'est la raison de ne
     pas en faire un ticket — mais c'est la même forme, donc c'est écrit.
  3. Un refus de listing **pendant** une itération tue son sous-shell (la politique
     d'échec écrit dans le tracker, et le refus voyage sous `set -e`). Le pilote le
     nomme `iteration-lost` et rend le ticket ; personne ne ment, mais une
     itération payée est perdue là où un message aurait suffi.

- **Pièges de harnais, pour le suivant.** `FORGE_PAGE 2` + `FORGE_PAGES 1` avec
  deux issues est la façon la moins chère de faire refuser **tous** les listings
  d'un run sans simuler de panne — et ça met en scène l'état stable de [76]
  plutôt qu'un incident. Une session scriptée peut faire grossir le faux tracker :
  le shim `claude` exécute le script avec son propre environnement, donc
  `$RALPH_SHIM_STATE/forge` est atteignable depuis la session (écrire `issue.N.*`
  et une ligne dans `order`). Et sur un backend distant, le reçu d'audit se lit
  avec `forge_request_body N`, pas dans un fichier.

- **Ce que ce ticket a ajouté aux gates** : cinq tests (deux runs entiers dans
  `test/tracker-remote.bats`, un unitaire sur `select_frontier_count`, le témoin
  local dans `test/loop-happy-path.bats`, un unitaire sur `retro_wanted` dans
  `test/retro.bats`) et **sept** mutations, dont deux témoins appairés — le mot
  posé en dur dans l'autre sens (le run local doit redevenir rouge) et la liste du
  rétro réduite à ce qu'elle était.

- **Écart de write-surface, déclaré.** `receipt.sh` gagne la phrase de
  `not-marked` (sans elle le reçu tombait dans le cas générique et disait « rien
  ci-dessous n'est un verdict » d'une itération dont le gate était vert) ;
  `retro.sh` gagne le mot dans `retro_wanted` (voir plus haut) ; `test/retro.bats`
  et `test/mutate.sh` tiennent ces deux-là ; `docs/frontiere-de-confiance.md` était
  obligatoire — trois lignes du tableau nommaient ce ticket comme propriétaire.

- **Ouvert par [18], livré le 08/09/2026 : deux endroits, une seule forme.** La
  boucle lit l'interface de l'adaptateur à travers des constructions qui **jettent
  un statut**, et ça ne s'était jamais vu parce que le seul backend qui existait ne
  refusait presque jamais.

  1. **`tracker_mark_resolved`.** `loop.sh` l'appelle et pose `outcome=resolved`
     derrière, sans lire son code. Sur un backend distant avec `WAIT_CI` — le
     défaut — un pipeline rouge fait escalader le ticket par l'adaptateur, qui rend
     non zéro : le tracker dit `ready-for-human` et **`run.log` dit `resolved`**.
     Le tracker a raison ; la ligne de journal enregistre le verdict du gate de ce
     run, et le verdict de la forge arrive après lui. C'est vrai, et c'est illisible
     pour un humain au matin.
  2. **`tracker_frontier`.** `loop__next_ticket` lit `select_frontier` dans une
     substitution de commande en heredoc, qui avale le statut. Un listing refusé —
     une coupure réseau, un jeton expiré — arrive donc au pilote comme une
     **frontière vide**, et une frontière vide est ce qui déclenche le gate de
     valeur terminal, c'est-à-dire une session qui peut fermer la feature. C'est la
     règle de [59] à l'endroit où elle coûte le plus cher, et `select_next_ticket`
     — qui, lui, lit le statut — n'est appelé par personne dans le pack.

- **Pourquoi [18] ne les a pas prises** : son AC 1 dit « la boucle reste agnostique
  (aucun changement de control-flow) », ce qui est la bonne contrainte pour un
  ticket qui ajoute deux backends et la mauvaise pour ces deux lignes-là. Ce que
  [18] a fait de son côté de l'interface : les deux opérations **refusent
  correctement** (code de retour, jamais une sortie de shell, [71]), et
  `forge__api` redemande une lecture avant d'abandonner — trois essais — de sorte
  qu'un aléa réseau ne soit pas une nuit. Le reste est ici.

- **Le piège, mesuré en écrivant [18]** : `outcome` n'est pas une chaîne de
  journal, c'est ce que lisent la politique d'échec, le reçu et le compteur de
  stérilité. Une valeur de plus (`not-marked`, ou autre) touche ces trois-là, et
  `resolved` est la seule valeur que [35] autorise à sortir un ticket de la
  frontière. La sortie la moins chère est probablement de ne pas inventer d'issue :
  lire le refus, journaliser ce que le tracker dit **vraiment** après l'appel, et
  laisser la politique d'échec en dehors.

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

## Contrainte écrite par [76] (livré le 08/09/2026)

Le listing distant a désormais **une source de refus de plus**, et elle n'a besoin
d'aucune panne réseau pour arriver : `forge__listing` refuse quand il a atteint son
plafond de pages (`FORGE_PAGES`, 20, sur des pages de `FORGE_PAGE`, 100) sans
qu'aucune page ne soit venue courte. Un dépôt de plus de 2 000 issues rend donc
`forge_ids` et `forge_frontier` non zéro, avec une phrase, **à tous les coups**.

Ce que ça change pour ce ticket : le cas que la ligne du tableau de confiance
décrivait comme « un listing qui a refusé arrive au pilote comme une frontière
vide, et une frontière vide déclenche le gate de valeur terminal » n'est plus
seulement un 404 ou un timeout — c'est aussi un dépôt trop gros, c'est-à-dire un
état stable et reproductible plutôt qu'un incident. Le correctif attendu ici (faire
lire à `loop.sh` le statut que la substitution de commande en heredoc avale) est le
même ; ce qui change est le coût de ne pas le faire.

**Et un second avaleur, trouvé en livrant [76] et non réparé là-bas** :
`forge__slug_taken` lit `forge__records` dans un heredoc avec `|| printf ''`, donc
un listing refusé s'y lit « ce slug n'est pas pris » et `forge_open_unique` ouvre un
doublon. Il est dans l'adaptateur et non dans `loop.sh`, mais c'est la même règle —
un refus n'est pas une réponse — et il devient certain plutôt qu'accidentel dès que
le plafond de pages refuse : sur un gros dépôt, chaque ticket `retro-*` ou
`capability-*` censé être ouvert une seule fois est rouvert à chaque run.
