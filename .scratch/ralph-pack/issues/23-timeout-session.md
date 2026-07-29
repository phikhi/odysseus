# 23 — Timeout de session

**What to build:** Borner le **temps** d'une session, pas seulement son contexte. Le filet smart-zone [04] tue une session qui gonfle sa fenêtre, `GATE_TIMEOUT` [07] tue une branche de gate qui dépasse ; une session `claude` qui pend sans émettre un token n'est bornée par **rien** — `monitor_watch` ne tique que sur ce que le flux écrit. Pour un pack qui tourne huit heures sans surveillance, c'est un run qui ne broie rien et ne rend jamais la main.

**Blocked by:** 04

**Write-surface:** `.claude/lib/monitor.sh`, `.claude/lib/session.sh`, `.claude/lib/failures.sh`, `.claude/loop.sh`, `.claude/ralph.config.sh.example`, `test/smart-zone.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Une session qui n'écrit plus rien pendant `SESSION_STALL_TIMEOUT` est terminée par le même chemin que la limite molle (SIGTERM à l'arbre de processus), avec un message qui dit « pend » et non « trop de contexte ».
- [ ] Un délai mur total `SESSION_TIMEOUT` borne aussi la session qui émet lentement pour toujours : un flux qui progresse n'est pas une preuve de progrès.
- [ ] Zéro ou non-numérique = pas de délai, comme `GATE_TIMEOUT`, et les deux défauts sont explicites dans `ralph.config.sh.example`.
- [ ] L'itération sort avec un `outcome` distinct d'`over-soft-limit` : une session coupée pour contexte dit quelque chose sur la *taille du ticket* (`too-big`, re-slice), une session qui pend ne dit rien du tout.
- [ ] Une classe dans `failures_classify` ([07]) : un timeout est retryé en session fraîche jusqu'à `RETRY_N` puis `ready-for-human`, **sans** passer par le re-découpage.
- [ ] La ligne « Une session finit » de `docs/frontiere-de-confiance.md` ne dit plus « Rien ».

## Comments

- **Origine et pourquoi ce ticket existe séparément.** Le trou est écrit depuis [04] comme « le pendant manquant » (« le filet borne le contexte d'une session, pas son temps »), il est resté **sans propriétaire pendant 22 tickets**, et il a été retrouvé en faisant le compte rendu de [20] — c'est-à-dire par accident, comme les quatre défauts de `docs/frontiere-de-confiance.md`. Ouvert le 29/07/2026 après arbitrage : ni un amendement de [04] (clos), ni un morceau de [12].

  Pourquoi pas rouvrir [04] : la terminaison a besoin d'une **classe dans `failures_classify`**, donc la write-surface sort de celle de [04] ; et c'est une garantie distincte, qui veut sa propre entrée de mutation et sa propre ligne au tableau de confiance. Pourquoi pas [12] : [12] borne des **gardes tenues par des pids morts**, celui-ci borne un **enfant vivant qui ne dit rien** — deux mécanismes, deux tickets.

- **Le mécanisme est déjà à portée de main, ne pas en construire un second.** `monitor_watch` ([04]) tique toutes les 0,1 s et tient le flux sur un **descripteur ouvert** : il sait donc à chaque tick si la session vient d'écrire, sans relire le fichier et sans forker. Le délai de silence est un **compteur de ticks sans nouvelle donnée**, pas un `date` par tick — la revue de [04] a mesuré ce que coûte un moniteur qui refait du travail à chaque tick (0,358 s le tick à 20 Mo, contre 0,03 ms après correction). Même remarque pour le délai mur : un seul `ralph_now` au départ, pas un par tick.

- **Piège de conception, à trancher ici : un seul des deux délais ne suffit pas.** Le silence seul ne borne pas une session qui boucle en émettant du texte ; le mur seul est brutal, une vraie session peut être longue et légitime. Les deux, avec un silence court et un mur généreux. Corollaire à vérifier : la partielle de ligne que le descripteur ouvert peut lire au milieu d'un `printf` ([04]) compte comme « la session a écrit » — sinon un flux qui arrive en deux morceaux lents ressemble à du silence.

- **Contrainte héritée de [20] : ce ticket touche le seul endroit du pack qui lance `claude`.** `session_spawn` est sous contrat (`test/contract-claude.bats`, sur le fake à chaque run et sur le vrai binaire sous `RALPH_REAL_CLAUDE=1`). Ajouter un chemin de terminaison ne doit pas ajouter une seconde invocation du binaire ni changer l'argv — le contrat dérive `permissionMode` de l'argv du shim, donc perdre `--dangerously-skip-permissions` en réécrivant le spawn ferait rougir le contrat, ce qui est le comportement voulu.

- **Contrainte héritée de [04]/[06] : le signal ne doit pas voyager par une variable de shell si un sous-process peut être dans le chemin.** `monitor_watch` positionne `RALPH_SOFT_LIMIT_HIT` dans le shell de `session_spawn`, donc dans celui de la boucle — mais une lentille de gate de [06] appelle `session_spawn` **depuis une branche**, c'est-à-dire un sous-process, où cette variable est perdue. Un second signal du même genre hérite du même piège : le prévoir par fichier de code de retour, ou dire explicitement qu'il ne vaut que dans le shell appelant.

- **Contrainte posée par [25], propriétaire [28] : tuer une session sans l'attendre laisse un orphelin.** Le piège déjà noté ici — « un timeout n'est pas un over-soft-limit » — en a un second, du même genre que celui que [25] a réparé dans le gate. `session_spawn` attend `claude` avec un `wait "$pid"` nu, et sur le chemin soft-limit `monitor_watch` rend la main **dès son TERM envoyé**, sans attendre l'extinction. Sondé le 29/07/2026 avec témoin : un TERM reçu par le run pendant cette extinction court-circuite le `wait`, la boucle reprend la main, `rm -f` le flux que `claude` écrit encore, et sort en le laissant vivant. Un chemin de terminaison par timeout écrit sur le même modèle reproduirait exactement cet orphelin. [28] tranche d'abord où vit la primitive de collecte (`gate__collect` est privée au gate, et `test/layering.bats` refuse qu'un lib appelle le `__` d'un voisin) ; ce ticket-ci doit l'utiliser plutôt que d'en écrire une troisième.

- **Ce que le run réel fait et que les fakes ne font pas.** Les fakes de la suite finissent vite ; le scénario de ce ticket est précisément une session qui **ne finit pas**. Le test qui vaut est un shim qui dort sans rien écrire (silence) et un shim qui écrit une ligne par seconde sans jamais émettre `result` (mur), avec des délais de l'ordre de la seconde en test. Asserter l'état du tracker après, pas seulement le code de sortie : un timeout qui tue la session mais laisse le ticket `claimed` serait un faux vert de plus.
