# Passe transversale du 26/08/2026

Faite sur `main` à `3d6915b` (merge de [15]), avant [09]. Trois tickets la précédaient
depuis la passe du 07/08 : [45], [14], [15]. Arbre propre au départ, **rien édité dans
`.claude/` ni dans `test/`** — les sondes sont des `.bats` qui pilotent le pack tel qu'il
est livré, et elles sont conservées cette fois dans `sondes/passe-26-08/` plutôt que
perdues avec le scratchpad de la session.

Les sondes se terminent par un `false` volontaire : ce sont des instruments, pas des
tests. Elles rougissent toujours ; ce qu'on lit est ce qu'elles impriment avant.

---

## La racine commune, et c'est elle le ticket

**Ce pack a appris à se méfier de ce qu'une session écrit dans un arbre. Il ne s'est
jamais demandé ce qu'elle écrit dans les fichiers qui décident de ce que *le pack
lui-même* exécute.**

[30] a épinglé les clés git qui décident de ce qu'un contrôle **voit** —
`.git/info/exclude` et `core.excludesFile`, relevées avant la session et remises après.
C'était la bonne question posée à la moitié du sujet. La configuration git porte aussi des
clés qui décident de ce que git **lance** (`core.fsmonitor`) et de ce que git **produit**
(`filter.<n>.smudge`, via `.git/info/attributes`). Aucune des deux n'est épinglée, aucune
des deux n'est regardée, et les deux sont écrivables par une session — dans `.git/config`,
que le tableau de confiance décrit comme « vérifié par rien », et dans le `~/.gitconfig`
de l'opérateur, la porte que [15] a ouverte et dont il n'a mesuré que la moitié
« capacité ».

Les trouvailles 1 et 2 en découlent. La 3 est le canal du témoin de [15], et elle est la
raison pour laquelle les deux premières ne peuvent pas être livrées comme un simple
témoin de plus. La 4 est indépendante : c'est l'angle que [15] avait écrit pour [13] et
[27], et la passe l'a reproduit — en découvrant que ses deux propriétaires désignés sont
**clos**.

---

## 1. `core.fsmonitor` : le pack exécute une commande qu'une session a choisie

`core.fsmonitor` n'est pas un drapeau, c'est **un chemin de programme**. Git le lance à
chaque rafraîchissement d'index — donc à chaque `git add -A` du snapshot, à chaque
`git status`, à chaque worktree.

Sondé (`p1c-fsmonitor.bats`, `p3.bats` P3a) : une session écrit la clé, le run continue.

    === fsmonitor invocations: 248
    === distinct parents
    96281 /Applications/Xcode.app/Contents/Developer/usr/bin/git
    …
    === 01-alpha=resolved 02-beta=resolved
    === does any receipt name .gitconfig or a drift?
    (no receipt mentions it)

**248 exécutions du programme choisi par la session, sur un run de deux itérations**, dans
l'arbre de processus du pilote — pas dans celui d'une session, pas dans un worktree, pas
sous un gate. Les deux tickets sortent `resolved`, `run.log` ne dit rien, aucun reçu ne
dit rien.

Deux emplacements, tous les deux sondés et tous les deux suffisants :

- **`$HOME/.gitconfig`** (`p1c`). C'est la porte de [15] : `lenses_posture` passe
  `--setting-sources user` à dessein ([06]) parce que la direction de confiance est que le
  `$HOME` de l'opérateur n'est pas écrivable par la session jugée. Il l'est. [15] a mesuré
  ce que ça coûte en *capacités* ; ceci est ce que ça coûte en *exécution*, et c'est pire :
  un hook de `~/.claude/settings.json` tourne dans le process de la session suivante, une
  clé `core.fsmonitor` tourne dans le process du pack.
- **`<arbre principal>/.git/config`** (`p3a`). Plus proche : pas besoin de trouver le
  `$HOME`, `git worktree list` suffit à trouver l'arbre principal, et le tableau de
  confiance dit déjà de ce répertoire que « le rempart est l'isolation de l'hôte ».
  L'isolation de l'hôte borne le rayon ; elle ne dit rien du fait que le pack exécute la
  commande lui-même.

**Ce qui ne marche pas, et il faut le dire** : `core.hooksPath` ne tire jamais (`p1-home`
P1a, vérifié : le `post-commit` n'est pas appelé). `failures_make_durable` utilise la
plomberie exprès — « Plumbing rather than `git commit`, so the target project's hooks,
signing config and commit template have no say ». Le pack a donc déjà pensé à la
configuration git comme surface d'attaque ; il l'a bornée au dépôt et aux *hooks*.
`diff.external` ne tire pas non plus (`p1b` P1d).

**Cas voisin sain, sondé pour borner** : du texte qui n'est pas de la config dans
`~/.gitconfig` (`p1b` P1e) ne passe pas en silence — `rc=4`, `scope=red lang=red`,
« cannot read the working tree — nothing was rolled back », le run s'arrête et **un reçu
est émis** (c'est la cinquième trouvaille de [45] qui le tient). Le mode de panne bruyant
est couvert ; c'est le mode de panne *utile* qui ne l'est pas.

## 2. Un filtre `smudge` réécrit ce que toutes les sessions suivantes lisent

Le tableau de `docs/frontiere-de-confiance.md` nomme cette route et l'annonce
« **non sondé**, même famille, aucun propriétaire ». Sondée.

Vérifié d'abord au niveau de git, hors du pack : `.git/info/attributes` et
`[filter "x"] smudge` vivent dans le répertoire git **commun**, donc ils s'appliquent
dans un worktree lié — `git checkout-index` y passe le smudge.

    $ cd ../wt && rm -f f.txt && git checkout-index -a -f && cat f.txt
    the REWRITTEN line

Puis dans le pack (`p7.bats`) : l'itération 1 installe le filtre, l'itération 2 est un
worktree neuf.

    === 01-alpha=resolved 02-beta=resolved
    === what the second session was handed as CONTEXT.md:
    the REWRITTEN-BY-01-ALPHA line
    === main tree CONTEXT.md now:
    the original line
    === git's stored blob:
    the original line
    === anything said?
    (nothing)

**La deuxième session reçoit un `CONTEXT.md` que la première a réécrit, alors que le blob
git et l'arbre principal portent toujours l'original.** Aucun contrôle ne peut le voir :
le scope-guard compare deux trees, et les deux sont smudgés de la même façon, donc le
diff est vide. `CONTEXT.md` est précisément le document que le prompt de session nomme en
premier — et `docs/adr/`, que la lentille Standards va lire, est dans le même cas.

C'est la route que [14] a fermée pour `LEARNINGS.md` en le servant depuis une copie du
pilote. Elle est ouverte pour tout le reste de l'arbre.

**Ce que ça n'atteint pas, sondé plutôt que supposé** (`p8.bats`) : le **ticket** et sa
`Write-surface:` sont lus dans l'arbre principal et pas dans le worktree, donc ils ne sont
pas smudgés — le scope-guard a bien rougi `src/POISONED.txt`, et le prompt de la seconde
session portait la vraie surface. Et rien de réécrit n'atteint l'historique : le commit
sur vert ne prend que les chemins que le scope-guard a approuvés. La frontière est donc
nette : **le contexte est empoisonnable, le contrôle ne l'est pas.**

## 3. Le témoin de [15] n'a qu'un canal durable, et il est plus étroit que son critère

C'est [45] appliqué à [15], et c'est la même racine que la passe du 07/08 : un producteur
plus étroit que le critère écrit à côté de lui.

`capability_drift` tourne à **chaque** itération (`loop.sh:813`, hors du `if emit`), et
c'est écrit comme un choix : « it must be said whether or not the tier is on, […] and on
the red path as much as the green one ». Mais ce qu'il écrit est un `receipt_gap`, et le
reçu n'est émis que sur les quatre routes de [45]. Le second canal, `capability__log`, est
un `printf` sur stdout : `run.log` n'est écrit que par le pilote (`loop_journal_append`),
jamais par le shell d'itération.

Sondé (`p2.bats` P2b/P2c, `p3.bats` P3b) :

- Itération retryée **suivie d'autres** : le témoin finit par arriver, parce que la ligne
  de base est celle du run et que l'itération d'escalade émet, elle. Conforme à ce que
  [15] annonce. *(P2b)*
- Itération retryée sur laquelle **le run s'arrête** (`ITER_CAP`, et donc aussi `STERILE_K`,
  un arrêt demandé, un mur budget) :

      === receipts
      (none)
      === run.log
      2026-08-26T…	01-alpha	gate-red	turns=2	…	action=retry:1/2
      === the backdoor is there:
      -rw-r--r--  … backdoor.md

  Aucun reçu, aucune ligne de journal, le fichier est là. *(P2c)*
- Et le run **suivant** : le témoin est par run ([15], limite 5), donc il reprend le
  fichier comme ligne de base.

      === does run 2 say anything about the backdoor?
      (nothing — it is the baseline now)

  Le silence est donc **définitif**, pas différé. *(P3b)*

`ralph.config.sh.example` dit de ce témoin qu'« il est sur chaque reçu ». C'est la moitié
documentaire de la même chose.

**Pourquoi ça commande les trouvailles 1 et 2** : la réponse naturelle à un `.gitconfig`
qu'on ne peut pas défaire est un témoin de plus. Un témoin de plus posé sur ce canal-là
serait un détecteur dont les événements disparaissent exactement sur les runs qui
s'arrêtent mal — c'est-à-dire ceux qu'on lit le matin.

**Mineur de la même famille** : `capability_review` — donc le `receipt_note` qui avoue
`CAPABILITY=off` — n'est atteignable que par `retro_run`, qui sort avant lui quand
`RETRO=off`. Un projet en `RETRO=off` + `CAPABILITY=on` n'a **aucune** revue de capacités
et le reçu attribue le silence au seul tier retro. Sondé en creux par `p5.bats` P5c :
la ligne de dérive est bien là (le témoin, lui, est indépendant — l'AC de [15] tient), la
note d'aveu n'y est pas.

## 4. `tracker_open_ticket` : la course est reproduite, et ses deux réparations la manquent

L'angle que [15] a écrit pour [13] et [27]. Reproduit (`p4.bats` P4a) — et la fenêtre est
plus large qu'on ne la lit : `tracker_local_open_ticket` calcule `nn` **avant** de lire le
corps sur stdin, donc elle reste ouverte aussi longtemps que l'appelant met à produire ce
corps.

    === second opened: 03-second
    === first opened: 03-first
    === tracker
    01-alpha.md  02-beta.md  03-first.md  03-second.md
    === can a bare number resolve?
    rc=1 out=tracker: "03" matches 2 tickets — an ambiguous id is never safe to resolve

Conséquence permanente : un ticket portant `Blocked by: 03` ne rentre plus jamais dans la
frontière (`tracker_local__is_unblocked` rend faux dès que `tracker_local__path` refuse).
C'est exactement le défaut que [27] décrit, atteint cette fois **par la boucle elle-même**.

Deux contrôles existent et **aucun des deux ne peut l'attraper** :

- `tracker_preflight` le nomme parfaitement — sondé, il rend
  `03 ambiguous-id two or more tickets carry the number 03 (03-first, 03-second)`. Mais il
  tourne **une fois, au démarrage du run**, et cette collision naît en cours de run.
- `failures_quarantine_strays` renumérote — mais seulement ce qui n'est pas dans le
  registre des écritures de la boucle ([13], lu par les deux gardes depuis [42]). Sondé
  côte à côte (`p5.bats` P5a) :

      === the loop created them (ids in the register)
      rc=0 tracker: 01-alpha.md 02-first.md 02-second.md
      === a session created them (empty register)
      ralph: … quarantined 03-first 02-second
      ralph: … renumbered 02-first -> 03-first

  **Le registre qui protège les écritures de la boucle est exactement ce qui désarme la
  réparation quand c'est la boucle qui a écrit la collision.** Deux mécanismes corrects
  séparément, un trou à leur composition — la question 4 de `CLAUDE.md`, en une ligne.

La dédup de `capability_propose` a la même course par le même bout : deux itérations
peuvent lire `tracker_ids` avant que l'une des deux n'écrive, et ouvrir deux fois la même
proposition.

**Et le vrai problème de ce point** : [15] a écrit la contrainte dans [13] et dans [27].
Les deux sont **`resolved`**. Aucun ticket ouvert de la file ([09], [16], [11], [18], [19],
[37], [38], [39]) ne sérialisera `tracker_open_ticket`. Une contrainte écrite chez un
propriétaire clos n'a pas de propriétaire.

---

## Les angles disculpés, et il ne faut pas les resonder

- **`core.hooksPath` et `diff.external`.** Ne tirent pas. La plomberie de
  `failures_make_durable` est ce qui tient le premier ; le second n'est pas sur le chemin
  de `git diff-tree`. Ne pas les remettre dans une liste : une liste dérivée des cas plutôt
  que du critère est la faute que [31] a un ticket entier pour refuser.
- **Le ticket et sa `Write-surface:` face au smudge.** Lus dans l'arbre principal, hors du
  worktree, donc hors d'atteinte. Vérifié, pas supposé (P8).
- **L'historique face au smudge.** Le commit sur vert ne prend que les chemins approuvés :
  ni l'arbre principal ni le blob ne bougent (P7).
- **`CAPABILITY=off` et le témoin.** L'AC 4 de [15] tient : la clé n'éteint pas le témoin
  (P5c). C'est la *note d'aveu* qui manque quand `RETRO=off`, pas le témoin.
- **La lentille de la même itération et le `$HOME`.** Confirmé conforme à la limite 3 que
  [15] a écrite : la lentille de l'itération **a bien vu** le
  `$HOME/.claude/settings.json` que la session qu'elle juge venait d'écrire (P5b,
  `seen-by-lens`), et la ligne de dérive arrive après. C'est une limite écrite, pas une
  trouvaille — ne pas la resonder.
- **`RECEIPTS_RETENTION_DAYS`.** Toujours documenté comme un élagage actif, toujours lu par
  personne — vérifié, la seule occurrence hors de l'exemple est `test/smoke.bats`. Déjà
  écrit dans [19] par [45] ; rien à ajouter.

## Recommandation d'ordre

Deux tickets neufs, et le critère est celui du dépôt — minimiser la reprise, jamais la
gravité en exploitation.

- **[46]** porte les trouvailles 1, 2 et 3. Une seule racine et un seul mécanisme : le pin
  de [30], élargi de « ce qu'un contrôle voit » à « ce que git lance et ce que git
  produit » — plus le canal, sans lequel la détection s'évapore sur les runs qui
  s'arrêtent mal. **Avant [11] et [19]** : [11] ajoute une branche de gate donc des
  verdicts au reçu, [19] provisionne les clés de config.
- **[47]** porte la trouvaille 4. **Avant [16] et [18]** : [16] vide le puits où les
  doublons atterrissent, [18] doit implémenter `open_ticket` sur un backend distant et
  doit hériter de la question, pas la redécouvrir.

Ordre proposé : **[09] → [47] → [46] → [16] → [11] → [18] → [19]**. [09] reste en tête
parce qu'il est disjoint (`scheduler.sh`) et que rien ne l'attend.

Voir [[ralph-pack-ordre-livraison]] et [[ralph-pack-pieges-de-harnais]].
