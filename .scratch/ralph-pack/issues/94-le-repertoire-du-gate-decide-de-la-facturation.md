# 94 — Le répertoire du gate décide de la facturation et de la suite du run

**What to build:** Que ce que le parent lit dans le répertoire de travail du gate après la mort de la branche qui l'a écrit — la posture de refus d'une lentille, la classe d'échec, la zone de langue, les constats d'une branche — n'arrive plus par un fichier qu'un process extérieur à l'arbre du pilote peut écrire.

**Blocked by:** 95

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/lenses.sh`, `.claude/lib/lang.sh`, `test/gate.bats`, `test/lenses.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] La **posture de refus d'une lentille** n'est plus tirée d'un fichier que quiconque énumère `$TMPDIR` peut réécrire. C'est le poste qui décide le plus : `RALPH_GATE_QUOTA_ONLY=1` → outcome `budget-pause` → `failures_classify` rend `budget`, la seule classe qui n'appelle ni `tracker_bump_failures`, ni `reason`, ni `failures_preserve_attempt` — **et** `$slot/posture` part au pilote, qui pause puis arrête le run. Mesuré sur une itération **verte** : travail roulé en arrière, ticket jamais facturé, `sterile run: 3 iterations resolved nothing`, exit 4, sans une ligne.
- [ ] La **classe d'échec** (`$dir/scope.class` → `RALPH_GATE_SCOPE_CLASS`) arrive par le même canal neuf. Mesuré : `contract` forgé sur une suite rouge → une seule itération, `Failures:` vide, `escalated to the human sink (decision)`, run **exit 0**, et deux lignes de journal qui se contredisent (`scope=green` puis `scope overflow … contract`) sans que rien ne le remarque.
- [ ] La **zone de langue** (`$dir/lang.zone`) et les **constats d'une branche** (`$dir/<branche>.out`) sont traités par la même décision ou l'aveu est écrit pour chacun séparément. Le `.out` est aussi la source du reçu ([96] le cite), donc ce qui est décidé ici est ce dont [96] hérite.
- [ ] Le **prompt d'une lentille** (`$dir/lens-<nom>.prompt`) est tranché : c'est la consigne donnée au juge, elle est écrite par le parent et lue dans la branche, donc la réécrire est une course — nommée ou fermée, jamais laissée non-dite.
- [ ] La ligne 35 du tableau est réécrite. Sa phrase actuelle — *« Ce qui reste à portée d'un survivant, et qui n'est pas un verdict … jamais un vert »* — est vraie et insuffisante : la classe `budget` **n'est pas un vert** et elle vaut mieux qu'un vert pour qui veut que rien ne soit facturé.
- [ ] Les tests mettent en scène un **survivant réel** et assertent ce qui a changé — un ticket facturé, un run qui ne pause pas, un travail vert qui survit. Témoin appairé obligatoire : sans survivant, le même scénario doit donner l'autre résultat.
- [ ] Une entrée de mutation par garantie livrée, avec son témoin appairé.

## Comments

- **Ouvert par la passe transversale du 23/09/2026** (`../passe-transversale-23-09.md`, §1). Sondes : `../sondes/passe-23-09/q1-le-flux-dune-lentille.bats` et `../sondes/passe-23-09/q5-la-classe-dechec.bats`.

- **Ordre VALIDÉ par Philippe le 23/09/2026** : **[95] → [94] → [96]**. [95] devant parce qu'il change la **forme du fork** (`set -m` autour de `gate__start`, un groupe par branche, la course du chien de garde) et que ce ticket-ci doit précisément concevoir un canal **autour** de ce fork : le concevoir avant, c'est le reprendre. Le `Blocked by: 95` ci-dessus est donc définitif.

- **Ce que [92] a fermé et où il s'est arrêté.** Le `.rc` par branche et le marqueur `timed-out` sont sortis du répertoire parce qu'ils **étaient** des verdicts. Le commentaire de `gate__lens_phase` dit même pourquoi le second comptait : *« a survivor … that dropped a `timed-out` into the gate's directory would silence the refusal check for the whole fan »* — et la phrase suivante lit ce même contrôle dans un fichier du même répertoire. L'interrupteur a été fermé, la source non.

- **La contrainte technique, celle que [92] a rencontrée** : une branche est un sous-shell, donc une variable qu'elle pose meurt avec elle et **seul le statut de sortie traverse**. C'est la raison écrite pour laquelle ces quatre objets sont des fichiers. Un statut peut porter une classe à deux valeurs (`internal`/`contract`) ; il ne peut pas porter `<status> <window> <reset>` ni une phrase de couverture.

- **Les sorties candidates, et ce qui est déjà disqualifié.** [80] a disqualifié **le MAC** et **le fd délié** pour le registre d'écritures : relire pourquoi avant de les reproposer, et si l'une des deux revient, dire ce qui est différent ici. Ce qui est neuf et mesuré par cette passe (sonde `q3`) : une variable **non exportée** du shell qui forke est héritée par le sous-shell d'une branche et **jamais** par le `exec` de `bash -c "$TEST_CMD"` — `RALPH_WITNESS_SEAL` n'est pas dans les 70 variables que la commande du projet reçoit. C'est exactement la propriété qui fait tenir le sceau de [81], un étage plus bas.

- **Ne pas confondre les deux `$dir` de `gate.sh`.** `gate_frontier_common` (`ralph-frontier.*` : `exclude`, `global`, `attributes`, `manifest`, `path`, `ledger`, `guards`, `forensic.witness`) est **scellé** par [81] et sa fenêtre est tranchée par [83]. Celui de ce ticket est `gate_run`'s `mktemp -d ralph-gate.XXXXXX`, créé **dans le fork d'une itération** — donc hors de portée du sceau **par construction**, et [83] dit pourquoi ça ne peut pas venir du pilote.

- **La borne que ce ticket ne déplace pas** : `MAX_PARALLEL=1` est la valeur livrée et tout ce qui est mesuré ici l'est à cette valeur. Ce n'est pas la ligne du haut du tableau (une session sœur) : le porteur mesuré est un process de l'itération **elle-même**, et le plus ordinaire des trois est la commande de test du projet ([95]).

- **Ce qui borne déjà la forge et qui n'est pas une réparation** : `STERILE_K`. Le commentaire de `failures_handle` l'écrit — *« What bounds a session that forges this class … is `STERILE_K` in the loop »*. La borne fonctionne, et ce qu'elle achète est **l'arrêt du run**. Elle a été écrite en pensant au flux de la session de livraison ; le flux d'une **lentille** est la chose que le pack croit non-forgeable puisqu'elle est spawnée sans outil d'écriture.
