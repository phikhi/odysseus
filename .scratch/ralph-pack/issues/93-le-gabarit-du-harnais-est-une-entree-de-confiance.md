# 93 — Le gabarit du harnais est une entrée de confiance de la suite qui juge

**What to build:** Que le gabarit de projet gardé sous `$TMPDIR` cesse d'être cru sur parole par la suite qui décide si une itération est verte — et que ce qu'aucun pack ne peut tenir sur le cache de la commande de test d'un projet soit nommé dans le tableau.

**Blocked by:** 92

**Write-surface:** `test/helpers/harness.bash`, `test/smoke.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Le gabarit est **validé contre sa source** au moment où il est estampé, ou la suite cesse de le partager entre runs. C'est le cache d'une fonction pure du pack : comparer la sortie à l'entrée est ce qu'un cache doit faire, et l'empreinte lit déjà tout le pack à chaque `harness_setup`, donc le prix est connu et mesurable.
- [x] Le geste couvre les **deux** objets de ce préfixe : `ralph-harness.<empreinte>/project` et `ralph-harness.globals.<empreinte>`. Le second est sans conséquence pris seul ([89]), mais il vit sous la même clé et se répare du même geste.
- [x] Les deux décisions existantes sont **préservées ou retranchées explicitement** : les sept jours de conservation, défendus par un test de `init.sh sweep` (*« the suite's template cache is kept seven days on purpose »*), et le refus du motif `ralph-*` par [62] pour cette raison exacte. Réduire la durée ne répare rien — l'adressage est par contenu.
- [x] Le tableau porte la ligne générique : **ce que la commande de test d'un projet lit hors du dépôt n'est tenu par rien**, et ne peut pas l'être par un pack qui diffe des trees git. Posture de [39] — nommer ce qu'on ne sait pas adresser plutôt que faire semblant.
- [x] Le test qui tient tout ça met en scène la chaîne complète (pack cassé + gabarit forgé) et asserte **ce qui a changé**, avec son témoin appairé.
- [x] Une entrée de mutation par garantie livrée, avec le témoin appairé.

## Comments

- **Ordre validé par Philippe le 22/09/2026** : **[91] → [92] → [93]**.
  Le critère est celui d'habitude — minimiser la reprise, jamais l'urgence. [91]
  devant parce qu'un `bash` planté possède l'interpréteur des quatre commandes du
  projet et rendrait inutile toute réparation faite à l'intérieur du gate ; [92]
  ensuite, seul ticket qui touche le cycle de vie d'une session, et il réécrit la
  borne de la ligne 35 du tableau ; [93] en dernier, purement dans `test/`, sa
  ligne de tableau étant l'aveu générique dont les deux autres sont les cas
  adressables.

- **Ouvert par la passe transversale du 22/09/2026** (`../passe-transversale-22-09.md`,
  §3). Sonde : `../sondes/passe-22-09/q1-le-cache-du-harnais.sh`.
  C'est la question que **[89] a explicitement laissée à cette passe**, et elle est
  plus large que son ticket ne la décrivait.

- **Mesuré de bout en bout.** `A` run propre → gabarit sous `fp0 = 3290877307`.
  `B` une garantie du pack retirée (`state.sh`, entrée existante de `mutate.sh`)
  → `fp1 = 1448025410`. `C` une copie du gabarit **propre** déposée sous `fp1`.
  `D` `TEST_CMD` relancé → **vert**, `1 tests, 0 failures`. `E` témoin appairé,
  dépôt retiré → **rouge**, `test/state.bats:94: failed`. `F` contre-témoin, pack
  restauré → vert. Le pack de l'arbre est cassé et la suite dit vert.

- **Pourquoi le gabarit et pas le cache des globals.**
  `harness__install_pack` copie `loop.sh`, `human-loop.sh`, `settings.json` et
  les vingt-quatre libs dans `$TMPDIR/ralph-harness.<empreinte>/project/.claude`,
  et chaque test fait `cp -R "$template/project" "$PROJECT_DIR"` : **le pack que
  la suite teste est cette copie, pas celle du dépôt**.

- **L'adressage par le contenu est ce qui le rend accidentellement sûr, et
  délibérément atteignable.** Un gabarit périmé ne peut pas produire un faux vert :
  la clé change dès que le pack change — c'est aussi ce qui protège
  `test/mutate.sh`. Le canal exige qu'une session calcule l'empreinte de l'arbre
  qu'elle s'apprête à rendre au gate, avec la fonction qui est dans l'arbre.

- **La portée, à lire avant de dimensionner.** Ce dépôt n'est **pas** installé sur
  lui-même — pas de `.claude/ralph.config.sh`, les deux gates sont lancés à la
  main. Ce n'est donc pas un faux vert livré ici ; c'est le canal que reçoit tout
  projet dont la commande de test garde un cache hors du dépôt (`jest`, `pytest`,
  `gradle`, `ccache`, `node_modules/.cache`). Le pack ne peut pas le fermer : ce
  qui est hors de l'arbre lui est structurellement invisible (ligne 57 du tableau).
  Ce dépôt peut fermer le sien.

- **Hérité de [92]** : la ligne de tableau écrite ici est l'aveu générique dont
  [91] et [92] sont les deux cas adressables. Elle se lit après la borne que [92]
  réécrit, pas avant.

- **Ce que [92] laisse, livré le 23/09/2026.** La borne de la ligne 35 est
  réécrite et une ligne neuve a été ajoutée sous elle (« ce qu'une session laisse
  **tourner** derrière elle »). La ligne générique de ce ticket se lit après les
  deux. Et ce que [92] a nommé sans le refermer appartient à la même famille, donc
  à relire en écrivant la ligne générique : dans le répertoire du gate,
  `<branche>.out`, `scope.class` et `lang.zone` restent à portée de ce qu'une
  session laisse tourner. Aucun n'est un verdict — le verdict est le statut de
  sortie de la branche — mais `scope.class` décide d'une classe d'échec, donc d'un
  budget de reprise, et `<branche>.out` devient les constats d'un reçu que lit un
  humain.

- **Livré le 23/09/2026.** `harness__template_verify` compare le gabarit à sa
  source **au moment où il est rendu** et pas au moment où il a été bâti — le run
  qui l'a bâti n'est pas celui qui s'apprête à le croire. Quatre clauses, et
  aucune ne couvre ce qu'une autre couvre :
  **contenu** (chaque import, octet pour octet, par un sceau des deux côtés, avec
  `harness__import_diff` qui nomme le fichier une fois que les deux sceaux ont
  déjà divergé) ; **recensement** (le projet ne porte rien que le recensement ne
  nomme — `loop.sh` source `lib/*.sh` en ordre lexical, donc un fichier qui monte
  dans le gabarit n'est pas un fichier perdu, c'est un module du pack dans tous
  les tests) ; **config** (le seul fichier *généré* et pas copié, donc comparé à
  ce que `harness__install_config` écrit) ; **historique** (`git status` propre,
  ce qui lie `HEAD` à l'arbre déjà vérifié — le pack rejoue `HEAD`, et un lib gardé
  dans le commit et absent de l'arbre ne se voit nulle part ailleurs).
  Un gabarit refusé est **fatal et nommé**, jamais rebâti en silence.

- **La copie n'était pas typée deux fois.** `harness__template_imports` est le
  recensement, et il a **deux consommateurs** : `harness__install_pack` y copie,
  `harness__template_verify` y compare. C'est la forme de [85]/[89]/[91] : un
  recensement retapé au second site est exactement la dérive que ce pack
  n'arrête pas de retrouver. Conséquence pour qui ajoutera un fichier au
  gabarit : il doit passer par le recensement, sinon la clause « recensement »
  refuse **tout de suite et bruyamment**, ce qui est le bon échec.

- **Un défaut préexistant trouvé en écrivant, et fermé.** Le gabarit n'était pas
  une fonction pure du pack : `harness__install_pack` écrivait
  `set_config FEATURE "$RALPH_TEST_FEATURE"` — la feature du *test qui a bâti le
  gabarit*, pas celle du gabarit. Latent seulement parce qu'aucun test n'appelle
  `harness_setup <feature>` (vérifié). Un premier test qui l'aurait fait aurait
  laissé `FEATURE=<autre>` dans le gabarit que tous les tests suivants copient,
  avec un `spec.md` et un tracker sous `demo`. Corrigé
  (`$RALPH_TEMPLATE_FEATURE`), couvert par un test et une entrée de mutation.

- **AC « les deux objets du préfixe » : tranché explicitement, et la moitié
  refusée est nommée.** `ralph-harness.globals.<empreinte>` **n'est pas** comparé
  à sa source. Mesuré avant de décider : redériver le recensement coûte **0,45 s**
  par process, contre **0,54 s** pour un test de `state.bats` — chaque test de
  bats étant son propre process, le valider *est* la suite une seconde fois. La
  version la moins chère qu'on puisse écrire (les trois passes de [89] groupées
  sur tous les fichiers au lieu d'un fichier à la fois) tombe à 0,15 s, soit
  encore +28 %, et elle réécrirait un recensement qui a coûté un ticket.
  **Et il n'existe pas de contrôle moins cher** : une falsification par
  *omission* ne se voit que par la dérivation qu'elle remplace ; un sceau posé à
  côté du cache est dans le même `$TMPDIR` que lui ; une clé secrète est la sortie
  que [80] a déjà disqualifiée. Ce qui rend le refus supportable est la mesure de
  [89] : un nom que ce cache perd est un nom que personne ne désarme, et ça ne
  compte que si un shell **au-dessus du run** l'a exporté — pas un canal qu'une
  session atteint. Écrit dans le code (`harness_pack_globals`) **et** dans le
  tableau, pas seulement ici.

- **Ce que la comparaison coûte, mesuré et pas estimé.** 65 ms par appel, contre
  21 ms pour `harness__pack_fingerprint` que chaque `harness_setup` paie déjà, sur
  un test qui en prend ~540. Soit **+12 %**. Le ticket avait pré-autorisé ce prix
  (« l'empreinte lit déjà tout le pack à chaque `harness_setup` »). Deux décisions
  d'implémentation viennent de là et pas d'une préférence : le sceau est bâti avec
  **un `cat` et un `cksum`** construits dans le shell plutôt qu'à travers
  `awk`/`xargs` (sur cette plateforme le prix est le nombre de process, pas le
  mégaoctet lu), et `harness__quote` quitte `sed` pour une expansion de paramètre
  — équivalence vérifiée sur huit cas dont l'apostrophe, en bash 3.2, et couverte
  par un test et une entrée de mutation, parce que la config est maintenant écrite
  deux fois par test.

- **`GIT_OPTIONAL_LOCKS=0`, et c'est une sonde de run réel.** Un `git status`
  ordinaire rafraîchit l'index, donc prend `index.lock` et **écrit dans le gabarit
  partagé** qu'il est censé attester : deux runners se refuseraient l'un l'autre
  au hasard — un gate qui crie au loup et qu'on finit par éteindre. Sondé : deux
  `test/run.sh` lancés ensemble sur une empreinte neuve (un bâtisseur, un
  attendeur), verts tous les deux. Et le **statut** de `git` est lu à part de sa
  **sortie** : « git n'a rien dit » et « git n'a pas pu être interrogé » sont deux
  réponses et une seule est un arbre propre.

- **Les deux décisions existantes sont préservées, pas subies.** Les sept jours de
  conservation et le refus du motif `ralph-*` par [62] restent, et la raison est
  écrite à l'endroit du balayage : l'adressage est **par contenu**, donc un
  gabarit n'est jamais périmé au sens qu'une durée de vie réparerait ; ce qu'une
  durée de vie n'a jamais acheté, c'est la confiance, et la raccourcir n'aurait
  fait que rendre la copie forgée moins chère à garder fraîche.

- **Ce que les quatre clauses ne couvrent pas, dit ici.** (1) Les **modes** : un
  lib rendu non exécutable dans le gabarit passe — il est sourcé, pas exécuté ;
  `loop.sh` l'est, et un `loop.sh` non exécutable fait rougir le premier test. (2)
  Le contenu de `.git` **au-delà** d'un `status` propre : un `config` ou un reflog
  forgés ne sont pas lus. (3) La vérification **avant `.ready`** sur le chemin du
  bâtisseur (`rm -rf` du root et refus, pour ne pas publier aux autres runners un
  gabarit qui échoue sa propre comparaison) n'a **pas** d'entrée de mutation : la
  mettre en scène demande un build qui rate sa propre vérification, et une entrée
  qui ne rougit pas serait VACUOUS. Elle est ici plutôt que réputée couverte.

- **La ligne du tableau est générique, et c'est l'aveu.** Elle se lit après la
  borne réécrite par [92] (« ce qu'une session peut atteindre pendant qu'une autre
  itération est jugée ») et après la ligne neuve de [92] (« ce qu'une session
  laisse **tourner** »), dont elle est le cas général : ce que la commande de test
  d'un projet lit **hors du dépôt** n'est tenu par rien et ne peut pas l'être par
  un pack qui diffe des trees git. Ce dépôt ferme le sien ; `jest`, `pytest`,
  `gradle`, `ccache`, `node_modules/.cache` restent le canal de tout projet
  installé avec ce pack.

- **Pour la passe suivante, sans en faire un ticket.** Le cache des globals est
  nommé, pas fermé. Ce qui le fermerait vraiment n'est pas un sceau de plus : ce
  serait que `harness__clear_env` cesse de dépendre d'une *liste* (désarmer par
  préfixe ce que l'environnement porte réellement, la liste des noms propres au
  harnais étant dérivée du seul `harness.bash` et du `.bats` en cours). C'est une
  réécriture du mécanisme de [89], mesurée à ~15 ms, et elle n'appartient pas à ce
  ticket — elle appartient à une passe qui aura regardé les deux censi ensemble.

- **Gates, code livré.** `bash test/run.sh` : **997 tests, 0 failures, 6 skips opt-in** (baseline 991 ; aucun skip dans le canari). `bash test/mutate.sh` :
  **1049 mutations, 0 not ok** (baseline 1041) (dont les huit entrées `93 …`, toutes `ok`).
