# Unité de tâche & garantie <200K

Type: grilling
Status: resolved
Blocked by: —

## Question

Qu'est-ce qu'**une tâche** — l'unité qu'une session fraîche broie en une itération de boucle — et comment garantir qu'elle finit **sous 200K** de contexte ?

À trancher :
- Une tâche = un ticket `to-tickets` (slice verticale tracer-bullet) tel quel, ou une maille plus fine ?
- Quel **budget de contexte** cible par tâche (marge sous 200K : entrée du ticket + fichiers lus + travail + tests) ?
- Comment **estimer/vérifier** en amont qu'un ticket rentre : heuristique à la découpe (`to-tickets`), garde-fou runtime (avorter si le contexte approche le seuil), ou les deux ?
- Que fait-on d'un ticket **trop gros** : re-découpe automatique, retour humain, refus de la boucle ?
- Le contexte injecté au démarrage (ticket + `CONTEXT.md` + fichiers ciblés) compte dans le budget — comment le garder minimal et pertinent ?

## Answer

Décision verrouillée (grilling HITL).

**Unité = maille variable.** Défaut : 1 slice verticale `to-tickets` = 1 tâche = 1 session fraîche. La maille se re-découpe seulement si la slice ne rentre pas.

**Stratégie de taille = C (hybride)**, penchant réactif. La prédiction *précise* de taille est peu fiable (dépend du nb de fichiers lus et de tours de raisonnement, inconnus avant lancement) → le filet *mesuré* au runtime est la vraie garantie ; le pré-vol statique ne sert qu'à écarter les monstres évidents.

**Budget :**
- Plafond **dur = 200K** (frontière dumb-zone).
- Budget **mou = 150K (75%)** par tâche : le filet avorte au franchissement.
- **Auto-compaction = OFF** (sinon dégradation silencieuse = dumb-zone invisible).
- « Garantir » = **filet dur best-effort** : garantit qu'on ne *code jamais* en dumb-zone (avorte avant), PAS que chaque slice rentre du premier coup.

**Pré-vol statique** = heuristique cheap avant lancement (ex. taille-tokens des fichiers ciblés par le ticket + nb de critères d'acceptation) pour flagger un éléphant évident ; si le ticket ne déclare pas de cibles → sauter le pré-vol, s'en remettre au filet. Seuil/mécanique exacte → pinné dans Control-flow [06].

**Slice qui trébuche** (avortée à 150K OU flaggée au pré-vol) = **re-découpage autonome**. ⚠️ *Révisé par [08] (2026-07-24)* : la version initiale était « propose-puis-valide » (l'humain validait, `ready-for-human`). Décision courante : la boucle **re-découpe elle-même** (via `to-tickets`) **en préservant les critères d'acceptation** (même comportement, granularité plus fine), **ré-injecte les sous-slices en frontière** sans humain, et **saute à la branche suivante** ; le tout **loggé** (`run.log` + note sur le parent). C'est une décision *interne* au sens du contrat [05] (aucun impact sur les AC). **Soupape humaine unique** : si le split ne peut pas préserver les AC (cas *contractuel*), alors seulement `ready-for-human` avec proposition attachée. Garde l'AFK sur le cas courant tout en bloquant une dérive de scope silencieuse.

**Contraintes créées ailleurs :**
- Control-flow [06] : auto-compact OFF + filet 150K (monitoring `stream-json` live, fallback `--max-turns`/`--max-budget-usd`) + action « proposer un split ».
- Gate QA [08] : rollback propre d'une slice avortée (snapshot `HEAD` pré-spawn → `git reset --hard` + `clean`) + **re-découpage autonome** (préservant les AC) par défaut, `ready-for-human` seulement si les AC ne peuvent être préservées.
