# 05 — Gate QA objectif (tests + typecheck + scope-guard, checks //)

**What to build:** Le gate déterministe par itération : `TEST_CMD`, `TYPECHECK_CMD` et le scope-guard exécutés **en parallèle par la boucle bash** (autorité déterministe, complaisance LLM impossible). *resolved* = toutes les branches déclenchées vertes. C'est ce qui remplace le gate stub d'[03].

**Blocked by:** 03

**Write-surface:** `.claude/lib/gate.sh`, `test/gate.bats`

**Status:** resolved

- [x] Le gate lance `TEST_CMD`, `TYPECHECK_CMD` et le scope-guard en parallèle ; un exit non-zéro de n'importe lequel rend le gate rouge.
- [x] Le scope-guard échoue si `git diff --name-only` sort de la **write-surface déclarée** du ticket ; un débordement dans un fichier neutre est distingué d'un débordement dans un autre ticket.
- [x] *resolved* n'est prononcé que si **toutes** les branches déclenchées sont vertes ; un fake `claude` qui casse les tests ne produit jamais `resolved`.
- [x] Anti-faux-vert : une commande objective absente ou silencieuse ne compte pas comme verte (confirmation forcée).

## Comments

- **Write-surface élargie de quatre fichiers**, tous imposés par le câblage :
  - `.claude/loop.sh` — le gate stub d'[03] y est défini *après* le sourcing des libs, donc une `lib/gate.sh` ne pouvait pas le remplacer par simple redéfinition. Le stub est supprimé, la boucle appelle `gate_run` ; elle prend aussi le snapshot d'arbre pré-spawn dont le scope-guard a besoin — pas un `HEAD`, voir le dernier point.
  - `.claude/lib/tracker.sh` + `.claude/lib/tracker-local.sh` — nouvelle opération d'adaptateur `tracker_ids` (8ᵉ). Distinguer un débordement neutre d'un drift exige de savoir **qui d'autre** déclare le chemin ; un glob sur `.scratch/<feature>/issues/` aurait recâblé le backend local dans le gate, ce que l'architecture interdit explicitement. Les backends distants [18] devront la fournir.
  - `.claude/ralph.config.sh.example` — documentation de `TYPECHECK_CMD=none`.
  - `test/loop-happy-path.bats` — quatre fakes `claude` écrivaient leur marqueur (`session-cwd`, `status-during-session`, `call-seq`, `session-started`) dans le dépôt-fixture. Le scope-guard les rendait rouges à juste titre. Les marqueurs vivent maintenant hors du dépôt, dans `$RALPH_SHIM_STATE` — ce qu'ils auraient dû faire dès le départ : ce sont des instruments de test, pas du travail de session.

- **`git diff --name-only` seul ne suffit pas, et l'AC le demandait littéralement.** Deux trous, deux tests, deux mutations :
  1. **Les fichiers non suivis n'apparaissent pas dans un diff.** Or la write-surface d'un ticket neuf est faite précisément de fichiers qui n'existent pas encore : sur les fixtures, un guard qui ne regarde que les fichiers suivis ne voit jamais rien et passe vert quoi qu'écrive la session.
  2. **Une session qui commit son propre débordement échappe au diff du worktree.** La spec prévoit que la session commit ([06]) : la référence ne peut donc pas être l'état de l'index. Mutation vérifiée : en diffant le worktree, le test « overflow committé » passe au vert. Ce que la référence doit être exactement a demandé une seconde passe — dernier point.

- **Le bookkeeping de la boucle est exclu du diff.** Claim, `run.log` et flux de session vivent tous dans `.scratch/<feature>/` et sont écrits par la boucle, pas par la session. Sans le filtre, le tout premier gate de tout run est rouge — mutation vérifiée sur le happy-path.

- **Anti-faux-vert : trois portes, pas une.**
  1. Préflight qui **refuse de démarrer** (exit 2, avant le verrou) si `TEST_CMD` est vide, si `TYPECHECK_CMD` est vide, ou si le projet n'est pas un dépôt git — un scope-guard aveugle est un faux vert permanent.
  2. `TYPECHECK_CMD=none` est la seule façon de déclarer qu'un projet n'a pas de typecheck. Vide et `none` disaient la même chose dans l'exemple de config ; ce sont deux états différents (personne n'a rempli / quelqu'un a décidé) et un seul autorise le run. Une branche `none` n'est pas déclenchée, donc pas comptée verte non plus.
  3. **Une branche qui ne rend aucun verdict compte rouge.** Testé en tuant le process de branche (`TEST_CMD='kill -KILL $PPID'`) : aucun code de retour n'est écrit. Un gate qui n'agrège que les branches ayant répondu appellerait ça vert.

  Ce qui reste hors de portée : `TEST_CMD="true"` — une commande qui réussit sans rien exécuter. Aucun code de retour ne la distingue d'une suite verte ; c'est la confirmation forcée de l'installeur [19] qui doit l'attraper.

- **Le parallélisme est testé par rendez-vous, pas au chronomètre.** Chaque branche ne sort verte que si elle voit l'autre déjà démarrée ; en séquence, la première attend un marqueur qui ne peut pas encore exister et échoue. Déterministe, aucune mesure de temps, et la mutation (retirer le `&`) rougit.

- **La classification interne/contractuelle ne vivait d'abord que dans une variable que rien n'observait.** Un test au seam process ne pouvait pas la voir, donc elle n'était pas couverte. La boucle la logge maintenant (`scope overflow on 01-alpha: internal|contract`) et les deux tests l'assertent. Ce que la classe déclenche — retry pour un fichier neutre, escalade sans retry pour un drift — appartient à [07], qui lit `RALPH_GATE_SCOPE_CLASS`.

- **Nouvel outcome de journal `gate-red`**, distinct de `failed` (session crashée) et `over-soft-limit`. Le gate expose aussi `RALPH_GATE_VERDICTS` (`tests=green typecheck=red scope=green`) et `RALPH_GATE_FAILED`, que le reçu d'audit [10] consommera.

- **Pas de timeout de branche.** Une `TEST_CMD` qui pend fait pendre le run — le filet smart-zone ne couvre que la session, pas le gate. À traiter avec les échecs typés [07].

- **Le classement du drift est en O(fichiers hors surface × tickets)**, chaque lecture de champ coûtant un `sed`. Uniquement sur le chemin rouge, donc acceptable ; à revoir si un backend distant fait de `tracker_ids` un appel réseau.

- **Coût sur la suite** : 84 → 109 tests, 52 s → 87 s sur la même machine (~0,62 → ~0,80 s par test). Le gate ajoute trois process et cinq appels git par itération, plus un test de rendez-vous qui poll. Suite verte sous microbats, sous bats-core et sous le bash 3.2 de macOS.

- **Bug attrapé juste après le merge : la référence du scope-guard ne pouvait pas être `HEAD`.** La question « y a-t-il un risque pour la suite ? » a suffi à le faire tomber. Rien ne commite le travail d'une itération verte : les fichiers de l'itération 1 sont donc encore dans l'arbre quand la session 2 démarre. Comparée à `HEAD`, l'itération 2 héritait du travail de la première **comme de son propre débordement**, et le recevait classé **drift contractuel** — le verdict le plus dur, celui que [07] escaladera sans retry. Tout run produisant des fichiers s'arrêtait donc après une seule itération utile. Même bug pour un run lancé sur un dépôt déjà sale : le premier gate était rouge.

  La référence est maintenant un **objet tree de l'arbre de travail** (`git add -A` dans un index jetable + `git write-tree`), pris avant le spawn et après la session, comparés par `git diff-tree -r`. Il dit ce qu'il y avait quand *cette* session a commencé — la vraie question — au lieu de ce que le dernier commit contenait. Bénéfices en prime : les non-suivis sont couverts par construction (plus besoin d'un `ls-files` séparé), un dépôt sans commit initial ne casse plus rien, et le travail en cours d'un humain n'est plus imputé au ticket. Une baseline manquante rend le gate **rouge** au lieu de le laisser passer en silence — sinon la cécité serait un faux vert permanent.

  Le snapshot `HEAD` du rollback reste un besoin distinct ([07]) : un tree n'est pas un commit. Et le constat sous-jacent devient une contrainte pour [07] : **un gate vert doit rendre le travail durable** (commit), sans quoi le `git reset --hard` d'un échec ultérieur détruira tout ce que le run a produit avant.

  Coût assumé : deux `git add -A` par itération (un walk `stat` de l'arbre, comme `git status`) et quelques objets *loose* non référencés dans le dépôt cible, que le `gc --auto` de git finit par élaguer.

- **21 mutations vérifiées rouges** (branches séquentielles, verdict manquant compté vert, baseline ramenée à HEAD sur les deux faces de l'accumulation, guard aveugle qui passe, snapshot post-session absent, diff-tree non récursif, snapshot limité aux fichiers suivis, agrégation partielle, chacune des trois portes du préflight, `none` non honoré, non-suivis ignorés, diff sans base, bookkeeping non filtré, pas de classification, surface non déclarée permissive, verdict du gate ignoré par le marquage, outcome non distingué, gate non appelé).

- **Modifié par [07].** Trois ajouts dans `gate.sh`, tous exigés par la politique d'échec : (1) `RALPH_GATE_TREE`, l'objet tree que le scope-guard a jugé, publié par la branche scope via un sidecar — le rollback et le commit-sur-vert agissent ainsi sur exactement ce que le gate a approuvé, et non sur un arbre que `TEST_CMD` a pu modifier depuis ; (2) `gate_is_bookkeeping`, la règle « `.scratch/<feature>/` n'est pas l'œuvre de la session » extraite de `gate__drop_bookkeeping` parce que le rollback la lit chemin par chemin — deux copies auraient divergé, et un rollback qui restaure le tracker remet `Failures:` à zéro à chaque tentative, donc n'escalade jamais ; (3) le **chien de garde** de branche (`GATE_TIMEOUT`), qui referme le trou « aucune branche du gate n'a de timeout » noté ci-dessus.
- **Une mutation de ce ticket est devenue vacuous et a été repointée.** « the scope-guard baseline is the last commit » (remplacer le snapshot d'arbre par `HEAD`) visait le test d'accumulation ; comme [07] commite chaque itération verte, `HEAD` est redevenu une baseline correcte pour ce scénario-là et le test reste vert sans la garantie. L'entrée pointe maintenant sur `already dirty when the run started`, qui rougit toujours (un arbre sale **avant** le run n'est couvert par aucun commit du run). Le test d'accumulation est conservé : il asserte toujours une propriété vraie, elle est simplement portée par trois mécanismes au lieu d'un.
- L'assertion de statut du test de drift contractuel est passée de `ready-for-agent` à `ready-for-human` : c'est [07] qui décide qu'un drift n'est pas retryable.
- **Faille trouvée en livrant [07], ouverte en [21] : le filtre de bookkeeping est l'un des trois mécanismes qui rendent une écriture de session dans le tracker invisible.** `gate__drop_bookkeeping` écarte `.scratch/<feature>/` du diff jugé — à raison, le claim et le journal vivent là — mais `gate_write_surface` lit la surface **sur le disque au moment du gate**, donc après la session. Une session qui réécrit sa propre ligne `**Write-surface:**` en `*` obtient un scope-guard vert sur n'importe quelle écriture ; reproduit, `exit 0` et ticket `resolved` avec un fichier hors surface dans l'arbre. Le correctif appartient à [21] (juger contre la surface du spawn) ; noté ici parce que c'est cette ligne de gate.sh qui devra changer.
