# 03 — Ralph loop tracer-bullet (happy-path)

**What to build:** Le walking skeleton de la ralph loop. À partir d'une frontière peuplée, elle broie chaque ticket via une **session fraîche** et le marque `resolved`, jusqu'à frontière vide = exit succès. Le gate est stubbé vert à ce stade (les vraies branches arrivent en [05]). C'est la tracer bullet bout-en-bout : elle prouve la chaîne scan → session → marquage → journal sur de vrais process.

**Blocked by:** 02

**Write-surface:** `.claude/loop.sh`, `test/loop-happy-path.bats`, `test/smoke.bats`

**Status:** resolved

- [x] `loop.sh` acquiert le verrou de run, puis boucle : scan frontière → spawn session fraîche (`claude -p`, `--output-format stream-json`, `--dangerously-skip-permissions`) → gate (stub vert) → `mark_resolved` → append `run.log`.
- [x] Sur N tickets fixtures indépendants, un fake `claude` « succès » les fait tous passer `resolved`, puis la boucle sort en succès sur frontière vide.
- [x] Le marquage `resolved` est fait **par la boucle après le gate**, jamais par la session.
- [x] Les gardes anti-emballement coupent le run : kill gracieux (SIGTERM), cap `ITER_CAP`, détecteur de run stérile `STERILE_K`.
- [x] Le prompt de la session injecte le ticket + des pointeurs (CONTEXT / ADRs / index LEARNINGS) — vérifié par le contenu passé au fake `claude`.

## Comments

- **Write-surface élargie d'un fichier** : `test/smoke.bats`. Ce ticket change le contrat de `loop.sh` (le squelette du [01] devient une vraie boucle), donc deux tests de fumée assertaient un comportement qui n'existe plus. Adaptés, pas supprimés.

- **Bug attrapé par les tests : une session qui meurt sans rien écrire faisait exploser la boucle.** `grep` sur un fichier vide renvoie 1, `pipefail` le remonte, `set -e` tue le run — un crash de session, un OOM ou un kill terminaient donc le run entier au lieu de compter un échec. Une session morte sans sortie est un cas *normal* ici, pas une anomalie : l'extraction de champ renvoie maintenant du vide.

- **Codes de sortie** posés comme contrat, documentés en tête de `loop.sh` : `0` frontière vide · `1` verrou déjà tenu · `2` config absente · `4` arrêt sur garde (stop demandé, cap, stérile). Le `4` distingue « le run s'est arrêté sans finir » de « le run a échoué ».

- **Le kill est gracieux, pas une mise à mort.** Le verrou de run pose ses propres traps TERM/INT qui sortent immédiatement ; la boucle les remplace par un simple drapeau, le temps de finir l'itération. Sinon un SIGTERM en pleine itération laisserait un ticket `claimed` que plus personne ne possède. Vérifié : sans ce remplacement le run sort en 143 et le ticket reste claimé.

- **Le détecteur stérile compte des itérations *consécutives*.** La remise à zéro sur succès n'était couverte par aucun test — un run heureux n'incrémente jamais le compteur, donc la retirer ne cassait rien. Test ajouté sur un scénario mixte (échec, échec, succès, échecs) : sans la remise à zéro, le run abandonne deux itérations trop tôt. Mutation vérifiée.

- **`mark_resolved` dépend du verdict, pas de la session.** Prouvé de deux façons : un fake `claude` qui lit le tracker pendant qu'il tourne y observe `claimed` (jamais `resolved`), et une session en échec ne résout rien. Sans le test du code de retour de la session, le second rougit.

- **Pas de `jq`.** L'extraction de `num_turns` / `total_cost_usd` sur l'événement `result` se fait en `sed` : ces champs sont des scalaires plats et le pack promet de tourner sans rien d'installé. À revoir si le parsing devient structurel ([04] surveille le flux pour le seuil 150K).

- **Le journal de run** (`.scratch/<feature>/run.log`) est append-only, une ligne TSV par itération (horodatage, ticket, issue, tours, coût), échecs compris. Non autoritaire : un test le supprime en cours de route et le run suivant se comporte exactement pareil.

- **Ce qui reste stubbé ici** : `loop_gate` renvoie vert. Les checks objectifs, les lentilles et les échecs typés (pause budget, re-slice, retry-N puis escalade, rollback) arrivent en [05]/[07]. Aujourd'hui un échec rend simplement le ticket à la frontière, et c'est le détecteur stérile qui borne le run.

- **La suite prend 37 s** pour 69 tests (une première mesure annonçait 2 min : elle chronométrait trois exécutions enchaînées — microbats, bats-core, PATH minimal). Ramenée à 28 s ensuite en montant le projet-fixture depuis un template construit une fois par révision du pack. Le montage n'est plus le poste dominant (80 ms sur ~400 ms par test) ; le reste est le coût assumé du seam process.
