# 75 — Le drain d'un backend distant relit le tracker par ticket

**What to build:** Un cache de lecture du tracker dont la durée de vie dépasse une substitution de commande, et qui ne vit pas là où une session écrit.

**Blocked by:** None

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/forge.sh`, `test/tracker-remote.bats`

**Status:** ready-for-agent

- [ ] Un ticket drainé sur un backend distant coûte un ordre de grandeur de requêtes de moins.
- [ ] Le cache ne vit dans aucun fichier qu'une session routée peut écrire ([40], corollaire de [21]).
- [ ] Une écriture du tracker l'invalide **pour tous les process du run**, pas seulement pour celui qui a écrit.
- [ ] Une édition faite par un humain sur la forge pendant un run reste visible : la frontière est un scan sans mémoire, et un cache sans borne en ferait une photo.

## Comments

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
