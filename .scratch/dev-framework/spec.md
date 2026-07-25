# Spec — Pack de delivery autonome AFK (odysseus)

Status: ready-for-agent

> Synthèse du blueprint gelé [`blueprint.md`](blueprint.md) (décisions [03]→[26], sources [01]/[02]/[22]) au format spec, prête pour `/to-tickets`. Le vocabulaire est celui de [`CONTEXT.md`](../../CONTEXT.md) ; aucun chemin de fichier ni snippet de code n'est normatif ici (sauf l'exception « décision-encodée » signalée). Chaque décision renvoie au ticket de discovery qui en détient le pourquoi.

## Problem Statement

Un développeur qui possède une phase de discovery déjà solide (cadrage, spec, tickets validés) veut faire **broyer la delivery sans être présent** (AFK). Aujourd'hui, une session Claude Code interactive :

- se **compacte** dès que le contexte grossit et tombe en **dumb zone**, où la qualité de raisonnement chute et où les tâches longues dérapent ;
- **crame le budget d'usage** (fenêtre de session 5 h + limite hebdomadaire) sans s'en rendre compte, puis s'arrête net au milieu d'un run ;
- ne peut pas tourner **sans humain** en confiance : rien ne garantit qu'une tâche « verte » soit réellement livrée jusqu'à l'utilisateur, ni qu'une décision engageant le contrat ne soit prise en douce ;
- n'est **pas réutilisable** d'un projet à l'autre : chaque équipe réinvente la boucle, l'observabilité et les garde-fous.

Le développeur n'a pas de moyen fiable de dire « voici mes tickets prêts, broie-les toute la nuit, réveille-moi seulement pour ce qui relève de mon jugement ».

## Solution

Un **pack déposable dans n'importe quel projet** (vierge ou existant), **100 % bash + markdown** (fallback sans node), qui ajoute par-dessus le **substrat** de skills d'ingénierie déjà installés une **delivery autonome AFK**. Du point de vue du développeur :

1. Il dépose le pack par une **commande unique** (`init.sh` via wizard `npx`), règle **un seul fichier de config** (`ralph.config.sh`), et son dépôt passe de « rien » à « prêt à discovery ».
2. Il fait sa **discovery en HITL** avec le substrat (`grilling`, `domain-modeling`, `to-spec`, `to-tickets`) : elle produit le **contrat** — une spec validée + des tickets `ready-for-agent` auto-suffisants.
3. Il lance la **ralph loop** (`loop.sh`) : elle broie la **frontière** en **itérations** à **session fraîche** — jamais compactée, garantie « smart zone » <200K — sous **contrainte de budget d'usage**, avec **gate QA** par itération, **auto-apprentissage**, **reçus d'audit** et un **gate de valeur au niveau feature** avant l'exit succès.
4. Tout ce qui remonte au **jugement humain** (décision contractuelle, échec persistant, trou de spec, sign-off) est **escaladé** dans un puits `ready-for-human` que le développeur draine plus tard via la **boucle humaine** (`human-loop.sh`), laquelle **réinjecte** le résultat en `ready-for-agent`.

Les **deux boucles partagent le tracker** (seule autorité d'état) et sont **mutuellement exclusives** via le **verrou de run**. Le cycle **escalade → drain → réinjection** est le moteur de progression : la delivery est AFK, la discovery et la reprise de jugement restent HITL.

## User Stories

### Dépôt, form-factor & config

1. En tant que développeur, je veux déposer le pack par **une commande unique** dans un repo vierge **ou** existant, afin de passer de « rien » à « prêt à discovery » sans monter l'échafaudage à la main. [09]
2. En tant que développeur, je veux que l'installeur **auto-détecte** l'environnement et **valide** les préconditions (projet git, commandes de test/typecheck, endpoint d'usage), afin de savoir tout de suite si mon projet est broyable. [09]
3. En tant que développeur possédant déjà un `CLAUDE.md`, je veux qu'il soit **mergé et jamais écrasé**, afin de conserver mes règles projet. [09]
4. En tant que développeur, je veux **un seul fichier** (`ralph.config.sh`) à régler par projet, afin de ne pas avoir à comprendre l'intérieur du pack pour l'utiliser. [09]/[17]
5. En tant que développeur, je veux que le substrat soit **copié (vendoré, pinné à une version)** dans le pack plutôt que lié, afin que la sandbox de delivery soit autonome et reproductible. [09]
6. En tant que développeur, je veux que le pack **provisionne** les dossiers durables (`docs/adr`, `docs/playthroughs`, `receipts`, racine `.scratch/`) et une **posture headless** dans `settings.json`, afin que les artefacts aient une place dès le premier run. [09]/[19]
7. En tant que développeur sur une machine sans node, je veux que le **moteur reste bash pur**, afin que le pack fonctionne en fallback. [09]

### Contrat discovery → delivery

8. En tant que développeur, je veux **une seule porte d'approbation** (à `to-tickets`), afin de ne valider qu'une fois avant de lâcher l'AFK. [05]
9. En tant que développeur, je veux que le contrat exige des **AC machine-vérifiables**, un **flux utilisateur bout-en-bout explicite** dans la spec, une **write-surface déclarée** par ticket et un **blocage** explicite, afin que chaque ticket soit broyable sans moi. [05]/[12]/[15]
10. En tant que développeur, je veux la distinction **interne vs contractuel** appliquée partout (interne → autonome ; contractuel → escalade), afin que l'agent sache seul quand il a le droit de décider. [05]
11. En tant que développeur, je veux qu'un **e2e soit exigé dès qu'il y a une surface**, et une **garde de non-occlusion** dès qu'un élément est superposé, afin que « vert » veuille dire « vraiment livré ». [05]/[13]

### La ralph loop (AFK)

12. En tant que développeur, je veux que la boucle **choisisse seule la prochaine tâche** par un **scan sans mémoire** de la frontière (`open ∧ unblocked ∧ ready-for-agent ∧ non-claimed`, min NN), afin qu'aucun état ne soit hérité entre itérations. [04]/[06]
13. En tant que développeur, je veux que chaque itération **spawn une session fraîche** (`claude -p`, stream-json, permissions bypass en sandbox), afin de rester en smart zone. [01]/[06]
14. En tant que développeur, je veux que la session reçoive dans son prompt **le ticket + des pointeurs** (CONTEXT, ADRs, index LEARNINGS, consignes de langue), afin qu'elle reconstruise tout le contexte utile depuis le tracker seul. [06]/[11]/[26]
15. En tant que développeur, je veux des **gardes anti-emballement** (kill gracieux, cap d'itérations, détecteur de run stérile), afin qu'un run pathologique s'arrête au lieu de tourner à vide. [06]
16. En tant que développeur, je veux qu'à **frontière vide** la boucle exécute un **gate terminal de valeur** avant de conclure « tout résolu », afin de ne pas déclarer succès sur une feature non reliée à l'utilisateur. [06]/[12]

### Unité de tâche & garantie smart-zone

17. En tant que développeur, je veux que chaque **tâche** soit une **slice verticale « tracer-bullet »** dimensionnée pour finir **sous 200K**, afin que la session ne se compacte jamais. [03]
18. En tant que développeur, je veux un **filet runtime dur** (`auto-compact OFF`, SIGTERM au seuil mou 150K, dur 200K = frontière dumb-zone), afin que la garantie smart-zone ne repose pas que sur le découpage. [03]
19. En tant que développeur, je veux qu'une slice trop grosse soit **re-découpée de façon autonome en préservant les AC** puis ré-injectée, la soupape humaine n'intervenant que si les AC ne peuvent être préservées. [03]/[08]

### Budget d'usage & auto-chaînage

20. En tant que développeur, je veux que la boucle **surveille mon budget** (`five_hour`, `seven_day`, `seven_day_opus` via `GET /api/oauth/usage`) avec des **seuils asymétriques** (5 h agressif, hebdo conservateur), afin de ne jamais cramer mon quota par surprise. [07]
21. En tant que développeur, je veux un **gate de spawn proactif** (on vérifie le budget **avant** de lancer une session), afin de ne pas démarrer une itération qu'on ne pourra pas finir. [06]/[07]
22. En tant que développeur, je veux qu'un dépassement de la **fenêtre de session** déclenche un **`sleep` in-process jusqu'au reset**, afin que le run reprenne tout seul. [07]
23. En tant que développeur, je veux qu'un mur **hebdomadaire** programme un **successeur one-shot** au reset de la fenêtre bloquante (**jamais +7 j**), avec **repli humain** si aucun scheduler, afin de préserver l'AFK sans faire dormir un process des jours. [07]/[17]
24. En tant que développeur, je veux un **classifieur de budget** (un exit non-zéro est testé « budget ? » **avant** « échec »), afin qu'une pause budget ne soit jamais comptée comme un échec de ticket. [07]
25. En tant que développeur, je veux une **chaîne de scheduler auto-détectée, ordonnée par survie au reboot** (`at` avant `systemd-run` transient ; par plateforme Linux/macOS), afin que le successeur survive à un redémarrage. [17]/[22]
26. En tant que développeur, je veux une **protection anti-double-run** (successeur singleton + verrou de run), afin que deux runs ne se chevauchent jamais sur un tracker. [07]/[04]

### Gate QA, lentilles & échecs

27. En tant que développeur, je veux un **gate en checks parallèles** où **l'autorité déterministe prime sur le LLM**, afin qu'aucune complaisance de modèle ne fasse passer un ticket. [08]
28. En tant que développeur, je veux des **checks objectifs portés par la boucle bash** — **tests**, **typecheck**, **scope-guard** (diff vs write-surface), **gate de langue** — afin que « vert » soit vérifié hors du modèle. [08]/[19]/[26]
29. En tant que développeur, je veux un **registre de lentilles de revue** : **Standards** et **Spec** toujours actives, **Fidélité**, **Sécurité**, **Accessibilité** **gatées par prédicat** (surface visible, tag `security` ou write-surface ∩ `SECURITY_PATHS`), afin de ne payer une revue que quand le risque l'exige. [08]/[23]/[14]
30. En tant que développeur, je veux que ***resolved*** signifie **toutes les branches déclenchées vertes**, afin qu'il n'y ait pas de définition floue du « fini ». [08]
31. En tant que développeur, je veux des **échecs typés** : budget → pause ; too-big → re-slice autonome ; **gate rouge / crash non-budget** → **retry-N fresh** puis `ready-for-human` (compteur `Failures:`) ; contractuel → escalade directe. [08]
32. En tant que développeur, je veux un **rollback propre** (snapshot `HEAD` pré-spawn → `git reset --hard` + `clean`, branche `failed/<ticket>` avant l'escalade finale), afin qu'un échec ne laisse pas le dépôt sale. [08]
33. En tant que développeur, je veux que **toute escalade pose une raison `Escalation:`** (jeu fermé), afin que la boucle humaine sache router le ticket. [08]/[25]

### Gate de valeur au niveau feature

34. En tant que développeur, je veux qu'un **subagent frais rejoue le flux du `spec.md` sur les vrais assets** à frontière vide et produise un **playthrough persisté** (condition matérielle de clôture), afin d'attraper les **trous de câblage** que les tests unitaires ratent. [12]
35. En tant que développeur, je veux qu'un playthrough rouge soit traité en **hybride** (trou interne → ticket de câblage autonome ré-injecté ; contractuel → `ready-for-human`), **borné** par `PLAYTHROUGH_REINJECT_MAX`, afin de ne pas boucler indéfiniment. [12]
36. En tant que développeur, je veux une **échelle de défense** (e2e ticket-level + non-occlusion + fidélité + playthrough feature + canari full-loop maintenu dans le gate), afin que la valeur soit vérifiée à plusieurs altitudes. [12]/[05]/[13]/[14]

### Concurrence par-ticket

37. En tant que développeur, je veux un **worktree git par itération** (rollback localisé), afin que des itérations parallèles ne se marchent pas dessus. [15]
38. En tant que développeur, je veux un **séquencement par write-surfaces disjointes** (chevauchement → séquence ; fail-safe si inconnue), **unifié avec le scope-guard**, afin que le parallélisme soit sûr par construction. [15]/[19]
39. En tant que développeur, je veux un **claim atomique** (temp+`mv`, owner+horodatage) qui retire le ticket de la frontière pour les pickers concurrents. [15]
40. En tant que développeur, je veux une **liveness du claim par pid + TTL backstop + fail-open strict** (bash pur, sans heartbeat), afin qu'un claim mort soit toujours réclamé sans risque de deadlock. [21]
41. En tant que développeur, je veux un **cap `MAX_PARALLEL`** throttlé par le **budget agrégé**, et une **intégration sérialisée** (build parallèle, repli un-à-un), afin que la parallélisation reste bornée et déterministe à l'intégration. [15]/[07]

### Auto-apprentissage & ADR en delivery

42. En tant que développeur, je veux un **subagent retro frais post-gate** (tier bon marché, **auto-suppressif**) qui n'écrit **que** s'il y a une leçon, afin d'accumuler de la connaissance sans bruit. [11]
43. En tant que développeur, je veux qu'il puisse produire un **record de leçon** (index `LEARNINGS.md` injecté inline), **et/ou** un **ADR** pour une décision d'archi **interne** (le contractuel escalade), **et/ou** flagger un **gap de capacité**. [11]/[20]/[24]
44. En tant que développeur, je veux un **anti-bruit** sur l'index (dedup / supersession / **drain-par-promotion**) gardant un **working set** borné, afin que l'index reste injectable dans chaque session fraîche. [11]
45. En tant que développeur, je veux qu'une leçon récurrente soit **promue** — **autonome** (guidance `CLAUDE.md`) ou **escaladée** (gate/lint/hook = contractuel → `ready-for-human`), **jamais en silence**. [11]

### Revue de capacités au fil de l'eau

46. En tant que développeur, je veux que **détecter une capacité manquante ≠ la créer** : une capacité change le contrat, donc **toujours HITL** (proposée en discovery ou par le retro → `ready-for-human`, jamais auto-créée). [24]
47. En tant que développeur, je veux une **barre claire** (récurrence **ou** classe non couverte) et une préférence **réutiliser-avant-créer**, afin de ne pas faire proliférer les capacités. [24]

### Langues

48. En tant que développeur, je veux découpler **`LANG_INTERACT`** (parole à l'humain, HITL only) de **`LANG_ARTIFACT`** (prose durable : docs, tracker, commentaires, commits, PR — **pas** le code, **pas** le pack), afin de parler ma langue tout en gardant des artefacts cohérents. [26]
49. En tant que développeur, je veux que la consigne de langue soit **doublée d'un gate de langue objectif** (détection post-hoc, par-fichier, tolérant), afin qu'une consigne molle ne soit pas la seule garantie. [26]/[08]
50. En tant que développeur éditant un fichier existant, je veux que l'agent **matche la langue du fichier**, afin de ne pas panacher les langues dans un même document. [26]

### Backend de tracker

51. En tant que développeur, je veux une **interface d'adaptateur de tracker** stable (`frontier` / `read_ticket` / `claim` / `mark_*` / `open_ticket` / `append_note` / `emit_receipt`) avec **3 implémentations** (`local` par défaut, `github`, `gitlab`), afin de brancher mon outil sans toucher à la boucle. [16]
52. En tant que développeur en distant, je veux que **claim = assignee**, **reçu = la PR**, **liveness du claim en sidecar local**, et **`wait_ci` ON par défaut si CI détecté** (opt-out `WAIT_CI=off`), afin que le backend façonne la forme d'intégration. [16]

### Observabilité & audit

53. En tant que développeur, je veux **quatre couches distinctes** : **journal de run** (machine, non-autoritaire), **reçu d'audit** (humain, par itération), **playthrough** (par feature) et **LEARNINGS** (leçons distillées), afin de ne pas confondre observabilité brute et connaissance apprise. [04]/[18]/[12]/[11]
54. En tant que propriétaire relecteur, je veux un **reçu d'audit par itération** (résumé + 4 verdicts de gate + preuves + méta + **diff par référence**) comme **surface de relecture asynchrone** (fichier `receipts/` en local, la PR en distant), afin de relire sans flux PR obligatoire. [18]

### La boucle humaine

55. En tant que développeur, je veux une **boucle humaine interactive** qui **draine `ready-for-human`** et **route par `Escalation:`** (`decision`→grilling, `too-big`→to-tickets, `failed-impl`→implement/pair amorcé, `spec-gap`→to-spec, `sign-off`→approbation). [25]
56. En tant que développeur, je veux un **anti-faux-vert** : tout code repasse le gate via **réinjection `ready-for-agent`** (jamais de `resolved` direct sauf `sign-off`), afin qu'un correctif humain soit re-vérifié. [25]
57. En tant que développeur, je veux que les deux boucles soient **mutuellement exclusives** via le **verrou de run** (on broie **ou** on draine), afin qu'elles ne touchent jamais le tracker en même temps. [04]/[25]

## Implementation Decisions

### Architecture d'ensemble

- **Deux boucles sur un tracker partagé.** `loop.sh` (AFK) broie `ready-for-agent` ; `human-loop.sh` (HITL) draine `ready-for-human` et réinjecte en `ready-for-agent`. Le **tracker est la seule autorité d'état** ; une session fraîche reconstruit tout en le relisant seul. Le cycle **escalade → drain → réinjection** est le moteur de progression. [04]/[25]
- **Verrou de run grossier**, un par feature, couvrant AFK **et** human-loop : 1 run à la fois par tracker. [04]
- **Périmètre des phases** : discovery = HITL ; delivery = AFK. Multi-provider hors périmètre. [05]

### Modules du pack (bash + markdown)

- **`loop.sh`** — control-flow de la ralph loop [06] : verrou de run → gardes (kill / cap itérations / détecteur stérile) → scan frontière (N tickets à write-surfaces disjointes) → gate de budget proactif → spawn session fraîche → monitor SIGTERM 150K → gate QA → marquage → reçu → retro → append `run.log` ; frontière vide → playthrough terminal avant exit succès.
- **`human-loop.sh`** — routeur HITL du puits `ready-for-human` [25].
- **`lib/*`** — helpers sourcés, à responsabilité unique : sélection de frontière [04], budget [07], gate [08], état/marquage/verrou [04], claim + liveness [15]/[21], adaptateurs `tracker-{local,github,gitlab}.sh` [16].
- **Substrat copié (pinné)** — `grilling`, `domain-modeling`, `research`, `to-spec`, `to-tickets`, `implement`, `tdd`, `code-review`, `triage`, `wayfinder` (+ `teach` pour le format de leçon). Réutilisé, jamais réinventé. [09]
- **`docs/agents/`** (conventions tracker/triage), `.scratch/` (racine tracker), `docs/adr` / `docs/playthroughs` / `receipts` provisionnés, `settings.json` (posture headless + hook scope-guard optionnel), `CLAUDE.md` de base mergé, **`ralph.config.sh`** (seul fichier réglé). [09]/[19]
- **Installeur** : wizard `npx` (auto-détecte, valide) → moteur bash ; `init.sh` idempotent bootstrap une-commande, auto-suppressif. [09]

### Interface d'adaptateur de tracker

Interface fixe appelée par la boucle sans connaître le backend : `frontier`, `read_ticket`, `claim`, `mark_*`, `open_ticket`, `append_note`, `emit_receipt`. Trois impls `lib/tracker-<backend>.sh` (`local` par défaut = fichiers markdown ; `github` ; `gitlab`). Les ops durables sont remote-ables ; la **liveness du claim reste toujours locale** (sidecar). Pas de mode « offline » (le LLM exige le réseau ; AFK ≠ offline). [16]

### Modèle d'état sur le tracker

- **Frontière** = `open ∧ unblocked ∧ ready-for-agent ∧ non-claimed`, sélection = **scan sans mémoire**, **min NN**. [04]
- Champs portés par un ticket : `Status:`, `Blocked by:`, triage, **write-surface**, `Failures:`, `claimed` (owner+horodatage), `Escalation:` (jeu fermé). [04]/[15]/[25]
- **Marquage** = par la boucle, **après le gate** (jamais la session), écriture **atomique temp+`mv`**. [04]

### Control-flow AFK (décision encodée par le prototype)

> Extrait du prototype jetable `prototype-form-factor/.claude/loop.sh` — encode l'**ordre** des étapes (budget avant spawn, classifieur budget avant « échec », re-slice avant retry, rollback systématique) plus précisément que la prose. Squelette, pas du code de prod.

```bash
while :; do
  # gardes: kill gracieux / cap itérations / run stérile          [06]
  ticket="$(frontier_min_nn "$FEATURE")"                         # [04] scan sans mémoire, min NN
  [ -z "$ticket" ] && { playthrough terminal puis exit succès/bloqué-humain; }  # [12]/[06]
  budget_check ... || { budget_pause ...; continue; }            # [07] gate de spawn proactif
  PRE="$(git rev-parse HEAD)"                                    # [08] snapshot rollback
  out="$(cat ticket | claude -p ... --output-format stream-json \
         --dangerously-skip-permissions | tee monitor_150k)"    # [06]/[03] SIGTERM au seuil mou
  is_success || { budget? -> pause ; too_big? -> reslice ; sinon retry-N puis escalate ; rollback ; continue }  # [07]/[08]
  run_gate tests+typecheck+review // -> resolved | (bump Failures, retry-N, escalate, rollback)  # [08]
  append_runlog ; retro ; (( iter++ ))                           # [04]/[11]
done
```

### Surface de configuration — `ralph.config.sh`

Le **seul** fichier réglé par projet. Clés (voir blueprint §17 pour le tableau complet) : `FEATURE`/`MODEL` ; `TEST_CMD`/`TYPECHECK_CMD` (**confirmation forcée**, anti-faux-vert) ; `SOFT_LIMIT_TOKENS` (150K) ; `THRESH_5H`/`THRESH_WEEK`/`USAGE_UA` ; `ITER_CAP`/`STERILE_K`/`RETRY_N`/`HUMAN_CHECKPOINT_EVERY` ; `SCHEDULER`/`WEEKLY_RESUME` ; `MAX_PARALLEL` (fallback `=1` si test partagé) ; `CLAIM_TTL` ; `TRACKER_BACKEND`/`WAIT_CI` ; `VISUAL_CMD`/`RUN_CMD` ; `SECURITY_PATHS`/`SECURITY_REFS`/`FIDELITY_REFS` ; `LANG_INTERACT`/`LANG_ARTIFACT`/`LANG_CHECK` ; caps anti-bruit (`PLAYTHROUGH_REINJECT_MAX`, cap index LEARNINGS, rétention reçus). [09]/[17]

### Budget & scheduler

- Endpoint `GET /api/oauth/usage` (`User-Agent` obligatoire, cache 180 s), seuils asymétriques, classifieur budget. Fenêtre de session → `sleep` jusqu'au reset ; hebdo → successeur one-shot au reset (jamais +7 j) + repli humain. [07]/[17]
- Chaîne de scheduler auto-détectée, **ordonnée par survie au reboot** (`at` avant `systemd-run` transient ; par plateforme). Le skill `schedule` (cloud) est **hors** de la chaîne locale. [17]/[22]

### Gate QA & lentilles

- Fan de checks **parallèles**, **autorité déterministe > LLM**. Objectifs (par la boucle bash) : tests + typecheck + scope-guard + gate de langue. **Registre de lentilles** : Standards | Spec toujours ; Fidélité, Sécurité, Accessibilité **gatées par prédicat** ; extensible. *resolved* = toutes les branches déclenchées vertes. [08]/[19]/[23]/[14]/[26]

## Testing Decisions

- **Ce qu'est un bon test ici** : on teste le **comportement externe observable** du pack — les **transitions d'état du tracker** (Status `claimed`/`resolved`, `Escalation:`, `Failures:`, blocage) et les **artefacts produits** (reçus, `run.log`, playthrough, records de leçon, branches `failed/<ticket>`) — **jamais** l'intérieur d'une fonction bash. Un test ne doit pas connaître le nom d'une variable ou l'ordre interne d'un `lib/*.sh` ; il connaît l'entrée (tickets + config + stubs) et la sortie (état du tracker + fichiers).

- **Seam unique, le plus haut possible (validé avec le développeur)** : la **frontière process**. On pilote les **vrais** `loop.sh` / `human-loop.sh` comme des process, dans un environnement entièrement injecté, puis on assert sur l'état markdown du tracker. Un seul seam, e2e, qui **attrape le câblage** entre modules. Point de contrôle = injection ; point d'observation = le tracker (seule autorité d'état).

  - **Tracker** : adaptateur `local` dans un **répertoire temporaire** jetable, peuplé de tickets fixtures. [16]/[04]
  - **LLM** : **fake `claude` sur le `PATH`**, scripté pour émettre une sortie stream-json prédéterminée et écrire des diffs prédéterminés (succès, échec de gate, crash, dépassement 150K, décision contractuelle). [01]/[06]
  - **Budget** : endpoint `/api/oauth/usage` injectable (fake curl / URL), scénarisé pour fenêtre-de-session pleine, mur hebdo, retour sous seuil. [07]
  - **Gate objectif** : `TEST_CMD` / `TYPECHECK_CMD` stubbés (exit 0/non-0 au choix) ; scheduler stubbé (fake `at`). [08]/[17]

- **Modules testés via ce seam** (par le comportement, pas la fonction) : la ralph loop [06], le modèle d'état/marquage [04], le budget + auto-chaînage [07]/[17], le gate QA + échecs typés + rollback [08], la concurrence + claim + liveness [15]/[21], le gate de valeur feature [12], l'auto-apprentissage [11], la boucle humaine + routage [25], le gate de langue [26], l'adaptateur `local` [16].

- **Exception unit — logique pure seulement** : quelques helpers `lib/*.sh` sans effet de bord et à combinatoire riche méritent un test de fonction isolé (source + appel), parce que les couvrir end-to-end serait fragile et incomplet : le **classifieur de budget** (« budget ? » vs « échec »), la **liveness du claim** (pid vivant / TTL / fail-open), le **gate de langue** (détection par-fichier tolérante), et le **calcul de disjonction des write-surfaces** (globs → parallélisable ou séquencé). Ces tests restent l'exception, pas la règle.

- **Canari full-loop e2e** : un scénario e2e « bout-en-bout » (frontière → itérations → gate → frontière vide → playthrough → exit succès) est **maintenu en permanence dans le gate** comme canari de régression du pack lui-même. [12]/[08]

- **Prior art** : convention de test de scripts bash pilotés par l'environnement (style **bats** : `PATH` shim des binaires externes, fixtures en `tmpdir`, assertions sur fichiers/exit codes). Le pack étant 100 % bash, ce patron est le prior art naturel ; aucune dépendance node n'est requise pour tester (cohérent avec le fallback bash). [09]

## Out of Scope

- **Déploiement** de l'application cible (effort distinct). [blueprint §18]
- **Réconciliation de la stratégie quota** (§5.3 de l'analyse) — traitée par les seuils actuels, non ré-architecturée ici. [blueprint §18]
- **Multi-provider** (codex / gemini / cursor / opencode / junie…) — version ultérieure ; le pack cible Claude Code (headless, hooks, endpoint d'usage). [blueprint §18]/[09]
- **Concurrence multi-machine** : la liveness du claim est mono-machine (sidecar local) ; pas d'orchestration distribuée. [16]/[21]
- **Mode offline** : le LLM exige le réseau ; AFK ≠ offline. [16]
- **Création automatique de capacités** : détecter est dans le périmètre, créer une lentille/agent/skill est **toujours HITL**. [24]
- **Discovery elle-même** : le pack la rend possible (dépôt du substrat + conventions) mais ne l'automatise pas — elle reste HITL. [05]

## Further Notes

- **Handoff** : cette spec est la synthèse du blueprint **gelé** ([`blueprint.md`](blueprint.md)) et est prête pour `/to-tickets`. Le blueprint fixe le **quoi** (décisions verrouillées + surface de config) sans produire de code ; `to-tickets` produira les tickets `ready-for-agent` avec AC machine-vérifiables, write-surfaces déclarées et blocages.
- **Matière première** : le prototype jetable [`prototype-form-factor/`](prototype-form-factor/) incarne la forme cible (arborescence + `init.sh` + `ralph.config.sh` + `loop.sh`) — à consommer comme référence de forme, **pas** comme code de prod.
- **Vocabulaire** : toute la terminologie suit [`CONTEXT.md`](../../CONTEXT.md) (ralph loop, itération, run, session fraîche, smart/dumb zone, frontière, contrat, gate QA, playthrough, write-surface, scope-guard, claim, reçu d'audit, adaptateur de tracker, successeur one-shot, lentille de revue, boucle humaine, raison d'escalade, langues). Aucun synonyme proscrit ne doit dériver dans les tickets.
- **ADRs** : aucun ADR existant sous `docs/adr/` au moment de la spec ; aucune décision ici ne contredit d'ADR. Les ADR de delivery seront gravés au fil de l'eau par le subagent retro. [20]
- **Langues** : cette spec est un **artefact durable** rédigé en français (`LANG_ARTIFACT`), cohérent avec la consigne projet et le gate de langue. [26]
