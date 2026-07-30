# 29 — Le scope-guard juge un arbre qu'il prend pendant que le gate écrit déjà

**What to build:** Faire juger l'itération sur un arbre pris **avant** que le gate ne lance quoi que ce soit. Aujourd'hui `gate__scope_guard` prend son propre snapshot *depuis sa branche*, c'est-à-dire en parallèle de la suite de tests et du type-check que `gate_run` vient de démarrer. Le verdict de scope dépend donc de qui a écrit le premier : un artefact que la suite dépose avant le snapshot est imputé à la session, un artefact déposé après n'est ni jugé ni défait par le rollback. Même ticket, même session, deux verdicts.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/failures.sh`, `test/gate.bats`, `test/failures.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`, `README.md`

**Status:** ready-for-agent

- [ ] Le tree jugé est pris une seule fois, dans `gate_run`, **avant** le premier `gate__start`, et passé au scope-guard au lieu de lui faire calculer le sien. Un test prouve qu'un fichier écrit par `TEST_CMD` — quel que soit son délai — ne change plus le verdict de scope.
- [ ] Le verdict ne dépend plus d'un délai : la sonde 7b et la sonde 7 ci-dessous rendent le **même** verdict, et un test le montre avec les deux `TEST_CMD` (immédiat / retardé).
- [ ] `RALPH_GATE_TREE` est renseignée avant le fan, donc lisible par une branche. C'est la correction que [06] porte déjà dans ses commentaires : elle est déplacée ici, et [06] l'hérite au lieu de la refaire.
- [ ] Ce que le gate lui-même a écrit pendant qu'il jugeait est **nommé**, sur le modèle de la zone ignorée de [24] : le rollback ne le défait pas, et « l'arbre est remis où la session l'a trouvé » ne doit pas rester vrai à l'exception d'un ensemble de chemins que personne n'énumère. Deuxième exemption non énumérée du rollback, la première étant la zone ignorée.
- [ ] Le cas armé est couvert : un artefact de la suite qui tombe dans la write-surface d'un **autre** ticket ne peut plus escalader le ticket en cours en `decision`.

## Comments

- **Origine : passe transversale 24→26, le 30/07/2026.** Trouvé en posant la question 4 sur `gate_run` — que le gate lui-même laisse-t-il derrière lui ? Trois sondes, trois faces d'une même cause.

  *Sonde 7 — ce que la suite écrit après le snapshot n'est ni jugé ni défait.* `TEST_CMD='sleep 2; printf late >late-artifact.txt; exit 1'`, une session qui n'écrit que dans sa surface :

  ```
  ralph: gate: 01-alpha: tests=red typecheck=green scope=green
  ralph: rolled back 1 path(s) the session touched
  late-artifact.txt survives: yes        src/alpha.txt undone: yes
  ```

  Le fichier n'est pas ignoré par git : la ligne de zone de [24] ne le nomme donc pas, et rien d'autre ne le nomme. Il est là pour l'itération suivante, dont il fera partie du snapshot `base` — laundering complet.

  *Sonde 7b — le même fichier, écrit tout de suite, retourne le verdict.* `TEST_CMD='printf early >late-artifact.txt; exit 0'`, tout le reste identique :

  ```
  ralph: gate: 01-alpha: tests=green typecheck=green scope=red
    wrote late-artifact.txt, outside the declared write-surface
  ```

  Le scope-guard est la **troisième** branche démarrée ; son snapshot tombe donc après le début de la suite. Une suite qui écrit un rapport de couverture, un snapshot de test mis à jour, un `.log` — c'est-à-dire beaucoup de suites — rend le verdict de scope non déterministe. Un contrôle qui prend son entrée pendant que d'autres processus écrivent l'arbre ne rend pas un verdict, il rend un tirage.

  *Sonde 10 — et le tirage peut être définitif.* Le même artefact, mais dans la surface d'un autre ticket : `TEST_CMD='mkdir -p src; printf artefact >src/beta.txt; exit 0'` pendant que `01-alpha` est jugé, `02-beta` déclarant `src/beta.txt` :

  ```
  wrote src/beta.txt, inside the write-surface of 02-beta (drift)
  ralph: scope overflow on 01-alpha: contract
  01-alpha -> ready-for-human   Failures: []   Escalation: decision
  ```

  La classe `contract` est **délibérément non retryable** ([07]) : « deux tickets ont été dessinés sur un fichier, un retry n'y changera rien ». Ici les deux tickets sont disjoints et la session n'a rien fait de mal — c'est la suite de tests du projet qui a écrit. Le ticket part au puits humain sans consommer de retry, avec une raison fausse, et rien ne l'en fera revenir.

- **Le correctif est déjà écrit ailleurs, et c'est ce qui rend ce ticket petit.** La passe précédente avait noté dans [06] que `gate_changed_files "$base" "$RALPH_GATE_TREE"` est inapplicable depuis une branche, parce que `gate_run` vide les `RALPH_GATE_*` avant le fan et ne les remplit qu'après la collecte — et que le correctif est de **hisser le snapshot avant le fan**. Ce qui n'avait pas été vu : ce hissage n'est pas un confort pour les lentilles, c'est la correction d'un verdict non déterministe et d'une exemption silencieuse du rollback. Il change donc de propriétaire : ici, avant [06], parce que le défaut existe aujourd'hui sans lentille.

- **Ce que le hissage ne referme pas, et qu'il faut nommer plutôt que taire.** Après le hissage, un artefact que le gate écrit pendant qu'il juge est toujours dans l'arbre à la fin de l'itération, et le rollback ne le défait toujours pas — il n'est dans aucun des deux trees qu'il diffe. La différence est qu'il devient **déterministe** et **attribuable** : ce n'est plus « peut-être la session, peut-être la suite », c'est « ce que le gate a écrit ». C'est exactement le traitement que [24] a inventé pour la zone ignorée, et c'est la seconde moitié de ce ticket : une ligne qui dit ce que le rollback n'a pas pu défaire *parce que ça n'existait pas encore quand l'arbre a été pris*.

  Piège à ne pas répéter : la ligne ne doit pas devenir un verdict. Un projet dont la suite écrit un artefact à chaque run n'a rien fait de mal ; le rendre rouge, c'est refuser tout projet qui a un build — la même impasse que [24] a rencontrée sur la zone ignorée.

- **Piège de mesure, hérité de [24] et de [25].** La suite du dépôt utilise `stub-cmd` derrière `TEST_CMD`, qui rend la main immédiatement et n'écrit rien. Aucun test existant ne peut donc voir ce défaut : le seul moment où la fenêtre existe est celui où une branche écrit pendant que le scope-guard prend son arbre. Un test de ce ticket doit porter son `TEST_CMD` écrivant, dans les **deux** ordres, et le délai est porteur — sans lui, le test est un tirage au sort comme le code qu'il juge.

- **Contrainte pour [06].** Le registre de lentilles hérite du hissage et n'a plus à le faire. Deux conséquences à ne pas perdre : une lentille lit `RALPH_GATE_TREE` renseignée, donc juge le même arbre que le scope-guard ; et une lentille est elle-même une branche qui écrit (au minimum le flux de session `claude`), donc elle alimente précisément la ligne « ce que le gate a écrit » que ce ticket pose. Un flux de lentille qui atterrit dans l'arbre du projet est un cas de [19] (`.gitignore`), pas une exception à écrire ici.

- **Contrainte pour [10].** Le reçu d'audit héritera d'une troisième catégorie à porter, après « ce que le gate n'a pas jugé » (zone ignorée) et les verdicts : « ce que le gate a écrit et que le rollback n'a pas défait ». Trois exemptions, une seule promesse à ne pas laisser sonner complète.
