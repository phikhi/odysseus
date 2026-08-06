# 09 — Auto-chaînage : successeur one-shot + scheduler

**What to build:** Le franchissement d'un mur hebdomadaire sans faire dormir un process des jours : un **successeur one-shot** programmé au reset de la fenêtre bloquante, via une chaîne de scheduler auto-détectée et ordonnée par survie au reboot, avec repli humain si aucun scheduler.

**Blocked by:** 08

**Write-surface:** `.claude/lib/scheduler.sh`, `test/scheduler.bats`

**Status:** ready-for-agent

- [ ] Un mur hebdo programme un successeur one-shot au `resets_at` de la fenêtre bloquante — **jamais `+7j`**.
- [ ] La chaîne de scheduler est auto-détectée et ordonnée par survie au reboot (`at` avant `systemd-run` transient ; variantes par plateforme Linux/macOS) ; le skill cloud `schedule` n'est **pas** dans la chaîne locale.
- [ ] Sans scheduler disponible, la boucle sort proprement en `pause-hebdo` (repli humain).
- [ ] Anti-double-run : le successeur est singleton et protégé par le verrou de run ; deux successeurs ne se chevauchent jamais.
- [ ] Un fake `at` reçoit exactement une programmation, avec la bonne échéance (vérifié via le seam).

## Comments

- **Contrainte posée par la revue de [01]–[04] : les codes de sortie de `loop.sh` ont changé.** `0` signifie désormais « ce run a drainé la frontière » et **`5` « la frontière était déjà vide au démarrage »** (mauvais `FEATURE`, tout en triage, tracker illisible). Un successeur one-shot qui se réveille doit traiter `5` comme « plus rien à faire », pas comme un échec — et surtout ne pas se re-programmer en boucle dessus. `2` couvre maintenant aussi une config qui viderait le gate de son sens (`TEST_CMD`/`TYPECHECK_CMD` vides), ce qui est un cas où re-programmer un successeur ne servirait à rien : il refusera pareil.

- **Contrainte posée par [08], livré le 05/08/2026 : le mur hebdo existe déjà, il sort en `6`, et il t'attend.** `loop.sh` a un sixième code de sortie : `6`, « le budget d'usage bloque ce run ». Il tombe dans deux cas et deux seulement — une fenêtre `seven_day` (ou `seven_day_opus` quand `MODEL` nomme un opus) au-dessus de `THRESH_WEEK`, et une fenêtre de session dont le reset n'est pas un instant que le run peut attendre (`BUDGET_MAX_PAUSE`, ou un reset illisible). `6` et pas `4` est délibéré et c'est pour ce ticket : tous les autres arrêts sont des décisions que le run a prises sur lui-même, celui-ci est un mur qui se lève tout seul à un instant connu. Trois choses à savoir en écrivant le successeur :
  - **L'instant est déjà calculé** : `RALPH_BUDGET_RESET` (epoch) et `RALPH_BUDGET_WINDOW` sont posés par `budget_check` dans le shell de la boucle au moment où elle décide de s'arrêter, et la ligne de `run.log` est `budget-wall`. Il n'y a pas de second appel à l'endpoint à faire.
  - **Ne jamais programmer sur un reset que rien n'a mesuré.** Le cas « reset illisible » sort avec le *même* code 6, et son `RALPH_BUDGET_RESET` est vide ou hors du cap. Un successeur qui lit ce champ sans le vérifier programmerait à l'epoch 0 — c'est la forme exacte du repli qui se désarme tout seul ([27]). Le message de la boucle distingue déjà les deux ; le champ, lui, demande une garde.
  - **La source compte.** `RALPH_BUDGET_SOURCE` vaut `endpoint` ou `stream`. `stream` veut dire que l'instant vient du `rate_limit_event` d'une session, c'est-à-dire d'un fichier que la session jugée peut écrire ([08] borne ce que ça coûte à une pause ; un successeur programmé des jours plus loin sur la même valeur ne serait plus borné du tout). Programmer sur `stream` demande au minimum le même plafond que `BUDGET_MAX_PAUSE`, et l'AC « jamais +7j » ne suffit pas à le tenir.

- **Contrainte posée par [13], livré le 06/08/2026 : le successeur est armé par le pilote, jamais par une itération.** `loop_main` est devenu un pilote qui forke N itérations et les draine avant de sortir, donc l'instant d'armement est *après* la dernière itération en vol — et pas au moment où le mur budget est vu. Les deux sorties concernées (`exit 6`) passent désormais par un `stop_code` qui draine ; un `exit` immédiat laisserait un `claude` par slot en train de brûler du quota que le successeur est censé économiser ([28]).
