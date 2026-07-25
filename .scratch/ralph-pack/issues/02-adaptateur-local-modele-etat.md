# 02 — Adaptateur `local` + modèle d'état

**What to build:** L'interface d'adaptateur de tracker et son implémentation `local` (fichiers markdown), plus le modèle d'état : sélection de frontière, marquage atomique, verrou de run. À partir de tickets fixtures, les opérations produisent la bonne frontière et les bonnes transitions d'état, observables via le seam. Le tracker devient la seule autorité d'état : une relecture du tracker seul reconstruit tout.

**Blocked by:** 01

**Write-surface:** `.claude/lib/tracker.sh`, `.claude/lib/tracker-local.sh`, `.claude/lib/select.sh`, `.claude/lib/state.sh`, `test/tracker-local.bats`, `test/state.bats`, `test/helpers/harness.bash`

**Status:** resolved

- [x] L'interface d'adaptateur est fixée (`frontier`, `read_ticket`, `claim`, `mark_resolved`/`mark_*`, `open_ticket`, `append_note`, `emit_receipt`) ; l'impl `local` la satisfait sur `.scratch/<feature>/issues/NN-*.md`.
- [x] `frontier` ne retourne que les tickets `open ∧ unblocked ∧ ready-for-agent ∧ non-claimed`, ordonnés min-NN ; un ticket dont `Blocked by:` n'est pas entièrement résolu est exclu.
- [x] Le marquage est atomique (écriture temp + `mv`) : un crash pendant le marquage ne laisse jamais un ticket dans un état partiel.
- [x] Le verrou de run empêche un second run de démarrer sur le même tracker et est libéré à la sortie.
- [x] Une relecture du seul tracker reconstruit l'état complet (aucun état hors-tracker requis).

## Comments

- **Write-surface élargie de deux fichiers.** `.claude/lib/tracker.sh` : l'AC 1 exige que « l'interface d'adaptateur soit fixée », et avec trois backends sourcés en vrac par `loop.sh` les fonctions se seraient écrasées entre elles. Chaque impl préfixe donc les siennes (`tracker_local_*`) et un dispatcher les route selon `TRACKER_BACKEND` — ajouter `github` ne touche ni la boucle ni ce fichier. `test/helpers/harness.bash` : le harnais grandit avec chaque ticket, ici de `pack_run` (piloter les libs comme un process avant que la boucle ne les utilise) et de lectures de champ indépendantes du pack.

- **Les assertions lisent le markdown elles-mêmes**, jamais via le lecteur du pack. Un test qui partage son parseur avec l'implémentation ne peut pas attraper l'implémentation en train d'écrire n'importe quoi.

- **Le test d'atomicité par course a été jeté.** Un lecteur bash face à un écrivain non atomique passe au vert : la fenêtre de troncature est de l'ordre de la microseconde, une lecture en bash de la milliseconde. Vérifié — le test passait avec `cat > fichier` à la place de `mv`. Remplacé par deux vérifications déterministes : l'inode du ticket change à chaque marquage (donc publication par `rename`), et un ticket en lecture seule reste marquable (le remplacement passe par le répertoire, ce qu'une écriture en place ne peut pas faire). Les deux rougissent sur mutation.

- **La re-lecture du tampon de claim a été remplacée par un vrai test-and-set.** Écrire son propre `owner=` puis le relire ne tranche rien : avec deux pickers, chacun peut relire avant que l'autre n'écrase, et les deux se croient gagnants. Le read-modify-write se fait maintenant sous un guard `mkdir` — la seule primitive atomique d'un pack bash pur — tenu le temps de l'opération seulement. Un picker mort en cours de claim est récupéré par le même contrôle de liveness que le verrou de run, factorisé en `state_guard_take`. Le backstop TTL et le fail-open strict restent au ticket [12].

- **Le verrou de run se reprend si son détenteur est mort.** Sans ça, un run tué par un `kill -9` bloquerait la feature jusqu'à ce qu'un humain remarque le répertoire orphelin — inacceptable pour de l'AFK. La liveness est basée sur le pid, donc mono-machine, ce qui est déjà le périmètre déclaré.

- **Ce qui n'est pas encore couvert et le sera ailleurs :** disjonction des write-surfaces et `MAX_PARALLEL` [13], backstop TTL du claim [12], backends `github`/`gitlab` [18] (le dispatcher échoue proprement avec exit 3 en attendant), journal de run [03].

- **Les 51 tests passent sous microbats et sous bats-core**, avec un `PATH` réduit à `/usr/bin:/bin` (ni node ni homebrew). Cinq mutations vérifiées : publication non atomique, filtre `unblocked` retiré, trap de libération du verrou retiré, guard de claim retiré — toutes détectées.
