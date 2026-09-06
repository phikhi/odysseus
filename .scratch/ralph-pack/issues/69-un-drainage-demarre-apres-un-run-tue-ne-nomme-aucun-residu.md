# 69 — Un drainage démarré après un run tué ne nomme aucun résidu

**What to build:** `loop_main` dit au démarrage ce que les runs précédents ont laissé dehors (`gate_leftovers`) et dedans (`concurrency_leftovers`). `human_loop_main` n'appelle ni l'un ni l'autre — alors qu'un drainage démarré après un run tué est exactement la situation où un humain vient voir ce qui s'est passé.

**Blocked by:** None

**Write-surface:** `.claude/human-loop.sh`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** human-loop, observability

- [x] Un drainage démarré après un run tué nomme ce que ce run a laissé : `$TMPDIR` ([62]), les gardes d'exclusion morts ([49]), le marqueur de successeur ([53]), les worktrees encore enregistrés ([13]).
- [x] Le choix est **explicite** : `human_loop_preflight` est écrit comme *une liste et pas une délégation*, donc ce qui est ajouté l'est ligne par ligne, jamais par un appel à `loop_preflight`.
- [x] Ce qui est ajouté ne **refuse** rien : ces lignes comptent, elles ne jugent pas — même posture que dans `loop_main`, et un drain qui refuserait de démarrer sur un résidu empêcherait un humain de venir regarder.
- [x] Une entrée de mutation par garantie livrée, plus le témoin appairé.

## Comments

- **Le constat était ouvert dans [16]** et il a été qualifié par la passe transversale du 06/09/2026 (`../passe-transversale-06-09.md`, §5). Sondes : `../sondes/passe-06-09/q4-*.bats`.

- **Mesuré** (`q4`), run réel tué au `KILL` pendant le gate :

  | | |
  |---|---|
  | Q4a — un drainage démarré sur ce décor | décor : **9** entrées dans `$TMPDIR`, un marqueur de successeur, **1** worktree encore enregistré. Le drain en nomme **0** |
  | Q4b — témoin appairé, un run AFK sur le même décor | il en nomme **3** : les 9 entrées comptées **9**, le marqueur, le worktree |

- **Inerte, et c'est pour ça que c'est le moins cher des quatre** : un silence, pas un faux vert. Mais c'est un silence dans la seule situation où le pack a un humain qui regarde — un run tué, un puits qu'on vient vider le matin — et le pack a un document sur ce qu'il ne regarde pas.

- **Même racine que [55]/[56]/[57]** : une garantie qui est une propriété de `loop.sh` et pas du pack. La liste des choses que `loop_main` fait au démarrage et que `human_loop_main` ne fait pas a été mesurée en entier par la passe ; ce qui reste après ce ticket est délibéré (`budget_*`, `concurrency_cap`, `claim_reclaim_stale`, `playthrough_*`, `retro_*`, `capability_witness` — un drain ne spawne pas d'itération, ne juge rien et ne clôt aucune feature).

- **Contrainte pour [19].** Le commentaire de `gate_leftovers` désigne l'installeur comme le composant entitled à balayer, et [62] a fait de `gate_tmp_names` la spécification de ce balayage. Ce ticket ajoute un **second lecteur** de `gate_leftovers` : ce que [19] balaye sera nommé par deux points d'entrée, et une divergence entre les deux serait deux vérités sur le même disque.

- **Piège de sonde.** Un ticket `ready-for-human` ne fait pas démarrer un gate : une sonde qui veut tuer un run doit semer un ticket `ready-for-agent` en plus. Et un run tué garde ses verrous — `rm -rf "$(run_lock_dir)" "$(tree_lock_dir)"` avant de démarrer quoi que ce soit derrière lui.

- **Place dans la file, validée par Philippe le 06/09/2026 : premier.** Aucune
  arête (`Blocked by: None`), la plus petite surface des quatre — deux lignes dans
  `human_loop_main` — et c'est le seul des quatre dont la réparation ne touche pas
  `router.sh`. Il livre en passant le décor de sonde que [67] et [66] réutilisent :
  « un run réel tué au `KILL` pendant le gate, puis un drain démarré derrière »,
  avec ses deux pièges (semer un ticket `ready-for-agent` en plus du ticket du
  puits, et retirer les deux verrous que le run tué garde). Ordre complet retenu :
  [69] → [67] → [66] → [68] → [18] → [19].

## Livraison — 06/09/2026

- **Deux lignes dans `human_loop_main`**, juste après `draining ready-for-human` et
  avant `router_run_notes` : le bloc `while … <<LEFTOVERS $(gate_leftovers || true)`
  et `if leftovers="$(concurrency_leftovers)"; then human_loop_log …; fi` — les
  mêmes que `loop_main` dit au même endroit. Aucun appel à `loop_preflight` :
  l'AC du choix explicite est tenue par le fait qu'il n'y a rien d'autre à lire
  que ces deux lignes, et le commentaire le dit pour le prochain lecteur.

- **Mesuré après correctif sur le run réel**, pas seulement sur un décor posé :
  `sondes/ticket-69/verification.bats` rejoue `passe-06-09/q4` (session qui écrit,
  gate qui tourne, `kill -KILL` au milieu, les deux verrous retirés, un
  `ready-for-agent` semé en plus du ticket du puits). Le décor produit **9**
  entrées dans `$TMPDIR`, un marqueur de successeur, **1** worktree enregistré —
  et **0 garde**, un run tué pendant le gate n'en tenant aucun. Le drain en nomme
  **3**, exactement le témoin AFK de Q4b. `V2` ferme le ticket du puits derrière :
  `rc=0`, `Status: wontfix` — rien n'a été refusé.

- **Le garde mort de [49] est le seul des quatre que le décor réel ne produit
  pas**, donc il est posé à la main dans `test/human-loop.bats` (`.open.guard` au
  pid d'un sous-shell sorti) avec son témoin appairé vivant (`.busy.guard` au pid
  du test). C'est l'écart entre les deux décors, et il est ici plutôt que caché.

- **Frontière de confiance, question posée avant d'écrire.** Rien de ce qui est
  ajouté n'est un contrôle : les trois zones lues sont écrivables par une session
  routée — `$TMPDIR` est dans son environnement, `*.guard` est dans la zone de
  bookkeeping que le scope-guard laisse tomber, le marqueur est l'un des deux
  fichiers de `.git/` que le tableau nomme déjà. Un faux résidu forgé fait dire
  une phrase de plus, à un drainage comme à un run, et rien de plus, parce que
  rien ne décide dessus. La ligne du tableau est élargie en conséquence.

- **Ce que `|| true` tient, et ce qu'il ne tient pas.** Mesuré : une substitution
  de commande dans un here-document **avale** le statut, donc retirer le `|| true`
  ne casse rien et une entrée de mutation qui le retire serait `VACUOUS`. La
  moitié qui refuse vraiment est l'assignation de `concurrency_leftovers` : sans
  son `if`, `set -e` tue le drain le matin où rien n'a été laissé. Les deux
  directions sont couvertes — l'entrée qui retire le `if`, et celle qui **insère**
  un refus sur résidu (forme de [17], une garantie qui est une absence).

- **Quatre entrées de mutation**, `69 …`, toutes sur `.claude/human-loop.sh` :
  les deux suppressions, plus la paire refus/silence. `741 mutations` au total.

- **Écart de write-surface, déclaré.** Au-delà des quatre chemins annoncés, ce
  ticket écrit dans `.scratch/ralph-pack/` : les tickets [16], [19] et [67] (les
  contraintes que la DoD demande d'écrire là où elles seront relues) et le nouveau
  `sondes/ticket-69/verification.bats`. Zone de bookkeeping, aucun code du pack.

- **Ce qui reste ailleurs.** Contrainte écrite dans [19] (deux lecteurs de
  `gate_leftovers`) et dans [67] (l'ordre du démarrage du drain a changé : les
  résidus passent avant `router_run_notes`). Le constat ouvert de [16] est fermé.
