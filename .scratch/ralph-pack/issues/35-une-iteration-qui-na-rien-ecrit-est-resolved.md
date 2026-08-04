# 35 — Une itération qui n'a rien écrit est `resolved` dès qu'aucune lentille ne tourne

**What to build:** Sortir du palier de lentilles la seule garantie déterministe qu'il porte. [06] a livré « un diff vide est rouge sans dépenser de session » et l'a écrit comme une garantie nouvelle et gratuite ; elle est implémentée **dans `lenses_review`**, donc une fois par lentille, donc pas du tout quand aucune lentille ne tourne. Deux configurations parfaitement légitimes l'éteignent : `LENSES` vide ou `none` (un projet a le droit d'éteindre le palier, [24] l'écrit), et un `LENSES` de lentilles gatées qu'un ticket ne déclenche pas. Une session qui ne modifie **aucun fichier** est alors `tests=green typecheck=green scope=green`, le ticket est marqué `resolved`, `sterile` est remis à zéro, et le run sort `0` — « ce run a broyé tout ce qu'il pouvait ».

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/lenses.sh`, `.claude/lib/failures.sh`, `.claude/loop.sh`, `test/gate.bats`, `test/lenses.bats`, `test/failures.bats`, `test/loop-happy-path.bats`, `test/smart-zone.bats`, `test/canary.bats`, `test/helpers/harness.bash`, `test/helpers/shims/claude`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`, `CONTEXT.md`

**Status:** resolved

- [x] Une itération dont le gate ne voit changer aucun fichier n'est jamais `resolved`, quel que soit `LENSES` et quelles que soient les lentilles déclenchées. Le contrôle est déterministe et vit là où vivent les autres contrôles déterministes du gate, pas dans le palier subjectif.
- [x] Le cas n'est pas confondu avec un échec d'implémentation : rien n'a été jugé, la session a répondu, et la cause est « il n'y a rien à juger ». Ce que ça vaut dans `failures_classify` est tranché ici — un retry en session fraîche est plausible, un re-slice ne l'est pas, et le plafond doit router vers une raison qu'un humain peut lire (ni `failed-impl`, qui enverrait lire un verdict, ni `decision` par défaut).
- [x] Le double comptage est évité : quand des lentilles tournent, le refus tombe **une** fois pour l'itération et pas une fois par lentille. `lenses_review` peut garder sa propre garde (un juge sans diff ne doit pas passer) mais ne doit plus être ce qui tient la garantie.
- [x] Le test couvre les trois configurations, parce que c'est la combinaison qui fait le trou et non l'une d'elles : `LENSES=none`, `LENSES` gaté non déclenché, et `LENSES` par défaut. Le canari tourne au défaut livré, donc il ne peut pas voir ce trou : c'est `test/gate.bats` qui doit le tenir.
- [x] La ligne correspondante de `docs/frontiere-de-confiance.md` existe, et elle dit ce que `LENSES` **ne peut pas** éteindre — corollaire de [24] appliqué à cette clé.

## Comments

- **Origine : passe transversale du 03/08/2026** (fenêtre [06], [23], [28], [29], [30], [31]). Trouvé en poussant la sonde d'un autre ticket : une itération verte qui ne commitait rien, sur un projet configuré comme le harnais de test configure le sien.

  *Sonde — un `claude` qui répond et n'écrit rien, trois tickets à la suite, `LENSES=none`.* Rien d'hostile : c'est ce que fait une session qui refuse la tâche, qui tombe sur un prompt tronqué, ou qui a passé son temps à lire.

  ```
  ralph: iteration 1: 01-alpha
  ralph: gate: 01-alpha: no review lens ran (LENSES is empty): nothing here judged
    this work by anything but its own tests
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green
  ralph: iteration 1: 01-alpha -> resolved
  ralph: iteration 2: 02-beta  -> resolved
  ralph: iteration 3: 03-gamma -> resolved
  ralph: frontier empty after 3 iterations

  exit: 0        01-alpha resolved   02-beta resolved   03-gamma resolved
  commits: 1 (le commit de fixture)          src/: (vide)
  run.log:  01-alpha resolved turns=2 …  /  02-beta resolved …  /  03-gamma resolved …
  ```

  Toute la frontière drainée, trois lignes de livraison dans le journal, zéro fichier écrit, zéro commit, et un code de sortie qui dit à un humain que la nuit s'est bien passée. `sterile` étant remis à zéro par chaque `resolved`, le filet `STERILE_K` ne peut pas l'attraper non plus.

  *Sonde — le même trou sans éteindre le palier.* `LENSES="security accessibility"`, ticket ordinaire (ni tag `security`, ni surface visible) :

  ```
  ralph: gate: 01-alpha: no review lens was triggered by this ticket
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green
  ralph: iteration 1: 01-alpha -> resolved
  ```

  Donc ce n'est pas « le projet a désarmé le palier » : c'est le chemin normal de `gate__lens_phase`, qui rend `0` dès que `lenses_triggered` est vide, avant tout ce qui suit.

  *Témoin — le même scénario au défaut livré (`LENSES="standards spec fidelity security accessibility"`) :*

  ```
  ralph: gate: standards red (exit 1)
    the standards lens has nothing to review: this iteration changed no file the gate can see
  ralph: gate: spec red (exit 1)
    the spec lens has nothing to review: …
  ralph: 01-alpha: escalated to the human sink (failed-impl)
  ```

  La garantie existe donc bien, et elle est portée par **chaque lentille**, une fois par lentille, comme un effet de bord du fait qu'un juge sans diff refuse de juger.

- **La cause, dans l'ordre où elle se lit.** `gate__lens_phase` teste `[ -z "${lenses# }" ]` et retourne `0` — verdict « aucune lentille », pas « rien à juger ». Le refus du diff vide est dans `lenses_review`, sur l'échec de `lenses__write_prompt`. Aucune des trois branches objectives ne regarde si l'itération a changé quelque chose : `tests` et `typecheck` sont les commandes du projet, et le scope-guard juge un **débordement**, donc un diff vide le satisfait par construction — il n'y a rien qui dépasse.

- **Pourquoi c'est le pire mode de panne du pack, dit franchement.** Toutes les autres trouvailles de cette passe coûtent une itération, un retry ou un angle mort. Celle-ci produit un **faux livré** : le ticket quitte la frontière pour de bon, `Failures:` est lâché avec le claim ([26]), et rien dans le tracker ne se souvient que personne n'a rien fait. C'est exactement ce que la distinction `exit 0` / `exit 5` de `loop.sh` existe pour empêcher — « une nuit de silence rapportée comme un succès » — obtenue par l'autre bout.

- **Piège pour qui livrera ça.** Le contrôle doit être **déterministe et avant le fan**, pas une quatrième branche : l'information est déjà là, `RALPH_GATE_TREE` et `base` sont pris avant le premier `gate__start` depuis [29], et `gate_changed_files` sait déjà exclure le bookkeeping de la boucle. En faire une branche ferait payer un process pour un test de chaîne vide, et surtout ferait dépendre le verdict de l'agrégation là où il peut être rendu tout de suite.

  Second piège, plus subtil : un diff vide et un **arbre illisible** ne sont pas la même chose. `gate_changed_files` rend non-zéro quand il manque un arbre et une liste vide quand rien n'a changé ; un contrôle qui confond les deux transforme le fail-closed de [30] en « rien à livrer » (voir [34], qui est la même erreur chez d'autres appelants). **[34] livré le 04/08/2026** : `gate_unjudged_changes` distingue maintenant les deux dans son statut, et ses quatre lecteurs choisissent explicitement — deux rougissent, deux disent qu'ils n'ont pas pu compter. Le contrôle de ce ticket-ci est un cinquième lecteur du même genre de valeur et doit choisir pareil, en écrivant lequel des deux il est : un « rien à livrer » calculé sur un arbre qu'on n'a pas pu lire serait précisément le faux livré que ce ticket existe pour fermer, obtenu par la porte d'à côté.

  Troisième : la boucle a déjà un cas où un diff vide est légitime, et il faut vérifier qu'il ne devient pas rouge — une itération dont la session a *tout* fait dans le tracker ne peut pas exister ([21] restaure), mais une itération dont le seul effet est une suppression est un diff non vide, et une itération dont l'effet est un fichier identique au précédent en est un vide. Le second cas est un vrai « rien livré » ; le dire dans le ticket plutôt que le découvrir.

- **Ce que ça change pour `LENSES` comme interrupteur.** [24] a posé la règle : une clé de config est un interrupteur, il faut dire ce qu'elle ne peut pas éteindre. `LENSES` annonce qu'elle éteint le **jugement subjectif** — et la boucle le dit à chaque itération, ce qui est exactement le bon comportement. Elle éteint en plus un contrôle déterministe que personne n'a rangé au bon étage. Après ce ticket, la ligne « le palier de jugement ne peut pas être éteint par une session » gagne une phrase de plus : ce qu'un projet a le droit d'éteindre, et ce qui reste debout quoi qu'il fasse.

- **Une seconde route vers le même faux livré, trouvée en sondant [34] le 04/08/2026.** `failures_make_durable` commite le diff `base..arbre jugé`. Dans la sonde B de [34], l'itération 1 laissait son travail dans l'arbre (rollback impossible) et l'itération 2 partait d'un `base` qui le contenait déjà : ticket `resolved`, ligne `resolved` dans `run.log`, **zéro commit**, et le travail toujours en `??`. Ce chemin-là est fermé depuis, puisque le run s'arrête au lieu d'enchaîner — mais la leçon vaut pour ce ticket, parce qu'elle dit où poser le contrôle. Un ticket est livré quand quelque chose est **commité**, et l'itération qui ne commite rien n'est pas seulement celle dont la session n'a rien écrit : c'est aussi celle dont le travail était déjà dans le `base`. Un contrôle posé sur « la session a-t-elle changé un fichier » ne voit que la première ; un contrôle posé sur « ce que ce gate a approuvé est-il non vide » voit les deux. À trancher ici, avec le coût de chaque option.

- **Contrainte pour [06].** La phrase de son compte rendu — « un diff vide est rouge sans dépenser de session, déterministe, donc tranché avant tout spawn » — est vraie dans la fenêtre où une lentille tourne et fausse ailleurs. À corriger dans son ticket quand celui-ci sera livré : la garantie a changé d'étage.

- **Contrainte pour [08].** Le budget compte « une session plus les lentilles déclenchées » ([06]) ; un refus avant le fan économise les lentilles d'une itération qui n'a rien livré, ce qui va dans le bon sens et doit être compté comme tel plutôt que comme une itération verte.

- **Contrainte pour [10] et [16].** Un nouvel `outcome` (ou une nouvelle raison d'escalade) apparaît sur ce chemin. C'est le troisième depuis [23] : le reçu d'audit et le puits humain doivent le router, et « rien à juger » ne se lit pas comme « jugé rouge ».

## Livré le 04/08/2026

- **Le contrôle, et les trois décisions qui le placent.** `gate__nothing_delivered base now` répond « cette itération n'a rien livré », et `gate_run` l'appelle **avant le fan**, juste après avoir pris `RALPH_GATE_TREE`. Trois choses ont été tranchées là :

  - *Sur quelle liste.* `gate_changed_files "$base" "$RALPH_GATE_TREE"`, c'est-à-dire **exactement** la liste que `failures_make_durable` commite. La question du piège 4 (« la session a-t-elle écrit » contre « ce que le gate a approuvé est-il non vide ») ne se tranche donc pas : ce sont deux formulations du même calcul, vérifié plutôt que supposé, et la seconde route vers le même faux livré — le travail déjà dans le `base` — est fermée par le même `if`.
  - *Avant le fan et pas comme quatrième branche.* Le verdict est `delivery=red`, posé à la main dans `RALPH_GATE_VERDICTS`, et ni `tests` ni `typecheck` ni `scope` ne démarrent. Un test l'asserte par `stub_call_count tests == 0` : sur un vrai projet, `TEST_CMD` est ce que le gate a de plus cher, et le dépenser pour une itération dont le verdict est déjà connu n'achète rien. La phase des lentilles n'est pas atteinte non plus, ce qui est la moitié de l'AC 3 — l'autre étant que le refus s'imprime **une** fois (asserté par un `grep -c` à 1 au défaut livré de `LENSES`).
  - *Ce qu'il fait d'une mesure refusée.* Rien : `[ -z "$now" ] || ! changed=...` → `return 1`, et le fan tourne, où le scope-guard refuse déjà de passer un arbre qu'il ne peut pas lire et le dit en mots. C'est un choix explicite de cinquième lecteur ([34]) et non un oubli : rougir ici aurait étiqueté « rien livré » une itération dont personne n'a pu regarder l'arbre, ce qui est le faux livré de ce ticket obtenu par la porte d'à côté. Deux sondes le tiennent, une par bout de la valeur (pas de `base`, pas d'arbre).

- **Une ligne qu'il a fallu rapatrier, trouvée en écrivant le short-circuit.** Les findings de `gate_ignore_frontier` voyagent sur la sortie du scope-guard — qui ne démarre plus sur ce chemin. Une session qui élargit `.git/info/exclude` **et n'écrit rien derrière** aurait donc vu sa règle remise en silence, ce qui contredit « une zone qu'on ne peut pas fermer, on la nomme à chaque tour » ([24], [30]). Les findings sont donc réimprimés ligne à ligne dans la branche du refus, avec sa sonde et sa mutation.

- **Le vocabulaire, en un endroit.** Verdict `delivery=red` ; `RALPH_GATE_NOTHING_DELIVERED=1` lu par la boucle ; outcome de journal `nothing-delivered` ; classe `nothing-delivered` dans `failures_classify` (retryable comme un gate rouge, jamais re-slicée — rien n'a mesuré la tranche) ; raison d'escalade `nothing-delivered` au plafond. Trois précisions qui ne se déduisent pas du code :

  - **`tracker-write` garde la priorité** sur `nothing-delivered` dans la boucle. Une session qui n'écrit *que* le tracker est les deux à la fois ; la règle qu'elle a franchie est celle qui ne se défait pas après coup, et c'est celle qu'un humain doit voir.
  - **La branche `failed/<ticket>` n'est pas écrite** sur ce chemin, contrairement à `session-timeout` : elle porterait l'arbre que la session a reçu, c'est-à-dire un artefact forensique de rien, offert à un humain comme la chose à aller lire. [16] l'avait anticipé mot pour mot.
  - **Une note est posée sur le ticket au plafond**, parce que la raison seule ne dit pas quoi faire : la question n'est ni « pourquoi ce code est faux » (aucun code) ni « la machine avait-elle un problème » (la session a répondu) mais « pourquoi ce ticket ne fait-il rien faire à une session ».

- **Le coût assumé, écrit ici et dans le tableau.** Une session dont les seules écritures tombent dans la zone ignorée n'a rien livré au sens de ce contrôle. C'est le bon verdict — rien n'en serait commité — et ça rend indélivrable, à chaque tentative et jusqu'à l'escalade, un ticket dont toute la write-surface est ignorée par le projet cible. Sondé et asserté (le fichier survit aussi : aucun rollback ne l'atteint).

- **Ce que le ticket a coûté au harnais, et c'est la trouvaille.** Le faux `claude` de la suite n'écrivait rien par défaut, et c'était écrit comme un choix raisonnable. Après ce contrôle, ce défaut-là n'est plus « une session coopérative » : c'est la seule panne que ce ticket refuse, donc **chaque vert de la suite était mesuré sur elle**. Le défaut du pack a vécu trente-cinq tickets à l'abri de ses propres fixtures. Le fake écrit maintenant la write-surface que son ticket déclare (ce que faisait déjà la session honnête du canari), `session_writes_nothing` demande le cas vide, et un `read` sans `IFS=` a été nécessaire pour que `\`a\`, \`b\`` ne produise pas un fichier nommé ` b`. Une entrée de mutation garde le tout : si le fake cesse de livrer, `test/gate.bats` doit rougir.

- **Trois tests ont changé de sens, et aucun n'a été « réparé ».**
  - `a ticket with no write-surface that writes nothing is still resolvable` → `…has nothing it could deliver`. C'était l'AC de ce ticket écrite à l'envers.
  - `the loop leaves tickets it must not touch alone` énumère maintenant ses fixtures au lieu de prendre tout le répertoire : 07 partage sa surface avec 01 par construction (donc drift dès qu'une session écrit ce que son ticket déclare) et 08 ne déclare rien (donc ne peut rien livrer). Les deux ont leurs propres tests ; ce test-là parle des tickets qu'on ne touche pas.
  - `an iteration that changed nothing is red, and costs no lens session` (lenses) → `…never reaches a lens`, plus un test neuf qui appelle `lenses_review` **directement**. La garde locale reste dans `lenses__write_prompt` — un juge sans diff ne doit pas être dépensé — mais elle est devenue inatteignable depuis la boucle, donc c'est un appel direct qui la couvre et l'entrée de mutation de [06] a été réaimée dessus.

- **Write-surface élargie en cours de route, et pourquoi.** Le ticket avait été écrit contre `gate.sh` + `lenses.sh` ; l'AC 2 demande une décision dans `failures_classify` (donc `failures.sh`) et un outcome de journal (donc `loop.sh`), et le harnais a dû changer pour la raison ci-dessus. `CONTEXT.md` s'y ajoute : le « jeu fermé » des raisons d'escalade y était faux depuis [23] — `session-timeout` n'y avait jamais été ajouté — et il porte maintenant les deux, avec ce qu'elles ont en commun (rien n'a été jugé).

- **Une conséquence que seule la passe de mutation a trouvée, et c'est la plus utile du ticket.** Un refus neuf couvre les scénarios que d'anciennes garanties couvraient, donc il rend leurs tests vacuous **en silence**. `03 the session decides whether it succeeded` — la mutation qui fait ignorer `rc` à la boucle — est revenue VACUOUS : le faux de son test mourait sans avoir rien écrit, donc la boucle mutée refusait l'itération quand même, pour n'avoir rien livré. Le faux écrit maintenant sa write-surface *puis* meurt, ce qui est aussi le crash réaliste, et l'entrée mord de nouveau. La règle : lancer `test/mutate.sh` **en entier** après un ticket qui ajoute un refus, jamais seulement les entrées du ticket.

- **Et un piège de ce fichier de mutations, troisième occurrence.** `gate__nothing_delivered` refuse un `now` vide avec exactement la même ligne que `gate__scope_guard`, et il est défini **au-dessus** : la substitution sans `/g` de l'entrée `29 a scope-guard handed no tree recomputes one` s'appliquait donc proprement à la mauvaise fonction, et rendait VACUOUS un test qui n'avait rien perdu. Ré-ancrée sur la ligne `local` qui précède. Le symptôme reste ce qu'il était en [29] et en [05] : VACUOUS sur un test en bonne santé, c'est-à-dire l'exact inverse de ce qui s'est passé.

- **État des gates au moment de la livraison** : `bash test/run.sh` → 306 tests, 0 échec, 5 skips (`RALPH_REAL_CLAUDE`) ; `bash test/mutate.sh` → 253 mutations, dont les 9 de ce ticket. L'entrée `23 a TERM nobody answers hangs the run for ever` reste instable (mesurée 3 `ok` pour 1 `VACUOUS` sur quatre relances isolées, sur cette branche) : c'est [38], pas une régression d'ici.

- **Contrainte rendue à [06], [07], [08], [10], [16], [32]** : leurs tickets ont été mis à jour. Celle de [07] est la plus lourde et n'était prévue nulle part — le parent d'un re-slice est maintenant escaladé au lieu d'être tamponné vert. Rien de nouveau pour [17] ni [13].
