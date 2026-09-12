# 75 — Le drain d'un backend distant relit le tracker par ticket

**What to build:** Un cache de lecture du tracker dont la durée de vie dépasse une substitution de commande, et qui ne vit pas là où une session écrit.

**Blocked by:** 77

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/forge.sh`, `test/tracker-remote.bats`

**Status:** ready-for-agent

- [ ] Un ticket drainé sur un backend distant coûte un ordre de grandeur de requêtes de moins.
- [ ] Le cache ne vit dans aucun fichier qu'une session routée peut écrire ([40], corollaire de [21]).
- [ ] Une écriture du tracker l'invalide **pour tous les process du run**, pas seulement pour celui qui a écrit.
- [ ] Une édition faite par un humain sur la forge pendant un run reste visible : la frontière est un scan sans mémoire, et un cache sans borne en ferait une photo.

## Comments

- **Contrainte écrite en livrant [81] (10/09/2026) — le cache hérite du sceau.**
  [77] a logé la zone de ce backend dans le répertoire-témoin du run, et [81]
  scelle **tout** ce que ce répertoire porte : un digest par fichier, pris à
  l'instant où le pilote finit de prendre ses témoins, gardé dans une variable du
  pilote que rien n'exporte. Deux conséquences pour ce ticket, à choisir
  explicitement plutôt qu'à découvrir :

  - un fichier de cache créé **avant** la prise du sceau est tenu à son **digest**,
    c'est-à-dire immuable pour la durée du run. Ce n'est probablement pas ce qu'un
    cache veut.
  - un fichier créé **après** n'est tenu par rien du tout, et c'est le résidu que
    [81] a nommé sans le fermer (`capability.seen` est le cas déjà présent).

  Si le cache doit bouger pendant le run, il lui faut une ligne dans
  `gate_witness_mutable` avec sa borne — `grows` (longueur, pour un fichier
  append-only) ou `rewritten` (existence ici, contenu tenu par son propre
  propriétaire, comme `retro_hold_index` le fait pour l'index des leçons). Une
  troisième borne demanderait de dire ce qu'elle achète, et la passe du 10/09 a
  montré ce que coûte une liste dont le critère n'est écrit que dans une phrase.


- **Ouvert par [18], livré le 08/09/2026, et le chiffre est mesuré et non estimé.**
  `lib/forge.sh` mémoïse le listing des issues dans une **variable du shell
  appelant**. Ce que ça achète est exactement une chose : les lectures d'un
  **même appel** se replient sur une requête — un scan de frontière de quarante
  tickets portant chacun un blocage coûte une requête et non quarante et une.

  Ce que ça n'achète pas : une variable de shell meurt à la première
  substitution de commande, et une substitution est **la** façon dont tout ce
  pack lit le tracker (`$(tracker_ids)`, `$(tracker_field …)`, un heredoc nourri
  par l'une des deux). Donc un appelant qui demande six choses sur quarante
  tickets paie quarante listings, quoi que fasse le mémo. Ordres de grandeur sur
  un tracker de quarante : **1** requête pour un scan de frontière, **41** pour
  un débordement de surface dans un chemin que personne ne déclare, **240** pour
  **un** ticket drainé (`router__tracker_state` lit cinq champs plus le ticket
  entier pour chaque ticket, à chaque ticket drainé — [58]/[61]).

- **Les deux durées de vie possibles, et pourquoi [18] a refusé les deux plutôt
  que d'en choisir une mal.**

  1. *Un fichier dans `.scratch/<feature>/`* — à côté du sidecar de claim. C'est
     un fichier qu'une session routée écrit, donc [40] et le corollaire de [21] :
     un contrôle qui lit ce que la chose contrôlée peut écrire n'est pas un
     contrôle. Et ce cache-ci décide de ce que le tracker **dit**, c'est-à-dire
     de tout — la frontière, le claim, la write-surface que le scope-guard juge.
  2. *Un fichier dans le répertoire témoin du run* (`RALPH_FRONTIER_COMMON`, un
     `mktemp -d` que le pilote n'exporte jamais, où [70] loge déjà son témoin et
     qui n'ajoute **aucun** nom à `gate_tmp_names`). C'est la bonne réponse, et
     `human-loop.sh` n'en fabrique pas : le drain — celui qui paie les 240 — n'a
     pas de répertoire de run. Lui en donner un est une modification du point
     d'entrée, pas d'un backend, donc hors de la write-surface de [18].

- **Le piège à ne pas manquer en le livrant** : l'invalidation doit traverser les
  process. Une écriture faite dans un sous-shell (`n="$(tracker_bump_failures …)"`
  est la forme la plus courante) n'efface aujourd'hui que le cache de ce
  sous-shell ; avec un fichier, elle doit effacer celui de tout le run, sans quoi
  le parent lira l'état d'avant sa propre écriture. Sur-invalider est sûr,
  sous-invalider est un ticket réclamé deux fois.

- **Et la borne à ne pas oublier** : la frontière de ce pack est un **scan sans
  mémoire** ([04]) — c'est ce qui fait qu'un run planté, une édition humaine
  entre deux itérations et un démarrage à froid se comportent pareil. Un cache
  sans TTL sur une nuit en ferait une photo prise au démarrage, et un humain qui
  ajoute un ticket à trois heures du matin ne serait pas vu. La borne qui
  ressemble le plus à ce que le pack fait déjà est celle de `budget__fetch`
  (`USAGE_CACHE_TTL`), qui est courte et configurée.

- **Deux choses de la passe transversale du 08/09/2026**
  (`../passe-transversale-08-09.md`).

  1. **Le cache que ce ticket doit loger a déjà un voisin, et il est dans la
     mauvaise zone.** `.scratch/<feature>/.forge-claims` — le sidecar de [18] —
     porte le claim, le numéro de requête et l'URL du reçu, et une session
     l'écrit sans que rien le voie (mesuré, `../sondes/passe-08-09/q2-*.bats` ;
     ticket **[77]**). Le raisonnement qui a fait refuser `.scratch/<feature>/`
     pour le cache est donc **déjà** contredit par ce qui y vit : ne pas
     « rejoindre le voisin » au prétexte qu'il est là.
  2. **Le consommateur qui rend ce ticket nécessaire est [73].** La remise d'un
     tracker distant, telle que `router_protect_tracker` la fait déjà, lit cinq
     champs plus le corps par ticket et par fenêtre. Livrer [73] sans cache
     multiplierait ce coût par le nombre d'itérations d'une nuit ; livrer ce
     ticket-ci d'abord donne à [73] son budget. L'ordre n'est pas indifférent.

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

Le budget que ce ticket doit chiffrer a changé de forme : **une lecture de tracker
n'est plus une requête, c'en est une par page** (`FORGE_PAGE`, 100 issues par page),
et `forge__api` réessaie une lecture jusqu'à `FORGE_READ_TRIES` (3) fois. Un tracker
de 21 pages coûte donc jusqu'à 63 requêtes dans le pire cas, contre 3 avant — et
c'est exactement ce que la relecture par ticket multiplie.

Deux propriétés de la mémoïsation existante à ne pas casser en la déplaçant :

- elle est posée **seulement en cas de succès**. Un refus — une page qui refuse,
  ou le plafond de `FORGE_PAGES` atteint — n'est pas mis en cache, donc l'appelant
  suivant repaie tout. C'est délibéré : un tracker partiellement lu n'est pas un
  tracker, et le mettre en cache serait servir une liste courte depuis la mémoire.
  Un cache qui survit à un shell doit reprendre cette décision explicitement.
- elle est clé sur `<flavour>/<repo>` et vidée par `forge__forget` à **chaque
  écriture**, pour la raison écrite là-bas : l'état d'avant une écriture est une
  frontière qui tient encore le ticket.

## Note écrite par [77] (livré le 09/09/2026)

**Le logement du cache est choisi, et c'est la raison pour laquelle [77] passait
devant ce ticket dans la file.** `forge_sidecar_witness` range la copie que le run
tient dans le **répertoire témoin du run** — celui que `gate_frontier_common`
fabrique, en `$TMPDIR` sous un `mktemp` que le pilote n'exporte pas ([30], [40]) —
et l'opération d'interface qui la prend (`tracker_sidecar_witness DIR`) reçoit ce
répertoire en argument plutôt que de le composer. Trois choses à reprendre telles
quelles :

- la prise se fait **avant la première session**, dans `forensic_witness`, qui est
  le seul endroit du pack où « avant que quoi que ce soit d'écrivable existe » est
  vrai ;
- l'ajout ne coûte **aucun nom** à `gate_tmp_names` ni au balayeur de [19], parce
  que le répertoire est déjà sur la liste ;
- une lecture du module passe par un accesseur unique (`forge__reading`) qui
  choisit la copie ou le fichier, jamais par un `if` recopié au point d'appel.

## Note écrite par la passe transversale du 10/09/2026

**Le logement tranché par [77] n'est pas remis en cause, et il hérite d'une
obligation.** Le répertoire témoin du run reste le bon endroit — il n'y en a pas
de meilleur dans ce pack, et la passe l'a mesuré plutôt que supposé : la zone est
énumérable par la session jugée (`ls "$TMPDIR"/ralph-*`), mais toutes les
alternatives le sont autant ou davantage.

Ce que ça ajoute : ce cache **décide de ce que le tracker dit** — la frontière,
le claim, la write-surface que le scope-guard juge. Il est donc, au sens de
**[81]**, un témoin et pas un fichier de travail : il entre dans le recensement
et il porte un digest, au même titre que la copie du sidecar de [77]. Ne pas
l'écrire comme une exception « c'est un cache, pas un témoin ».

Et la borne de fraîcheur que ce ticket doit poser ne dispense pas du digest : un
cache périmé est une décision de ce ticket, un cache **réécrit** est un contrôle
qui lit ce que la chose contrôlée a écrit.

## Note écrite par [82] (livré le 11/09/2026)

**Un cache ne mémorise jamais un refus.** `forge__listing` ne pose sa variable
qu'après avoir vérifié que la pagination s'est terminée — un listing refusé ne
laisse rien derrière lui, et c'est ce qui fait que le refus se répète à chaque
lecture au lieu d'être remplacé par une liste vide qui, elle, aurait l'air d'une
réponse. Un cache avec une durée de vie plus longue doit garder cette propriété
**explicitement** : écrire un fichier de cache sur un listing refusé, ou lire un
fichier de cache vide comme « ce tracker ne porte aucun ticket », rouvre [76],
[74] et [82] d'un coup — la frontière, le scope-guard et la remise lisent tous
cette liste.

Corollaire pour l'interface de ce ticket : depuis [82], une lecture a **trois**
réponses (`lib/tracker.sh`, « what a refusal of a *read* means »). Un accesseur
qui choisit entre la copie et le réseau doit rendre les trois, pas deux — un
`2` que le cache aplatit en `1` ferait lire « il n'y a pas de tel ticket » à
`gate_write_surface`, `lenses_has_tag` et `router_pin`, qui est exactement la
réponse que [82] leur a retirée.
