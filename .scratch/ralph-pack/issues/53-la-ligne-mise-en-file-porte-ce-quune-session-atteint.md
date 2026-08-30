# 53 — la ligne mise en file porte trois choses qu'une session atteint

**What to build:** Refermer les trois entrées par lesquelles une session décide de
ce qu'un successeur fera — ou ne fera pas — et rendre durable la raison quand rien
n'est armé. [09] a demandé avec soin ce qu'un successeur hérite comme **ligne de
base** (index de leçons, témoin de capacités, brief de reprise : refusés, sur
l'argument de [40]). Il n'a pas posé la même question sur ce qu'il hérite comme
**contexte d'exécution** : le canal (`successor.log`, un chemin dans la zone qu'une
session écrit), la cible (`FEATURE`, que la ligne ne porte pas du tout), et la
condition de pose (le marqueur, forgeable depuis une itération verte pour autant
de nuits que l'instant choisi).

**Blocked by:** None

**Write-surface:** `.claude/lib/scheduler.sh`, `.claude/loop.sh`,
`.claude/lib/gate.sh`, `.claude/ralph.config.sh.example`, `test/scheduler.bats`,
`test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** securite, frontiere-de-confiance

- [x] **Le canal.** Le successeur n'écrit plus dans un chemin qu'une session
      choisit. Aujourd'hui la ligne finit par `>>'<feature_dir>/successor.log'
      2>&1`, et cette redirection est la **première chose que le shell du job
      fait** — avant `loop.sh`, donc avant tout préflight et tout gate. Deux
      directions, trancher et écrire le prix :
      **déplacer** le journal hors de la zone écrivable (le `.git/` du marqueur, ou
      `$TMPDIR`) — mais [10] a déjà refusé ce raisonnement pour `run.log` et sa
      raison vaut ici : *un journal que personne ne lit n'est pas un journal*, et
      c'est le fichier qu'un humain ouvre au matin ;
      **ou vérifier au réveil** — le job teste que la cible est un fichier ordinaire
      dont il est propriétaire avant de rediriger, et sinon se rabat sur un chemin
      sûr **en le disant**. Un `bash -c` qui teste puis exec est la seule forme
      possible : la redirection d'une ligne `at` n'a pas de garde.
- [x] **La cible.** La ligne mise en file porte `FEATURE`, ou bien le préflight
      refuse d'armer quand `FEATURE` ne vient pas d'une source que le successeur
      relira. C'est le raisonnement que [31] a imposé pour `RALPH_CONFIG` — « sous
      le nom qu'il a réellement, parce qu'un run lancé avec une autre valeur ne doit
      pas recevoir le défaut en silence » — appliqué au second sélecteur que
      l'environnement fournit. Attention à la conséquence jumelle : le chemin de
      `successor.log` est calculé avec le `FEATURE` du run **mourant**, donc une
      divergence entre les deux fait écrire le journal d'une feature dans le
      répertoire d'une autre.
- [x] **La condition.** Un marqueur ne peut plus éteindre l'armement
      indéfiniment. Aujourd'hui `scheduler_armed_at` ne compare que son premier
      champ à `now`, donc l'instant écrit — par une session, depuis une itération
      verte — décide combien de nuits. Une borne dérivée du critère et non d'un cas
      : un marqueur ne peut légitimement pointer plus loin que le plafond de la
      fenêtre qui l'a produit (`scheduler_deadline` connaît déjà ces plafonds :
      5 h / 7 j), donc un marqueur au-delà est un marqueur que ce pack n'a pas pu
      écrire. Garder la direction prudente de [09] (un forgé *empêche*, il n'arme
      pas), mais la borner.
- [x] **La raison atteint un document durable.** Le refus « one is already armed
      for this working tree » est un `scheduler__log`, donc stdout, donc perdu avec
      le process ; `run.log` enregistre `weekly-pause`, qui est **le mot exact d'un
      projet ayant choisi `WEEKLY_RESUME=human`**. Un lecteur du matin ne peut pas
      distinguer les deux. Même famille que ce que [46] a réparé pour la dérive de
      capacités : `run.log` n'est écrit que par le pilote, et une garantie portée
      par un `loop_log` meurt avec le process.
- [x] **Le troisième état du mur budget est nommé.** Un run tué entre le mur et la
      queue de `loop_main` laisse `budget-wall` **seul** — mesuré, l'angle (a) de
      [09] supposait `run.log` muet et c'était faux. Les trois fins se distinguent
      donc déjà ; ce qui manque est que le troisième état soit écrit quelque part
      comme un état, au tableau et dans l'en-tête de `scheduler.sh`.
- [x] **Un marqueur orphelin est compté.** `gate_leftovers` compte les `*.guard`
      morts de la feature depuis [49] et les répertoires de `$TMPDIR` depuis [36] ;
      `<gitdir>/ralph.successor` n'est compté par personne. Inerte quand son instant
      est passé — donc c'est un constat, pas un rouge, exactement comme les deux
      autres.

## Ce qui a été mesuré, le 30/08/2026 (passe transversale)

Sondes conservées dans `.scratch/ralph-pack/sondes/passe-30-08/` :
`r2-le-marqueur-que-personne-ne-balaie.bats`,
`r3-successor-log-en-zone-ecrivable.bats`, `r4-deux-features-un-arbre.bats`,
`r1-le-kill-entre-le-mur-et-la-queue.bats`.

- **`R3a`** — `successor.log` est un **répertoire** au réveil :
  `bash: … Is a directory`, job `exit 1`, **`loop.sh` ne démarre jamais** (0 appel
  `claude`, 0 appel `curl`). Le message part dans le mail d'`at`, c'est-à-dire dans
  le silence que la redirection existait pour éviter.
- **`R3b` / `R3d`** — `successor.log` est un **lien** vers `.claude/settings.json`,
  qui est scellé. `R3d` le fait bout en bout depuis une session : l'itération qui
  pose le lien est **verte** (`tests=green typecheck=green scope=green lang=green`,
  `01-alpha resolved`), et au réveil le successeur écrit dans le fichier scellé —
  153 → **1240 octets**, JSON cassé pour tout `claude` suivant. Le scellement n'est
  pas contourné, il est **hors circuit** : l'écrivain est le pack, à un instant où
  aucun run n'existe.
- **`R4a`** — un run lancé `FEATURE=x bash loop.sh` (la forme livrée du config est
  `FEATURE="${FEATURE:-}"`) annonce « armed a one-shot successor », journalise
  `successor-armed`, écrit le marqueur — et le successeur sort **`exit 2`,
  « FEATURE is empty »**.
- **`R2b`** — marqueur forgé à ~5,8 j : **nuit 1 et nuit 2** refusées, marqueur
  intact, `run.log` = `budget-wall weekly-pause` les deux fois, rien de durable ne
  nomme le marqueur.
- **`R2c`** — la pose est à portée d'une itération **verte** (`scope=green`,
  `01-alpha resolved`) par `git rev-parse --git-common-dir`. `.git/` est hors de
  portée d'un `git add -A`, d'un `git clean` et d'un `rm -rf .scratch` — et par la
  même occasion hors de portée de tout gate et de tout compteur.
- **`R2a`** — un marqueur laissé par un successeur qui ne s'est jamais réveillé
  (le cas `atrun` désactivé, que le tableau assume) n'est nommé par personne.
- **`R4b` / `R4c`** — angle disculpé : deux runs concurrents sur deux features d'un
  arbre sont refusés par le **verrou d'arbre** avant que la question du marqueur se
  pose. Séquentiellement, la première feature prend l'unique créneau de l'arbre :
  comportement voulu, à écrire et non à réparer.

## Ce qu'il faut savoir avant d'ouvrir ce code

- **`FEATURE="${FEATURE:-}"` posé après un `FEATURE='demo'` ne stage rien.** La
  forme livrée relit la variable de shell que la ligne précédente vient de poser.
  Pour tester « FEATURE ne vient que de l'environnement », il faut **retirer** la
  ligne injectée par le harnais, pas en ajouter une après. Mesuré par une sonde
  jetable avant d'en conclure quoi que ce soit.
- **`set +e` dans un corps de sonde désarme le `false` final** : la sonde rend `ok`
  et n'imprime rien. `set -e` juste avant le `false`.
- **Le test qui tient « le successeur démarre vraiment » doit exécuter la ligne
  mise en file**, pas la lire. C'est la règle que [09] a écrite pour l'armement
  (« une garantie “le job programmé est un run du pack” s'exécute, elle ne se lit
  pas ») et elle vaut deux fois ici : les trois défauts de ce ticket sont
  invisibles à une assertion sur le texte de la ligne.
- **Le cache de 180 s de [08]** ne fait poser qu'une question d'usage par run :
  `USAGE_CACHE_TTL=0` pour servir un second corps de `usage_respond`.
- **Un test qui fait échouer `at` fait tomber la chaîne sur `systemd-run`** :
  épingler `SCHEDULER=at`.

## Ce qui a été livré, le 30/08/2026

**Le canal — vérifier au réveil, et le journal reste où un humain l'ouvre.** La
ligne ne redirige plus, elle exécute `bash -c '<scheduler__wake>' ralph-successor
<log> <repli> <loop.sh>`. Quatre refus : un lien sur le chemin, un lien sur son
répertoire immédiat, un non-fichier ou un fichier d'un autre propriétaire, un
append qui échoue. Le repli est `<gitdir>/ralph.successor.log`, à côté du
marqueur. Trois décisions à l'intérieur :

- **un refus n'est jamais fatal.** Le défaut mesuré était que le job mourait
  *avant* `loop.sh` ; un garde qui refuse la nuit aurait été le même défaut par
  l'autre bout. Si les deux chemins sont pris, le successeur tourne quand même,
  sortie où le planificateur voudra.
- **la phrase voyage par `RALPH_SUCCESSOR_NOTE`** et `loop_main` la journalise
  (`successor-log-refused`). Le repli est dans le répertoire git, où personne ne
  va regarder : dire dans le fichier de repli qu'on a écrit dans le fichier de
  repli n'est pas le dire. L'environnement est le seul canal qu'un shell qui n'a
  pas encore sourcé le pack partage avec lui.
- **une seule ligne.** Le shim d'`at` enregistre `command: <une ligne>` et
  `sched_queued_command` la relit par `sed` ; un script multi-ligne aurait cassé
  la lecture de la file dans tous les tests et dans les sondes. Les trois
  fragments sont assemblés par `printf '%s %s %s\n'` pour rester lisibles en
  source.

**La cible.** `FEATURE` est sur la ligne, sous le nom qu'il a réellement. Referme
la conséquence jumelle : le chemin du journal est calculé avec le `FEATURE` du
run mourant, donc les deux d'accord est ce qui garde le successeur d'une feature
hors du répertoire d'une autre. **Pas de garde « refuser d'armer si `FEATURE` est
vide »** : le préflight l'a déjà refusé en 2, donc ce garde ne pourrait jamais
rougir — c'est la règle de [47], ne pas livrer une réparation qu'aucune mutation
ne peut rendre rouge.

**La condition.** `scheduler__ceilings` est devenu **une table** (nom → plafond)
avec deux lecteurs : `scheduler_deadline` pour l'instant qu'un mur donne,
`scheduler_armed_at` pour l'instant qu'un marqueur prétend, borné par
`scheduler__ceiling_max`. Dérivé et non retapé : une fenêtre ajoutée élargit les
deux ou aucun. **Le prix, explicite** : un marqueur forgé *à l'intérieur* du
plafond est indiscernable d'un vrai et achète jusqu'à sept nuits, contre un
nombre illimité avant. Rien ici ne peut répondre « qui a écrit ce fichier » ; ce
qui est répondable est « ce pack aurait-il pu l'écrire ».

**La raison.** `scheduler_arm` rend un **code par refus** (1 human, 2 residue,
3 instant, 4 marker, 5 mechanism) et `scheduler_outcome` le traduit en mot de
journal. Un code et pas une variable : le pilote lit `scheduler_arm` à travers
une substitution de commande, et une variable posée dans un sous-shell y meurt —
le piège de [10]. Limite à connaître : le journal porte le **genre** du refus,
pas l'instant ; la sonde `R2b` cherche la phrase « already armed » et continuera
de répondre « (nowhere durable) », c'est sa question qui est périmée, pas la
réponse. Un lecteur qui veut l'instant lit le marqueur — que `gate_leftovers`
nomme avec sa date une fois périmé.

**Le troisième état** est écrit dans l'en-tête de `scheduler.sh` (les trois fins
d'un mur hebdo) et au tableau.

## Écarts et pièges

- **Écart de write-surface** : `.claude/lib/gate.sh` n'était pas dans la liste et
  il le fallait pour le marqueur orphelin (`gate__stale_successor`). Ajouté
  ci-dessus. Conséquence de couche : `scheduler__marker` avait un second appelant
  et un nom privé à deux appelants est un mensonge — renommé
  **`scheduler_marker_path`**, public (`test/layering.bats` aurait refusé
  l'autre). C'est la règle 6 de CLAUDE.md appliquée telle quelle.
- **Ce que le `-L` ne couvre pas** : il porte sur le chemin et sur son répertoire
  **immédiat**. Un lien posé plus haut (`.scratch/` lui-même) fait écrire un
  fichier nommé `successor.log` ailleurs — un fichier de plus, jamais un fichier
  scellé, puisque le nom ne change pas. Écrit au tableau plutôt que découvert.
- **TOCTOU assumé** : entre le test et le `exec` il y a une fenêtre. Ce qui la
  borne n'est pas le code mais le fait qu'à cet instant aucun run n'existe, donc
  aucune session non plus.
- **Le repli est dans `.git/`, que la même session atteint** (`r2c`) : ce n'est
  pas un abri, c'est un second essai.
- **`FEATURE="${FEATURE:-}"` posé après le pin du harnais ne stage rien.** Le
  test retire la ligne du config (`sched_feature_from_the_environment_only`) au
  lieu d'en ajouter une.
- **Mutations recalibrées** (6, toutes attendues, aucune VACUOUS) : les trois
  plafonds de `scheduler_deadline` sont passés dans la table ; la ligne du
  `loop.sh` mis en file a perdu son `\` final ; la redirection a quitté
  `scheduler_command` pour `scheduler__wake` ; le mot du journal a quitté
  `loop.sh` pour `scheduler_outcome`. Et le test « lands beside the run journal »
  **exécute** maintenant la ligne : depuis que la redirection est dans un script,
  une ligne qui nomme `successor.log` n'est plus une preuve qu'on y écrit — il
  serait resté vert sur la mutation qui retire le `exec >>`.
- **Sondes du 30/08 rejouées sur la branche** : `R3a` le job sort 6 au lieu de 1,
  1 appel `curl` au lieu de 0, `run.log` porte
  `successor-log-refused budget-wall successor-armed` ; `R3d` bout en bout depuis
  une itération verte, `settings.json` **153 → 153** octets ; `R4a`
  `run start (feature=demo …)` au lieu d'`exit 2` ; `R2a` le marqueur périmé est
  nommé au démarrage du run suivant ; `R2b` inchangé et c'est le prix écrit
  ci-dessus (5,8 j est *sous* le plafond).

## Ce que ça laisse au ticket suivant

**[52]** (`PATH`) pose son garde sur les mêmes fonctions. `scheduler__wake` est le
**préflight du job** : c'est là que va tout ce qui doit être vrai *avant* qu'on
fasse confiance à `loop.sh` pour le vérifier, et le commentaire de la fonction le
dit. Trois contraintes pour y loger quelque chose : la sortie doit rester **une
seule ligne** ; les chemins arrivent en positionnels (`$1` log, `$2` repli,
`$3` loop.sh) donc un argument ajouté décale la numérotation — l'ajouter **après**
`$3` ; et le shell du job est bash par chemin absolu, pas `sh` (le `-O` de la
clause de propriété n'est pas POSIX).
