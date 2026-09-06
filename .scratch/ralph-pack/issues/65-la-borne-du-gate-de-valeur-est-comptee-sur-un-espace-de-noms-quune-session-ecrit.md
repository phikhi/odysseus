# 65 — La borne du gate de valeur est comptée sur un espace de noms qu'une session écrit

**What to build:** `PLAYTHROUGH_REINJECT_MAX` doit borner ce que **le pack** a ouvert, pas ce qui **porte un nom**. Aujourd'hui trois fichiers déposés par une session dans `issues/` éteignent définitivement la réinjection du gate de valeur pour cette feature.

**Blocked by:** None

**Write-surface:** `.claude/lib/playthrough.sh`, `test/playthrough.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** playthrough, tracker, security

- [x] Le compte que `PLAYTHROUGH_REINJECT_MAX` borne vient d'une source qu'une session n'écrit pas. Le registre d'écritures du pilote ([13]/[40], `RALPH_TRACKER_LOG`, un `mktemp` jamais exporté) est la forme évidente ; le ticket doit dire pourquoi celle-là et pas une autre, et ce qu'elle coûte au « a variable resets, a tracker does not » qui a justifié le scan.
- [x] La déduplication de `tracker_open_unique` sur le slug est regardée par le même bout : une session qui pose un ticket portant *exactement* le slug que le gate utiliserait fait ouvrir **rien** au gate. Même direction, même silence.
- [x] Quand la borne est atteinte ou que la dédup mord, la phrase dit **qui** a mis les tickets là si le pack le sait. Aujourd'hui elle nomme la borne (« past the 2 re-injection(s) `PLAYTHROUGH_REINJECT_MAX` allows this feature ») et jamais la contrefaçon.
- [x] **Attention à la condition d'arrêt.** Les deux mutations écrites en livrant [11] retiraient déjà la borne dans la direction qui **termine encore** ; toute entrée neuve doit faire pareil, sinon `mutate.sh` reste bloqué avec un défaut planté dans l'arbre.
- [x] Entrée de mutation par garantie livrée, plus le témoin appairé.

## Comments

- **Trouvé par la passe transversale du 05/09/2026** (`../passe-transversale-05-09.md`, §4). Sonde : `../sondes/passe-05-09/q3-…bats`, cas `Q3e`.

- **Le commentaire dit pourquoi il lit le tracker, jamais qui l'écrit.** `playthrough__injected` compte les ids contenant `PLAYTHROUGH_SLUG_PREFIX` (`playthrough-wiring`), « read off the tracker rather than counted in the run, for the reason the header gives: **a variable resets, a tracker does not** ». C'est vrai et c'est insuffisant : `issues/` a deux écrivains.

- **Mesuré, run réel** (`q3` Q3e). Une session de livraison dépose trois fichiers `60/61/62-playthrough-wiring-forged.md` dans `issues/`. La quarantaine de [07] les voit, les **nomme** et leur **laisse leur nom** :

  ```
  ralph: 01-alpha: the session wrote the tracker itself — quarantined
         60-playthrough-wiring-forged, 61-…, 62-…
  ```

  Après le run :

  ```
  tickets présents      : 01-alpha.md 60-…-forged.md 61-…-forged.md 62-…-forged.md
  playthrough__injected : 3
  ```

  Avec le défaut `PLAYTHROUGH_REINJECT_MAX=2`, cette feature ne rouvrira **plus jamais** un ticket de câblage : chaque playthrough rouge part droit au puits humain par `playthrough__why_human`.

- **La direction est sûre, et ce n'est pas une excuse.** Le compte ne peut que monter — une session ne peut pas supprimer un ticket, [21] restaure —, donc l'effet est « un humain est demandé plus tôt » et jamais un faux vert. Ce qui est perdu est **l'autonomie de la nuit** : le palier que [11] a construit pour se réparer tout seul est éteint par une session, en silence, et la phrase que l'humain lit accuse la borne.

- **C'est la question 5 du CLAUDE.md dans sa forme canonique** — *un contrôle qui lit un fichier que la session peut écrire n'est pas un contrôle* ([21], [55]) — appliquée à une **borne** plutôt qu'à un champ. La famille est celle de [55] (`Escalation:` lu sur le ticket) et de [42] (les deux gardes du tracker qui ne lisaient pas le registre) ; la réparation de [42] est exactement le registre qu'il faut réutiliser ici.

- **Ce que [18] hérite.** [11] avait déjà écrit dans [18] que `playthrough__injected` lit le slug **dans l'id** et qu'un backend numérotant côté serveur casse la borne. Cette trouvaille l'élargit : la borne ne lit pas seulement un id, elle lit un espace de noms **à deux écrivains**. Si ce ticket passe avant [18], [18] écrit contre un compteur réparé ; sinon [18] hérite des deux problèmes à la fois.

- **Piège rencontré en sondant.** `$FEATURE` n'est pas dans l'environnement du faux `claude` : une sonde qui veut écrire dans `issues/` depuis une session prend le répertoire par un glob (`ls -d "$root"/.scratch/*/issues`), jamais par `$FEATURE`. Et un `pack_run` écrase `$status`/`$output` — copier la sortie du `run_loop` avant.

- **Place dans la file, validée par Philippe le 05/09/2026 : troisième**, avant
  [64] et [18]. `[18] Blocked by:` porte maintenant `65` : si ce ticket répare la
  borne en cessant de scanner le tracker (registre d'écritures du pilote,
  [13]/[40]), la contrainte que [11] avait écrite dans [18] — « un backend qui
  numérote côté serveur casse la borne » — disparaît avec le scan au lieu d'être
  une obligation de plus. Ordre complet retenu : [63] → [62] → [65] → [64] →
  passe transversale → [18] → [19].

## Livré le 05/09/2026

**Sonde rejouée avant d'écrire** (`../sondes/passe-05-09/q3`, cas `Q3e`, sur le
code livré de [62]) : `rc=0`, `tickets présents : 01-alpha.md
60/61/62-…-forged.md`, `playthrough__injected : 3`. Le défaut est celui décrit,
au mot près.

### La trouvaille du ticket : le registre était la mauvaise source

Le ticket, la passe transversale et le tableau de confiance disaient tous les
trois que le registre d'écritures du pilote ([13]/[40]) était « la forme
évidente ». **Il a été écrit, puis mesuré sur un run réel, et il est faux.**

`tracker_writes_since` répond à « quels tickets la boucle a **écrits** », et la
toute première chose que la boucle fait d'un ticket de câblage contrefait est de
le **mettre en quarantaine** — `failures_quarantine_strays` →
`tracker_mark_escalated` → une écriture → une ligne au registre portant son id.
Mesuré (`../sondes/ticket-65/verification.bats`, S1, sur le code déjà corrigé
« au registre ») :

```
rc du run                : 4
la borne a-t-elle mordu ?: 1   ← « past the 2 re-injection(s) … allows this run »
ligne de réinjection     : (vide)
```

Exactement le défaut d'origine, avec un garde neuf par-dessus. Et
`playthrough__strangers` ne nommait personne, registre et tableau étant d'accord.
**Un garde vert dans la suite et sans valeur dans une nuit** — c'est-à-dire la
chose que la définition of done existe pour attraper, attrapée par la question 3
(« sonder le run réel ») et par rien d'autre : les quatre tests écrits contre le
registre étaient verts.

La leçon appartient à [13] et y est écrite : **le registre est indexé par id et
ne dit pas quelle opération a écrit.** Il répond à « ce ticket a-t-il bougé par la
boucle » — la question des deux gardes de `issues/` — et ne peut pas répondre à
« la boucle l'a-t-elle **créé** ». C'est la limite que [42] avait déjà écrite
(« la granularité reste un id »), payée pour la première fois par un appelant.

### Ce qui a été écrit

- `playthrough__injected` **n'existe plus**. Dans `.claude/lib/playthrough.sh` :
  - `RALPH_PLAYTHROUGH_OPENED` — les ids que **ce run** a ouverts, un par ligne.
    Variable du pilote, alimentée par `playthrough_close` et par rien d'autre.
  - `playthrough__opened` / `playthrough__note_opened` — la lire, l'alimenter.
  - `playthrough__strangers` — les tickets de câblage que le tracker porte et que
    ce run n'a pas ouverts.
  - `playthrough__opened_slug` — le ticket qui porte déjà ce slug est-il un
    ticket de ce run.
  - `playthrough__count`, `playthrough__names` — compter, et rendre une liste
    « un par ligne » pour un humain (jamais `tr '\n' ' '`, [37]).
- **L'ajout est fait dans `playthrough_close` et pas dans `playthrough__inject`**,
  où il se lirait mieux : l'appelant prend l'id dans une **substitution de
  commande**, donc une affectation faite là-dedans meurt en revenant. Une entrée
  de mutation déplace l'ajout dans la substitution, précisément pour prouver
  qu'un test s'en aperçoit.
- `.claude/lib/tracker.sh` **n'est pas touché** (une première version y ajoutait
  `tracker_has_register` ; elle est partie avec le registre).

### Pourquoi une variable du pilote, et ce que ça coûte

C'est la source que le commentaire d'origine avait écartée (« a variable resets,
a tracker does not »). L'argument est retourné, pas ignoré : **aucune source
n'est à la fois durable et hors d'atteinte d'une session** — tout ce qui survit à
un run vit dans l'arbre, et une session écrit l'arbre, historique git compris
(une session a `Bash`). Le choix réel n'était donc pas « durable ou pas » mais
« un compte que le pack tient, ou un compte que n'importe qui écrit ».

Le prix : **la borne borne un run** et non plus la vie de la feature — une nuit
tuée puis relancée rouvre son budget. Payé exprès : ce que cette borne existe
pour arrêter est une *boucle*, et la boucle est dans un run. Rien ici ne démarre
le suivant — un successeur n'est armé que par un mur hebdomadaire ([09]) et est
une nuit neuve.

Le résidu, nommé : une variable est perdue si l'appel passe un jour dans un
sous-shell, et une liste perdue est une borne qui ne borne plus — **fail-open**,
là où le témoin de la spec, deux écrans plus haut, échoue fermé. Deux choses
devant : l'entrée de mutation ci-dessus, et `tracker_open_unique`, qui fait
terminer *le même* trou quoi que dise la liste.

### La dédup : dite, pas refermée

`tracker_open_unique` déduplique sur le slug, dans l'adaptateur, donc le gate ne
peut pas la contourner sans `tracker_open_ticket` — c'est-à-dire sans le garde
qui fait **terminer** ce chemin. Ce qui change est la phrase : « un trou de
câblage que le tracker porte déjà sous le slug que ce gate aurait utilisé, **et
que ce run n'a pas ouvert** ». Ce trou est **plus étroit** que le compte, et
c'est écrit dans le code plutôt que laissé à redécouvrir : le slug vient d'un
titre que la session du gate de valeur invente, donc une session doit le
**deviner**, là où le compte lisait n'importe quel nom portant le préfixe.

### Ce que le pack sait, et ce qu'il refuse de dire

Un ticket de câblage laissé par un run *antérieur* est indistinguable d'une
contrefaçon depuis ici. La phrase dit donc la seule chose que le pack tient —
« ce run ne l'a pas ouvert » — et jamais qui l'a mis là. `playthrough__strangers`
porte ce commentaire pour que la formulation ne dérive pas vers une accusation.

### Vérification sur un run réel, après correctif

`../sondes/ticket-65/verification.bats`, conservée :

| | avant | après |
|---|---|---|
| S1 — une session dépose trois `NN-playthrough-wiring-forged.md`, borne à 2 | `rc=4`, borne franchie, aucune réinjection | `rc=0`, `is on the frontier (1 of 2)`, ticket broyé, `src/wired.txt` écrit, feature close |
| S2 — même session, borne à 0 | la phrase nomme la borne seule | la phrase nomme la borne **et** les trois intrus |

La session de la sonde écrit pour de vrai dans `issues/` pendant le run, la
quarantaine tourne, l'itération commite et le gate juge : c'est l'écart que la
leçon 3 du CLAUDE.md demande de sonder, et c'est là que le premier correctif est
mort.

### Tests

Quatre neufs dans `test/playthrough.bats`, plus deux réfutations ajoutées à des
tests existants comme témoins appairés :

| test | ce qu'il tient |
|---|---|
| `wiring tickets this run did not open do not spend its re-injection budget` | trois `6N-playthrough-wiring-forged` posés dans `issues/`, borne à 2 : le run réinjecte quand même (`is on the frontier (1 of 2)`), broie et clôt |
| `the count the bound is compared against is what this run opened` | au module : une ouverture notée, deux noms sur le tableau, un registre qui porte *aussi* les deux — `opened` rend un, `strangers` rend les deux |
| `at its bound the sentence names the wiring tickets this run did not open` | `PLAYTHROUGH_REINJECT_MAX=0`, un intrus : la phrase nomme la borne **et** l'intrus |
| `a ticket under the slug this gate would use, opened by nobody here, is named as one` | la dédup mord sur un slug que ce run n'a pas ouvert, et la phrase le dit |
| `past its bound …` (existant) | `refute_output_contains "did not open"` — la clause ne s'imprime pas sur une liste vide |
| `the same hole twice …` (existant) | `refute_output_contains "did not open it"` — un doublon de ce run est rapporté comme tel |

Le slug attendu par le quatrième test est **épelé**
(`70-playthrough-wiring-render-the-markers-the-demo-writes`) et non calculé par
`playthrough__slug` : un test qui appelle la fonction du pack ne peut pas
attraper le pack qui déduplique sur autre chose. Même raison que
`playthrough_file`.

### Mutations

Sept neuves sous `65 `, plus la ré-ancre de `11 the wiring tickets already opened
are counted by nobody` (l'ancienne visait `playthrough__injected`, qui n'existe
plus). **Toutes retirent le garde dans la direction qui termine encore** — un
compte trop haut demande un humain plus tôt, une phrase fausse est dite une fois.
Trois paires écrites dans les deux sens ([61]) : la liste (jamais notée / notée
dans la substitution qui la perd), la dédup (toujours mien / jamais mien) et la
clause (jamais imprimée / imprimée sur du vide).

### Gates

Mesurés d'un bloc sur le code livré, rien d'autre en cours :

- `bash test/run.sh` — **725 tests, 0 failures, 6 skips** (tous opt-in
  `RALPH_REAL_USAGE` / `RALPH_REAL_CLAUDE`, aucun dans le canari). Baseline 721 +
  les 4 tests neufs.
- `bash test/mutate.sh` — **725 mutations, 0 not ok**. Baseline 718 + 7.

*Erreur d'outillage à ne pas refaire, consignée en mémoire :* un premier
`run.sh` complet a été lancé alors que `mutate.sh` tournait encore — sa sortie
partielle donnait l'illusion qu'il avait fini, `printf` de bash bufferisant par
blocs de 4 Ko. `mutate.sh` édite `.claude/**` en place : run jeté, `pkill -f
microbats` et `pkill -f loop.sh` en plus du `pkill` sur `run.sh`, relancé d'un
bloc.

### Ce que le ticket laisse ailleurs

- **[13]** — propriétaire du registre : *il est indexé par id et ne dit pas
  quelle opération a écrit*, et le run sans registre n'est toujours refusé par
  personne. Écrit dans le ticket.
- **[64]** — le `$(tracker_ids 2>/dev/null)` de `playthrough__injected` est
  maintenant dans `playthrough__strangers`. Même forme, place plus grave : ce
  n'est plus un compte interne qui perd la ligne de [48], c'est la **phrase
  adressée à un humain**.
- **[18]** — la contrainte de [11] (« un backend qui numérote côté serveur casse
  la borne ») est **morte avec le scan** : le compte ne lit plus du tout la forme
  d'un id. Deux lecteurs la lisent encore et sont écrits dans [18] :
  `playthrough__opened_slug` (phrase fausse à chaque doublon) et
  `playthrough__strangers` (silence sur ce qui n'a pas été compté). Plus une
  contrainte de fond : la source du compte doit rester hors d'atteinte d'une
  session, donc pas une trace tenue par le backend.
- **[11]** — son en-tête renvoie à `playthrough__opened` pour l'argument complet,
  et deux de ses phrases ont changé de texte : « allows this feature » → « allows
  this run », « this feature already carries a ticket for » → « this run already
  carries a ticket for ».
