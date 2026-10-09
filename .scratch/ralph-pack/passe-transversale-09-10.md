# Passe transversale du 09/10/2026

Dix-septième passe. Faite sur `main` à `1907f9d` (merge de [105]). **Cinq**
livraisons depuis celle du 29/09 : [101] `3d4df83`, [102] `028a359`, [103]
`235d656`, [104] `3c836f5`, [105] `1907f9d`. Cinq sur cinq, la règle telle quelle
— voir la mémoire `ralph-pack-cadence-des-passes`. Le compte repart à 0/5 après
elle.

Sondes : `sondes/passe-09-10/README.md` (les rejeux et leur verdict). **Aucune
sonde neuve** : la passe a rejoué celles des cinq tickets sur `main`, et la seule
matière ouverte était déjà mesurée par [105] (`sondes/ticket-105/t1`). **Ni
`.claude/`, ni `test/`, ni `init.sh` touchés** → la baseline de [105] tient telle
quelle (`run.sh` **1069**/0/**7 skips**, `mutate.sh` **1132**/0) et les deux gates
n'ont pas été rejoués.

---

## La racine

> **La série [101]–[105] a fermé ce que le pack lance programme par programme, et
> chaque ticket a trouvé le suivant en posant la question 5 au précédent : les
> deux points de fork ([101]), le répertoire de hooks ([102]), l'instant où un
> canal a un nom ([103]), git ([104]), curl ([105]). La seule chose que la série
> n'a jamais reposée est son critère d'exclusion.**
>
> [101] a écarté de `proc_exec_bare` les `*_TOKEN_CMD` et la soumission du
> planificateur comme *« commands the operator wrote, not the project and not the
> session »* (`proc.sh:314`). Le critère est **qui a écrit la ligne**. Or ce n'est
> pas celui que [101] a appliqué à `TEST_CMD` : la commande de test est écrite
> dans la même configuration scellée, et elle est fermée parce que **ce qu'elle
> lance** peut être écrit par la session. Le code le dit lui-même deux fois, sans
> voir la contradiction : `TRACKER_TOKEN_CMD` et `USAGE_TOKEN_CMD` sont *« exactly
> as trusted as `TEST_CMD` »* (`forge.sh:232`, `budget.sh:200`). Vrai de la ligne.
> Faux de ce qu'elle tient : depuis [101], `TEST_CMD` ne tient rien au-dessus de
> stderr, et les deux commandes de jeton tiennent tout ce que tient le shell qui
> les évalue.

Le recensement, refait à partir de ce que le pack lance et pas des tickets qui
l'ont fermé — chaque endroit où un programme reçoit les descripteurs d'un shell du
pack :

| Ce qui est lancé | Depuis | Ce qu'il tient | Ce qui le tient |
|---|---|---|---|
| `claude` (livraison, re-découpe, lentilles, rétro, gate de valeur) | `session_spawn` | stdin, son flux, stderr | `proc_exec_bare` ([101]) |
| `TEST_CMD`, `TYPECHECK_CMD`, `RUN_CMD`, `VISUAL_CMD` | `proc_group_fork` | stdin `/dev/null`, stdout, stderr | `proc_exec_bare` ([101]) |
| `lsof` du contrôle de canal | `proc__channel_alone` | rien du canal qu'il examine | `proc_exec_bare` ([103]) |
| chaque `git`, et ce que sa configuration lui fait lancer | `proc_git` | rien au-dessus de stderr | [104], plus le jeton de [102] |
| chaque `curl` | `proc_curl` | rien au-dessus de stderr, aucune config | [105] |
| les utilitaires de la liste de [91] (`sed`, `awk`, `cat`, `cksum`, `mktemp`…) | partout | tout | épinglés par chemin ([52], [91]), ne lisent aucun fichier de l'utilisateur et ne lancent rien — **une phrase de [105], pas un recensement** |
| `at`, `systemd-run` | `scheduler__submit` | tout, le temps de la soumission | le job tourne plus tard hors de l'arbre du pilote (`atd`, le gestionnaire de services) — disculpé ci-dessous |
| **`TRACKER_TOKEN_CMD`** | `forge__http`, `$(eval …)` | **tout** : dans l'itération, le canal du reçu ([96]) | **rien** → §1 |
| **`USAGE_TOKEN_CMD`** | `budget__request`, `$(eval …)` | **tout** : dans le pilote | **rien** → §1 |

Deux lignes de ce tableau sont la passe, et elles sont la même ligne.

---

## §1 — Les deux commandes de jeton tiennent tout ce que tient le shell qui les évalue

Sonde `../sondes/ticket-105/t1` (ouverte en livrant [105], rejouée ici).

**Ce qui est mesuré.** L'opérateur écrit
`TRACKER_TOKEN_CMD='bash "$HOME/bin/forge-token"'` — un script de son `HOME` qui
imprime un jeton. La session tourne avec le même `HOME` et réécrit ce script.
`forge__http` l'évalue par `$(eval …)` dans le shell de l'itération, qui tient le
canal du reçu de [96] de `receipt_open` à `receipt_close`. Rendu, sur `main` :

| | Ce que le run fait |
|---|---|
| **C1** la session réécrit le script | 6 exécutions, fd 5 écrivable 5 fois, **4 lignes forgées dans le reçu**, `rc=0`, `resolved` — identique à la mesure de [105] |
| **C0** témoin, script intact | aucune exécution du forgeur, aucune ligne, `resolved` |

**Pourquoi l'exclusion de [101] ne tient pas, avec son propre critère.** [101]
ferme ce qu'il ferme parce qu'*« a program the pack did not write has no business
with any descriptor but the three it is handed »* (`proc.sh`). Le pack n'a pas
écrit la commande de jeton, et ce qu'elle lance n'est ni le pack ni la ligne : un
script du `HOME`, un binaire qui lit sa propre configuration dans le `HOME`, ou les
deux. La phrase « l'opérateur l'a écrite » répond à la question *« qui a choisi
cette ligne ? »* ; la question que [101] posait à `TEST_CMD` est *« qui peut
écrire ce qu'elle lance ? »* — et pour `TEST_CMD` la réponse était « la session,
dans le worktree », exactement comme ici « la session, dans le `HOME` ».

**Ce que la fermeture coûterait.** Rien qu'on ait trouvé : une commande de jeton
imprime un jeton, elle n'a l'usage d'aucun descripteur du pack. La forme existe
deux fois ([104] et [105]) — un sous-shell qui ferme 3 à 255 avant d'évaluer.
Ce qui reste à trancher par le ticket : l'environnement (rendu à l'opérateur comme
par `proc_exec_bare`, ou gardé comme par `proc_git`), et si la commande doit encore
pouvoir appeler une fonction du pack (aujourd'hui `eval` le permet, aucune
installation connue ne s'en sert).

**Ce que la fermeture n'achète pas, à écrire avec elle.** Le **jeton** lui-même
reste ce que la commande imprime : une session qui réécrit le script choisit
l'identité avec laquelle le pack parle à la forge. Ce n'est pas un trou neuf — une
session qui atteint le script peut déjà le lancer elle-même et parler à la forge
avec le jeton de l'opérateur (ligne « Ce qu'une session écrit dans le tracker d'un
backend distant ») — mais la phrase doit le dire plutôt que laisser lire « fermé ».

**Et la question 4 : ce que [98] hérite si rien ne change.** [98] va faire tenir
à chaque itération le **bout écrivain** de son canal vers le pilote pendant toute
sa vie, et au pilote un **bout lecteur** par itération en vol (forme instruite dans
le ticket). Les deux commandes de jeton tombent exactement de part et d'autre :

- `TRACKER_TOKEN_CMD` est évaluée **dans l'itération**, à chaque opération d'un
  backend distant — donc pendant que l'itération tient l'écrivain du slot. Le
  canal que [98] livre pour que `outcome`, `posture`, `drift` cessent d'être
  écrivables par la session serait, sur un backend distant, écrivable par ce que
  la session a mis dans le `HOME` : **[98] livrerait sa garantie avec le trou le
  jour même**, et la ligne de son tableau devrait l'avouer.
- `USAGE_TOKEN_CMD` est évaluée **dans le pilote**, à chaque `budget_check` (avant
  chaque claim) — donc, à `MAX_PARALLEL≥2`, pendant que le pilote tient les bouts
  lecteurs des sœurs en vol. Un lecteur ne s'écrit pas (mesuré sur darwin pour
  curl, [105]) ; il se lit et se vide : la réponse d'une itération lue par un autre
  que le pilote, ou disparue avant lui. Un déni, comme le (c) de [105].

C'est la forme exacte de [101]–[105] : **fermer avant de construire dessus**.
[105] a été passé avant [98] pour cette raison, et la même raison vaut ici.

---

## Ce que la passe a rejoué et trouvé intact

Les sondes « run réel » des cinq tickets, sur `main` à `1907f9d` (détail et
sorties : `sondes/passe-09-10/README.md`).

- **[101]** — `ticket-98/f2` L1, L2 : la session jugée et la `TEST_CMD` du projet
  ne trouvent **aucun** descripteur écrivable au-dessus de 2 ; aucune ligne forgée
  dans le reçu.
- **[102]** — `ticket-98/f2` L3 : le hook posé dans le répertoire commun **ne
  tourne pas** (« hook runs: none »).
- **[103]** — `ticket-98/f3` : le survivant qui boucle gagne toujours **12
  fenêtres**, et **0 ligne forgée** ; le run sort en **4** — le canal refusé, pid
  dit. C'est le reste écrit de [103] (un déni, pas une forge), et c'est ce que [98]
  héritera pour le canal du slot (déjà écrit dans le ticket).
- **[104]** — `ticket-102/h4` : hook configuré planté pendant que la sœur est dans
  son gate (C2b) **14** exécutions, depuis `~/.gitconfig` (C3) **160**,
  `core.fsmonitor` (C4) **958** — **0 descripteur, 0 ligne forgée** partout ;
  `ticket-104/g1` : 958 exécutions, **aucune** avec un descripteur ouvert. Les
  chiffres de [104], au même près.
- **[105]** — `ticket-98/f4` C1/C0 : sous un `~/.curlrc` écrit par la session,
  36 appels `curl`, **0 ligne forgée**, `resolved` ; témoin identique.

## Ce que la passe a regardé et disculpé

Écrit pour que ça ne soit pas re-sondé.

- **La soumission du planificateur** (`at`, `systemd-run`), l'autre moitié de
  l'exclusion de [101]. Ce sont des programmes de la liste de [91], épinglés par
  chemin, qui tiennent les descripteurs du pilote le temps de la soumission et ne
  lisent aucun fichier qu'une session écrit ; le job, lui, est lancé plus tard par
  `atd` ou le gestionnaire de services, hors de l'arbre du pilote, et n'hérite de
  rien. L'environnement remis à `at` est déjà celui de l'opérateur ([102]). Rien à
  atteindre.
- **Les utilitaires de la liste de [91]** (`sed`, `awk`, `cat`, `sort`, `cksum`,
  `mktemp`, `ps`, `lsof`…). Ils tiennent tout ce que tient le shell qui les lance,
  et c'est sans conséquence tant qu'ils ne lisent aucun fichier de l'utilisateur
  et ne lancent rien d'autre que ce que le pack leur passe — ce que [105] écrit
  pour curl (« le seul programme de la liste qui lise un fichier de l'utilisateur
  à chaque démarrage »). C'est vrai sur darwin et sur un Linux à coreutils, et
  c'est une **phrase**, pas un recensement : un programme ajouté demain à la liste
  de [91] n'est jugé par rien sur ce critère. Pas un ticket ; à écrire dans le
  ticket de §1 comme ce qu'il ne recense pas.
- **Le drain** (`human-loop.sh`) : la session interactive hérite le fd 3 de la
  liste de travail (un heredoc). Ce qu'une session y lirait ou y viderait décide
  de l'ordre des tickets `ready-for-human` montrés à un humain — sous la ligne 75
  du tableau (« un humain devant l'écran, et rien d'autre »), qui est déjà la plus
  large. Pas un ticket.
- **Les recensements de [104] et [105]** sont dérivés et ont tenu au rejeu ; ils
  sont par **mot** (`git`, `curl`). Les deux `$(eval …)` de §1 ne sont vus par
  aucun recensement : un recensement des évaluations de chaînes de configuration
  est la forme dérivée naturelle du ticket de §1.

---

## Les tickets

| # | Ce qu'il ferme | Fichiers |
|---|---|---|
| **[106]** | les commandes de jeton de l'opérateur ne tiennent rien du shell qui les évalue | `.claude/lib/proc.sh`, `.claude/lib/forge.sh`, `.claude/lib/budget.sh`, `.claude/lib/receipt.sh`, `test/proc.bats`, `test/tracker-remote.bats`, `test/budget.bats`, `test/gate.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |

### Ordre — **VALIDÉ par Philippe le 09/10/2026**

**[106] → [98] → [99] → [100]**, arête neuve **106 → 98**. Critère habituel :
minimiser la reprise. Sans [106] devant, la ligne du tableau de [98] s'écrit avec
un aveu (« sur un backend distant, la commande de jeton tient l'écrivain ») que
[106] réécrirait ensuite — c'est l'argument qui a fait passer [105] devant [98].
[99] et [100] inchangés ; [97] reste hors file.

Les deux autres options posées : [106] après [98] (l'aveu écrit par [98], réécrit
par [106]), et ne pas rouvrir la décision de [101] (l'exception reste nommée au
reçu et au tableau, aucun ticket). Écartées.

**Prochaine passe** : après le cinquième ticket livré à partir d'ici — la file en
a quatre ([106], [98], [99], [100]), donc après un de plus, à moins qu'il ne
s'ouvre en route.
