# 44 — Un run tué laisse une itération qui continue de livrer

**What to build:** Faire qu'une itération cesse d'agir quand le run qui l'a lancée n'existe plus. Depuis [13] une itération est un sous-shell forké qui **trappe TERM/INT à dessein** — c'est la promesse de [25] et [28], « l'itération en cours finit » — et qui porte tout ce qui décide : le gate, le commit durable, le repli sur la branche, le marquage du ticket. Le pilote, lui, porte tout ce qui *surveille* : la revérification des deux verrous à chaque tour, le journal, le compteur de stérilité, le plafond d'itérations. Tuer le pilote ne tue donc plus la partie qui écrit. Sondé : `kill -KILL` sur le pilote pendant qu'une session tourne, et vingt secondes plus tard — le run étant mort — le ticket est `resolved`, le travail est commité, **la branche a bougé**, `run.log` est vide et le worktree reste enregistré. La boucle a livré au nom d'un run qui n'existait plus, sans qu'aucune ligne nulle part ne le dise.

**Blocked by:** None

**Write-surface:** `.claude/loop.sh`, `.claude/lib/concurrency.sh`, `.claude/lib/proc.sh`, `test/concurrency.bats`, `test/claim.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Une itération dont le pilote a disparu n'écrit plus rien de durable : elle ne commite pas, ne déplace pas la branche, ne marque pas son ticket. Ce qu'elle fait à la place est une décision à écrire — s'arrêter net, ou finir son gate et rendre son résultat à un slot que personne ne lira — mais pas livrer.
- [x] Le lien de parenté est l'instrument, pas un pid : c'est la réponse que [36] a déjà payée et sondée pour les deux délais du pack (`proc_countdown` découvre qui il sert au lieu de se le faire dire ; un zombie répond `kill -0` comme un vivant, un numéro se réattribue). Une itération qui vérifie « mon parent est-il encore celui du fork » utilise la même primitive, et le fait de la réutiliser plutôt que d'en écrire une seconde fait partie du critère.
- [x] **Où** la question est posée est le cœur du ticket, pas un détail : il y a au moins trois points de non-retour dans une itération — le commit durable, le repli sous garde, le marquage du ticket — et un contrôle posé seulement à l'entrée laisse toute la fenêtre du gate. Écrire lesquels sont gardés et pourquoi les autres n'ont pas besoin de l'être.
- [x] Le repli refuse aussi de son côté : `concurrency_integrate` prend un garde dans le répertoire git commun, et un garde pris par un orphelin au nom d'un run mort est exactement ce que [22] refuse à un second run. Le CAS reste la garantie ; ce qui manque est que l'orphelin n'ait pas le droit de le tenter.
- [x] Le témoin appairé : le même `kill -KILL` sur le pilote **avant** que la session ne démarre, et le même run tué par un TERM ordinaire — dans le second cas l'itération doit toujours finir et marquer, sinon le correctif a défait [25] et [28]. *(Le premier des deux est staged autrement que littéralement — voir « Ce que le témoin appairé est devenu » plus bas.)*
- [x] La mutation vise le refus, et elle a besoin de sa jumelle ([36]) : toute entrée qui supprime le refus doit avoir une jumelle qui supprime la capacité d'agir, sinon un correctif qui n'agit jamais rend tout vert.
- [x] Le worktree et le slot d'une itération orpheline sont comptés au démarrage du run suivant, pas silencieux — `concurrency_leftovers` et `gate_leftovers` le font déjà, vérifier qu'ils couvrent ce cas précis.

## Comments

- **Origine : passe transversale du 06/08/2026**, trouvée en disculpant un test instable plutôt qu'en lisant du code. `a run killed mid-session leaves a claim, and the next run reclaims it and grinds the ticket` (claim.bats) échoue une fois sur deux, **sur `main` comme sur la branche**, avec deux symptômes différents : `expected 'resolved', got 'ready-for-human'`, et `The 01-alpha session edited the tracker itself (1 ticket file(s))` dans un test qui ne met en scène aucune édition de tracker. Les deux ont la même cause, et ce n'est pas de la flakiness.

  Ce test tue le pilote au `SIGKILL` puis tue le pid de la session enregistré par le faux `claude`. Depuis [13] il y a un troisième processus entre les deux — le sous-shell de `loop__iterate` — que personne ne tue. Il voit sa session mourir, classe l'échec, **écrit `01-alpha.md`**, et cette écriture tombe dans la fenêtre que le run suivant est en train de surveiller : le garde de [21] la lit comme l'œuvre de sa propre session, refuse le vert, et le ticket part au puits humain. Le test avait raison ; c'est le pack qui a changé sous lui.

  *Sonde H — ce que fait l'orphelin quand on le laisse finir.* Un ticket, une session qui écrit sa surface puis dort 5 s. `kill -KILL` sur le pilote dès que la session a démarré, **et rien d'autre n'est tué**.

  ```
  === juste après le SIGKILL sur le pilote ===
  01-alpha -> claimed
  HEAD: e96c6fe test: seed tracker
  shells du pack encore vivants: 1

  === vingt secondes plus tard, le run étant mort ===
  01-alpha -> resolved (claimed: )
  HEAD: 8957ada 01-alpha: iteration delivered (gate green)
  src/alpha.txt dans HEAD: 1
  run.log: (vide)

  === worktrees enregistrés ===
  …/project                      8957ada [main]
  …/T/ralph-worktree.g8Rghq      8957ada (detached HEAD)
  ```

  Et la sortie du pilote — un fichier que personne ne lit une fois le run mort — porte les lignes que l'orphelin a écrites après le décès : `tests=green typecheck=green scope=green lang=green`, `committed 1 path(s)`, `folded onto the branch`.

- **Ce que ça casse, et ce n'est pas seulement du bruit.**
  - **`run.log` est vide.** Le journal est écrit par `loop__finish`, dans le pilote. Une livraison faite par un orphelin n'a donc *aucune* trace : un humain qui lit le matin voit un run mort et une branche qui a avancé, sans une ligne pour relier les deux. C'est le pire cas pour [10].
  - **Les deux verrous ne sont plus revérifiés.** `run_lock_is_ours` et `tree_lock_is_ours` sont des contrôles du **pilote**, à chaque tour de boucle. L'orphelin n'en fait aucun. Un `SIGKILL` ne déclenche pas le trap EXIT, donc les verrous restent posés — mais `state_guard_take` reprend le garde d'un propriétaire mort, donc un run suivant démarre légitimement pendant que l'orphelin commite encore. C'est très exactement la destruction mutuelle que [22] existe pour empêcher, atteignable en tuant un run.
  - **Le tracker est écrit par deux runs à la fois.** L'orphelin marque un ticket que le run suivant a déjà repris par le balayage de liveness ([12]) — le pid du pilote est mort, donc le claim est réclamable — et re-claimé. Les deux marquent. C'est la moitié « flaky » du test ci-dessus.
  - **La branche bouge.** Le repli prend le garde d'intégration dans le répertoire git commun et fait son CAS ; le CAS empêche l'orphelin d'écraser le commit d'un frère, il ne l'empêche pas de poser le sien.

- **Pourquoi c'est neuf, et c'est la question 4 sous sa forme la plus pure.** Avant [13], une itération *était* le shell du pilote. Tuer le run arrêtait immédiatement tout ce que le pack écrivait ; ce qui survivait était le `claude` orphelin, et c'est écrit noir sur blanc dans le tableau depuis [36] — « une session survit orpheline en brûlant du quota », une fuite de quota et rien d'autre. Depuis [13] ce qui survit n'est plus une session qui brûle du quota, c'est **le pack lui-même**, avec le droit de commiter. Aucun ticket n'est faux pris isolément : [25] et [28] ont raison de vouloir qu'une itération finisse, [13] a raison de la forker, [36] a raison de ne pas tirer au nom d'un run mort. C'est leur composition qui livre.

- **Piège attendu, et il est le vrai contenu du ticket.** « L'itération finit ce qu'elle a commencé » ([25], [28]) et « une itération n'agit pas pour un run mort » sont en tension directe. La ligne à tracer n'est pas entre « finir » et « ne pas finir » mais entre **mesurer** et **livrer** : un gate qui tourne sans son pilote ne fait de mal à personne, un commit et un marquage si. Le correctif qui refuserait tout dès la mort du pilote reprendrait à [25] et [28] ce qu'ils ont payé, et il faudra écrire pourquoi la version retenue ne le fait pas — ou pourquoi elle le fait quand même.

- **Contrainte pour [10].** Une livraison sans ligne de journal est le trou que ce reçu ne peut pas combler après coup. Tant que [44] n'est pas livré, `run.log` n'est pas une source complète de ce qui est arrivé au dépôt.

- **Contrainte pour [38].** Ce ticket est la cause du premier des deux tests instables du dossier ; l'entrée correspondante n'a pas de correctif de synchronisation à trouver, elle attend celui-ci.

- **Contrainte pour [19].** Le balayage doit ramasser les worktrees d'itération orphelins comme les répertoires de gate, et les compter avant de les enlever : ici c'est un run mort qui l'a laissé, mais un worktree enregistré une seconde plus tôt appartient à un run bien vivant. *Toujours valable après livraison, et un peu plus large : un run tué laisse maintenant aussi son **répertoire de slot** (`ralph-slot.*`) — le pilote qui le balayait est justement celui qui est mort. `gate_leftovers` le compte déjà, avec son `-mtime +0`.*

## Livraison — 07/08/2026

- **Ce qui tient, et par quoi.** Une itération prend son propriétaire à l'entrée et le **reçoit** au lieu de le découvrir : `proc_owner_take "$$"`, `$$` étant le pilote dans tous ces sous-shells (bash 3.2 n'a pas de BASHPID). Découvrir aurait été le bug : un pilote mort entre le fork et la première ligne du fils aurait été **remplacé par init**, et tous les refus auraient ensuite été armés contre un shell qui ne meurt jamais. La vérification est `proc_owner_gone`, c'est-à-dire la primitive de [36] et pas une seconde — `proc_countdown` passe par la même paire depuis ce ticket, et son entrée de mutation a été réancrée sur la nouvelle ligne.

- **Les cinq points, et pourquoi ceux-là.** L'AC parlait de trois points de non-retour ; il y en a cinq à garder et un à ne pas garder, et la liste est ce que le ticket a réellement produit.

  | Où | La fenêtre que ça ferme |
  |---|---|
  | entrée de `loop__iterate` | avant les quatre snapshots et le spawn : un run déjà mort ne coûte pas une session |
  | après la session | avant `failures_protect_tracker`, `failures_quarantine_strays` et le gate — donc avant toute écriture dans le tracker **et** avant la moindre lentille. C'est le point où atterrit la sonde H |
  | après le gate, branche verte | avant le commit durable, le repli et le marquage, qui sont contigus. La fenêtre est `GATE_TIMEOUT`, 1800 s au défaut |
  | après le gate, branche rouge | avant `failures_handle` : `Failures:`, escalade, ref `failed/<ticket>` dans le répertoire git **commun**, re-slice qui crée des tickets et spawne une session |
  | retour de `concurrency_integrate` | avant `tracker_unclaim` : rendre le ticket est une écriture comme une autre |
  | `concurrency_integrate` lui-même | l'attente du garde d'intégration, jusqu'à 60 s, que `state_guard_take` accorderait à un orphelin |

  Ce qui n'a **pas** besoin d'être gardé, et c'est la moitié de la réponse : le **commit durable de [07]** est pris sur le `HEAD` détaché d'un worktree jetable. Ce n'est pas un point de non-retour, et le test le sonde là où ça se vérifie — dans le worktree que le run mort a laissé, encore sur le commit d'avant.

- **Ce que l'orphelin ne fait pas non plus : rendre le ticket.** Le claim reste où le kill l'a laissé, et le balayage de [12] le reprend au run suivant. C'est le comportement d'avant [13], et c'est ce que `claim.bats` assertait déjà. Un orphelin qui désassignerait serait un second écrivain à côté du run qui vient de reprendre le ticket — la moitié « flaky » de ce test-là.

- **Ce que le témoin appairé est devenu.** Le second (TERM ordinaire) est le test qui existait déjà, `a stop request lets the iterations in flight finish`, et c'est lui que nomment les jumelles de mutation. Le premier — `kill -KILL` **avant** que la session démarre — n'est **pas** staged littéralement, et il faut dire pourquoi : entre le fork et `proc_owner_take` il n'y a qu'un `cd`, donc la fenêtre est de quelques microsecondes et un test qui viserait cet instant mesurerait l'ordonnanceur, ce que ce dépôt a déjà payé ([38]). La propriété est couverte à deux endroits à la place : `proc.bats` sonde le primitif — un fils dont le forkeur est mort avant qu'il ne prenne son propriétaire refuse (`take.dead` vaut 1, `take.alive` vaut 0 dans le même test, sinon un refus universel passerait) — et `concurrency.bats` sonde le call site sous un `ps` cassé, où l'itération s'arrête **avant le spawn** : `claude_call_count` vaut 0, le pilote rend le ticket et le run sort en 4.

- **La sonde H rejouée, et ce qu'elle rend maintenant.** Même mise en scène que l'originale (session tenue sur un fichier, `kill -KILL` sur le pilote, rien d'autre tué) : `HEAD` inchangé, ticket toujours `claimed`, pas de `Failures:`, **un seul `claude`** alors qu'une lentille était configurée — le garde est devant le gate — et la ligne `the run that forked this iteration is gone`. Le run suivant compte le worktree laissé (`iteration worktree(s) of earlier runs are still registered`), reprend le claim par le balayage et livre.

- **Ce que ça rend à [38].** `a run killed mid-session leaves a claim, and the next run reclaims it and grinds the ticket` (claim.bats) n'est plus intermittent : trois passes consécutives vertes après correctif. L'entrée [38] correspondante n'avait pas de correctif de synchronisation à trouver, elle attendait celui-ci ; il reste l'autre famille (`a stop request lets the iterations in flight finish`) et `23 a TERM nobody answers`.

- **Ce que ça rend à [10].** `run.log` reste **vide** pour un run tué — le journal est écrit par le pilote — mais il n'y a plus de livraison à raconter. La contrainte « tant que [44] n'est pas livré, `run.log` n'est pas une source complète de ce qui est arrivé au dépôt » tombe : ce qui n'est pas dans le journal n'est plus dans le dépôt non plus.

- **Ce qui reste ouvert, et c'est une décision et pas un oubli.** Une **édition du tracker faite par la session** dans l'instant où son run meurt n'est plus défaite : `failures_protect_tracker` est derrière le deuxième garde. Restaurer serait écrire un ticket que le run suivant est peut-être déjà en train de reprendre, et [42] a montré ce que deux écrivains font à ce fichier. Un kill laisse ce qui a été écrit avant lui — c'était déjà vrai avant [13], la session mourant avec son run. Ce qui rattrape ce cas est le balayage de [12], **qui ne relit pas la write-surface du ticket qu'il rend** : une session qui s'est accordé `Write-surface: *` puis dont le run est tué laisse cette ligne au run suivant. Propriétaire naturel : [12] pour le balayage, [21] pour la surface. Écrit dans le tableau de la frontière.

- **Deux fuites inchangées**, nommées ici parce qu'un lecteur les cherchera : la session orpheline continue de brûler du quota (la boucle ne la tue pas, exactement comme à tout autre instant où un run est tué — c'est écrit depuis [36]), et le flux de session `.scratch/<feature>/.session.*.jsonl` reste dans l'arbre, le `rm -f` de fin d'itération n'étant pas atteint. Les deux étaient déjà vraies avant ce ticket ; aucune n'est une écriture que quelqu'un pourrait prendre pour une livraison.

- **Écart de write-surface, assumé.** Le ticket déclarait `test/concurrency.bats` et `test/claim.bats` ; la livraison touche aussi **`test/proc.bats`**, parce que la primitive a deux garanties propres (un propriétaire illisible, un propriétaire déjà mort) et que leur place est dans le fichier du module. `test/claim.bats` n'a en revanche **pas** été touché : le test qui rougissait par intermittence est passé vert sans être réécrit, ce qui est le bon signe — il avait raison, c'est le pack qui avait changé sous lui.

- **Piège pour qui reprendra ce code.** `proc_owner_gone` répond « pas parti » quand `PROC_OWNER` n'est pas posé, et c'est délibéré : un appelant qui n'a pris personne n'est surveillé par personne (`concurrency_integrate` appelé directement par un test, par exemple). C'est une porte qu'un correctif pourrait franchir en silence — supprimer le `proc_owner_take` et tous les refus s'évaporent — d'où les jumelles de mutation, et d'où l'entrée `44 an iteration never records which run forked it`, qui vise exactement cette porte.
