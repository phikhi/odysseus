# 28 — La session n'est pas attendue quand le stop tombe pendant son extinction

**What to build:** Fermer le second exemplaire du défaut de [25]. `session_spawn` attend `claude` avec un `wait "$pid"` nu, que bash court-circuite dès qu'un signal piégé arrive — le trap `loop_request_stop` en est un. La boucle reprend alors la main pendant que `claude` tourne encore : elle juge, rollbacke, `rm -f` le flux qu'il écrit, et sort du run en le laissant vivant. La primitive de collecte existe déjà (`gate__collect`), mais elle est privée au gate : la première décision de ce ticket est de dire **où elle vit**.

**Blocked by:** None

**Write-surface:** `.claude/lib/session.sh`, `.claude/lib/gate.sh`, `.claude/lib/state.sh`, `test/smart-zone.bats`, `test/gate.bats`, `test/layering.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Un TERM reçu pendant qu'une session se ferme ne fait pas sortir la boucle avant elle : `claude` est attendu jusqu'à son code de retour, ou il est tué avec son arbre de processus avant que le run ne rende la main. Aucun `claude` ne survit au run.
- [ ] Le flux de session n'est pas supprimé tant qu'un `claude` peut encore y écrire.
- [ ] La primitive de collecte a un seul exemplaire dans le pack. Un second appelant sur une fonction `__` veut dire qu'elle est publique (règle 6) : la renommer et la placer, pas la recopier dans `session.sh`. `test/layering.bats` refuse un lib qui appelle le `__` d'un voisin, et c'est ce refus qui pose la question.
- [ ] Le test vise la fenêtre **soft-limit**, la seule où `wait` bloque vraiment : sur le chemin normal `monitor_watch` ne rend la main qu'une fois le process parti, donc `wait` retourne tout de suite et la fenêtre est de quelques microsecondes.
- [ ] La ligne « Une itération en cours finit quand un humain arrête le run » de `docs/frontiere-de-confiance.md` cesse de décrire une fenêtre ouverte.

## Comments

- **Origine : question 4 posée en livrant [25], le 29/07/2026.** Le trou du gate était un `wait` nu ; `grep -n '\bwait\b' .claude/` en rend **deux**, et le second est écrit séparément avec la même faille. La leçon est dans `docs/frontiere-de-confiance.md` : une primitive de la boucle est un défaut répété autant de fois qu'elle est appelée.

- **Pourquoi la fenêtre est réelle, et laquelle viser.** `monitor_watch` sort de sa boucle de deux façons. Sur le chemin normal il attend d'avoir constaté le process parti (`alive=0`, plus une dernière lecture), donc le `wait` qui suit ne bloque pas : la fenêtre est de l'ordre de la microseconde, et si elle est touchée la conséquence est une session verte rollbackée et retryée. Sur le chemin **soft-limit** il fait `kill -TERM` puis `rc=1; break` — il rend la main *sans* attendre que `claude` meure. `wait` bloque alors pendant toute l'extinction, et un vrai `claude` ne se ferme pas instantanément. C'est cette fenêtre qu'il faut tester.

- **Sonde reproduite, le 29/07/2026, avec témoin dans les deux sens.** `SOFT_LIMIT_TOKENS=1000`, un faux `claude` qui émet un `usage` à 5010 tokens, **ignore** le TERM du moniteur (`trap '' TERM`), pose un marqueur 0,6 s plus tard — le temps que le moniteur ait tiré et que la boucle soit entrée dans `wait` — puis vit 8 s de plus. Seule la première session est lente : sinon le `claude` du re-slice tient le run plus longtemps que celui qu'on observe et l'orphelin a le temps de finir, ce qui a masqué la sonde au premier essai.

  ```
  ralph: iteration 1: 01-alpha
  ralph: stop requested — finishing the current iteration
  ralph: session crossed the 1000-token soft limit (peak 5010) — terminated
  ralph: 01-alpha: no re-slice plan came back
  ralph: 01-alpha: escalated to the human sink (too-big)
  ralph: stopped on request after 1 iterations
  === ORPHELIN : le run est sorti, claude tournait encore ===
  ```

  Témoin, même scénario sans TERM envoyé au run : `=== claude avait fini quand le run est sorti ===`. C'est bien l'interruption du `wait` qui produit l'orphelin, pas le chemin soft-limit lui-même.

- **Ce que la sonde ne change pas, et pourquoi la gravité reste bornée.** Le *verdict* est le même dans les deux cas : `RALPH_SOFT_LIMIT_HIT` valant 1, la boucle prend la branche `over-soft-limit` quel que soit le code que `wait` a rendu. Ce qui fuit est le process et le quota, pas la décision. Sur le chemin normal en revanche, une interruption ferait passer une session verte en `failed` — fenêtre minuscule, conséquence franche.

- **Conjonction requise, à peser pour la priorité.** Il faut un humain qui arrête le run *pendant* l'extinction d'une session qui vient de franchir la limite douce. Rare. Ce qui le rend digne d'un ticket : la conséquence est du quota brûlé sans surveillance sur un run AFK — le budget est un abonnement, donc c'est de la capacité prise à la nuit suivante — et [06] multiplie les appelants de `session_spawn`.

- **Contrainte pour [06].** Une lentille qui lance `claude` passe par `session_spawn` ([20]), donc elle héritera de cette primitive. Deux choses à savoir : dans une branche de gate les traps du parent sont **réinitialisés** (bash ne conserve pas un trap non ignoré dans un sous-shell), donc une branche ne reçoit pas le TERM du run et n'est pas exposée à cette fenêtre ; mais la branche est tuée par le chien de garde via `gate__kill_tree`, qui descend l'arbre de processus — c'est ce chemin-là, et non `wait`, qui doit garantir qu'aucun `claude` de lentille ne survit à un dépassement de `GATE_TIMEOUT`.

- **Contrainte pour [23].** Le pendant temporel d'une session qui pend est ce ticket-là, et les deux se rejoignent sur `session.sh`. Un timeout de session qui tuerait `claude` sans l'attendre reproduirait exactement l'orphelin décrit ici : le piège déjà noté dans [23] (« un timeout n'est pas un over-soft-limit ») en a un second, celui-ci.
