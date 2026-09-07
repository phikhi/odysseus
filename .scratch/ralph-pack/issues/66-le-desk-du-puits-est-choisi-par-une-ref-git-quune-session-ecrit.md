# 66 — Le desk du puits est choisi par une ref git qu'une session routée écrit, et efface

**What to build:** Épingler `refs/heads/failed/<id>` avec les trois champs que `router_pin` épingle déjà, et faire dire au drain ce qu'une session routée a laissé **hors de l'arbre de travail et hors de `issues/`** — les deux endroits que le garde nommé pour ça ne regarde pas.

**Blocked by:** 67

**Write-surface:** `.claude/lib/router.sh`, `.claude/human-loop.sh`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** human-loop, trust-boundary

- [x] `router_pin` épingle l'existence **et** la cible de `refs/heads/failed/<id>` avant que le dossier soit montré, comme il épingle `Escalation:` ([55]) et `Failures:` ([61]).
- [x] `router_desk` et `router_dossier` décident et racontent sur la valeur épinglée, jamais sur l'état du dépôt au moment de la lecture.
- [x] Une session routée qui **crée** une ref `failed/<id>` est nommée. Une session routée qui en **efface** une l'est aussi, et la phrase dit que la preuve est perdue — pas seulement qu'un chemin a bougé.
- [x] `router_tree_note` (ou son successeur) cesse d'être nommé comme le garde de « ce qu'une session a laissé hors de `issues/` » tant qu'il ne l'est pas : soit il couvre les refs et la zone de bookkeeping, soit le commentaire de `router_desk` cesse de le nommer et dit qui garde vraiment.
- [x] Une entrée de mutation par garantie livrée, plus le témoin appairé (une session qui n'écrit pas de ref ne doit rien faire dire au drain).

## Comments

- **Trouvé par la passe transversale du 06/09/2026** (`../passe-transversale-06-09.md`, §1). Sondes : `../sondes/passe-06-09/q1-*.bats`.

- **C'est [61] par l'autre bout, et [61] est cité dans le commentaire qui laisse la ref dehors.** `router_desk` distingue les trois arrivées de `decision` par deux preuves : l'existence de `refs/heads/failed/<id>` et la valeur de `Failures:`. [55] a épinglé `Escalation:` ; [61] a épinglé `Failures:` après avoir **mesuré** qu'une session routée qui s'ajoute `**Failures:** 1` envoyait la session suivante du même ticket de `admit` à `triage-host` — « two desks on one ticket, the second chosen by the first ». Le commentaire écrit ensuite, mot pour mot :

  > The `failed/<id>` ref is still read as it stands, and that is the boundary: pinning a git ref is a different mechanism, a routed session that writes one has left a branch behind it in the repository, and **`router_tree_note` is what looks at what a session left outside `issues/`**.

  `router_tree_note` lit `router__tree_dirt`, qui est `git diff --name-only HEAD` plus `git ls-files --others`, **moins `gate_is_bookkeeping`**. Une ref n'est pas un chemin de l'arbre de travail. La phrase nomme un mécanisme qui ne fait pas le travail.

- **Mesuré** (`q1`), session routée qui n'écrit **que** la ref, dans un drain réel :

  | | |
  |---|---|
  | Q1a — `git update-ref refs/heads/failed/20-decision HEAD` | desk **`admit` → `arbitrate`** ; le dossier suivant dit « branch failed/20-decision — the tree of the attempt, as it was. `git log -p failed/20-decision` » ; le drain a nommé **0 chemin** |
  | Q1b — témoin appairé, la même session sans la ref | desk **`admit`**, « branch there is none. nothing ever ran on this ticket » |
  | Q1c — `git update-ref -d` sur la ref d'une tentative **réellement jugée** | desk **`arbitrate` → `admit`** ; le dossier affirme « **there is none. nothing ever ran on this ticket** » ; **0 chemin nommé** |

- **Les deux sens ne coûtent pas la même chose, et c'est ce qui doit décider de la réparation.** Q1a est une **fausse route** : un humain envoyé au guichet `arbitrate`, avec la question, le traitement et le prompt de la session suivante qui vont avec — exactement le défaut de [61], réparable par un épinglage. Q1c est une **destruction de preuve** : la branche forensique est ce que le reçu envoie lire quand un ticket a vieilli dans le puits (`router_dossier` : « `failed/<id>` is a ref: it survives, and it is what to lean on for a ticket that has been in this sink for a while »), et un épinglage ne la rend pas. Ce qu'un épinglage achète sur Q1c est **de le dire** — le drain sait qu'il y avait une ref au début du ticket et qu'il n'y en a plus.

- **Ce que le tableau de frontière dit aujourd'hui** (ligne « Ce qu'une session écrit dans `.git/` ») : « le reste de `.git/` — refs, objets, `config` au-delà des clés que ces deux mécanismes épinglent — n'est vérifié par rien : le rempart est l'isolation de l'hôte ». C'était suffisant tant que **rien ne lisait une ref pour décider**. Depuis [16], une ref est l'entrée d'un contrôle. La ligne est à élargir en livrant.

- **Une session AFK atteint les mêmes refs**, et c'est à écrire plutôt qu'à découvrir : un worktree d'itération partage le répertoire git commun, donc `git -C <worktree> update-ref` écrit les mêmes refs que le pilote. Ce qui borne le cas AFK est que le gate juge l'arbre et pas les refs — donc l'itération n'en devient pas verte — mais la ref, elle, survit au rollback comme tout ce qui est dans `.git/`. Décider ici si la garantie visée est « le drain décide sur ce qu'il a épinglé » (suffisant) ou « les refs `failed/*` sont gardées » (plus large, et ce serait un ticket à soi).

- **Contrainte pour [18].** [18] porte déjà la remarque « `router_desk` distingue les trois arrivées de `decision` par les preuves […] la branche est une **ref git locale** ; sur un backend distant elle peut vivre ailleurs, et un ticket dont l'arbre de tentative est une PR fermée sera routé sur le guichet `admit` (« aucun run n'a jamais jugé ceci »), ce qui est faux. Si ce ticket déplace la trace forensique, il possède la question de savoir comment le routeur la trouve. » Ce ticket-ci ajoute la moitié qui manquait : **et qui l'épingle**. Un backend distant qui rend la trace forensique par une requête rend une preuve écrite par ce qu'une session peut appeler.

- **Piège de sonde.** Un drain rend 3 (« stdin ended ») dès que le script de réponses est épuisé — ce n'est pas un refus, ne pas asserter dessus. Et `printf '%s' "$out" | grep -c journal` compte le libellé du dossier : pour mesurer un silence il faut chercher la phrase exacte.

- **Place dans la file, validée par Philippe le 06/09/2026 : troisième**, derrière
  [67] et **immédiatement avant [18]**. C'est le point de convergence des trois
  premiers tickets de la passe (`router_pin` + `router_tree_note`), donc la plus
  grosse surface, et l'arête **dure** vers [18] : `[18] Blocked by:` porte
  maintenant `66`, parce qu'un backend distant qui déplace la trace forensique
  déplace une preuve, et qu'une preuve doit être lue à travers un épinglage pris
  avant la session routée. Collé à [18] pour la raison qui a fait coller [64] :
  le mécanisme est écrit et rempli dans la foulée plutôt que relu deux fois.
  Ordre complet retenu : [69] → [67] → [66] → [68] → [18] → [19].

- **Ce que [67] laisse à ce ticket, livré le 07/09/2026.** Quatre choses à hériter
  avant de rouvrir `router.sh`.

  1. **Une phrase du drain affirme désormais que rien ne garde cette zone.**
     `router__run_notes_caveat` dit, au-dessus des quatre mots du run, « `run.log`,
     under `.scratch/`, which nothing in this pack guards and nothing can ». Si ce
     ticket ajoute un garde qui **nomme** ce qu'une session laisse dans
     `.scratch/<feature>/`, cette phrase devient à moitié fausse le jour de la
     livraison — la relire est un AC de [66], pas un détail de rédaction. Même
     question pour la réserve jumelle de `router_journal_lines`, qui la porte
     depuis [16].
  2. **`router_journal` tient un témoin, donc tout nouvel appelant doit être dans
     le shell du drain.** `ROUTER__JOURNAL_WITNESS` est une variable du process ;
     un `router_journal` appelé depuis une substitution de commande, la droite d'un
     pipeline ou un `&` écrit la ligne dans le fichier et **pas** dans le témoin,
     et le drain se termine en s'accusant d'une réécriture que personne n'a faite.
     C'est ce qui a coûté à [67] de sortir `router_protect_tracker` de son
     `moved="$(…)"`.
  3. **`router_protect_tracker` imprime son propre préfixe `ralph: `** et est
     appelé comme une instruction (`router_protect_tracker "$id" || true`). Un
     ticket qui veut capturer sa sortie doit se demander d'abord où ses neuf
     `router_journal` atterrissent.
  4. **Un épinglage de refs se compare, il ne se journalise pas dans une boucle.**
     La posture que [67] a tenue et que [69] avait posée : ces mécanismes comptent
     et ne jugent rien — `router_journal_verify` ne change jamais le code de sortie
     du drain, parce qu'un refus donnerait à une session routée une ligne pour
     renvoyer chez lui l'humain venu vider le puits. Un garde de refs qui
     **refuserait** le drain casserait la même règle au même endroit.

- **Livré le 07/09/2026.** Ce qui a été construit, et surtout ce qui a été
  décidé de ne pas construire.

  **La question que le ticket demandait de trancher — « le drain décide sur ce
  qu'il a épinglé » ou « les refs `failed/*` sont gardées » — est tranchée sur la
  première.** Les refs ne sont pas gardées : rien n'en remet une, rien ne refuse
  un drainage sur une. Deux raisons, et elles sont écrites dans le code plutôt
  qu'ici seulement. Remettre une ref, c'est écrire un objet dont ce drain n'est
  pas l'auteur — `failures.sh` les écrit — vers un commit qui peut déjà être
  inatteignable ; c'est la ligne que `router__put_back` a tracée pour le tracker
  (« ce drain ne réécrit que ce qu'un verbe public définit »). Refuser, c'est
  casser la posture de [69] tenue par [67] au même endroit : ces mécanismes
  comptent et ne jugent rien, et un garde de refs qui pourrait arrêter le
  drainage donnerait à une session routée un `git update-ref` pour renvoyer chez
  lui l'humain venu vider le puits. La garantie plus large a un propriétaire
  naturel — [18] — et la clause est écrite là-bas.

  **Ce qui est dans `router.sh` :** `ROUTER__PINNED_REFS`, pris par `router_pin`
  au même appel que les trois champs, l'arbre et le tracker ;
  `router__failed_refs` (`git for-each-ref … refs/heads/failed/`, une ligne
  `<objectname><TAB><refname>`) ; `router__ref_target` et `router__pinned_ref`
  pour lire une liste ; `router_has_branch` qui répond sur l'épinglage pour le
  ticket épinglé et retombe sur le dépôt pour les autres ; et
  `router_branch_note`, appelée depuis `human_loop__session` comme une
  instruction, avec ses trois bras — créée, effacée, déplacée.

  **Trois décisions plus fines, chacune coûtant quelque chose :**

  1. **L'espace de noms entier, pas la ref du ticket.** L'AC ne demandait que
     `failed/<id>`. Une session routée sur `20-first` qui écrit
     `failed/21-second` déplace le guichet d'un ticket dont personne n'a parlé à
     l'humain — c'est la trouvaille de [58] sur le tracker, une zone plus loin, et
     `router__tracker_state` regarde déjà tous les tickets pour exactement cette
     raison. Le coût est un `for-each-ref` par ticket drainé.
  2. **L'épinglage décide et la présentation ne retombe pas.** `router__field`
     retombe sur le tracker pour un ticket non épinglé parce qu'un dossier doit
     montrer ce qui est sur le disque ; `router_has_branch` ne retombe **pas**
     pour le ticket épinglé, et c'est l'AC 2 : « ce qu'un humain lit et ce sur
     quoi le drain décide doivent être une seule valeur ». Le prix est visible et
     il est celui de l'épinglage lui-même : le menu est réoffert après une
     session, donc le prompt d'une **seconde** session sur un ticket nomme encore
     une ref que la première a effacée. Ce qui le dit est `router_branch_note`,
     entre les deux.
  3. **Un refus de git n'est pas un espace de noms vide** ([59]). Lu comme une
     liste vide, il transforme chaque ref épinglée en ref effacée, et la phrase
     qui va avec accuse quelqu'un d'avoir détruit une preuve. `router_pin` le lit
     comme vide — il dégrade alors vers la lecture d'avant ce ticket — et
     `router_branch_note` **refuse** et ne nomme rien. L'asymétrie est écrite dans
     `router__failed_refs` : c'est la faute que chacun des deux commettrait.

  **L'AC 4 est tenue par le second terme de son alternative.** `router_tree_note`
  ne couvre ni les refs ni `.scratch/<feature>/` et ce ticket ne le lui fait pas
  couvrir : le commentaire de `router_desk` cesse de le nommer et porte la carte
  de qui garde quelle zone — l'arbre (`router_tree_note`), `issues/`
  (`router_protect_tracker`), les refs (l'épinglage + `router_branch_note`),
  `run.log` (`router_journal_verify` pour le bloc du drain, la réserve pour le
  reste), et l'aveu que le reste de `.scratch/<feature>/` n'est gardé par rien et
  ne peut pas l'être. Le tableau de zones de `router__tree_dirt` pointe vers cette
  carte au lieu d'en tenir une seconde copie — deux auteurs pour une affirmation
  est exactement ce qui a produit la phrase fausse que ce ticket corrige.

  **Ce que [67] laissait à relire, point (a) : les deux réserves sont inchangées
  et c'est vérifié, pas supposé.** `router__run_notes_caveat` et sa jumelle dans
  `router_journal_lines` disent que rien ne garde `.scratch/<feature>/` et que
  rien ne le peut. Ce ticket met un garde sur les **refs**, qui sont dans
  `.git/` ; il n'en met aucun sur `.scratch/<feature>/`. Les deux phrases restent
  littéralement vraies, et la carte ci-dessus les redit au même mot près plutôt
  que de les contredire.

- **Mesuré après correctif** (`../sondes/ticket-66/verification.bats`), sur des
  drains et un run AFK réels :

  | | |
  |---|---|
  | V1 — la session crée `failed/20-decision` | guichet **`admit`** aux deux sessions, dossier « there is none », création **nommée** (1 ligne par retour de session) et journalisée `ref-drift created`. **Résidu mesuré** : la ref survit, donc le drainage **suivant** l'épingle et route sur `arbitrate` |
  | V2 — la session efface la ref d'une tentative jugée | guichet **`arbitrate`** tenu, la phrase nomme la ref **et sa cible** (`77f6db7…`) et dit « The evidence is lost, not moved ». Rien ne la remet : le drainage suivant dit « there is none », et c'est bien pour ça que la phrase doit le dire |
  | V3 — témoin appairé : une session qui écrit, **commite** et déplace un ticket voisin | **0** ligne de ref, **0** `ref-drift` dans `run.log`, **0** plainte du témoin de journal — et la dérive du tracker, elle, est journalisée (1). Le drain ne s'accuse pas |
  | V4 — un run AFK **réel** (`TEST_CMD=false`) écrit une vraie `failed/01-alpha`, puis un drain | **0** `ref-drift`. Le producteur du pack est épinglé comme une preuve légitime et le dossier envoie lire `git log -p failed/01-alpha` |
  | V5 — la ref est écrite sur `21-second` pendant que le drain est sur `20-decision` | nommée à l'écran et dans le journal sous **`21-second`**. **Résidu mesuré** : `21-second` reçoit quand même `arbitrate` dans ce drainage — son épinglage est pris *après* la session. Nommé, jamais défait : le sort que `router_protect_tracker` réserve déjà à `Failures:` |

- **Dix entrées de mutation** (`test/mutate.sh -f "66 "`), toutes `ok` : les deux
  moitiés de l'épinglage (pris / lu), les trois bras de la note, la phrase de la
  preuve perdue, le témoin appairé (la note qui parlerait sur un espace de noms
  intact), la note rétrécie au seul ticket drainé, l'appel remis dans une
  substitution de commande (le piège de [67] : le témoin de journal meurt dans le
  sous-shell et le drain s'accuse), et le refus de git lu comme un vide.

- **Ce qui reste ouvert ailleurs, écrit ici parce que personne ne relit un ticket
  clos.** Les deux résidus V1 et V5 sont des propriétés de « l'épinglage est par
  ticket », qui est la doctrine de `router_pin` et non un oubli : une base de
  comparaison à l'échelle du drainage entier fermerait V5 mais mettrait deux
  durées de vie dans la même structure. Si un ticket veut la fermer, c'est le même
  ticket que « les refs `failed/*` sont gardées », et il commence par relire
  `router_pin` en entier.
