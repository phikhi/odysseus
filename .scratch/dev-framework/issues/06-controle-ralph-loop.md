# Control-flow de la ralph loop

Type: grilling
Status: resolved
Blocked by: 01, 02, 03, 04

## Question

Quel est le **flux de contrôle** du script bash de la ralph loop, bout en bout ?

À trancher (s'appuie sur les faits headless [01], limites [02], l'unité [03], le modèle d'état [04]) :
- Boucle de base : `choisir prochaine tâche → spawn session fraîche → exécuter → vérifier → marquer → répéter`. Forme exacte en bash.
- **Conditions d'arrêt** : plus de ticket débloqué, budget épuisé, N échecs consécutifs, kill humain. Lesquelles, dans quel ordre ?
- **Garde anti-emballement** : plafond d'itérations, détection de boucle stérile (rien de nouveau résolu), point de contrôle humain périodique.
- Que passe une itération au `claude` headless (prompt template, tickets, tools autorisés) et comment lit-elle la sortie (code retour, JSON) ?
- Gestion d'erreur d'une itération : retry immédiat, re-file, ou escalade (lié au gate QA [08]).

### Contraintes héritées du ticket 03 (Unité & <200K)

- **Auto-compaction = OFF** — la boucle doit garantir qu'aucune session ne compacte en silence (config à confirmer/forcer).
- **Filet runtime à 150K mou / 200K dur** — implémenter la détection : monitoring `stream-json` live (surveiller les tokens de contexte par tour, SIGTERM au franchissement) avec fallback `--max-turns` / `--max-budget-usd`. Rappel : la sortie JSON `--output-format json` n'arrive qu'à la fin → pour couper *pendant*, il faut `stream-json`.
- **Pré-vol statique** léger avant lancement (flag éléphant évident) + action **« proposer un split »** (rappeler `to-tickets`) quand une slice trébuche.

### Indice sous-agents / scout (issu du grilling du ticket 05)

Piste d'allègement de contexte à trancher ici : une session delivery **peut** offloader l'*exploration jetable* (read-heavy) à un sous-agent « scout » — sa fenêtre de contexte est séparée, il ne rend qu'un brief compact, donc les fichiers lus restent hors du contexte parent → sert la garantie 200K sans compacter. Garde-fous décidés en discussion :

- **Read-heavy oui, write-heavy non** : le scout sert à *comprendre* (localiser le seam, cartographier une API). Les sous-agents *écrivains* en parallèle sont à proscrire — conflits (worktrees coûteux) + l'écriture est précisément ce que le gate QA [08] doit juger, on ne la disperse pas.
- **Ne pas masquer une slice trop grosse** : le scout ne doit pas servir à faire rentrer une slice surdimensionnée dans une session — ça court-circuiterait le filet de re-découpe du ticket 03 (« propose-puis-valide »). Une slice qui ne rentre qu'avec offloading massif = signal de re-slice, pas d'offloading.
- **Mécanique pure → script, pas LLM** : un renommage / codemod / boilerplate déterministe se fait par `sed`/codemod (gratuit, déterministe), pas par un sous-agent LLM. Un fan-out mécanique massif se traite comme **un autre ticket** (expand-contract de `to-tickets`), pas comme un sous-agent interne.

## Answer

Décision verrouillée (grilling HITL). Assemble les faits headless [01], limites [02], l'unité/200K [03], le modèle d'état [04] et le contrat [05].

### Squelette de la boucle

```bash
acquérir verrou de run par feature                                  # [04]
iter=0 ; sterile=0
trap 'kill_flag=1' SIGINT SIGTERM                                   # D2 : kill gracieux
while true:
  [[ $kill_flag ]]                 && exit "arrêt humain"           # D2 (tête de boucle)
  [[ $iter -ge $CAP ]]            && exit "cap itérations atteint"  # D3
  [[ $sterile -ge $K ]]          && exit "run stérile (alerte)"    # D3
  tâche = min NN de la frontière [04]   # scan fichiers, gratuit
  si aucune :
     reste-t-il des ready-for-human ? → exit "bloqué-humain (N)" sinon exit "tout résolu"  # D2
  budget PROACTIF : utilization > ~90 % ? → sleep jusqu'à resets_at [07] ; continue   # D2
  pré-vol statique [03] : éléphant ? → proposer split [03], ready-for-human, continue
  out = ( cat "$tâche" | claude -p "$TEMPLATE"                      # [05] : ticket via stdin
            --output-format stream-json --model opus                # [01]/[03]
            --dangerously-skip-permissions                          # D1
            [--max-turns N] [--max-budget-usd X]                    # [03] fallback
            --append-system-prompt "$RÔLE" )
        └─ monitor live des tokens de contexte ; SIGTERM l'enfant au franchissement 150K  # [03]
  is_error / total_cost_usd / num_turns  ← dernière ligne `result` du NDJSON            # [01]
  exit non-zéro OU signal budget ? → budget RÉACTIF : re-check → sleep jusqu'à resets_at [07] ; continue  # D2
  gate QA [08] :
     pass → marquer resolved (temp+mv) [04] ; sterile=0
     fail → gestion d'échec [08] (Failures++ sur le ticket [04], retry N ou escalade ready-for-human) ; sterile++
  append run.log [04] ; iter++
```

**D1 — Posture de permission.** `--dangerously-skip-permissions` (bypass). En headless une session **ne peut rien demander** : une allowlist curée (`dontAsk`) est fragile (une commande imprévue de `/implement` la bloquerait → échec parasite). On donne l'autonomie totale à la session et on **déporte la sécurité vers l'environnement d'exécution (sandbox/conteneur, réseau restreint)** — c'est aussi le choix AFK retenu par [02]. Contrainte d'environnement → **[09]**.

**D2 — Conditions d'arrêt & précédence.** Ordre par tour : (1) **kill humain** — trap SIGINT/SIGTERM pose un drapeau lu en tête ; **gracieux** = on ne démarre pas de nouvelle itération, une session en vol est **laissée finir** pour que son travail soit gaté/marqué (pas de perte) ; (2) **scan frontière** (gratuit, fichiers locaux) *avant* tout appel API ; (3) **frontière vide → one-shot** : exit qui **distingue** « tout résolu » de « reste N `ready-for-human` — relancer après validation » (l'exit + `run.log` le disent) ; pas de daemon qui idle (brûlerait la fenêtre 5h et compliquerait [07] ; la re-validation humaine est async → mieux vaut relancer un run) ; (4) **budget proactif** (appel API, donc après le scan gratuit) → pause/reprise [07] ; (5) **post-exit non-zéro** → budget réactif [07] sinon échec réel → [08]. Rappel [03] : la re-slice d'une slice escaladée ré-entre la frontière → reprise au run suivant.

**D3 — Gardes anti-emballement.** La boucle **termine déjà naturellement** : chaque itération résout OU escalade le ticket → il quitte la frontière ([04]+[08]), donc la frontière décroît strictement (pas de boucle infinie par construction). Les gardes sont **défensives** : (a) **cap d'itérations** dur (backstop contre un bug de non-marquage qui re-piocherait en boucle) ; (b) **détecteur de run stérile** : K itérations d'affilée sans aucune résolution (échecs/escalades en série = run qui part mal) → stop + alerte, pour ne pas brûler du budget sur un contrat cassé ; (c) **checkpoint humain périodique optionnel, OFF par défaut** (l'AFK est le but ; activable pour un run risqué). Frontière [06]/[08] : [08] gère le retry *par-ticket* ; D3 gère les gardes au niveau *run*.

**CLI & lecture de sortie.** `claude -p` **nu** (jamais `--continue`/`--resume`) = contexte frais garanti [01]. `--output-format stream-json` (NDJSON) — nécessaire pour le monitoring live des tokens (couper à 150K [03], car le JSON complet n'arrive qu'à la fin). Succès/échec = champ **`is_error`** (pas le seul `$?`, dont aucun code n'est dédié au quota [02]) ; coût = `total_cost_usd`, tours = `num_turns` (message `result`, dernière ligne). **Pas de `--bare`** : il couperait l'auto-découverte des **skills**, or la session a besoin du substrat (`/implement` → `/tdd` + `/code-review`) → la boucle s'appuie sur le `.claude/` committé du projet cible (provisionné par [09]). Prompt = ticket via **stdin** (`cat "$tâche" | claude -p …`) + pointeurs [05] + instruction `/implement` ; `--append-system-prompt` pour le rôle (agent de delivery autonome, implémente ce seul ticket).

**Champs du `run.log`** (fixe le fog Observabilité côté données) : par itération — tâche, `is_error`, `total_cost_usd`, `num_turns`, timestamp ; par run — compteur d'itérations, compteur stérile, statut de sortie. Le *surfacing* (tail/dashboard) descend à [09].

### Contraintes créées ailleurs

- **[07] Budget** : implémenter les deux hooks décidés ici (proactif >90 % avant spawn ; réactif post-exit non-zéro) via `GET /api/oauth/usage` (User-Agent `claude-code/<v>` obligatoire, cache ~180 s, backoff) → `sleep` jusqu'à `resets_at` (+marge) ; **distinguer** le 429 transitoire (capacité API, géré par le SDK) de l'épuisement de plan (session/hebdo) ; ne jamais calculer le reset hebdo par « +7 j » (lire `resets_at`).
- **[08] Gate QA** : le gate est **invoqué par la boucle après la session, avant le marquage** [04] ; définir les critères de *resolved* (tests/typecheck/`code-review`, **e2e si surface visible** [05]), same-session vs verify séparé, le retry par-ticket N et la mécanique d'escalade `ready-for-human` (`Failures++` sur le ticket [04]). Le détecteur stérile [06] lit le compteur de résolutions produit par le gate.
- **[09] Form-factor** : garantir l'**exécution sandboxée** (D1) ; **provisionner le substrat de skills** dans le `.claude/` cible (conséquence du « pas de `--bare` ») ; exposer la config des chemins injectés [05] ; **surfacer le `run.log`**.
