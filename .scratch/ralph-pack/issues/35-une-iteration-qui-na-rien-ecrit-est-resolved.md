# 35 — Une itération qui n'a rien écrit est `resolved` dès qu'aucune lentille ne tourne

**What to build:** Sortir du palier de lentilles la seule garantie déterministe qu'il porte. [06] a livré « un diff vide est rouge sans dépenser de session » et l'a écrit comme une garantie nouvelle et gratuite ; elle est implémentée **dans `lenses_review`**, donc une fois par lentille, donc pas du tout quand aucune lentille ne tourne. Deux configurations parfaitement légitimes l'éteignent : `LENSES` vide ou `none` (un projet a le droit d'éteindre le palier, [24] l'écrit), et un `LENSES` de lentilles gatées qu'un ticket ne déclenche pas. Une session qui ne modifie **aucun fichier** est alors `tests=green typecheck=green scope=green`, le ticket est marqué `resolved`, `sterile` est remis à zéro, et le run sort `0` — « ce run a broyé tout ce qu'il pouvait ».

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/lenses.sh`, `test/gate.bats`, `test/lenses.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Une itération dont le gate ne voit changer aucun fichier n'est jamais `resolved`, quel que soit `LENSES` et quelles que soient les lentilles déclenchées. Le contrôle est déterministe et vit là où vivent les autres contrôles déterministes du gate, pas dans le palier subjectif.
- [ ] Le cas n'est pas confondu avec un échec d'implémentation : rien n'a été jugé, la session a répondu, et la cause est « il n'y a rien à juger ». Ce que ça vaut dans `failures_classify` est tranché ici — un retry en session fraîche est plausible, un re-slice ne l'est pas, et le plafond doit router vers une raison qu'un humain peut lire (ni `failed-impl`, qui enverrait lire un verdict, ni `decision` par défaut).
- [ ] Le double comptage est évité : quand des lentilles tournent, le refus tombe **une** fois pour l'itération et pas une fois par lentille. `lenses_review` peut garder sa propre garde (un juge sans diff ne doit pas passer) mais ne doit plus être ce qui tient la garantie.
- [ ] Le test couvre les trois configurations, parce que c'est la combinaison qui fait le trou et non l'une d'elles : `LENSES=none`, `LENSES` gaté non déclenché, et `LENSES` par défaut. Le canari tourne au défaut livré, donc il ne peut pas voir ce trou : c'est `test/gate.bats` qui doit le tenir.
- [ ] La ligne correspondante de `docs/frontiere-de-confiance.md` existe, et elle dit ce que `LENSES` **ne peut pas** éteindre — corollaire de [24] appliqué à cette clé.

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

  Second piège, plus subtil : un diff vide et un **arbre illisible** ne sont pas la même chose. `gate_changed_files` rend non-zéro quand il manque un arbre et une liste vide quand rien n'a changé ; un contrôle qui confond les deux transforme le fail-closed de [30] en « rien à livrer » (voir [34], qui est la même erreur chez d'autres appelants).

  Troisième : la boucle a déjà un cas où un diff vide est légitime, et il faut vérifier qu'il ne devient pas rouge — une itération dont la session a *tout* fait dans le tracker ne peut pas exister ([21] restaure), mais une itération dont le seul effet est une suppression est un diff non vide, et une itération dont l'effet est un fichier identique au précédent en est un vide. Le second cas est un vrai « rien livré » ; le dire dans le ticket plutôt que le découvrir.

- **Ce que ça change pour `LENSES` comme interrupteur.** [24] a posé la règle : une clé de config est un interrupteur, il faut dire ce qu'elle ne peut pas éteindre. `LENSES` annonce qu'elle éteint le **jugement subjectif** — et la boucle le dit à chaque itération, ce qui est exactement le bon comportement. Elle éteint en plus un contrôle déterministe que personne n'a rangé au bon étage. Après ce ticket, la ligne « le palier de jugement ne peut pas être éteint par une session » gagne une phrase de plus : ce qu'un projet a le droit d'éteindre, et ce qui reste debout quoi qu'il fasse.

- **Contrainte pour [06].** La phrase de son compte rendu — « un diff vide est rouge sans dépenser de session, déterministe, donc tranché avant tout spawn » — est vraie dans la fenêtre où une lentille tourne et fausse ailleurs. À corriger dans son ticket quand celui-ci sera livré : la garantie a changé d'étage.

- **Contrainte pour [08].** Le budget compte « une session plus les lentilles déclenchées » ([06]) ; un refus avant le fan économise les lentilles d'une itération qui n'a rien livré, ce qui va dans le bon sens et doit être compté comme tel plutôt que comme une itération verte.

- **Contrainte pour [10] et [16].** Un nouvel `outcome` (ou une nouvelle raison d'escalade) apparaît sur ce chemin. C'est le troisième depuis [23] : le reçu d'audit et le puits humain doivent le router, et « rien à juger » ne se lit pas comme « jugé rouge ».
