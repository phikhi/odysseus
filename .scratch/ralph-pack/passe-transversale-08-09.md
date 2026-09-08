# Passe transversale du 08/09/2026

Dixième passe. Faite sur `main` à `5dc7ed6` (merge de [18]), avant [19]. Une
livraison depuis celle du 07/09 : [18] `5dc7ed6`, qui a ajouté trois fichiers de
pack (`lib/forge.sh`, `lib/tracker-github.sh`, `lib/tracker-gitlab.sh`) et une
21ᵉ opération d'interface.

Sondes conservées : `sondes/passe-08-09/` (README avec le verdict de chacune).
**Ni `.claude/` ni `test/` touchés** → la baseline de [18] tient telle quelle
(`run.sh` 825/0/6 skips, `mutate.sh` 842/0) et les deux gates n'ont pas été
rejoués.

---

## La racine

> **Les garanties que ce pack croit tenir sont, pour la plupart, des propriétés
> du _support_ du backend local : un répertoire qu'un glob lit en entier, un
> champ de ticket qu'un tree object restaure, un garde posé là où quelque chose
> le compte. [18] a changé le support et rien n'a redemandé ce que ces
> propriétés deviennent. Le seul contrôle qui a traversé le changement est celui
> qui était écrit contre l'**interface** — le drain — et personne ne l'avait
> remarqué.**

Trois mesures, trois supports :

| Ce que le pack croit | Ce qui le tient sur `local` | Ce qui le tient sur `github`/`gitlab` |
|---|---|---|
| `tracker_ids` et `frontier` rendent **tous** les tickets | un glob `"$dir"/*.md` : complet par construction | une lecture paginée dont la borne **ne compte jamais le premier enregistrement d'une page** — donc une seule page, toujours (§1) |
| le claim, le reçu et le garde du tracker sont hors d'atteinte d'une session | un champ de ticket restauré par [21] ; un garde dans `issues/` | **un fichier de la zone comptable** que le scope-guard exclut, que [21] ne lit pas et que rien ne restaure (§2) |
| ce qu'une session écrit dans le tracker est remis | `failures_protect_tracker`, écrite contre `git read-tree` | **rien côté boucle** — et `router_protect_tracker`, écrite contre l'interface, le fait déjà côté drain (§3) |

La ligne du milieu est celle qui se lit le plus mal, parce qu'elle est vraie des
**deux** backends : le garde de claim du backend local vit dans `issues/` sous un
nom que [49] a explicitement sorti des chemins restaurés. Le geste qui arrête la
nuit est le même à un chemin près (§2, Q2e et Q2f).

Le précédent est celui que la passe du 07/09 avait déjà nommé pour [70] : *le
pack sait faire ce qui manque et l'a fait une fois ailleurs*. Ici l'« ailleurs »
est `router.sh`, et il est à deux modules de distance.

---

## 1. La première page est tout le tracker d'un backend distant — ticket [76]

`forge__listing` pagine, et son commentaire dit exactement pourquoi : « a tracker
of a hundred tickets is ordinary and a first page is not the tracker ». La borne
qui décide de demander la page suivante est écrite ainsi :

```sh
count="$(printf '%s' "$body" | LC_ALL=C awk -F'\t' '
  { split($1, f, "."); if (f[1] != last) { n++; last = f[1] } }
  END { print n + 0 }')"
[ "${count:-0}" -ge "${FORGE_PAGE:-100}" ] || break
```

`f[1]` sorti de `split()` est un **strnum** — « 0 » ressemble à un nombre — et
`last` n'est pas initialisée : awk compare alors **numériquement**, `0 == 0`, et
le premier enregistrement de chaque document n'est jamais compté. Mesuré
(sonde `q1`) : **1** sur une page de deux enregistrements, **99** sur une page
pleine de cent. `99 >= 100` est faux.

**Donc la page deux n'est jamais demandée, sur aucun tracker, jamais.** Et
`state=all` — la décision de [18], correcte, parce qu'un ticket résolu revendique
sa write-surface autant qu'un ouvert — garantit que n'importe quel dépôt un peu
vécu dépasse cent issues.

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q1a | quatre issues, deux par page, `FORGE_PAGE=2` | `tracker_ids` rend **2** ids sur 4, la frontière aussi, et `3-gamma` — ouverte, `ready-for-agent` — se lit **« pas de ticket »** (rc=1). Une seule page demandée |
| Q1b | témoin appairé : les mêmes quatre sur une page | **4** ids |
| Q1c | `FORGE_PAGE=1`, ce qui met la pagination en marche | pages 1, 2, 3 demandées — et le pack voit **`3-gamma`, `4-delta`** : la page deux a écrasé la page une |
| Q1d | ce que ça coûte au scope-guard | `src/delta.txt`, write-surface d'un ticket de la page deux : **personne ne la revendique** |

Q1c est le **second défaut, que le premier cache** : `forge__records` reconstruit
un enregistrement par **indice de tableau** (`rec = substr(p, 1, dot - 1)`) et
`forge_json` numérote les éléments de **chaque document**, donc la première issue
de la page deux est `0.number` comme celle de la page une et l'écrase. Les deux
sont à réparer ensemble : réparer la borne seule remplace un tracker tronqué par
un tracker faux.

Ce que la troncature coûte, en descendant les consommateurs de `tracker_ids` :

- **le scope-guard** — c'est l'AC 5 de [18], atteinte par l'autre bout. Un
  débordement dans la write-surface d'un ticket que le listing a perdu est classé
  débordement interne, donc **retry au lieu d'escalade**, en boucle (Q1d) ;
- **la frontière** — les tickets de la page deux ne sont jamais travaillés, et la
  frontière vide est ce qui déclenche le gate de valeur terminal ;
- **`Blocked by:`** — `forge__is_unblocked` fait bloquer un id qui ne pointe sur
  rien (fail-safe correct), donc tout ticket bloqué par un ticket de la page deux
  quitte la frontière **pour de bon** ;
- **`failures_quarantine_strays`**, **`claim_reclaim_stale`**, **le drain** — un
  claim de run mort posé sur un ticket de la page deux n'est jamais balayé.

Une troisième borne, silencieuse elle aussi et à traiter dans le même ticket :
`while [ "$page" -le 20 ]` s'arrête sans un mot. Et `per_page=100` est écrit dans
le gabarit d'URL de chaque backend pendant que la comparaison lit `FORGE_PAGE` —
deux autorités pour un nombre, ce qui est la forme dont ce dépôt a déjà payé le
prix ailleurs.

---

## 2. Les gardes et le sidecar du pack vivent dans la zone que tous ses contrôles excluent — ticket [77]

Sur un backend distant, trois faits locaux vivent dans un fichier :
`.scratch/<feature>/.forge-claims`, append-only, dernière ligne gagnante.

    claim    `owner=<qui> at=<iso>` — l'autorité de `tracker_field ID Claimed`,
             donc de toute la liveness de `lib/claim.sh`
    request  le numéro de la requête ouverte
    receipt  **l'URL que `router_dossier` montre à un humain comme le reçu**

[18] a écrit que ce fichier « a exactement l'exposition du verrou de run — une
session peut l'écrire — et c'est déjà la ligne *Le reste de `.scratch/<feature>/`*
du tableau de confiance ». La phrase est vraie sur l'exposition et **fausse sur
ce que ça coûte** : le verrou de run décide qu'un second run refuse ; ces
trois lignes-là décident *qui tient un ticket* et *quelle preuve un humain va
lire*.

**Mesuré** (sonde `q2`) :

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q2a | une itération **verte** dont la session appende une ligne `receipt` pour le ticket du puits | run **rc=0**, ticket travaillé `resolved`/`closed`, **0** mot. Le dossier du drain montre `receipt https://forge.invalid/pull/9999 — verdicts, findings, and the zones nothing judged` |
| Q2b | témoin appairé, sans la ligne | « receipt none was kept for this ticket » |
| Q2c | un claim de run **mort**, tel quel | reclaim : `2-alpha retry`, la forge repasse à `ready-for-agent` |
| Q2d | le même, avec une ligne appendue derrière (pid vivant) | reclaim **silencieux**, ticket toujours `claimed`, **frontière vide** |
| Q2e | une session pose `.scratch/<feature>/.forge.guard/pid` (pid vivant) | le run **s'arrête** — `rc=4`, sterile — après deux itérations qui n'ont rien réclamé |
| Q2f | le même geste sur le backend **local**, `issues/01-alpha.md.guard/pid` | **identique**. Le défaut n'est pas de [18] |

Trois choses en sortent, et la troisième est la plus large.

**(a) C'est [70] rouvert par une autre porte.** [70] a passé un ticket entier sur
« les deux preuves que le dossier montre sont écrites par une session jugée », et
[18] a relu la réserve du dossier pour un reçu distant — correctement, la phrase
imprimée parle du réseau. Ce que ni l'un ni l'autre n'a vu : **l'URL elle-même
n'est pas lue sur le réseau, elle est lue dans un fichier de cet arbre**. La
réserve envoie donc le lecteur regarder du côté où il n'y a rien à voir. Il ne
manque pas un garde : il manque une phrase exacte, et une ligne dans le tableau.

**(b) Le claim d'un backend distant est un fichier, et [12] est écrit contre un
champ.** `claim.sh` dit de sa liste d'exemption : « an id the run is holding is a
fact only the run knows, **it is written nowhere a session can reach** ». Vrai de
la liste. Le **record** que la même fonction lit juste au-dessus, lui, est sur le
backend local un champ de ticket que [21] restaure et sur un backend distant une
ligne que n'importe quelle session appende. Q2d : une ligne, et le ticket sort de
la frontière tant que le pid vit — que la session peut renouveler à chaque
itération. Borné par `CLAIM_TTL` (5400 s par défaut), **non borné** avec
`CLAIM_TTL=0`, qui est la lecture « pas de backstop » que [12] autorise.

**(c) Le garde qui sérialise le tracker arrête la nuit, sur les deux backends, et
la phrase qu'on lit accuse le tracker.** `forge__guard` (tout le tracker) et
`tracker_local_claim` (un ticket) prennent un `state_guard_take` dans une zone
qu'une session écrit ; `state_guard_take` respecte un pid vivant ; le pack imprime
alors « could not claim X — its status is still ready-for-agent and **the tracker
refused the write: nobody is named as holding it** », ce qui est faux dans les
deux moitiés et envoie un humain lire le ticket. `gate__stale_guards` ne rattrape
ni l'un ni l'autre : il ne regarde que `<feature_dir>/*.guard` — donc pas
`issues/<id>.md.guard`, un niveau plus bas — et seulement des propriétaires
**morts**, alors que le geste qui mord est un propriétaire vivant. Le tableau de
confiance dit d'ailleurs de cette ligne qu'elle « compte, elle ne juge pas ».

---

## 3. Le drain remet un tracker distant que la boucle ne remet pas — contrainte pour [73]

[73] est ouvert sur « rien ne restaure le tracker d'un backend distant » et
conclut que la remise demande de rendre `failures_protect_tracker` agnostique du
transport. La moitié qui n'est écrite nulle part : **le drain le fait déjà**.

| Sonde | Ce qu'elle demande | Verdict |
|---|---|---|
| Q3a | une session **routée** met le voisin `2-alpha` à `resolved`, backend distant | le drain le **remet** — `tracker_mark_ready`, donc par le réseau — le nomme, et redit la réserve de [61] sur les trois champs qu'il ne remet pas |
| Q3b | une session d'**itération** met `1-decision`, dans le puits humain, à `resolved` | run **rc=0**, itération **verte**, `1-decision` reste **`resolved`** |
| Q3c | témoin appairé : le même geste sur le backend **local** | « the session edited the tracker — restored 1 ticket file(s), the iteration cannot be green », outcome `tracker-write` |

Q3b est le prix de [73] mesuré sur un run réel : **une session a sorti du puits
humain un ticket qui attendait une décision, et l'itération est verte.** C'est
l'écriture même que [58] existe pour attraper côté drain et que [21] restaure
côté boucle.

Et la parade que [73] cherche existe : `router_pin` prend l'état du tracker par
l'adaptateur (`router__tracker_state`) et `router__put_back` remet par
`tracker_mark_*`. Deux opérations de l'interface, donc sans une ligne de git.
Ce que ça coûte est déjà chiffré et appartient à [75] — cinq champs plus le corps
par ticket, par ticket drainé — donc les deux tickets se rencontrent : la remise
de [73] est le consommateur qui rend le cache de [75] nécessaire, et non
l'inverse.

---

## Angles sondés et disculpés — ne pas les resonder

- **Le rejeu des sept jeux de sondes de vérification est à l'identique**
  (`ticket-64`, `-65`, `-66`, `-67`, `-68`, `-69`, `-70`). Aucune régression :
  chaque verdict est celui que son ticket a consigné. [71] et [72] n'ont pas de
  répertoire de sondes ; leurs témoins sont `passe-07-09/q2` et `passe-07-09/q4`.
- **Le piège `IFS=<TAB> read` que [18] a trouvé ne mord nulle part ailleurs dans
  le pack.** Les vingt-et-un sites ont été relus avec leur producteur :
  `failures.sh:822` et `gate.sh:2520` lisent un `--name-status` **sans `-M`**
  (deux champs, statut jamais vide) ; `forensic.sh:429` et `gate.sh:1861/1886`
  lisent des enregistrements dont le producteur écrit `-` pour l'absence
  (`forensic__moved`, `gate__path_where`, `gate__digest`) ; `gate.sh:350` lit un
  marqueur dont le producteur (`scheduler__mark`) reçoit un `armed` qu'un
  `[ -z "$armed" ]` garantit non vide ; `loop.sh:1257` lit un enregistrement de
  slot dont les cinq champs sont non vides par construction (`tree` est refusé
  vide une ligne plus haut, `slot` sort d'un `mktemp`) ; les canaux
  `subject/outcome/message` ont trois producteurs, tous littéraux. La règle qui
  tient le pack est **le sentinelle `-`**, et elle est appliquée partout où un
  champ peut manquer.
- **Aucun programme nouveau n'est lancé par son nom.** `forge.sh` appelle `curl`,
  `git`, `awk`, `cut`, `date`, `sleep`, `mkdir`, `basename`, `dirname` — les neuf
  sont dans `gate_path_programs`, donc le témoin de PATH de [52] couvre le
  backend distant sans modification.
- **Les adaptateurs distants ne posent aucun `mktemp`**, donc `gate_tmp_names`
  n'a rien à gagner ([62] est intact, et son test le vérifie sur le pack livré).
- **`forge__forget` est bien appelée par toutes les écritures** — `forge__update`
  la porte, et `forge_claim` la rappelle avant sa relecture. Le mémo ne survit à
  aucune écriture du même shell.
- **Le sidecar n'est pas un problème de concurrence.** Append-only avec des
  lignes courtes : deux itérations qui enregistrent deux tickets n'ont pas besoin
  de verrou, et c'est ce que le fichier annonce. Le problème est l'écrivain
  qu'il n'a pas prévu (§2), pas l'entrelacement.
- **Le refus de `tracker_receipt_dir` et celui de `tracker_tickets_dir` sont dits
  une fois chacun au démarrage du run**, et la seconde phrase est celle que [18]
  a ajoutée. Vérifié dans Q2a : deux lignes, une fois.

---

## Ce qui est écrit ailleurs

Écrit maintenant, parce qu'une ligne fausse dans le tableau attend un faux vert :

- `docs/frontiere-de-confiance.md` — la ligne « Le reste de `.scratch/<feature>/` »
  (elle porte désormais le claim, l'emplacement du reçu et le garde de tout le
  tracker d'un backend distant, et le garde de claim du backend local n'y était
  pas nommé) ; la ligne du reçu d'audit (l'URL d'un reçu distant est lue dans un
  fichier de cet arbre, pas sur le réseau) ; et une ligne neuve — *ce que
  `tracker_ids` et `tracker_frontier` rendent est tout le tracker* — dont la
  réponse est « un glob sur `local`, la première page ailleurs, et §1 est ouvert
  dessus ».
- **[73]** — la mesure de Q3b (une session sort un ticket du puits humain et
  l'itération est verte), le précédent de `router_protect_tracker`, et le fait
  que le sidecar est une seconde zone non restaurée que son AC ne nomme pas.
- **[75]** — le cache qu'il doit loger a un voisin qui existe déjà et qui est dans
  la mauvaise zone ; et la remise de [73] est le consommateur qui le rend
  nécessaire.
- **[18]** — les deux tickets ouverts par cette passe, comme il l'a fait pour
  [73]/[74]/[75].
- **[12]** — le record de claim est un champ de ticket sur un backend et une ligne
  de fichier sur l'autre ; la phrase « written nowhere a session can reach » ne
  vaut que pour la liste d'exemption.
- **[49]** — la règle de placement des gardes a maintenant un prix mesuré : un
  garde posé par une session, avec un propriétaire vivant, arrête la nuit sur les
  deux backends.
- **[19]** — l'installeur écrit le `.gitignore` de cette zone : `.forge-claims` et
  `.forge.guard` sont deux noms de plus, et le second est un répertoire.

## L'ordre — à valider

Six tickets ouverts : [19], [73], [74], [75], [76], [77]. Proposition dans le
message qui accompagne cette passe ; rien n'est écrit dans `Blocked by:` avant
validation.
