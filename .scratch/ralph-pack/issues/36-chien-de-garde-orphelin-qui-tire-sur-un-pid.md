# 36 — Un chien de garde orphelin tire sur un pid qu'il ne vérifie plus

**What to build:** Donner au chien de garde du gate le garde-fou que le reaper de session a déjà. `gate__watchdog` dort `GATE_TIMEOUT` secondes — 1800 par défaut — puis appelle `proc_kill_tree` sur les pids qu'on lui a passés, sans jamais vérifier que son run est encore vivant ni que ces pids portent encore ce qu'il visait. Un run tué de force pendant le gate le laisse en vol : une demi-heure plus tard, un processus qui n'appartient plus à personne envoie un TERM à un arbre de pids qui, sur une machine qui tourne, peut avoir changé de propriétaire. `monitor__reaper`, écrit pour le même office par [23], vérifie `kill -0` à chaque seconde et abandonne dès que sa cible est partie ; le chien de garde ne vérifie rien.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/monitor.sh`, `.claude/lib/proc.sh`, `test/gate.bats`, `test/proc.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Un délai qui tire vérifie d'abord qu'il tire sur ce qu'il visait : sa cible est vivante, et son run est encore là pour vouloir sa mort. Les deux processus de délai du pack — le chien de garde du gate et le reaper de session — répondent à la même exigence, et l'écart entre eux aujourd'hui est écrit dans le ticket, pas laissé au lecteur.
- [x] Un run mort n'a plus de délai qui tire en son nom. Le mécanisme est tranché ici — surveiller le pid parent, ou faire porter la garde par un `kill -0` sur le run — et il ne doit pas dépendre d'un fichier de `$TMPDIR` que la même violence emporte.
- [x] Ce que le pack laisse dans `$TMPDIR` quand il meurt de mort violente est nommé quelque part : un répertoire de gate par run tué, plus un témoin d'ignore par itération interrompue. Le nettoyage opportuniste existe déjà pour les templates du harnais (`find -mtime +7`), pas pour le pack.
- [x] Le test prouve les deux moitiés séparément : que le tir n'a plus lieu quand le run est parti, et qu'il a toujours lieu quand le run est là et que la branche dépasse — sinon le correctif désarme le délai et la suite reste verte, ce qui est le faux vert de [28] (« un délai de fake porte la mutation d'un autre ticket »).

## Comments

- **Origine : passe transversale du 03/08/2026** (fenêtre [06], [23], [28], [29], [30], [31]), question 4 posée sur [23] et [28] : *que laissent derrière eux les processus que ces tickets ont ajoutés ?* Trouvé en comptant les répertoires de gate laissés dans `$TMPDIR` par la suite de tests — quarante, dont un portant un marqueur `timed-out` écrit **trente minutes** après les verdicts qui l'accompagnaient. Ce marqueur est la signature d'un chien de garde qui a survécu à son run et a tiré.

  *Sonde A — le chien de garde survit à un run tué de force.* `GATE_TIMEOUT=8`, `TEST_CMD='sleep 45'`. Le run est tué par `kill -9` dès que la suite est en vol :

  ```
  run pid: 29309        répertoire de gate: /…/ralph-gate.kr8t5h
  TEST_CMD en vol: 1
  run vivant après -9: non
  timed-out juste après: non          TEST_CMD encore en vol: 1
  timed-out 9 s plus tard: OUI — un chien de garde orphelin a tiré
  TEST_CMD après le tir: 0
  répertoire laissé derrière: oui (scope.rc typecheck.rc tests.out timed-out …)
  ```

  Neuf secondes après la mort du run, un processus sans parent écrit dans un répertoire que plus personne ne nettoiera et tue un arbre de processus. Au défaut livré, ce serait une demi-heure après.

  *Sonde B — sur quoi il tire.* `gate__watchdog 1 marker <pid>` avec, à la place d'une branche, un processus innocent qui a lui-même un enfant :

  ```
  innocent=28085 enfant=28087
  innocent vivant:   NON — tué
  son enfant vivant: NON — tué
  ```

  `proc_kill_tree` descend l'arbre par construction — c'est ce qu'on lui demande, et c'est ce qui rend le tir aveugle coûteux : ce n'est pas un signal à un processus, c'est un signal à une descendance. Rien dans le chemin ne demande si le pid est encore celui qu'on visait.

- **Pourquoi c'est plus qu'une fuite.** Les pids sont réutilisés. Sur macOS ils montent à 99999 puis rebouclent, et une demi-heure d'activité suffit largement sur une machine de développement. Le pack promet de tourner sur une machine dont on lui a dit qu'elle ne portait rien de précieux ([24] : « le rempart est l'isolation de l'hôte ») — mais cette phrase couvre ce qu'une **session** écrit, pas ce que le pack tue lui-même après sa propre mort. C'est une garantie que personne n'a écrite : le pack n'a pas d'effet en dehors du dépôt et de sa fenêtre de vie.

- **Ce que le reaper fait et que le chien de garde ne fait pas.** `monitor__reaper` dort par pas de une seconde et sort dès que `kill -0` échoue : sa cible morte, il ne tire pas. Sa fenêtre est bornée par `SESSION_KILL_GRACE` (30 s), et son objet est précisément de tuer une cible qui refuse de mourir, donc il ne peut pas se contenter de « la cible est partie » pour renoncer — il le fait quand même, correctement. `gate__watchdog` dort la même façon (par pas de une seconde, pour la même raison écrite dans son commentaire) et n'a jamais reçu la vérification. Les deux fonctions ont été relues ensemble par [23], qui a déplacé `proc_kill_tree` en primitive partagée et s'est demandé si le **KILL** devait suivre côté gate (réponse sondée : non, un sous-shell meurt du TERM). La question de la liveness n'a pas été posée dans le même mouvement.

- **Piège pour qui livrera ça, sondé pour ne pas l'écrire à l'envers.** Le réflexe est `kill -0 "$PPID"`, et il vise le mauvais processus : dans un `( … ) &` de bash 3.2, ni `$$` ni `$PPID` ne sont remis à jour (vérifié sur 3.2.57 — `$$` et `$PPID` du sous-shell sont ceux du shell qui l'a forké). Donc `$PPID` répond le parent **du run** — le terminal, qui survivra joyeusement au run — et c'est `$$` qui vaut le pid du run, directement lisible depuis le chien de garde sans rien capturer. La bonne primitive est celle qui a l'air fausse.

  Ça ne suffit pas pour autant : un run mort dont le pid a été recyclé rend `kill -0` vrai à nouveau, donc un garde-fou qui ne s'appuie que sur un numéro déplace le problème d'un cran. Deux pistes à peser dans le ticket : `$$` plus une vérification de la cible (deux `kill -0` valent mieux qu'un, sans être une preuve), ou un canal qui meurt avec le run — un descripteur hérité dont la lecture rend EOF quand le dernier écrivain disparaît, ce qui est POSIX, sans dépendance, et insensible au recyclage. La seconde est la seule qui ne repose pas sur un numéro.

  Second piège : ne pas transformer ça en « le chien de garde renonce dès que la cible est partie ». Une branche partie n'a pas besoin d'être tuée, mais le chien de garde a un second effet — écrire `$dir/timed-out`, que `gate__aggregate` lit pour dire « red (timed out) » plutôt que « red (no verdict) ». Un correctif qui sort trop tôt fait perdre la cause dans le rapport.

- **Ce que ce ticket ne prétend pas fermer.** Un `kill -9` sur le run est par définition hors de portée de tout code du run ; ce qui est en portée, c'est ce que les processus que le run a laissés font **ensuite**. La fuite de `$TMPDIR` en fait partie ; le tir, surtout.

- **Note posée par [32], livré le 04/08/2026 : le témoin d'ignore laissé dans `$TMPDIR` n'est pas qu'un répertoire à balayer.** La remise de la frontière d'ignore tombe maintenant sur les trois sorties d'une itération (gate, re-slice, classification d'échec), donc le seul cas où `.git/info/exclude` reste élargi est un run **tué** — et son témoin meurt avec lui. Un nettoyage opportuniste de `$TMPDIR` retenu ici ne doit donc pas être lu comme « on récupère l'état » : le témoin d'un run mort ne sert à rien à personne, la frontière élargie, elle, sera épinglée par le run suivant. C'est écrit comme une limite structurelle dans `docs/frontiere-de-confiance.md` (il faudrait un état qui survive au run, et le seul qui existe est le tracker, que la session écrit) — à ne pas rouvrir par inadvertance en croyant qu'un fichier de `$TMPDIR` peut le porter.

- **Contrainte pour [13].** Plusieurs itérations concurrentes veulent plusieurs chiens de garde, donc plusieurs tireurs en vol : un tir aveugle par worktree, et une machine où les pids des branches d'un run sont ceux des branches d'un autre run une minute plus tard. La garde de ce ticket est un préalable à la concurrence, pas un complément.

- **Contrainte pour [19].** L'installeur est le seul composant qui tourne hors de la boucle ([31]) : si un nettoyage opportuniste de `$TMPDIR` est retenu ici, c'est lui qui a le droit de le faire au démarrage d'un run, pas une itération.

## Livré le 04/08/2026

- **Le mécanisme tranché : le lien de parenté, et pas un pid.** Les deux pistes du ticket étaient « `$$` plus une vérification de la cible » et « un canal qui meurt avec le run ». Aucune des deux n'a été prise telle quelle, et les deux sondes qui l'ont décidé valent d'être gardées.

  *Contre le numéro.* Un run tué par un parent qui ne le récolte pas reste un **zombie**, et un zombie répond `kill -0` exactement comme un vivant — sondé le 04/08/2026 avec un parent perl qui n'appelle jamais `wait` : `kill -0` réussit, `ps -o state=` dit `Z`. Un garde-fou bâti sur `kill -0 $$` aurait donc cru à un run mort depuis des minutes, dans le cas précis où le run a été tué. Et pour les cibles c'est pire, parce que ça n'attend même pas la mort du run : bash récolte ses jobs de fond de façon asynchrone, donc une branche finie libère son numéro **pendant que le run vit**, et `kill -0` sur la cible répond oui pour l'inconnu qui l'a hérité.

  *Contre le descripteur hérité.* Séduisant sur le papier — EOF quand le dernier écrivain disparaît, POSIX, insensible au recyclage — et faux ici pour une raison de plomberie : un fd ouvert par `exec` n'est pas `close-on-exec`, donc **toute** la descendance du run en hérite. Dans la sonde A du ticket (run tué, `TEST_CMD` orphelin toujours en vol) l'écrivain survit à son run, l'EOF n'arrive pas, et le chien de garde tire quand même : le correctif ne referme pas le défaut qu'il vise. Le rendre correct demanderait de fermer le fd à chaque site de spawn — `gate__start`, `session_spawn`, `lenses_review` — c'est-à-dire de recopier une primitive autant de fois qu'elle est appelée, ce que [25] a déjà facturé une fois.

  *Ce qui a été pris.* Le **lien de parenté**, qui donne les deux propriétés d'un coup. Un processus n'est jamais reparenté qu'à init, et ça se produit à la mort du parent et non à sa récolte : « mon parent est encore celui de l'armement » ne peut donc être ni hérité avec un numéro ni mis en défaut par un zombie. `proc_countdown` **découvre** qui il sert au lieu de se le faire dire — le shell qui forke un délai est celui qui veut le tir — et chaque délai ne tire que sur une cible qui répond encore au parent auquel elle répondait à l'armement. Sondé : reparentage observé à la seconde suivante d'un `kill -9`, `parent-of-self` passant de 27112 à 1.

- **Le piège du ticket, vérifié dans les deux sens.** `$$` vaut bien le pid du run depuis un `( … ) &` et `$PPID` le terminal (rejoué sur 3.2.57), donc la primitive qui a l'air fausse est bien la bonne — mais aucune des deux ne répond « moi », et bash 3.2 n'a pas de `BASHPID`. D'où `proc_self` : une substitution de commande forke depuis le shell courant, donc le `$PPID` du `sh` qu'elle exécute *est* ce shell. Elle répond par la variable `PROC_SELF` et pas sur stdout, et ce n'est pas un goût : `self="$(proc_self)"` forkerait un sous-shell de plus et rendrait le pid de celui-là.

- **Le second piège, honoré : le marqueur n'est pas conditionnel.** Le chien de garde écrit `$dir/timed-out` dès que le délai expire avec son armeur vivant, avant de regarder s'il reste quoi que ce soit à tuer. Renoncer plus tôt ferait perdre la cause — `gate__aggregate` lit ce fichier pour dire « red (timed out) » plutôt que « red (no verdict) », et une branche qui dépasse est le cas où les deux sont vrais. Une entrée de mutation le tient (`36 a deadline that fires at nobody loses the cause`), et elle rougit par le test où *rien* n'est tué.

- **Ce que le reaper de session gagne, et ce que ça coûte.** L'écart entre les deux délais n'a jamais été une question de soin : celui-ci renonçait déjà sur une cible partie, ce qui bornait à une seconde la fraîcheur de son numéro, là où le chien de garde ne vérifiait rien et dormait `GATE_TIMEOUT`. Même faute, deux ordres de grandeur d'écart. Il gagne quand même les deux gardes, parce que la propriété « un run mort n'a plus de délai qui tire en son nom » vaut mieux comme propriété du pack que comme jugement au cas par cas — et parce que [13] va multiplier les délais en vol par le nombre de worktrees. **Le prix, assumé** : une session qui a reçu son TERM dans l'instant d'avant la mort de son run n'est plus KILLée trente secondes plus tard, donc elle survit orpheline en brûlant du quota. C'est déjà ce qui arrive à *tout autre* instant où un run est tué, faute de reaper en vol : ce KILL était un accident de calendrier, pas une promesse.

- **AC 3, tranchée : nommer, pas balayer.** `gate_leftovers` compte au démarrage de chaque run les `ralph-gate.*` et `ralph-ignore.*` de `$TMPDIR` **de plus d'un jour**, et le dit dans `run.log`. Trois décisions dedans. *Où* : dans `gate.sh`, parce que c'est ce module qui fabrique les deux répertoires et que leurs noms sont à lui — une liste recopiée dans `loop.sh` aurait été la faute de [28] (« un harnais qui énumère le pack à la main »). *L'âge* : le pack verrouille un arbre et pas une machine ([22]), donc un run d'un autre dépôt a parfaitement le droit de posséder un `ralph-gate.*` tout neuf en ce moment. *Pas de balayage* : la contrainte écrite ici pour [19] dit que c'est à l'installeur de le faire, et elle est respectée à la lettre. La note de [32] est honorée aussi — la ligne ne prétend rien récupérer, et le tableau de la frontière dit que la frontière d'ignore élargie d'un run tué reste élargie.

- **La question de la frontière de confiance, posée sur la ligne neuve.** `gate_leftovers` lit `$TMPDIR`, et `$TMPDIR` est exactement la zone dont le tableau dit « rien ne juge ce qu'une session y écrit ». Une session peut donc fabriquer mille `ralph-gate.*` datés d'hier et faire mentir le compte. Ce n'est pas un trou parce que **ce n'est pas un contrôle** : la ligne annonce, elle ne juge rien, ne rougit rien et ne supprime rien — un humain lit un nombre faux dans un journal, ce qui est le pire que ça puisse produire. La confondre avec une garantie serait précisément l'erreur que ce document existe pour empêcher, et c'est pour ça que la ligne est écrite dans le tableau comme une fuite de disque nommée et pas comme une garde. Le corollaire vaut aussi pour qui voudra la faire évoluer : le jour où quelque chose *agit* sur ce compte — un balayage ([19]) — l'entrée devient un chemin qu'une session choisit, et il faudra dire qui garde cette zone.

- **Ce que le test compte, et pourquoi il y a trois répertoires dans la fixture.** L'assertion est « 2 » avec deux vieux répertoires et un neuf. Sans le neuf, la mutation qui retire `-mtime +0` serait restée verte : le run annonce **avant** de fabriquer le moindre répertoire à lui, donc rien dans la fixture n'aurait produit de troisième ligne. C'est exactement la question que [32] a laissée en corollaire — quel chemin de code produirait la deuxième, et est-ce que ma fixture le lui permet.

- **Ce que les tests couvrent, et l'endroit où ils ne peuvent pas aller.** Trois tests pour le gate (le tir n'a pas lieu quand le run est parti ; il n'a pas lieu sur un pid qui a changé de mains ; il a **toujours** lieu quand le run est là et que la branche dépasse), un pour la primitive partagée, un pour le reaper. Le « changement de mains » est mis en scène par un shell intermédiaire qu'on tue — la vraie cause, un pid réémis, ne se commande pas. Et une chose n'est couverte par aucune mutation, dite ici plutôt que passée sous silence : la supériorité du **lien** sur `kill -0` dans le cas du run zombie. La mettre en scène demanderait un run que son parent ne récolte pas, et le parent est ici un bash qui récolte ses jobs tout seul. Elle est sondée, pas testée.

- **La sonde A rejouée sur un vrai run, dans les deux sens.** Les tests unitaires appellent `gate__watchdog` à la main ; la sonde d'origine passait par la boucle entière, et c'est celle-là qu'il fallait refaire. `GATE_TIMEOUT=8`, `TEST_CMD='sleep 45'`, `kill -9` sur le run dès que la suite est en vol, puis quatorze secondes d'attente :

  ```
                     marqueur timed-out    TEST_CMD après l'échéance
  code d'avant [36]        1               tué — un chien de garde orphelin a tiré
  code livré               0               vivant
  ```

  Le premier tour n'est pas un souvenir : le corps pré-[36] a été remis en place le temps de la sonde, et il reproduit la trouvaille du ticket à l'identique. Un correctif dont la sonde d'origine n'a pas été rejouée avec l'ancien code à côté ne prouve que la moitié verte de son test. Et les deux tours laissent la même chose derrière eux — un `ralph-gate.*` et un `ralph-ignore.*` dans `$TMPDIR` — ce que ce ticket nomme au lieu de le balayer.

- **Ce que la passe de mutation complète a trouvé, et que la passe filtrée ne pouvait pas trouver.** Les huit entrées `36` étaient `ok` lancées seules ; dans `bash test/mutate.sh` en entier, « a deadline fires at a pid that changed hands » est revenue **VACUOUS**. La faute n'est pas dans le correctif, elle est dans la façon dont le test lisait le monde : le chien de garde **écrit son marqueur avant d'envoyer le moindre signal**, donc attendre le marqueur, c'est se réveiller dans la fenêtre où un tir ordonné n'a pas encore atterri. Sur une machine chargée cette fenêtre est assez large pour que la cible soit encore vivante, et le test mesurait la charge de la machine au lieu du pack. Deux corrections, et les deux comptent : se synchroniser sur la **fin du processus de délai** (le `wait` du run de paille rend la main quand le chien de garde a fini, donc un tir aurait forcément été ordonné avant), puis asserter la vie de la cible **sur trois secondes** et non à un instant, parce qu'ordonner un signal et voir la cible partie ne sont pas le même moment. Le test jumeau du reaper avait la même faiblesse sans l'avoir montrée — corrigé aussi, avant qu'une passe future ne la trouve à ma place.

- **Contrainte pour [13], mise à jour.** La garde est là, donc la concurrence n'hérite plus d'un tireur aveugle par worktree. Ce dont elle hérite en revanche : `proc_countdown` s'appuie sur le fait que le shell qui forke un délai est celui qui veut le tir. Un ordonnanceur qui armerait un délai depuis un shell autre que celui qui a forké les cibles casserait la garde de la cible sans casser celle du run — et le symptôme serait un délai qui ne tire jamais, donc un run qui pend, pas un faux vert.

- **Contrainte pour [10].** Le reçu d'audit a maintenant une ligne de plus à connaître au démarrage d'un run (`N temporary director(ies) from earlier runs…`), et c'est le seul endroit du pack qui parle de ce qui vit hors du dépôt.

- **Passe transversale du 06/08/2026 : la même question, sur le processus que ce ticket n'a pas regardé.** Ce ticket a rendu les deux *délais* révocables — un ordre différé se révoque en regardant qui l'a donné, jamais un numéro — et la ligne « Le pack n'agit plus quand le run est mort » du tableau a été écrite à partir de là. Elle est fausse du troisième processus : depuis [13] l'itération elle-même est un sous-shell forké, elle porte tout ce qui écrit, et rien ne lui demande si son pilote existe encore. Sondé : `kill -KILL` sur le pilote, et vingt secondes plus tard le ticket est `resolved`, le travail est commité et `HEAD` a bougé. C'est [44], et le correctif y réutilise la primitive de ce ticket (`proc_countdown` / le lien de parenté) plutôt que d'en écrire une seconde.
