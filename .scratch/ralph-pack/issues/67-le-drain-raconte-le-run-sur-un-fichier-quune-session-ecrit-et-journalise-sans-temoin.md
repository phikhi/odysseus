# 67 — Le drain raconte le run sur un fichier qu'une session écrit, et journalise sans témoin

**What to build:** Les deux moitiés d'un même fichier. `router_run_notes` tire quatre conclusions de `run.log` sans la réserve que son voisin `router_journal_lines` imprime deux fonctions plus haut, et l'une des quatre est une négation qu'une ligne suffit à faire taire. Et `router_journal` écrit dans le même fichier sans le témoin que `loop_journal_append` tient depuis [10] — alors que ses lignes sont la seule trace de ce qu'un **humain** a décidé.

**Blocked by:** 69

**Write-surface:** `.claude/lib/router.sh`, `.claude/human-loop.sh`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** human-loop, observability, trust-boundary

- [x] Les quatre conclusions de `router_run_notes` arrivent à l'humain avec la réserve que porte `router_journal_lines` — ou avec ce qui la rend inutile. Ne pas laisser une des deux lectures du même fichier réservée et l'autre affirmative.
- [x] La **négation** (`budget-wall` sans `successor-armed`/`weekly-pause`/`successor-blocked-*`) cesse d'être un silence qu'une ligne suffit à acheter : soit elle est dite autrement, soit son absence est dite.
- [x] Le drain tient un témoin de ce qu'il a écrit dans `run.log`, et le dit en fin de drainage quand le fichier ne le porte plus — comme `loop_journal_verify`, et pour la même raison : ces lignes-là sont ce qu'un **humain** a décidé.
- [x] Le témoin est une variable du process du drain et **jamais un fichier** ([08], [10]) : un fichier serait un fichier que la session routée écrit.
- [x] Le témoin est écrit en dehors de tout sous-shell — c'est le piège que [10] a payé (« les lignes de reclaim étaient écrites depuis la droite d'un pipeline ») et son test jumeau « un drain honnête ne s'accuse pas » fait partie des AC.
- [x] Une entrée de mutation par garantie livrée, plus le témoin appairé.

## Comments

- **Trouvé par la passe transversale du 06/09/2026** (`../passe-transversale-06-09.md`, §2 et §3). Sondes : `../sondes/passe-06-09/q2-*.bats` et `q3-*.bats`.

- **Deux lecteurs du même fichier, à deux fonctions d'écart, et un seul porte la réserve.** `router_journal_lines` :

  > That file is under `.scratch/`, which nothing in this pack guards: the session these lines are about could have written them. **Read them, do not rely on them.**

  `router_run_notes` n'en dit rien et affirme quatre choses. L'une est :

  ```sh
  grep -q 'budget-wall' && ! grep -q 'successor-armed\|weekly-pause\|successor-blocked-'
  ```

  dont le commentaire dit *« Nothing in this pack writes that end down as a state »* — cette phrase est le **seul** endroit où cet état est jamais dit.

- **Mesuré** (`q2`), sessions routées réelles dans un drain réel :

  | | |
  |---|---|
  | Q2a — `run.log` portant `budget-wall` seul | la note est dite |
  | Q2b — une session routée ajoute une ligne portant `successor-armed` | `router_run_notes` **rc=1**, la note **disparaît** ; le drain a nommé **0 chemin** |
  | Q2c — témoin appairé, la même session sans la ligne | la note est dite |
  | Q2d — une session routée fabrique `claim-refused` sur un `run.log` **vierge** | le drain suivant dit « the frontier is short of a ticket nothing else would have mentioned » — sur un run qui n'a jamais refusé de claim |
  | Q2e — un run AFK complet passe ensuite sur la ligne fabriquée | run **vert rc=0**, `loop_journal_verify` se tait (**0**), la note est toujours dite après |

  **Q2e est ce qui rend la contrefaçon durable** : le témoin de [10] ne se prononce que sur le **bloc du run courant**, et une ligne écrite *avant* le run entre dans `RALPH_JOURNAL_BASE`. Une ligne posée par un drain est invisible à tous les runs qui suivent — ce n'est pas un défaut de [10], c'est une limite qu'il écrit lui-même (« les lignes des runs *précédents*, qui ne sont pas à ce run de garantir »).

- **Mesuré** (`q3`), la seconde moitié, deux tickets dans le puits :

  | | |
  |---|---|
  | Q3a — l'humain ferme `20-decision` (`c`), puis ouvre une session sur `21-second` qui écrase `run.log` | `20-decision` est **`wontfix`** et **sa ligne `drained` n'existe plus** ; le drain ne se plaint **0** fois, ne nomme **0** chemin |
  | Q3b — témoin appairé, le même écrasement côté AFK | « the run journal does not hold exactly the 2 line(s) this run wrote, where it wrote them: something rewrote … » **plus la copie du run imprimée dessous** |
  | Q3c — témoin appairé, le même drain sans l'écrasement | les deux lignes sont là |

  Les deux points d'entrée donnent des réponses opposées au même événement, et celui qui se tait est celui dont les lignes disent ce qu'un **humain** a voulu. C'est [57] à la lettre, sur un autre objet.

- **Pourquoi le drain n'a rien nommé, et c'est structurel.** `router__tree_dirt` saute `gate_is_bookkeeping`, c'est-à-dire `.scratch/${FEATURE}/`, c'est-à-dire exactement le répertoire de `run.log`. Le garde que le commentaire de `router_desk` nomme pour « ce qu'une session a laissé hors de `issues/` » est aveugle à cette zone par construction. Ce ticket répare le **journal** ; le garde est [66].

- **Ce que le tableau de frontière dit aujourd'hui reste littéralement vrai, et c'est ce qui l'a caché.** La ligne de [10] dit « rien ne le relit pour **choisir ou marquer** ». `router_run_notes` ne choisit rien et ne marque rien : il *raconte*, à l'humain qui va décider. La catégorie n'existait pas quand la phrase a été écrite ; [16] l'a créée. À élargir en livrant plutôt qu'à corriger comme une erreur.

- **Ce qu'il ne faut pas faire, et [10] l'a déjà refusé** : sortir `run.log` de la zone atteignable. C'est le fichier qu'un humain ouvre au matin ; un journal dans `$TMPDIR` est un journal que personne ne lit. Rendre **détectable**, pas inviolable.

- **Contrainte pour [16]** : `human_loop_preflight` est écrit comme *une liste et pas une délégation*. Un témoin ajouté ici ne doit pas devenir un appel à `loop_preflight` par la bande.

- **Piège de sonde.** `grep -c 'journal'` sur la sortie d'un drain compte le libellé du dossier (`journal  its own lines in run.log, below.`) : pour mesurer une plainte, chercher `does not hold exactly`.

- **Place dans la file, validée par Philippe le 06/09/2026 : deuxième**, derrière
  [69] et avant [66]. Il rouvre `human-loop.sh` immédiatement après [69] : deux
  tickets dessinés sur un fichier sont un `decision` que le pack sait produire tout
  seul, et les coller évite de relire ce point d'entrée deux fois. Devant [66]
  parce que le témoin du journal est un mécanisme **fermé** (une variable du
  process du drain, une comparaison en sortie, rien qui dépende de ce que [66]
  décidera de `router_pin`), alors que [66] rouvre `router_pin` et
  `router_tree_note` : livré derrière, il aurait à choisir entre s'accrocher au
  nouvel épinglage ou rester à côté. `Blocked by: 69`. Ordre complet retenu :
  [69] → [67] → [66] → [68] → [18] → [19].

- **Ce que [69] laisse à ce ticket, livré le 06/09/2026.** `human_loop_main` a deux
  lignes de plus au démarrage, placées **entre** `draining ready-for-human` et
  `router_run_notes` : le bloc `gate_leftovers` (heredoc) et l'appel à
  `concurrency_leftovers`. Trois choses à hériter. (1) L'ordre : les résidus
  passent avant les quatre mots du run, donc un témoin ajouté à `router_run_notes`
  n'est plus la première chose qu'un drain dit. (2) `human_loop_main` déclare
  maintenant `local leftovers` — un second `local` du même nom dans la même
  fonction serait une redéclaration silencieuse. (3) La posture, qui est la même
  que celle demandée ici : ces lignes **comptent et ne jugent pas**, et un refus
  de la fonction appelée veut dire « rien à dire ». Le `if` de
  `concurrency_leftovers` est ce qui le tient sous `set -e` ; côté heredoc la
  substitution avale le statut, mesuré. Un témoin de journal qui refuserait le
  drain sur une plainte casserait cette posture au même endroit.

- **Décor de sonde, prêt.** `../sondes/ticket-69/verification.bats` porte « un run
  réel tué au `KILL` pendant le gate, puis un drain démarré derrière », avec ses
  deux pièges déjà réglés (semer `01-alpha` en `ready-for-agent` pour que le gate
  démarre, et `rm -rf "$(run_lock_dir)" "$(tree_lock_dir)"` avant de relancer).
  À copier plutôt qu'à réécrire.

## Livraison — 07/09/2026

- **Première moitié : la réserve, et ce que seul ce lecteur-ci doit dire.**
  `router_run_notes` est devenu deux fonctions — `router__run_notes_words`, les
  quatre `if` inchangés, et un enrobage qui imprime `router__run_notes_caveat`
  **au-dessus** d'eux quand il y a quelque chose à dire. La réserve n'est pas une
  copie de celle de `router_journal_lines` : elle ajoute la phrase qui manquait
  aux deux, *trois de ces mots sont lus comme des présences et le quatrième comme
  une absence, donc ce fichier achète le silence au prix où il achète une
  affirmation*. Un lecteur qui ne sait que « ces lignes peuvent être forgées » lit
  encore une note manquante comme un fait.

- **Seconde moitié de la première : la négation dite dans les deux sens.** Le
  `if grep -q budget-wall && ! grep -q …` est devenu un `if` imbriqué à deux bras.
  Le bras vide dit la phrase d'origine, mot pour mot. Le bras plein **nomme le mot
  qui a retiré la note** et redit que cet état n'est écrit nulle part ailleurs :
  « one line carrying one of those words, anywhere in this file […] read that word
  as a claim and not as a fact ». Les trois mots sont cherchés par **une** ligne de
  `grep` dans une boucle et non par un `grep` chacun — sans quoi l'ancre de
  l'entrée de mutation `16 weekly-pause …` cesserait d'être unique dans le
  fichier, ce que `test/mutate.sh` décrit comme un mensonge latent.

- **Ce que la réparation ne fait pas, écrit comme une limite.** La contrefaçon
  reste possible : rien ne peut l'empêcher dans cette zone, et [10] a déjà refusé
  l'autre sortie (sortir `run.log` de la zone atteignable, c'est-à-dire de la
  vue). Ce qui change est qu'elle n'est plus **silencieuse**.

- **Troisième moitié : le témoin du drain.** `ROUTER__JOURNAL_WITNESS` et
  `ROUTER__JOURNAL_BASE`, deux variables du process du drain et jamais des
  fichiers ([08], [10]) ; `router_journal` en garde copie, `router_journal_base`
  prend la borne, `router_journal_verify` compare une fois en fin de drainage.
  Trois emplacements d'appel, qui sont les trois sorties pouvant suivre une
  décision : le puits vidé ou quitté (`exit 0`/`exit 3`), le puits vide au départ
  (`exit 5` — le préflight journalise les constats du tracker avant les verrous),
  et le verrou perdu de [57] (`exit 4`, la seule que le `break` de la boucle
  n'atteint pas). La borne est prise dans `human_loop_main` **avant**
  `human_loop_preflight` et pas dedans : contrainte que ce ticket avait lui-même
  écrite dans [16], le préflight est une liste et pas une délégation.

- **Le témoin ne change jamais le code de sortie**, même posture que les résidus de
  [69] : ça compte et ça ne juge rien. Un témoin qui refuserait le drain sur une
  plainte donnerait à une session routée une ligne pour renvoyer chez lui l'humain
  venu vider le puits.

- **Le piège que le mécanisme a trouvé, et il est dans le pack et pas dans le
  ticket.** `router_protect_tracker` était lu par `moved="$(router_protect_tracker
  "$id")"`, donc dans un **sous-shell** — et cette fonction porte neuf appels à
  `router_journal` (`tracker-drift gone/held/restored/restore-failed/named/created`
  plus les trois de `router__say_unrestored`). Un témoin ajouté naïvement aurait
  fait qu'un drain dont la session routée a bougé un ticket voisin se **serait
  accusé lui-même** d'une réécriture que personne n'a faite : c'est le piège des
  lignes de reclaim de [10], à un point d'entrée près. La fonction imprime
  désormais son propre préfixe `ralph: ` (dix `printf`, plus le refus stderr qui
  l'avait déjà) et `human_loop__session` l'appelle comme une instruction. Le
  commentaire de `router_protect_tracker` qui justifiait la substitution de
  commande est réécrit : écrire le tracker depuis un sous-shell reste sain,
  **journaliser** depuis un sous-shell ne l'est pas.

- **Mesuré sur des drains et des runs réels après correctif**,
  `sondes/ticket-67/verification.bats`, cinq cas :

  | | |
  |---|---|
  | V1 — Q3a rejoué : `c` sur `20-decision`, puis une session routée sur `21-second` écrase `run.log` | le drain **se plaint** (1) et imprime sa copie ; la ligne `20-decision … drained … action=closed` que la session a effacée est dans la copie |
  | V2 — témoin appairé le plus cher : la session **commite** et déplace `21-second`, `run.log` porte déjà 3 lignes d'un run précédent | **0 plainte**, la dérive est journalisée (`tracker-drift … action=restored`), le ticket est remis `ready-for-human` |
  | V3 — les deux écrivains qui se croisent : drain, run AFK réel, second drain | **0 plainte** aux trois étapes ; le run part d'une borne qui inclut ce que le drain a laissé, et le drain 2 d'une borne qui inclut ce que le run a laissé |
  | V4 — Q2b rejoué : une session routée pose `successor-armed` sur un `run.log` portant `budget-wall` | le drain suivant dit le **retrait nommé** au lieu de se taire, réserve comprise |
  | V5 — le bruit : un run AFK vert ordinaire, puis un drain | **0** ligne `run.log carries`, **0** réserve — la nouvelle phrase n'arrive pas sur un matin où rien n'a heurté le mur |

- **Huit entrées de mutation `67 …`**, dont trois paires : le retrait de la réserve
  et les deux directions de la négation (la note perdue, et la note dite sur un
  fichier qui n'a rien retiré) ; le témoin absent, jamais lu, jamais comparé ; et
  la paire qui garde le témoin honnête — le sous-shell remis autour de
  `router_protect_tracker`, et la borne non prise. La seconde de cette paire ne
  rougirait pas sur un `run.log` vide : le test jumeau sème donc trois lignes d'un
  run précédent, ce que la suite ne faisait nulle part.

- **Une entrée existante ré-ancrée** : `57 a lock the drain no longer holds is said
  and not acted on` visait `human_loop_log … \n  exit 4`, et le témoin s'est
  intercalé entre les deux. Ré-ancrée sur le seul `exit 4` du fichier, en fin de
  fonction, ce qui ne bougera plus au prochain ajout.

- **Les deux gates, mesurés d'un bloc sur le code livré** : `bash test/run.sh` =
  **745 tests, 0 failures, 6 skips opt-in** (aucun dans le canari) ;
  `bash test/mutate.sh` = **749 mutations, 0 not ok**. Baseline précédente : 740 /
  741 ([69]).

- **Frontière de confiance, question posée avant d'écrire.** Rien de ce qui est
  ajouté n'est un **contrôle** : `router_journal_verify` lit un fichier qu'une
  session routée écrit, et il ne décide de rien — il n'entre dans aucun code de
  sortie, aucune transition, aucun marquage. Ce qu'une session peut acheter en
  écrivant dans `run.log` est une phrase de plus (une plainte que le fichier
  mérite alors vraiment, puisqu'il ne porte plus ce que le drain a écrit), jamais
  un vert. La ligne du tableau (`Le reste de .scratch/<feature>/`) est élargie :
  les deux moitiés livrées, ce que le témoin tient, et les deux limites qui
  restent — le témoin ne vaut que pour le bloc de *ce* drain, exactement comme
  celui de [10] pour son run, et rien de ce qu'une session laisse dans cette zone
  n'est encore **nommé** (`router__tree_dirt` saute `gate_is_bookkeeping`).

- **Écart de write-surface, déclaré.** Au-delà des cinq chemins annoncés, ce ticket
  écrit dans `.scratch/ralph-pack/` : les tickets [16] et [66] (les contraintes
  que la DoD demande d'écrire là où elles seront relues) et le nouveau
  `sondes/ticket-67/verification.bats`. Zone de bookkeeping, aucun code du pack.

- **Ce qui reste ailleurs.** Contrainte écrite dans [16] (la borne reste hors du
  préflight ; tout `router_journal` doit rester dans le shell du drain ; le témoin
  ne juge pas) et dans [66] (quatre points, dont celui-ci : la réserve affirme que
  *rien ne garde cette zone* — le jour où [66] y met un garde, cette phrase et sa
  jumelle de `router_journal_lines` sont à relire). Le constat 2 de la liste
  ouverte dans [16] est fermé ; restent 1 ([66]) et 3 ([68]).
