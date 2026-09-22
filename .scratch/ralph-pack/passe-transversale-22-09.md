# Passe transversale du 22/09/2026

Quatorzième passe. Faite sur `main` à `ce4be5b` (merge de [89]). Cinq livraisons
depuis celle du 14/09 : [87] `726e62c`, [90] `03ddac5`, [86] `392774e`,
[88] `e007d84`, [89] `ce4be5b`.

Deuxième passe sans aucun ticket derrière elle : les 90 tickets du tracker sont
résolus. Ce qu'elle trouve **est** la file.

Sondes conservées : `sondes/passe-22-09/` (README avec le verdict de chacune).
**Ni `.claude/`, ni `test/`, ni `init.sh` touchés** → la baseline de [89] tient
telle quelle (`run.sh` 975/0/6 skips, `mutate.sh` 1024/0) et les deux gates n'ont
pas été rejoués.

---

## La racine

> **Le pack épingle tout ce qu'il exécute, et rien de ce qui le juge.** Treize
> passes ont demandé *« qu'est-ce qu'une session peut écrire que rien ne
> vérifie ? »* et deux tickets ont élargi la réponse à ce qui décide de ce que le
> pack **exécute** ensuite — la configuration git ([46]), le `PATH` ([52]).
> Celle-ci pose la question à l'objet pour lequel tout le reste existe : **le
> verdict du gate**. Il a trois couches, et le pack n'en épingle aucune.

Le verdict d'une itération, c'est cette ligne :

    gate__start "$dir" tests bash -c "$TEST_CMD"

Trois choses en décident, et elles se lisent de l'extérieur vers l'intérieur :

1. **le shell qui l'exécute** — `bash`, résolu par le `PATH`, et absent des
   trente-deux noms que [52] surveille ;
2. **l'état que la commande lit** — dans ce dépôt, le gabarit de projet que le
   harnais garde sept jours dans `$TMPDIR`, qui contient une copie du pack et
   qui est le pack que la suite teste réellement ;
3. **le fichier où le verdict est écrit** — `$dir/tests.rc`, dans un répertoire
   `mktemp` qu'un `ls` énumère, pendant que tourne ce qu'une session a laissé
   derrière elle.

Les trois sont mesurés ci-dessous, chacun avec son témoin appairé, et chacun
produit **un run vert, un ticket `resolved`, et pas une ligne**.

**Ce qui rend la racine nette plutôt qu'accusatrice** : le pack *connaît* cette
classe. La ligne « un témoin bâti avec git ne témoigne pas contre git » est dans
le tableau depuis [46]. Le commentaire de `gate__path_where` nomme explicitement
*« le `bash -c` de `TEST_CMD` »* comme partie exposée. La ligne « Ce qu'une
session peut atteindre pendant qu'une autre itération est jugée » décrit mot pour
mot l'attaque de §2 — `.rc` par branche compris — et la borne à `MAX_PARALLEL>1`.
Ce que la passe trouve n'est pas une classe neuve : c'est que **les trois bornes
posées autour de cette classe sont fausses à la valeur livrée**, chacune pour une
raison différente, et qu'aucune des trois n'avait été mesurée.

---

## §1 — Le verdict passe par un nom que le manifeste ne connaît pas

Sonde `q2`. Mesuré dans les deux sens.

[52] a sorti le `PATH` de la ligne « limite assumée » : la **résolution et le
contenu des noms que le pack lance par leur nom nu** sont épinglés au démarrage
du run, comparés à chaque itération, et un mouvement refuse d'armer le
successeur (`scheduler_arm` code 6, `successor-blocked-path`). La liste est
`gate_path_programs` : **trente-deux noms, écrits à la main**.

`bash` n'y est pas. Il est lancé par son nom nu quatre fois dans le pack livré :

| Site | Ce qu'il porte |
|---|---|
| `gate.sh:3814` | `bash -c "$TEST_CMD"` — la branche `tests` |
| `gate.sh:3821` | `bash -c "$TYPECHECK_CMD"` — la branche `typecheck` |
| `playthrough.sh:291` | `bash -c "$cmd"` — `RUN_CMD` et `VISUAL_CMD`, le gate de valeur |
| `scheduler.sh:510` | `command -v bash`, figé dans la ligne mise en file du successeur |

Mesuré sur une itération verte réelle, avec un `bash` enregistreur en tête du
`PATH` : **treize** passages, dont les **quatre** qui portent un verdict —
`-c stub-cmd tests`, `-c stub-cmd typecheck`, `-c stub-cmd run`,
`-c stub-cmd visual`. Le manifeste que le run épingle
(`gate_path_witness`) fait trente-deux lignes et aucune ne dit `bash`, donc
`gate__path_moved` reste muet et le successeur est armé.

Ce n'est pas la dette que le tableau nomme déjà (*« un site d'appel ajouté au
pack dans un programme absent de la liste rouvre le trou »*) : ces quatre sites
sont **antérieurs** à [52]. La liste n'a pas dérivé — elle était incomplète le
jour où elle a été écrite, et le nom qui manque est celui par lequel passent les
quatre commandes du projet.

Et `scheduler.sh:510` est le second étage du même défaut : le shell du
successeur est résolu par `command -v`, c'est-à-dire par **la fonction que le
commentaire de `gate__path_where` interdit en toutes lettres** — *« `command -v`
et `type -P` répondent depuis la table de hachage de bash »* — puis figé dans une
ligne qui s'exécutera des heures plus tard. Que la réponse vienne de la table ou
du `PATH`, elle n'est comparée à rien, parce que le nom n'est pas surveillé.

**Le second demi-cas, qui est une décision et pas un oubli** : le premier mot de
`TEST_CMD`, `TYPECHECK_CMD`, `RUN_CMD`, `VISUAL_CMD` (`npm`, `jest`, `pytest`,
`cargo`…) est un programme que le pack fait exécuter à chaque itération et dont
il croit le code de sortie plus que n'importe quoi d'autre. Il est hors du
critère de [52] — *« ce que **ce pack** lance par son nom nu »* — parce qu'il est
lancé par la ligne de commande du projet. Quatre valeurs de configuration
suffisent à le dériver ; c'est l'autre moitié du ticket, et elle se tranche.

---

## §2 — Un process laissé par une session écrit le verdict du gate, à `MAX_PARALLEL=1`

Sonde `q3`. Mesuré, témoin appairé.

La ligne « Ce qu'une session peut atteindre pendant qu'une **autre** itération
est jugée » du tableau repose sur une prémisse écrite en toutes lettres :

> *« Jusqu'ici aucune session n'était vivante pendant qu'un gate écrivait : le
> gate tourne après la session qu'il juge, donc ses fichiers de verdict dans
> `$TMPDIR` — un `.rc` par branche, le marqueur `timed-out`, le témoin d'ignore,
> le répertoire de slot — n'étaient à portée de personne. Avec deux itérations en
> vol c'est faux. »*

Et sa borne : *« `MAX_PARALLEL=1` est la valeur livrée et rien de tout ça n'est
ouvert à cette valeur. »*

**La prémisse est fausse à `MAX_PARALLEL=1`.** « La session a fini » et « les
process de la session ont fini » sont deux choses, et le pack ne confond les deux
que sur les chemins d'échéance. `proc_kill_tree` — la marche d'arbre qui existe
précisément *« parce que tuer le process seul laisserait tourner ce qu'il a
démarré — une suite de tests qui pend, un serveur de dev monté par l'outil Bash
d'une session »* — a **quatre** appelants, et les quatre sont des échéances :
`monitor__reaper` (TERM puis KILL), le chien de garde du gate, celui du
playthrough. Une session qui **finit normalement** n'est marchée par personne.

Mesuré, `MAX_PARALLEL=1`, suite rouge (`stub_exit tests 1`) dans les deux cas :

| | Ce que le run fait |
|---|---|
| **Témoin appairé** — aucun survivant | `tests=red` trois fois, deux retries frais, ticket `ready-for-human`, `exit 4` |
| **La même suite rouge**, la session laisse un process derrière elle | `tests=green typecheck=green scope=green lang=green`, ticket **`resolved`**, run `exit 0`, **dès la première itération** |

Le survivant est un `nohup bash -c '…'` de quarante lignes qui attend
`$TMPDIR/ralph-gate.*` et réécrit `0` dans les `.rc`. Il a vu le répertoire du
gate, et aucune ligne du run ne le nomme — `gate_run` finit par `rm -rf "$dir"`,
donc il n'en reste rien non plus.

Troisième mesure, sans rien d'hostile : une session qui laisse un `sleep` est
**encore vivante quand le run a fini**, reparentée à `init` (`ppid 1`), et le run
n'en dit pas un mot. C'est le cas ordinaire — un serveur de dev, un watcher, une
suite de tests en fond — et c'est celui que le commentaire de `proc_kill_tree`
décrit pour expliquer pourquoi la marche existe.

**Ce que ça change dans le tableau** : la ligne 35 n'est pas seulement à élargir,
sa borne est à réécrire. Et elle en emporte une autre — `$dir/*.rc` est
exactement la forme de [80] (*« un nom indevinable dans un répertoire
énumérable »*), un `mktemp` sous `$TMPDIR` que le sceau de [81] ne couvre pas
puisqu'il est créé **après** le sceau, par le gate lui-même.

**Ce que la passe ne tranche pas, et qui est le contenu du ticket** : il y a deux
réparations, elles ne coûtent pas la même chose et elles ne ferment pas la même
chose.

- *Le canal du verdict.* `gate__await` jette le statut des branches à dessein —
  *« le verdict d'une branche est le fichier `.rc` qu'elle a écrit »* — alors que
  `proc_collect` le lui rend. Reprendre le statut du `wait` fait passer le verdict
  par un canal qu'aucun process extérieur ne peut écrire, et laisse le `.rc`
  comme diagnostic. C'est petit, et ça ferme §2 tel qu'il est mesuré.
- *La marche d'arbre au retour normal.* Elle ferme la classe et pas seulement ce
  canal — mais elle ne peut pas être « `proc_kill_tree` sur le pid de la session
  après coup » : le pid est mort, ses enfants sont déjà reparentés à `init`, la
  marche ne trouve rien. Il faut un **groupe de process**, que le commentaire de
  `proc_kill_tree` dit justement que ce shell ne fabrique jamais. C'est une
  décision de conception avec un prix, pas un correctif.

---

## §3 — La suite qui juge est bâtie à partir d'un cache que la session écrit

Sonde `q1`. Mesuré de bout en bout, témoin appairé et contre-témoin.

C'est la question que [89] a explicitement laissée à cette passe, et elle est
plus large que ce que son ticket décrivait. Le cache des globals
(`ralph-harness.globals.<empreinte>`) est la moitié inoffensive : il n'alimente
que `harness__clear_env`, et les noms qu'il fait oublier ne peuvent être posés
que par le shell d'un humain ([89] l'a tranché). **La moitié qui porte est le
gabarit de projet**, et il date de [01] :

`harness__template` garde sous `$TMPDIR/ralph-harness.<empreinte>/project` un
projet complet, `.git` compris — et `harness__install_pack` y a copié
`loop.sh`, `human-loop.sh`, `settings.json` et les vingt-quatre libs. Chaque test
fait `cp -R "$template/project" "$PROJECT_DIR"`. **Le pack que la suite teste est
cette copie, pas celle du dépôt.** L'empreinte est un `cksum` de
`.claude init.sh test/fixtures test/helpers/harness.bash`, donc calculable par
qui lit l'arbre — et la fonction qui la calcule est dans l'arbre.

Mesuré, en jouant la chaîne dans l'ordre où une session la joue :

| | |
|---|---|
| **A** run propre | vert, gabarit bâti sous `fp0 = 3290877307` |
| **B** une garantie du pack retirée (`state.sh`, entrée existante de `mutate.sh`) | `fp1 = 1448025410` |
| **C** la session dépose sous `fp1` une copie du gabarit **propre** | — |
| **D** `TEST_CMD` relancé | **vert** — `1 tests, 0 failures` |
| **E** témoin appairé : on retire le dépôt, tout le reste identique | **rouge** — `test/state.bats:94: failed` |
| **F** contre-témoin : pack restauré, sans forge | vert |

Le pack de l'arbre est cassé, la suite dit vert. C'est la forme de [80] posée au
harnais : un objet indevinable dans un répertoire énumérable, sauf qu'ici il
n'est même pas indevinable — il est **adressé par le contenu**, donc une session
qui sait ce qu'elle va rendre au gate sait sous quelle clé déposer.

**Ce qui empêche d'appeler ça un accident** : la durée de vie du cache est une
décision, prise et défendue par un test. `init.sh sweep` balaie tout ce que
`gate_tmp_names` nomme et **préserve** `ralph-harness.*`, avec sa raison écrite :
*« the suite's template cache is kept seven days on purpose »*. C'est [62] qui a
refusé le motif `ralph-*` pour cette raison exacte. La décision est bonne ; la
question 5 ne lui a jamais été posée.

**Ce qui borne la portée, et il faut le lire avant de dimensionner le ticket** :
ce dépôt n'est **pas** installé sur lui-même — il n'y a pas de
`.claude/ralph.config.sh`, les deux gates sont lancés à la main. Le canal mesuré
n'est donc pas un faux vert livré ici ; c'est le canal que reçoit **tout projet
installé avec ce pack dont la commande de test garde un cache hors du dépôt** —
`jest`, `pytest`, `gradle`, `ccache`, `node_modules/.cache`. Le pack ne peut pas
fermer ça : il diffe des trees git, et ce qui est hors de l'arbre lui est
structurellement invisible (ligne 57 du tableau). Ce qu'il peut faire est ce que
[39] a posé comme posture — **nommer ce qu'on ne sait pas adresser** — et ce que
ce dépôt peut faire pour sa propre suite est valider le cache contre sa source,
puisque le gabarit n'est que le cache d'une fonction pure du pack.

---

## Ce que la passe a regardé et disculpé

Écrit pour que ça ne soit pas re-sondé.

- **Le cache des globals de [89] pris au sens étroit.** `ralph-harness.globals.*`
  n'alimente que `harness__clear_env`. Une version forgée fait oublier des noms
  que seul le shell d'un humain peut poser — aucun n'est exporté vers une session
  ([89]). Sans conséquence prise seule ; elle vit sous le même préfixe et la même
  clé que le gabarit, donc elle est réparée par le même geste.
- **`test/mutate.sh` n'est pas un canal de session.** Il édite les fichiers réels
  en place dans l'arbre principal et se lance à la main. Rien d'une itération ne
  l'atteint, et l'empreinte du gabarit change à chaque mutation — c'est ce qui
  fait que le second gate ne peut pas hériter d'un gabarit forgé.
- **L'adressage par le contenu est ce qui rend le cache *accidentellement* sûr.**
  Un gabarit périmé ne peut pas produire un faux vert tout seul : la clé change dès
  que le pack change. Le canal exige qu'une session calcule l'empreinte de l'arbre
  qu'elle s'apprête à rendre. C'est faisable en trois lignes, mais ce n'est pas
  atteignable par hasard, et ça ne se répare donc pas en raccourcissant les sept
  jours.
- **L'écriture d'un verdict par une session *sœur*** (`MAX_PARALLEL>1`) est déjà
  nommée, mesurée et assumée par le tableau. §2 ne la rouvre pas : il montre que
  la borne « rien de tout ça n'est ouvert à `MAX_PARALLEL=1` » est fausse.
- **`gate_config_keys` (53 entrées) et `gate_path_programs` (32 noms) portent la
  même dette de liste écrite à la main**, et le tableau le dit déjà aux deux
  endroits. §1 n'ouvre pas la dette générale : il traite le seul nom manquant qui
  porte un verdict.
- **Le rouge instable de `test/budget.bats`** (*« a lens the gate's own deadline
  killed is not read as a refusal »*, famille de [38]) n'a pas tiré pendant cette
  passe. Disculpé par la voie structurelle de [57] ; ne pas le poursuivre.

---

## Les tickets

| # | Ce qu'il ferme | Fichiers |
|---|---|---|
| **[91]** | le shell qui porte les quatre commandes du projet entre dans ce que le run épingle, et le premier mot des quatre commandes est tranché | `.claude/lib/gate.sh`, `.claude/lib/scheduler.sh`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |
| **[92]** | le verdict d'une branche ne passe plus par un fichier qu'un survivant écrit, et ce qu'une session laisse derrière elle est tranché | `.claude/lib/gate.sh`, `.claude/lib/proc.sh`, `.claude/lib/monitor.sh`, `.claude/lib/session.sh`, `test/gate.bats`, `test/proc.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |
| **[93]** | le gabarit du harnais cesse d'être une entrée de confiance de la suite qui juge, et ce qu'aucun pack ne peut tenir sur le cache d'un projet est nommé | `test/helpers/harness.bash`, `test/smoke.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md` |

### Ordre proposé

**[91] → [92] → [93]**, critère habituel — minimiser la reprise, jamais
l'urgence :

1. **[91] devant** : c'est le plus petit, il est local à une liste et à sa
   dérivation, et il ferme la couche **la plus extérieure** du même objet. Un
   `bash` planté rend inutile n'importe quelle réparation faite à l'intérieur du
   gate — dont celle de [92]. Un plancher avant la pièce.
2. **[92] ensuite** : le plus gros, et le seul qui touche le cycle de vie d'une
   session. Il réécrit la borne de la ligne 35 du tableau, que [93] va citer.
3. **[93] en dernier** : purement dans `test/`, aucune surface du pack, et il
   hérite des deux lignes de tableau que les deux autres viennent d'écrire — la
   sienne est l'aveu générique dont [91] et [92] sont les deux cas adressables.

Arêtes : [91] → [92] (le plancher avant la pièce), [92] → [93] (la borne
réécrite avant l'aveu qui la cite). Aucune autre.
