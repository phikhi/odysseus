# 106 — Les commandes de jeton tiennent tout ce que tient le shell qui les évalue

**What to build:** Que `TRACKER_TOKEN_CMD` et `USAGE_TOKEN_CMD` ne tiennent rien au-dessus de stderr du shell qui les évalue, comme tout ce que le pack lance depuis [101]–[105] — ou que chacune dise ce qu'elle tient. Aujourd'hui les deux sont évaluées par `$(eval …)` dans le shell qui les appelle : `TRACKER_TOKEN_CMD` dans l'itération, qui tient le canal du reçu ([96]) ; `USAGE_TOKEN_CMD` dans le pilote, qui tiendra les bouts lecteurs de [98]. [101] les a écartées de `proc_exec_bare` comme « commandes de l'opérateur » ; mais ce qu'elles lancent peut vivre dans le `HOME` qu'une session écrit.

**Blocked by:** None

**Write-surface:** `.claude/lib/proc.sh`, `.claude/lib/forge.sh`, `.claude/lib/budget.sh`, `.claude/lib/receipt.sh`, `test/proc.bats`, `test/tracker-remote.bats`, `test/budget.bats`, `test/gate.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] **Le cas mesuré ne forge plus rien** (`../sondes/ticket-105/t1-la-commande-du-jeton.bats`, C1) : backend `github`, l'opérateur a écrit `TRACKER_TOKEN_CMD='bash "$HOME/bin/forge-token"'`, la session réécrit le script, et le reçu de l'itération porte quatre lignes forgées, `rc=0`, `resolved`. Témoin appairé C0 (script intact) : aucune.
- [ ] **`USAGE_TOKEN_CMD`, même décision**, testée là où elle tombe : dans le pilote, à chaque `budget_check`. Aujourd'hui le pilote ne tient aucun canal de reçu, donc la mise en scène doit demander à **tous** les descripteurs de ce que la commande lance (`fd_forger`), pas à un canal qui n'existe pas encore — et le test doit rester significatif le jour où [98] fait tenir au pilote des bouts lecteurs.
- [ ] **Le critère d'exclusion de [101] est réécrit**, là où il est écrit (`proc.sh`, le commentaire de `proc_exec_bare`) : la question n'est pas « qui a écrit la ligne » mais « qui peut écrire ce qu'elle lance » — celle que [101] a posée à `TEST_CMD`. Les deux phrases « exactly as trusted as `TEST_CMD` » (`forge.sh`, `budget.sh`) deviennent vraies, ou sont corrigées.
- [ ] **Deux choix à trancher et à écrire avec leur prix** : l'environnement rendu à l'opérateur (forme de `proc_exec_bare`) ou gardé (forme de `proc_git`) ; et si la commande peut encore appeler une fonction du pack (`eval` le permet aujourd'hui, aucune installation connue ne s'en sert).
- [ ] **Recensement dérivé** : toute évaluation d'une chaîne de la configuration passe par la forme qui ferme, et une évaluation nue rougit un test (`test/gate.bats`, comme les recensements de [104] et [105]). Il n'y en a que deux aujourd'hui.
- [ ] **Ce que la fermeture n'achète pas, écrit avec elle** : le jeton reste ce que la commande imprime — une session qui réécrit le script choisit l'identité avec laquelle le pack parle à la forge. Pas un trou neuf (la session peut déjà lancer le script elle-même, ligne « Ce qu'une session écrit dans le tracker d'un backend distant »), mais la phrase doit le dire.
- [ ] **La phrase de provenance du reçu** (`receipt_render`) perd son exception « commande de jeton » — ou la garde, si le ticket conclut autrement, avec sa raison.
- [ ] La ligne du tableau est réécrite (aujourd'hui la commande de jeton est nommée comme exception dans la ligne de `curl`), et ce que la ligne **ne recense pas** y est dit : les utilitaires de la liste de [91] tiennent les descripteurs du shell qui les lance, et c'est sans conséquence tant qu'ils ne lisent aucun fichier de l'utilisateur et ne lancent rien — une phrase de [105], pas un recensement.
- [ ] Témoin appairé ; le canari reçoit le cas qui décide (un reçu distant sans ligne forgée par une commande de jeton réécrite) ; une entrée de mutation par garantie.

## Comments

- **Ouvert par la passe transversale du 09/10/2026** (`../passe-transversale-09-10.md`, §1). Trouvé en livrant [105] (sonde `../sondes/ticket-105/t1`), laissé à la passe par la règle de session, rejoué par elle sur `main` à `1907f9d`.

- **Pourquoi avant [98].** [98] fera tenir à chaque itération le bout écrivain de son canal vers le pilote pendant toute sa vie, et au pilote un bout lecteur par itération en vol. `TRACKER_TOKEN_CMD` est évaluée dans l'itération à chaque opération d'un backend distant : sans ce ticket, le canal que [98] livre pour que `outcome`, `posture`, `drift` cessent d'être écrivables par la session le serait, sur un backend distant, par ce que la session a mis dans le `HOME`. `USAGE_TOKEN_CMD` est évaluée dans le pilote avant chaque claim : à `MAX_PARALLEL≥2` elle tiendrait les bouts lecteurs des sœurs — de quoi lire ou vider la réponse d'une itération avant le pilote (un déni, le (c) de [105]). C'est l'argument qui a fait passer [105] devant [98] : fermer avant de construire dessus.

- **Le prix, tel qu'on le voit avant d'écrire** : aucun trouvé. Une commande de jeton imprime un jeton et n'a l'usage d'aucun descripteur du pack. La forme existe deux fois (`proc_git`, `proc_curl`) : un sous-shell qui ferme 3 à 255 avant d'évaluer. À mesurer plutôt qu'à supposer : un jeton servi par un agent qui parle sur un descripteur hérité (un agent de mots de passe lancé autrement que par socket) serait cassé — aucune installation connue, à vérifier sur les gestionnaires usuels.

- **Disculpé par la passe, à ne pas rouvrir ici** : la soumission du planificateur (`at`, `systemd-run`), l'autre moitié de l'exclusion de [101] — le job tourne plus tard hors de l'arbre du pilote et n'hérite de rien.

- **Ordre VALIDÉ par Philippe le 09/10/2026** : **[106] → [98] → [99] → [100]**, arête **106 → 98**. Premier de la file. Les deux autres options posées — après [98], ou ne pas rouvrir la décision de [101] — ont été écartées.
