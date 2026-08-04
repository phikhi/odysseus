# 36 — Un chien de garde orphelin tire sur un pid qu'il ne vérifie plus

**What to build:** Donner au chien de garde du gate le garde-fou que le reaper de session a déjà. `gate__watchdog` dort `GATE_TIMEOUT` secondes — 1800 par défaut — puis appelle `proc_kill_tree` sur les pids qu'on lui a passés, sans jamais vérifier que son run est encore vivant ni que ces pids portent encore ce qu'il visait. Un run tué de force pendant le gate le laisse en vol : une demi-heure plus tard, un processus qui n'appartient plus à personne envoie un TERM à un arbre de pids qui, sur une machine qui tourne, peut avoir changé de propriétaire. `monitor__reaper`, écrit pour le même office par [23], vérifie `kill -0` à chaque seconde et abandonne dès que sa cible est partie ; le chien de garde ne vérifie rien.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/monitor.sh`, `.claude/lib/proc.sh`, `test/gate.bats`, `test/proc.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Un délai qui tire vérifie d'abord qu'il tire sur ce qu'il visait : sa cible est vivante, et son run est encore là pour vouloir sa mort. Les deux processus de délai du pack — le chien de garde du gate et le reaper de session — répondent à la même exigence, et l'écart entre eux aujourd'hui est écrit dans le ticket, pas laissé au lecteur.
- [ ] Un run mort n'a plus de délai qui tire en son nom. Le mécanisme est tranché ici — surveiller le pid parent, ou faire porter la garde par un `kill -0` sur le run — et il ne doit pas dépendre d'un fichier de `$TMPDIR` que la même violence emporte.
- [ ] Ce que le pack laisse dans `$TMPDIR` quand il meurt de mort violente est nommé quelque part : un répertoire de gate par run tué, plus un témoin d'ignore par itération interrompue. Le nettoyage opportuniste existe déjà pour les templates du harnais (`find -mtime +7`), pas pour le pack.
- [ ] Le test prouve les deux moitiés séparément : que le tir n'a plus lieu quand le run est parti, et qu'il a toujours lieu quand le run est là et que la branche dépasse — sinon le correctif désarme le délai et la suite reste verte, ce qui est le faux vert de [28] (« un délai de fake porte la mutation d'un autre ticket »).

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
