# Passe transversale du 07/09/2026

Neuvième passe. Faite sur `main` à `050bf55` (merge de [68]), avant [18].
Quatre livraisons depuis celle du 06/09 : [69] `88619b0`, [67] `b8240ea`,
[66] `650f636`, [68] `050bf55`.

Sondes conservées : `sondes/passe-07-09/` (README avec le verdict de chacune).
**Ni `.claude/` ni `test/` touchés** → la baseline de [68] tient telle quelle
(`run.sh` 758/0/6 skips, `mutate.sh` 770/0) et les deux gates n'ont pas été
rejoués.

---

## La racine

> **Six tickets ont durci le drain contre la seule session qu'il ouvre
> lui-même. Tout ce qu'il décide, tout ce qu'il montre et tout ce qu'il écrit
> vient pourtant de l'autre point d'entrée — et entre les deux il n'y a ni
> épinglage, ni verrou pris à temps, ni contrat qui dise ce qu'une opération a le
> droit de refuser.**

La passe du 06/09 avait trouvé le symétrique : *tout ce que le pack épingle, il
l'épingle autour d'une session d'itération AFK, et la session routée n'est
entourée de rien*. [55], [56], [58], [61], [66], [67] et [68] ont refermé ça,
objet par objet : les trois champs, l'arbre, le tracker, les refs `failed/*`,
`spec.md`, le journal. Chacun de ces mécanismes prend son instantané **au moment
où le drain prend le ticket** et le compare **au retour de la session routée**.

C'est exactement la fenêtre où la session routée écrit. Ce n'est aucune des
trois autres :

| ce que le drain fait | de qui il le tient | ce qui le tient |
|---|---|---|
| il décide du guichet sur `refs/heads/failed/<id>` | d'un **run AFK** | rien : l'épinglage de [66] compare l'avant-drain à l'après-drain, et la contrefaçon est **antérieure** (§1) |
| il montre le reçu d'audit comme la preuve du verdict | d'un **run AFK** | rien, et sans même la réserve que ses deux voisines portent (§3) |
| il écrit `run.log` | **lui-même**, avant les verrous | rien : le refus « un seul écrivain ici » tombe **après** l'écriture, dans les deux sens (§4) |
| il remet un ticket voisin que la session a bougé | **lui-même** | une opération de l'interface qui refuse en **tuant le shell** — et le drain sort `0`, « le puits est vide » (§2) |

Les deux premières lignes sont la même phrase que [66] a écrite pour la ref, lue
à l'envers : la session routée « n'a ni worktree, ni scope-guard, ni gate, ni
rollback », donc on l'épingle. La session d'itération a les quatre — **et une ref
n'est un chemin d'aucun arbre, et l'arbre principal n'est pas le worktree que le
scope-guard juge**. Les quatre contrôles regardent ailleurs, ensemble, et rien ne
le disait.

Le pack sait pourtant déjà faire ce qui manque, et l'a fait une fois : [14]
prend une copie de `LEARNINGS.md` dans `$TMPDIR` **avant qu'aucune session
n'existe** et détecte une réécriture dans l'arbre principal. Il le fait pour le
seul fichier de cette famille que **la boucle** lit. Les deux qu'elle **montre à
un humain** n'ont rien.

---

## 1. Une session jugée écrit la ref forensique sur laquelle le drain décide — ticket [70]

[66] a épinglé `refs/heads/failed/*` autour de la session routée. La moitié
manquante est celle qui les **produit** : `failures_preserve_attempt` les écrit,
et **rien dans `loop.sh`, `gate.sh` ni `failures.sh` ne les relit jamais** —
`router.sh` est le seul lecteur de tout le pack, et il est dans le drain.

Une itération AFK tourne dans un worktree, et `refs/heads/*` vit dans le
répertoire git **commun** : un worktree y écrit comme l'arbre principal.

**Mesuré** (sonde `q1`) :

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q1a | une itération **verte** dont la session fait `git update-ref refs/heads/failed/20-decision <commit>` | `tests=green typecheck=green scope=green lang=green`, `01-alpha -> resolved`, run **rc=0**. Le run dit **0** mot d'une ref, le reçu **0**. La ref survit. Le drain suivant : desk **`admit` → `arbitrate`**, et le dossier envoie l'humain lire `git log -p failed/20-decision` |
| Q1b | témoin appairé : le même run vert, sans la ref | desk **`admit`**, « branch there is none. nothing ever ran on this ticket » |
| Q1c | l'autre sens : la même itération verte **efface** une ref écrite par un run précédent | la ref est partie, le run dit **0** mot, et le drain affirme « there is none. **nothing ever ran on this ticket** » sur un ticket qu'un run a réellement jugé |

**L'épinglage de [66] ne mord pas ici, et c'est structurel** : il compare la
photo prise quand le drain a pris le ticket à celle prise au retour de session.
Une contrefaçon posée par un run **avant** le drainage est dans la photo de
base. `router_branch_note` se tait — correctement, au sens de son propre
contrat. C'est le résidu V1 de [66] atteint par l'autre bout : là-bas la
contrefaçon survit **au** drainage et le drainage suivant l'épingle ; ici elle
n'a même pas besoin de survivre à quoi que ce soit, elle arrive déjà épinglée.

---

## 2. Le drain meurt sur son propre garde et sort `0` — ticket [71]

`router_protect_tracker` remet un ticket **voisin** que la session routée a
bougé. La remise est `router__put_back`, qui appelle `tracker_mark_escalated
<id> "$was_esc"`. `was_esc` est une **valeur de champ**, lue sur le ticket.

`tracker_local_mark_escalated` (ligne 315) est écrite ainsi :

```sh
local id="$1" reason="${2:?tracker: an escalation needs a reason}"
```

`${2:?}` n'est pas un `return` : dans un shell non interactif c'est une **sortie
du shell**. Et depuis [67] cette fonction est appelée **dans le shell du drain**
et non plus à travers un `moved="$(…)"`.

**Mesuré** (sonde `q2`), un ticket voisin dans le puits **sans** `**Escalation:**` :

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q2c | une session routée sur `20-decision` met `21-second` à `resolved` | le drain **meurt** en pleine remise. `rc = 0` — dont son propre en-tête dit *« 0 the sink is empty: everything in it was drained »*. `20-decision` est toujours `ready-for-human`, **`21-second` est `resolved`**, `run.log` est **vide** (pas une ligne, pas même le `drain-session`), et les deux verrous sont relâchés |
| Q2d | témoin appairé : le même voisin **portant** `**Escalation:** decision` | remis, nommé, `tracker-drift restored` journalisé, drain rc=3 |
| Q2b | témoin appairé : deux sessions, aucune n'écrit le voisin | silence, **0** ligne de dérive, rc=3 |

**C'est un faux vert livré, et le cas est ordinaire.** `capability_propose` est
le producteur unique du puits pour le palier capacité, le palier rétro et
`playthrough__escalate` ; il écrit `**Status:** ready-for-human` et
`**Blocked by:** None`, **et aucun `Escalation:`**. Ce sont exactement les
tickets du guichet `request`, c'est-à-dire ceux que le puits a été construit pour
recevoir. Il suffit qu'il y en ait un dans le puits et qu'une session routée
touche son `Status:` — l'écriture même que [58] existe pour attraper.

**Le commentaire du pack affirme le contraire du comportement** :
`router_protect_tracker` écrit « a ticket that was in this sink without an
`Escalation:` comes back with an empty one ». Il ne revient pas : il tue le
drain.

**Ce que [67] a hérité sans le savoir.** Avant [67], l'appel était
`moved="$(router_protect_tracker "$id")"` — un sous-shell. Un `${:?}` y tue le
sous-shell et rien d'autre (mesuré : la substitution rend le vide, l'appelant
survit, rc 0). Le rapport était perdu, le drain vivait. [67] a sorti l'appel de
la substitution — pour la bonne raison, le témoin de journal — et a transformé un
rapport perdu en drain mort qui annonce un puits vidé. C'est la question 4 de
`CLAUDE.md` dans sa forme la plus pure : le défaut n'était faux dans aucun des
deux tickets pris isolément.

**Les dix-neuf autres `${N:?}` du pack ont été inventoriés** : tous prennent un
argument d'appelant — un id, un nom de champ, un prompt — jamais une valeur lue
sur un ticket. Et
`failures.sh` appelle `tracker_mark_escalated` sous un `if [ -n "$reason" ]` :
le chemin AFK ne peut pas atteindre cette sortie.

---

## 3. Le reçu d'audit que le dossier montre est un fichier qu'une session jugée écrit — ticket [70]

`router_dossier` envoie l'humain lire trois preuves. Depuis [67] l'une des trois
— `run.log` — porte sa réserve (« Read them, do not rely on them »). Depuis [66]
la deuxième est épinglée autour de la session routée. La troisième est présentée
nue :

```
  receipt  <chemin> — verdicts, findings, and the zones nothing judged.
           It references git objects a `gc` may already have collected;
           `failed/<id>` is a ref and survives.
```

`tracker_local_receipt_path` est un `[ -f ]` sur
`<racine>/receipts/<FEATURE>/<id>.md`. C'est un chemin de l'**arbre principal**,
que `git worktree list` nomme à qui le demande — le harnais de test le dit en
toutes lettres depuis [13].

**Mesuré** (sonde `q3`) :

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q3a | une itération **verte** dont la session écrit `receipts/demo/20-decision.md` dans l'arbre principal | run **rc=0**, `01-alpha -> resolved`, **0** mot du reçu forgé. Le dossier du drain le présente comme le reçu d'audit — « verdicts, findings, and the zones nothing judged » — avec **0** réserve, et ajoute la phrase qui envoie l'humain vers l'autre objet contrefaisable |
| Q3b | témoin appairé : le même run vert, sans le reçu forgé | « receipt none was kept for this ticket » |

Le reçu est le document dont [10] a fait sa garantie de **provenance** :
« assemblé par le process qui a mesuré l'itération ». La provenance tient pour le
document que le pack écrit. Elle ne dit rien du fichier qu'un lecteur trouve à
cet emplacement, et le seul lecteur est un humain à qui le drain le présente sans
un mot de réserve.

§1 et §3 sont le même trou sur deux objets, et c'est pour ça qu'ils font **un
seul ticket** : ce qui manque n'est pas deux gardes, c'est un témoin du côté du
run — la place que [14] occupe déjà pour `LEARNINGS.md`.

---

## 4. Les deux points d'entrée journalisent avant de savoir s'ils ont le droit de tourner — ticket [72]

`loop_main` et `human_loop_main` sont écrits dans le même ordre, et les deux
commentaires expliquent pourquoi la base du journal est prise **avant** le
préflight : « a base read on the first append is already past whatever went
missing before it ». Correct. Ce qui n'a pas été posé est ce que le préflight
**écrit** : depuis [64], `*_report_tracker_findings` journalise les constats du
tracker — et il tourne **avant les deux verrous**, dans les deux fichiers.

**Mesuré** (sonde `q4`), un tracker portant deux tickets sur le numéro `20`
(l'état que [27] et [47] existent parce qu'il arrive) :

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q4a | un run AFK tourne, un humain lance un drainage | le drain écrit `20 ambiguous-id … action=drain` dans `run.log`, **puis** découvre que l'arbre est tenu (`rc=1`). Le run se termine en accusant : « the run journal does not hold exactly the 3 line(s) this run wrote … **do not believe it about this run** » |
| Q4b | témoin appairé : le même run, sans drainage à côté | **0** accusation |
| Q4c | l'autre sens : un drainage tient les verrous, un run AFK démarre | le run écrit `20 ambiguous-id … action=none`, **puis** refuse (`rc=1`). C'est le témoin du **drain** qui accuse, avec la même phrase |

Les deux témoins sont ceux de [10] et de [67], et leur raison d'être est de dire
« une session a réécrit ton journal ». Ici c'est **le pack lui-même** qui l'a
réécrit, par son second point d'entrée, en faisant précisément ce que ces deux
mécanismes ne savent pas distinguer d'une contrefaçon.

Inerte sur les décisions — [10] et [67] tiennent tous deux que le journal n'est
une autorité pour personne — et pas inerte sur le lecteur : c'est le corollaire
du 24/08 (« une ligne qui dit *je n'ai pas pu* doit être nette de ce qu'elle a
pu ») lu sur le signal le plus cher du pack. Un humain qui a vu cette phrase une
fois pour rien ne la relira plus.

Et le déclencheur est le plus banal des gestes : lancer le drainage pendant que
le run tourne.

---

## Angles sondés et disculpés — ne pas les resonder

- **Les six jeux de sondes de vérification des tickets livrés rejouent à
  l'identique** : `ticket-64` (deux constats, une fois chacun ; repli à 13 sur le
  nom apparu pendant le run ; silence à zéro), `ticket-65` (les trois tickets
  contrefaits ne comptent plus, et la phrase de la borne les nomme), `ticket-66`
  (V1 à V5), `ticket-67` (V1 à V5), `ticket-68` (V1 à V4), `ticket-69` (V1, V2).
  Aucune régression : chaque verdict est celui que son ticket a consigné.
- **`router_branch_note` et `router_spec_note` font ce qu'ils annoncent.** Une
  ref ou un `spec.md` écrit **pendant** le drainage est nommé, journalisé, et le
  témoin appairé se tait. Ce qui n'est pas couvert est l'écriture **antérieure**,
  et le contrat de ces fonctions ne prétend pas la couvrir.
- **`LEARNINGS.md` n'est pas un trou, c'est le précédent.** [14] sert le prompt
  depuis une copie prise dans `$TMPDIR` avant la première session et détecte une
  réécriture de l'arbre principal. C'est le mécanisme que §1 et §3 réclament, à
  l'endroit où il existe déjà.
- **`run.log` porte sa réserve aux deux lectures** depuis [67], et le témoin AFK
  tient (Q4b).
- **Le chemin AFK ne peut pas atteindre la sortie de §2** : `failures.sh` appelle
  `tracker_mark_escalated` sous `if [ -n "$reason" ]`, et les trois raisons
  écrites sont des littéraux du pack.
- **Les dix-neuf autres `${N:?}` du pack prennent un argument d'appelant** — un
  id, un nom de champ, un prompt. Un seul site est piloté par une valeur lue sur
  un ticket, et c'est celui de §2.
- **`docs/playthroughs/<feature>.md` est de la même famille que le reçu** — écrit
  par le pack dans l'arbre principal, lu par un humain le matin — mais rien dans
  le pack ne le relit et le drain ne le montre pas. Nommé dans [70] comme le
  troisième objet de la même liste, pas sondé.

---

## Ce qui est écrit ailleurs

Écrit maintenant, parce qu'une ligne fausse dans le tableau attend un faux vert :

- `docs/frontiere-de-confiance.md` — la ligne `.git/` (les refs sont écrites par
  une session **jugée** et le chemin AFK n'a aucun lecteur), la ligne du reçu
  d'audit (la provenance ne dit rien du fichier qu'un lecteur trouve à cet
  emplacement), et la ligne « un artefact que le pack écrit lui-même dans l'arbre
  principal ».
- **[16]** — trois constats de plus : le drain écrit `run.log` avant les verrous,
  il meurt sur `router__put_back`, et les deux preuves qu'il montre viennent d'un
  run.
- **[10]** — la phrase de `receipt.sh` (« nothing in this pack guards that
  directory ») est à moitié fausse depuis [68], et le reçu lui-même est
  maintenant concerné par [70] : la provenance est une garantie sur ce que le
  pack **écrit**, pas sur ce qu'un lecteur **trouve**.
- **[11]** — `docs/playthroughs/<feature>.md` rejoint la liste des artefacts de
  l'arbre principal que rien ne témoigne.
- **[64]** — le constat qu'il journalise est écrit avant les verrous ; c'est ce
  que [72] déplace.
- **[66]** — son résidu V1 a un jumeau antérieur : la contrefaçon posée par un
  run arrive déjà dans la photo de base.
- **[67]** — sa réparation a déplacé un `${:?}` d'un sous-shell vers le shell du
  drain ; c'est [71].
- **[18]** — deux clauses d'interface de plus, écrites dans son ticket.

## L'ordre, validé par Philippe le 07/09/2026

**[71] → [72] → [70] → [18] → [19]**

Par le critère du dépôt — **minimiser la reprise**, jamais la gravité :

1. **[71]** — le seul **faux vert livré** des trois (un ticket `resolved` sans
   gate, et un `rc=0` qui annonce un puits vidé), la plus petite surface
   (`router.sh` + `tracker.sh` + `tracker-local.sh`), et sa clause d'interface —
   *ce qu'une opération a le droit de refuser, et sous quelle forme* — est ce que
   [18] écrira contre. Le précédent est [59], ordonné premier pour la même
   raison.
2. **[72]** — délié, deux fichiers, un seul mécanisme, et il **tranche où le
   préambule de `loop_main` a le droit d'écrire**. [70] pose son épinglage dans ce
   même préambule : livré derrière, il choisit sa place sous une règle déjà
   écrite ; livré devant, il la choisit deux fois.
3. **[70]**, collé à [18] — la plus grosse surface (`loop.sh`, `failures.sh`,
   `receipt.sh`, `router.sh`) et l'**arête dure** : un backend distant déplace le
   reçu vers une PR et la trace forensique hors d'une ref locale, donc [18] doit
   dire ce qui atteste l'une et l'autre. [66] avait déjà écrit la moitié « ref »
   de cette arête dans [18] ; [70] y ajoute la moitié « reçu ».

`Blocked by:` en conséquence, écrit le 07/09 après validation : `[71] None`,
`[72] None`, `[70] 72`, et `[18]` gagne `70` et `71` (soit
`02, 10, 64, 65, 66, 70, 71`). Écrit dans les trois tickets sous « Place dans la
file ».
