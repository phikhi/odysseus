# 70 — Les deux preuves que le dossier montre sont écrites par une session jugée

**What to build:** Le dossier du drain envoie un humain lire trois preuves. `run.log` porte sa réserve depuis [67]. Les deux autres — la ref `refs/heads/failed/<id>` et le reçu d'audit `receipts/<feature>/<id>.md` — sont écrites par un **run AFK**, dans deux zones qu'aucun contrôle du chemin AFK ne regarde : une ref n'est un chemin d'aucun arbre, et l'arbre principal n'est pas le worktree que le scope-guard juge. Une itération **verte** peut créer, déplacer ou détruire l'une et l'autre, et rien — ni le gate, ni le scope-guard, ni le rollback, ni le reçu, ni l'épinglage de [66] — ne dit un mot.

**Blocked by:** 72

**Write-surface:** `.claude/loop.sh`, `.claude/lib/failures.sh`, `.claude/lib/gate.sh`, `.claude/lib/receipt.sh`, `.claude/lib/router.sh`, `test/gate.bats`, `test/failures.bats`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** human-loop, forensics, trust-boundary

- [ ] Une itération dont la session a écrit, déplacé ou détruit un `refs/heads/failed/*` **le fait dire**, dans le run où ça s'est passé. Ce que ça coûte — le guichet du drain suivant, la preuve perdue — est nommé, pas seulement compté.
- [ ] Même chose pour le reçu d'audit : un fichier apparu, réécrit ou effacé sous `receipts/<feature>/` que le pack n'a pas écrit est nommé par le run.
- [ ] Le dossier du drain ne présente plus le reçu comme une preuve nue : il porte la même sorte de réserve que `router_journal_lines`, ou bien quelque chose atteste réellement sa provenance. Les deux sont acceptables ; ce qui ne l'est pas est de le montrer sans dire lequel des deux est vrai.
- [ ] `docs/frontiere-de-confiance.md` cesse de dire que ce qu'une session écrit dans `.git/` « n'est vérifié par rien » sans dire **qui le lit** : la ligne nomme le lecteur (le guichet et le dossier du drain) et ce qui le tient.
- [ ] Une entrée de mutation par garantie livrée, plus les témoins appairés (le même run vert sans contrefaçon, et un run qui écrit une **vraie** ref et un **vrai** reçu, qui ne doit rien faire dire).

## Comments

- **Trouvé par la passe transversale du 07/09/2026** (`../passe-transversale-07-09.md`, §1 et §3). Sondes : `../sondes/passe-07-09/q1-*.bats` et `q3-*.bats`.

- **Mesuré** (`q1`), la ref :

  | | |
  |---|---|
  | Q1a — une itération **verte** dont la session fait `git update-ref refs/heads/failed/20-decision <commit>` | `tests=green typecheck=green scope=green lang=green`, ticket `resolved`, run **rc=0**. **0** mot d'une ref au run, **0** au reçu. Le drain suivant : desk **`admit` → `arbitrate`**, dossier « `git log -p failed/20-decision` » |
  | Q1b — témoin appairé, le même run sans la ref | desk `admit`, « there is none. nothing ever ran on this ticket » |
  | Q1c — l'autre sens, la même itération verte **efface** une ref d'un run précédent | la ref est partie, **0** mot, et le drain affirme « nothing ever ran on this ticket » sur un ticket réellement jugé |

- **Mesuré** (`q3`), le reçu :

  | | |
  |---|---|
  | Q3a — une itération **verte** dont la session écrit `receipts/<feature>/20-decision.md` dans l'arbre principal | run **rc=0**, **0** mot. Le dossier le présente comme le reçu d'audit — « verdicts, findings, and the zones nothing judged » — avec **0** réserve, et ajoute la phrase qui envoie l'humain vers l'autre objet contrefaisable (« `failed/20-decision` is a ref and survives ») |
  | Q3b — témoin appairé, le même run sans le reçu forgé | « receipt none was kept for this ticket » |

- **Pourquoi les quatre contrôles du chemin AFK regardent ailleurs, ensemble.** Le scope-guard, le rollback, le scellement et le témoin d'ignore sont tous construits sur des **trees git du worktree de l'itération**. `refs/heads/*` vit dans le répertoire git **commun**, qu'un worktree partage : un `git update-ref` depuis le worktree écrit dans l'arbre principal, et aucun chemin ne le nomme. `receipts/` est un chemin, mais de l'**arbre principal**, que `git worktree list` nomme à qui le demande — le harnais de test le dit en toutes lettres depuis [13]. Ce que le gate compare est le worktree, deux fois.

- **L'épinglage de [66] ne mord pas, et c'est structurel.** Il compare la photo prise quand le drain prend le ticket à celle prise au retour de la session routée. Une contrefaçon posée par un run **avant** le drainage est dans la photo de base : `router_branch_note` se tait, correctement au sens de son propre contrat. C'est le résidu V1 de [66] atteint par l'autre bout — là-bas la contrefaçon survit **au** drainage et le drainage suivant l'épingle ; ici elle n'a besoin de survivre à rien, elle arrive déjà épinglée.

- **Le mécanisme qui manque existe déjà dans le pack, une fois, et c'est le modèle** : [14] copie `LEARNINGS.md` dans `$TMPDIR` sous un `mktemp` que le pilote n'exporte pas, **avant qu'aucune session n'existe**, sert le prompt depuis la copie et détecte une réécriture de l'arbre principal (« is not what this run last wrote »). Le pack sait donc témoigner d'un fichier de l'arbre principal à l'échelle d'un run. Il le fait pour le seul objet de cette famille que **la boucle** lit. Les deux que la boucle **montre à un humain** n'ont rien.

- **Trois formes possibles, à trancher dans ce ticket** — et le choix a un précédent immédiat, [68], qui a écrit trois sorties et en a retenu une :

  1. *Un témoin par run*, sur le modèle de [14] : `loop_main` épingle l'espace de noms `refs/heads/failed/*` et l'état de `receipts/<feature>/` à son démarrage, et compare à la fin. Nomme, ne remet rien. C'est le moins cher et c'est ce que [72] rend plaçable.
  2. *Un témoin par itération*, autour de chaque session : plus précis — il nomme **quelle** itération a écrit — et il coûte deux mesures de plus par itération, dont une sur `for-each-ref` que [66] a déjà écrite (`router__failed_refs`, à remonter d'un module si elle sert aux deux).
  3. *Une réserve côté drain seulement* : le dossier dit du reçu ce qu'il dit déjà du journal. Le moins cher de tous et le plus honnête sur ce qu'il n'achète pas — il ne détecte rien, il arrête juste de faire croire.

  Les trois sont défendables ; ce qui ne l'est pas est de livrer (1) ou (2) **sans** (3), parce qu'un témoin par run ne dit rien d'une contrefaçon posée par un run que personne n'a fait tourner depuis.

- **Ce qui est déjà tranché et qu'il ne faut pas rouvrir : rien n'est remis.** L'argument est celui de [66] mot pour mot et il vaut pour les deux objets — ce drain n'est l'auteur ni des refs ni des reçus, le commit qu'une ref nommait peut être inatteignable, et une remise qui invente est un second auteur pour un état que personne n'a mesuré. Et rien ne **refuse** : la posture de [69], [67], [66] et [68] tient ici aussi, un garde qui pourrait arrêter un run ou un drainage sur une ref donnerait à une session un `git update-ref` pour renvoyer chez lui l'humain venu vider le puits.

- **Le troisième objet de la même liste, nommé et non sondé :** `docs/playthroughs/<feature>.md`. Écrit par le pack dans l'arbre principal ([11]), lu par un humain le matin, atteignable par une session jugée exactement comme le reçu. Rien dans le pack ne le relit et le dossier ne le montre pas, donc il ne porte pas le défaut mesuré ici — mais il est dans la même zone, avec le même mécanisme absent, et un correctif qui l'oublierait laisserait la liste plus étroite que son critère ([31], [45]).

- **Contrainte héritée de [72]** : c'est [72] qui décide où le préambule de `loop_main` a le droit d'écrire et d'épingler avant les verrous. L'épinglage de la forme (1) va exactement là. `Blocked by: 72` pour cette raison et pour aucune autre.

- **Arête dure vers [18], et elle a deux moitiés.** [66] avait écrit la première dans [18] : *un backend distant qui déplace la trace forensique déplace une preuve, qui doit être lue à travers un épinglage pris avant la session routée.* Celle-ci ajoute la seconde : sur un backend distant, **le reçu est une PR** ([10] et l'en-tête de `lib/tracker.sh` le disent), c'est-à-dire un objet qu'une session peut atteindre par le réseau, et `tracker_receipt_path` rend un emplacement que ce ticket-ci apprend à ne plus présenter nu. [18] doit dire ce qui atteste la provenance d'un reçu distant, ou dire que rien ne l'atteste.

- **Contrainte pour [10]** : la provenance du reçu est une garantie sur ce que le pack **écrit**, pas sur ce qu'un lecteur **trouve** à cet emplacement. La phrase de `receipt.sh` (« it does not read `run.log`: that file lives under `.scratch/`, which no check in this pack guards ») reste vraie et n'est plus suffisante — depuis [68] elle est même à moitié fausse pour `spec.md`, une ligne à relire dans le même passage.

- **Piège de sonde.** Une session d'itération atteint l'arbre principal par `git worktree list --porcelain | awk '/^worktree /{print $2; exit}'`, et les refs sans rien faire du tout. Et il faut un ticket `ready-for-agent` en plus du ticket du puits, sinon le run sort sur une frontière vide et n'ouvre aucune session.

- **Place dans la file (proposée par la passe du 07/09) : troisième, collé à [18].** La plus grosse surface des trois (`loop.sh`, `failures.sh`, `receipt.sh`, `router.sh`) et l'arête dure vers [18], qui rouvre les deux objets juste après. Même raison qui avait fait coller [64] puis [66] à [18]. Ordre proposé : [71] → [72] → [70] → [18] → [19].
