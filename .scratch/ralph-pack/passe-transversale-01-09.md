# Passe transversale du 01/09/2026 — un refus de git est lu comme une réponse, et une phrase est prise pour un contrôle

Sixième passe. Cinq livraisons depuis celle du 31/08 ([54], [57], [55], [56],
[58]), seuil atteint, et Philippe avait tranché « [58] d'abord, puis la passe,
avant [11] ».

Méthode : rejouer les sondes « run réel » avec les questions 4 (*qu'hérite le
ticket suivant ?*) et 5 (*frontière de confiance*) de CLAUDE.md en tête, et
commencer par ce que les cinq livraisons ont **elles-mêmes écrit** comme resté
ouvert — une passe qui redécouvre ce qui est déjà consigné n'a rien mesuré.

**Aucune ligne de `.claude/` ni de `test/` n'a été touchée** (`git diff -- .claude
test` vide). La baseline des deux gates est donc celle de [58], inchangée :
`run.sh` 656/0/6 skips, `mutate.sh` 640/0.

Sondes conservées : `sondes/passe-01-09/`, README avec le verdict de chacune.

---

## Les deux racines

Les trois passes précédentes ont buté sur *« le pack juge ce qu'une session
écrit ; ce qui décide de ce que lui-même exécutera ensuite est moins gardé »*.
Celle-ci en trouve deux autres, une par point d'entrée, et elles se disent en une
phrase chacune.

> **A — Un refus de git est lu comme une réponse.** `git add` peut refuser. Deux
> lecteurs lisent ce refus comme une **valeur** : `gate_tree_snapshot` en fait un
> arbre, et `concurrency__replay` en fait une suppression. C'est la leçon de [34]
> — *un refus lu comme un vide* — appliquée ticket par ticket et jamais à la
> couche.

> **B — Le drain garde deux champs et en écrit cinq.** [55] a épinglé
> `Escalation:` et `Write-surface:`, [58] a restauré `Status:`. Ce qui garde
> `Failures:`, `Blocked by:` et le corps est **une phrase du prompt** — et cette
> phrase arrive à la session **amputée des deux noms de champ qu'elle existe pour
> dire**, parce que le heredoc qui la porte n'est pas cité.

Et une conséquence de A qui vaut d'être isolée, parce que ce dépôt la traite
comme la pire classe de défaut : **elle produit un faux livré**. Un ticket sort
`resolved`, `HEAD` n'a pas bougé, et la livraison de la session n'est nulle part.
C'est le défaut de [35] par une porte que [35] ne couvre pas.

---

## Trouvaille 1 — le refus que `gate_tree_snapshot` documente n'a jamais existé → **[59]**

Le commentaire de la fonction écrit son refus en toutes lettres :

> No `|| true`, unlike the branch below … **`set -e` takes the function down, the
> caller gets no tree**, and that is the refusal it needs — a tracker guard handed
> an empty tree instead would read it as "the session changed nothing".

Deux faits mesurés hors du pack avant d'écrire quoi que ce soit :

1. `git add -A` échoue **WHOLE** sur un fichier illisible et laisse l'index
   **vide** — `write-tree` rend `4b825dc…`, l'arbre vide, pas un arbre partiel ;
2. `x="$(f)" || x=""` **suspend errexit** sur toute l'extension dynamique de `f`
   (un `false` au milieu de `f` ne la tue pas).

Les **onze** appelants de `gate_tree_snapshot` sont de cette seconde forme. Le
refus n'est donc jamais rendu. Mesuré (`q2`) :

| | |
|---|---|
| `gate_tree_snapshot` sur un arbre à un fichier illisible | **rc=0**, 24 entrées, **toutes sous `.claude/`** (le forçage de `GUARDED_PATHS`, qui a son `\|\| true`), contre 26 sur HEAD |
| `gate_tree_snapshot "no/such/path"` | **rc=0**, `4b825dc…`, l'arbre vide — la branche même dont le commentaire décrit le refus |
| `failures_tracker_tree` avec un ticket illisible | arbre vide, `diff-tree` marque **`D` sur les deux** tickets |

Et le run réel, avec son témoin :

- **write-surface étroite** — trois itérations `scope=red` sous
  `wrote CONTEXT.md, outside the declared write-surface`. La session n'a **pas
  écrit** ce fichier : elle l'a rendu illisible. La livraison réelle
  (`src/one.txt`) n'est dans aucun arbre, n'est jamais jugée, n'est jamais
  commitée. Budget de retries brûlé, `Escalation: failed-impl`, guichet
  `implement` qui demande à un humain « Why is the code wrong » à propos d'un code
  qu'aucun gate n'a lu. **Zéro ligne nomme la cause.**
- **write-surface qui couvre les chemins amputés** — `scope=green`,
  `failures_make_durable` ne trouve rien à enregistrer (les chemins refusés
  laissent `newtree == head^{tree}`), `concurrency_integrate` rend 0 sur un fold
  sans objet, **`Status: resolved`, `HEAD` immobile, rien sur la branche**.
  `gate__nothing_delivered` ne peut pas l'attraper : il compare `base` à l'arbre
  jugé, et l'amputation *est* une différence.

Ce qui rend le déclencheur atteignable sans rien d'hostile : un fichier non
ignoré que l'utilisateur ne peut pas ouvrir. La zone ignorée est hors de portée
(`git add -A` ne l'ouvre pas), ce qui borne le déclencheur sans le fermer. Et un
cas y échappe même après correctif : un **répertoire** en mode 000 rend `rc=0`
avec un `warning`, et les chemins dessous manquent en silence — écrit dans le
ticket comme un AC à part.

---

## Trouvaille 2 — le rejeu retire de la branche le commit d'un humain, au défaut → **[60]**

[54] avait renvoyé sa question ici, en écrivant qu'aucun cas atteignable n'avait
été construit. Il l'est, et il tient en une phrase : **un humain qui commite dans
un autre terminal pendant qu'un run tourne** — ce que [56] vient précisément de
demander aux humains de faire.

Mesuré (`q1`), avec le témoin appairé :

- **Q1a** — un commit sur la branche pendant l'itération suffit à déplacer le tip,
  donc à prendre la branche **rejeu** à `MAX_PARALLEL=1`. La ligne imprimée est
  `folded onto the branch over a sibling's commit` — **il n'y a aucun frère**.
  La phrase de gravité de [54] (« le chemin replay n'est atteint qu'au-dessus de
  `MAX_PARALLEL=1`, donc l'installation par défaut n'y touche pas ») est fausse.
- **Q1b** — plus un chemin livré rendu illisible **après** l'arbre jugé, dans la
  fenêtre exacte que [54] nomme :

      ralph: 50-fold: src/shared.txt was approved by the gate and could not be
             staged — it is not in this commit
      ralph: 50-fold: folded onto the branch over a sibling's commit
      ralph: iteration 1: 50-fold -> resolved

  Après le run, `src/shared.txt` **n'existe pas dans `HEAD`** et est **absent de
  l'arbre de travail** : le fold l'a retiré de la branche, puis
  `concurrency__refresh` l'a supprimé du disque — correctement de son point de
  vue. Le commit d'un humain détruit des deux côtés par un run qui vient de dire à
  voix haute qu'il n'a pas pu stager ce chemin. C'est le symptôme de [50], une
  fonction plus loin.
- **Q1c** — sans le refus de staging, le fichier survit. La seule différence entre
  les deux est le refus.

---

## Trouvaille 3 — le drain garde deux champs, et la phrase qui garde les autres arrive mangée → **[61]**

`router_prompt` construit le prompt de la session routée avec un heredoc **non
cité**. Le paragraphe que [58] y a ajouté le 01/09 écrit les deux noms de champ
entre backticks. Ce que la session reçoit (`q7`) :

    the drain took every ticket's
     and  before this session started, puts any ticket it
    finds moved out of the human sink back where it was, …

et ce que l'humain voit à **chaque** session routée :

    …/router.sh: line 1015: Status:: command not found
    …/router.sh: line 1015: Escalation:: command not found

**Aucun test de `test/` ne cite ce paragraphe** — c'est ce qui a permis de le
livrer cassé.

Puis les trois champs que [58] a nommés « personne », mesurés comme des
mécanismes et pas comme une limite :

| Ce qui est écrit | Ce que ça déplace | Ce que le drain en dit |
|---|---|---|
| `Failures:` sur un ticket **voisin** de la frontière | son budget de retries entier : **1** itération et escalade immédiate, contre **3** au témoin | rien — `router_protect_tracker` ne compare que `Status:` et `Escalation:` |
| `Failures:` sur **son propre** ticket | le guichet de la session **suivante** sur le même ticket : `admit` → `triage-host`, donc la question, le traitement et tout le prompt | rien |
| le **corps** d'un ticket voisin | la ligne arrive **verbatim dans le prompt** de la session ouverte sur ce voisin par le même drain | rien |

La deuxième ligne est **mot pour mot l'argument par lequel [55] a épinglé
`Escalation:`** — « le menu est ré-offert après une session, donc un `Escalation:`
relu sur le fichier laisserait la session choisir le guichet … de la session
suivante ». [55] a écarté `Failures:` en écrivant qu'il « déplace la question
posée à un humain et ne peut déplacer aucune transition » : la seconde moitié est
vraie, la première est exactement ce que le pin existe pour empêcher.

---

## Ce qui est confirmé sans être neuf

Les deux autres résidus que [58] avait nommés tiennent tels qu'écrits. Ce que la
passe ajoute est mince mais réel, et c'est écrit dans [61] :

- **Le sign-off fabriqué.** Un `needs-triage` — la boîte de réception d'un humain,
  état que `router__put_back` ne sait pas écrire — tiré vers le puits avec
  `Escalation: sign-off` est nommé au premier drain ; le **drain suivant** épingle
  la raison depuis le fichier, offre `desk: approve` et un `s` le résout. Le
  dossier ajoute alors *« Nothing in this pack writes `sign-off` today. This
  ticket was put here by hand »*, qui se lit comme « un humain l'a mis là ». **La
  seule trace de la fabrication est la ligne `tracker-drift` de `run.log`,
  c'est-à-dire le fichier que le dossier lui-même déclare non fiable.** [58] avait
  mesuré ce cas sur `resolved`, dont il notait que le dégât net était borné ;
  `needs-triage` ne l'est pas.
- **Le `claimed` d'un run mort** résolu par une session : nommé une fois, puis
  `exit 5` côté AFK, et le balayage de [12] ne relit pas un résolu.
- **[56], le résidu de son propre tableau.** Un humain qui **quitte** le drain et
  lance un run à la main lit toujours un vert que personne ne nomme (`q8`) : la
  session routée éteint `TEST_CMD`, l'humain tape `q`, et un **autre** ticket sort
  `resolved` à la première itération. Nouveau depuis le 31/08 : `router_tree_note`
  **nomme** le fichier au retour de la session — le drain parle, le run se tait.

---

## Angles disculpés

- **Pas d'injection de commande depuis un ticket.** Le heredoc de `router_prompt`
  n'étant pas cité, la question suivante était de savoir si le corps d'un ticket —
  que ce prompt déclare lui-même être de la donnée écrite par une session — passe
  par cette expansion. **Non** : mesuré avec `` `id -u` ``, `$(id -u)` et `$HOME`,
  les trois arrivent verbatim. Le corps entre par une substitution de commande, et
  le résultat d'une substitution n'est pas re-analysé.
- **Les réparations de [55] et [57] tiennent**, sondes du 31/08 rejouées : la
  session routée écrit `Escalation: sign-off` et le ticket reste
  `ready-for-human` ; le drain s'arrête `rc=4` sur un verrou perdu.
- **[58] a répondu à la sonde `ticket-55/s1`** : `21-second` ressort
  `ready-for-human` et est nommé quatre fois, là où le 31/08 rendait `resolved` et
  `grep -c` zéro.
- **Deux sondes conservées sont périmées, et l'une pour une raison que personne
  n'avait écrite.** `p2` l'était par construction ([56] l'annonçait). `p3` l'est
  aussi : la réécriture de `.claude/ralph.config.sh` **salit l'arbre**, donc le
  refus de [56] tombe dessus et la réinjection n'a plus lieu — [56] a rétréci le
  trou de la config sur le chemin `r` sans que ce soit écrit nulle part. La
  question est reprise par `q8`, dans le seul ordre qui existe encore.

---

## L'ordre proposé

Le critère reste la **minimisation de la reprise**, jamais la gravité en
exploitation.

    [59] → [60] → [61] → [11] → [48] → [18] → [19]

- **[59] avant [60]** : les deux lisent le même refus de `git add`. [59] décide de
  ce que le pack fait d'un refus de git ; [60] décide de ce que le **fold** en
  fait. L'inverse ferait écrire deux fois la même question. `Blocked by: 59` est
  écrit dans [60].
- **[61] avant [11]** : les deux écrivent `router.sh` et `human-loop.sh`, et [11]
  est le second point d'entrée des transitions. Livrer [11] au-dessus de trois
  champs que personne ne garde, c'est lui faire hériter du trou plutôt que du
  garde — exactement ce que [55] a refusé de faire pour le fail-closed.
- **[59] et [60] avant [61]** est arbitraire quant aux fichiers (rien en commun),
  et se décide sur autre chose : [59] est le seul des trois qui produise un faux
  **livré**, et c'est la classe que ce dépôt traite en premier.
