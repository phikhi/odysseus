# human-loop.sh — boucle HITL de traitement des ready-for-human

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (**post-complétion** — proposition du propriétaire). Une **2ᵉ boucle bash**, **non-AFK**, compagne de `loop.sh` : elle **draine le puits `ready-for-human`** que la ralph loop AFK remplit (escalades [08]/[05]/[11]/[12]/[19]/[24]…). L'humain adresse chaque ticket bloqué **avec l'aide d'un agent** (wayfinder, grilling, to-tickets, implement…).

## Question

Comment structurer une boucle HITL qui traite les tickets `ready-for-human` avec assistance IA, et la relie à la ralph loop AFK ?

À trancher :
- **Périmètre & frontière** : boucle séparée (`human-loop.sh`), frontière = tickets `ready-for-human` ; draine ce que l'AFK remplit ; réinjecte les résultats dans la frontière AFK.
- **Routage** : `ready-for-human` est **hétérogène** (décision / re-découpage / impl échouée / sign-off / gap de capacité…). Comment router chaque ticket vers le bon skill assistant (grilling/wayfinder / to-tickets / implement / approbation) ? → l'escalade doit-elle **porter sa raison** ?
- **Feedback & anti-faux-vert** : une résolution qui touche le code repasse-t-elle le gate [08] (réinjection `ready-for-agent`) ou la boucle humaine marque-t-elle `resolved` directement ?
- **Mécanique HITL** : interactif (≠ headless/sandbox de `loop.sh`) ; exclusion mutuelle avec l'AFK (verrou de run [04]) ; ordre de traitement (impact de déblocage ? NN ?).

## Answer

Décision verrouillée (grilling HITL). **Boucle compagne HITL** qui draine le puits `ready-for-human` que la ralph loop AFK remplit ; **routeur** vers le skill assistant ; réinjecte dans la frontière AFK.

**D1 — Périmètre & frontière.** `human-loop.sh` = 2ᵉ boucle bash, sœur de `loop.sh`, frontière = tickets `ready-for-human`. `loop.sh` **remplit** le puits (escalade), `human-loop.sh` le **draine** (1 itération = 1 ticket bloqué traité avec l'humain + un agent). **Cycle** : AFK broie → escalade → human-loop draine + **réinjecte** de nouveaux `ready-for-agent` → AFK reprend. Mêmes fichiers + ops d'adaptateur [16] (`frontier` filtré `ready-for-human`, `mark`, `open_ticket`).

**D2 — Routage (puits hétérogène).** L'escalade **tague sa raison** via une ligne **`Escalation:`** (jeu fermé) — contrainte back vers **tous les points d'escalade** ([05]/[06]/[08]/[11]/[12]/[19]/[24]). Table :
| `Escalation:` | Traitement HITL |
|---|---|
| `decision` / ambiguïté contractuelle | **grilling** (+ wayfinder si fog rouvert) |
| `too-big` (AC menacées) | **to-tickets** (re-découpage assisté) |
| `failed-impl` (gate rouge après retry-N) | **implement/pair**, amorcé par la branche `failed/<ticket>` + reçu [18] |
| `spec-gap` (playthrough [12]) | **grilling / to-spec** (compléter le flux) |
| `sign-off` (promotion [11] / capacité [24]) | **présentation → approuve/rejette** (pas de code) |
La boucle est un **routeur** au-dessus du puits, pas un traitement uniforme.

**D3 — Feedback & anti-faux-vert.** **Tout ce qui touche le code repasse le gate** : la boucle humaine **ne marque jamais `resolved` elle-même** → elle **réinjecte `ready-for-agent`**, l'AFK loop re-gate [08] (zéro bypass — l'anti-faux-vert vaut aussi pour l'humain). `too-big` → to-tickets produit N sous-tickets `ready-for-agent`. `failed-impl` → fix assisté puis réinjection. **Décision pure** → met à jour spec/AC [05] + gradue de nouveaux `ready-for-agent`. **`sign-off`** → pas de code : approuve → applique (règle [11] / capacité [24]) + ferme ; rejette → ferme avec note (**seul `resolved` direct**).

**D4 — Mécanique HITL.** HITL = **présence du jugement humain** dans la boucle (l'humain répond aux skills routés / donne les sign-offs), **PAS** l'approbation manuelle de chaque écriture. **Posture de permissions = le défaut de session de l'utilisateur (auto mode on)** — le framework **n'impose pas** de mode permission ; l'axe AFK-vs-human-loop est *« jugement humain présent ou non »*, pas *« permissions on/off »* (les deux tournent en auto-accept). **Exclusion mutuelle** avec l'AFK via le **verrou de run [04]** (on draine OU on broie, jamais les deux sur le même tracker → séquentiel, mécanique du cycle D1). **Ordre** : **impact de déblocage d'abord** (un `ready-for-human` qui bloque d'autres tickets → le drainer rouvre le plus de frontière AFK), à égalité **min NN**. **Rythmée par l'humain** (pas de successeur [17] ni de garde budget START [07]) ; affiche le **reçu [18]** du ticket comme contexte de départ.

### Contraintes créées ailleurs
- **Tous les points d'escalade** ([05]/[06]/[08]/[11]/[12]/[19]/[24]) : écrire une ligne **`Escalation:` <raison>** (jeu fermé) sur le ticket au moment d'escalader → sans quoi la boucle humaine ne peut pas router.
- **[04]** : le verrou de run couvre **les deux** boucles (exclusion mutuelle AFK / human-loop).
- **[06] / [09]** : `human-loop.sh` = 2ᵉ script du pack (interactif) ; **posture de permissions héritée de la session** (auto mode on par défaut, non imposée par le framework).
- **[08]** : les fixes issus de la boucle humaine **repassent le gate** via réinjection `ready-for-agent`.
- **[16] adaptateur** : `frontier` doit savoir filtrer `ready-for-human` ; réutilise `mark`/`open_ticket`.
