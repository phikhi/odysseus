# 72 — Les deux points d'entrée journalisent avant de savoir s'ils ont le droit de tourner

**What to build:** `loop_main` et `human_loop_main` prennent leur base de journal, puis appellent leur préflight — qui **journalise** les constats du tracker depuis [64] — et **seulement ensuite** demandent les deux verrous. Celui qui perd le verrou a donc déjà écrit dans le `run.log` de l'autre, et le témoin de l'autre ([10] côté run, [67] côté drain) l'accuse d'avoir réécrit son journal. Le refus « un seul écrivain ici » tombe après l'écriture qui le suppose, dans les deux sens.

**Blocked by:** None

**Write-surface:** `.claude/loop.sh`, `.claude/human-loop.sh`, `test/human-loop.bats`, `test/loop-happy-path.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` — plus `.claude/lib/router.sh`, **écart déclaré** : un commentaire seul (voir les commentaires de livraison).

**Status:** resolved

**Tags:** human-loop, journal, concurrency

- [x] Un point d'entrée qui n'obtiendra pas les verrous n'écrit **aucune ligne** dans `run.log`. Ce qu'il a à dire des constats du tracker, il le dit à l'écran comme aujourd'hui.
- [x] Le témoin de l'autre point d'entrée ne se déclenche pas : un run qui tourne pendant qu'un humain essaie de drainer finit sans accuser personne, et réciproquement.
- [x] La règle est écrite là où un lecteur la cherchera : *ce qui, dans le préambule d'un point d'entrée, a le droit d'écrire avant les verrous.* Les deux fichiers portent aujourd'hui un commentaire qui explique où la **base** est prise et rien sur ce qui **écrit**.
- [x] Le témoin appairé est livré avec : le même run, sans point d'entrée concurrent, ne dit rien.
- [x] Une entrée de mutation par garantie livrée.

## Comments

- **Trouvé par la passe transversale du 07/09/2026** (`../passe-transversale-07-09.md`, §4). Sondes : `../sondes/passe-07-09/q4-*.bats`.

- **Mesuré** (`q4`), sur un tracker portant deux tickets sur le numéro `20` — l'état que [27] et [47] existent parce qu'il arrive :

  | | |
  |---|---|
  | Q4a — un run AFK tourne, un humain lance un drainage | le drain écrit `20 ambiguous-id … action=drain`, **puis** découvre que l'arbre est tenu (`rc=1`, « another run already holds this working tree »). Le run finit en disant « the run journal does not hold exactly the 3 line(s) this run wrote … **do not believe it about this run** » |
  | Q4b — témoin appairé, le même run sans drainage à côté | **0** accusation |
  | Q4c — l'autre sens, un drainage tient les verrous et un run AFK démarre | le run écrit `20 ambiguous-id … action=none` **puis** refuse (`rc=1`) ; c'est `router_journal_verify` qui accuse, même phrase |

- **Inerte sur les décisions, pas sur le lecteur.** [10] et [67] tiennent tous deux que le journal n'est une autorité pour personne, donc rien n'est marqué de travers. Ce qui est perdu est le signal lui-même : c'est le corollaire du 24/08 — *une ligne qui dit « je n'ai pas pu » doit être nette de ce qu'elle a pu* — lu sur le mécanisme le plus cher du pack. Un humain qui a vu cette phrase une fois pour rien ne la relira plus, et elle est le seul endroit où le pack dit « une session a réécrit ton journal ».

- **Le déclencheur est le geste le plus banal qui soit** : lancer le drainage pendant que le run tourne. Le pack le refuse *correctement* — c'est [22] et c'est ce que les deux verrous sont — et le refus arrive après l'écriture.

- **Ce qui est en cause n'est pas la base, c'est l'écriture.** Le commentaire des deux fichiers explique très bien pourquoi la base est prise avant le préflight (« a base read on the first append is already past whatever went missing before it »), et cette raison-là tient. Ce que personne n'a posé est que le préflight, depuis [64], **écrit**. Les deux moitiés sont séparables : garder la base là où elle est et déplacer la journalisation derrière les verrous suffirait, à condition de dire ce que devient le constat quand le point d'entrée refuse de tourner — il doit rester dit à l'écran, sinon un humain perd la seule phrase qui explique pourquoi sa frontière est vide.

- **La règle à écrire est plus large que le correctif**, et c'est ce que [70] réutilise : *le préambule d'un point d'entrée s'exécute avant que le pack sache s'il a le droit de toucher cet arbre.* Tout ce qu'on y ajoute — un constat, un épinglage, un balayage — hérite de ça. [69] a déjà ajouté deux lignes à ce préambule (les résidus) et elles sont, elles, purement lisantes ; c'est une chance et pas une propriété.

- **Contrainte pour [70]** : c'est ici que se décide **où** le préambule de `loop_main` a le droit d'écrire et d'épingler. [70] pose un témoin dans ce même préambule ; livré derrière ce ticket, il place son épinglage sous une règle déjà écrite.

- **Contrainte pour [64]** : le constat qu'il a fait journaliser par les deux points d'entrée est exactement ce que ce ticket déplace. Sa garantie — « une fois par run **et** par drain, dans `run.log` et à l'écran » — doit rester vraie pour un point d'entrée qui tourne vraiment, et devenir « à l'écran seulement » pour celui qui refuse.

- **Piège de sonde.** Il faut deux processus vivants en même temps. Côté run : un faux `claude` qui touche `$RALPH_SHIM_STATE/in-session` puis attend `$RALPH_SHIM_STATE/go`. Côté drain : un **fifo** sur son stdin (`mkfifo` + `exec 9>`), sinon il sort immédiatement sur « stdin ended » et ne tient jamais les verrous.

- **Place dans la file, validée par Philippe le 07/09/2026 : deuxième.** Délié (`Blocked by: None`), deux fichiers, un seul mécanisme — et il tranche où le préambule de `loop_main` a le droit d'écrire, ce dont [70] a besoin pour placer son épinglage une seule fois. Ordre retenu : [71] → [72] → [70] → [18] → [19].

- **Deux contraintes écrites ici par [71], livré le 07/09/2026, parce que ce
  ticket touche les deux mêmes fichiers.**

  1. *`human-loop.sh` porte maintenant un piège `EXIT`.* Il convertit tout `0`
     qui n'est pas sa dernière ligne en **6**, « ended in the middle ». Deux
     choses le rendent fragile à un déplacement du préambule : il est armé en
     tête de fichier **et réarmé par `human_loop__arm_signals`**, parce que
     `run_lock_acquire` et `tree_lock_acquire` posent chacun leur propre
     `trap 'state_locks_release' EXIT` et le désarment donc en le prenant ; et
     `human_loop__on_exit` relâche les verrous lui-même, ce qui est ce qui
     autorise à remplacer leur trap. Déplacer les verrous, la base de journal ou
     le préflight sans regarder cette ligne rouvre le faux `0` — deux mutations
     et deux tests le disent (`ended in the middle`, `ended before it took its
     locks`).
  2. *`loop.sh` n'a rien de tel, et c'est la question 4 de [71].* Son `0` dit
     « the frontier was drained » et n'importe quel lib qui finirait le shell le
     lui fait dire sur une frontière pleine. Le chemin AFK n'atteint pas le
     défaut de [71] — `failures.sh` n'appelle `tracker_mark_escalated` que sous
     `[ -n "$reason" ]` — donc la forme est ouverte sans cas connu. Ce ticket est
     celui qui a `loop.sh` dans sa write-surface **et** qui regarde déjà le
     préambule des deux points d'entrée : la symétrie est à trancher ici, ne
     serait-ce que pour écrire qu'on ne la fait pas.

---

## Livré le 07/09/2026

- **Ce qui a bougé, et rien d'autre.** Les deux `*__report_tracker_findings` sont
  coupées en deux. La moitié qui **parle** reste dans le préflight : elle appelle
  `tracker_preflight` **une fois**, garde le résultat dans `LOOP__FINDINGS` /
  `HUMAN_LOOP__FINDINGS` — une variable du shell du point d'entrée, jamais un
  fichier — et imprime chaque constat. La moitié qui **écrit**
  (`loop__journal_tracker_findings`, `human_loop__journal_tracker_findings`) est
  appelée dans `*_main`, **après** les deux verrous, avant la ligne « run start » /
  « draining ready-for-human » — donc l'ordre du journal ne change pas.

- **`tracker_finding_said` n'a pas bougé, et c'était une erreur en cours de route
  qu'il faut laisser écrite.** Déplacé d'abord avec la ligne de journal, puis
  ramené : (a) il n'écrit rien que personne d'autre ne peut lire — c'est une
  variable de ce shell — donc la règle ne le vise pas ; (b) il *appartient* à la
  phrase (« dit tout haut » → « dit une fois », [64]) ; et surtout (c) c'est la
  **seule** opération d'interface que le préambule appelle nu, donc la seule cible
  possible du test « ended before it took its locks » de [71] côté drain et du même
  côté run. L'avoir déplacé aurait laissé ce test vert en ne testant plus rien —
  et la mutation `71 the guard is armed only once the locks are taken` serait
  devenue VACUOUS sans qu'aucune suite ne le dise.

- **La base de journal n'a pas bougé** (`RALPH_JOURNAL_BASE`, `router_journal_base`),
  et c'est ce que le ticket demandait : lire un compteur de lignes n'écrit rien.
  Les trois commentaires qui la justifiaient *par* « le préflight journalise »
  disaient maintenant faux ; les trois sont réécrits. Le troisième est dans
  `.claude/lib/router.sh` — **écart de write-surface déclaré**, commentaire seul,
  aucune ligne de code touchée : la phrase de `router_journal_base` nommait le
  comportement que ce ticket supprime, et la laisser aurait été le premier
  faux-ami du prochain lecteur.

- **La symétrie de [71], tranchée : faite.** `loop.sh` a maintenant son garde de
  sortie — `LOOP__REACHED_THE_END`, `loop__on_exit`, code **7** — armé en tête de
  fichier **et** réarmé juste après les deux verrous, qui écrasent tout trap EXIT
  en posant le leur. Pourquoi la faire plutôt que l'écrire : le `0` de `loop.sh`
  est le signal le plus cher du pack, et ce qui l'en protégeait était
  `[ -n "$reason" ]` dans `failures.sh`, c'est-à-dire un accident d'un garde dans
  un lib. **7 et pas 6** : 6 est le mur de budget ici. **7 et pas 3** : 3 est, chez
  le drain, un humain qui a quitté, c'est-à-dire une fin ordinaire.

- **Deux mesures faites en route, à ne pas redécouvrir.**
  1. *Un `${N:?}` ne rend pas toujours le même code, et le trap voit autre chose
     que le shell.* Sans trap, le pré-verrou sort en **1** ; avec le trap,
     `$?` vaut **0** à l'entrée du handler (le statut de la dernière commande
     exécutée) et le garde convertit. Post-verrou sans réarmement : **0**, parce
     que c'est `state_locks_release` du trap des verrous qui a rendu le statut.
     Les deux cas sont donc bien couverts par « seul un `0` est converti », mais
     la raison n'est pas la même des deux côtés.
  2. *Un run refusé par `run_lock_acquire` n'atteint jamais `loop__on_exit`* : le
     verrou d'arbre a déjà posé son propre trap EXIT par-dessus. La mutation
     « le garde réécrit toute sortie et pas seulement un zéro » visait d'abord ce
     test-là et est sortie **VACUOUS** ; elle vise maintenant la frontière vide
     (`exit 5`), qui est le plus court chemin vers une sortie non nulle avec le
     garde en place. La fenêtre de trois lignes entre `tree_lock_acquire` et le
     réarmement est **nommée dans le code** plutôt que fermée : la fermer voudrait
     dire que les verrous cessent de poser leur trap, ce qui est ce qui les rend
     sûrs pour tous leurs autres appelants.

- **Les sondes de la passe, rejouées sous forme déterministe.** `q4` avait besoin
  de deux processus vivants ; les tests livrés démarrent le **second point d'entrée
  depuis la session** du premier, qui la tient forcément pendant que le premier a
  les deux verrous. Côté run, le faux `claude` tourne dans un *worktree* et doit
  rejoindre l'arbre principal (`$RALPH_SHIM_STATE/project-dir`) — sans ça il
  drainerait la copie de `.scratch/` de son worktree et ne mesurerait rien. Quatre
  tests, deux par sens (le cas + son témoin appairé), plus deux pour le garde de
  sortie.

- **Piège de test rencontré** : `assert_file_contains` fait un `grep -qF`, donc un
  `"\t"` écrit dans une assertion est deux caractères et ne matche jamais une
  vraie tabulation — assertion vide, test vert. La ligne du journal s'asserte avec
  `"$(printf 'ambiguous-id\tturns=0\t…')"`.

### Contrainte écrite dans [70]

Le préambule de `loop_main` porte maintenant une règle écrite : il peut lire,
imprimer, et garder ce qu'il a trouvé dans une variable de son shell — il ne peut
**pas** écrire là où un second point d'entrée lit. Le témoin de [70] se pose donc
soit derrière les deux verrous, soit en pure lecture. C'est ce que ce ticket devait
trancher pour lui.

### Contrainte écrite dans [64]

Sa garantie devient : « une fois par run **et** par drain, à l'écran dans tous les
cas, et dans `run.log` pour le point d'entrée qui tourne vraiment ». Le point
d'entrée refusé le dit à l'écran et n'écrit rien. `tracker_finding_said` reste avec
la phrase, pas avec la ligne de journal.
