# 42 — Les deux gardes du tracker ne lisent pas tous le registre

**What to build:** Donner le registre de [13] aux deux gardes qui manipulent `issues/` et ne l'ont pas. `failures_protect_tracker` a **deux** appelants : celui de `loop.sh`, à qui [13] a passé le `mark`, et celui de `failures_reslice`, qui l'appelle sans — donc avec `ours=" "`, donc en traitant tout ce que la boucle a écrit pendant la fenêtre du re-slice comme l'œuvre de la session de plan. Et `failures_quarantine_strays`, qui garde le même répertoire contre les tickets qu'une session s'accorde, ne consulte le registre **nulle part** : les tickets qu'un re-slice voisin vient de créer sont des ids qui n'étaient pas là, donc des intrus. Les deux gardes se démolissent mutuellement dès `MAX_PARALLEL>1`, et le symptôme est celui que [13] décrit pour son propre défaut : un ticket `resolved` et son voisin coincé `claimed`.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/tracker.sh`, `test/failures.bats`, `test/concurrency.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Un re-slice qui tourne pendant qu'un frère est marqué ne défait pas ce marquage : le frère reste `resolved`, sans claim, et le re-slice n'est pas refusé au motif d'une édition qu'il n'a pas faite.
- [ ] Une itération dont la fenêtre couvre la création des enfants d'un re-slice voisin ne les met pas en quarantaine : les enfants entrent sur la frontière, la note « the session wrote these tickets into the tracker itself » ne nomme que ce que *sa* session a écrit.
- [ ] Les deux gardes lisent la **même** définition de « ceci n'est pas l'œuvre du jugé », lue au même endroit — la primitive du dispatcher — plutôt qu'une seconde liste tenue à côté. Un troisième garde ajouté plus tard doit hériter de la définition, pas la recopier.
- [ ] Le témoin appairé pour chacun des deux : le même scénario à `MAX_PARALLEL=1` laisse le frère `resolved` et les enfants sur la frontière. Sans lui, un test vert ne dit pas si le correctif a fait quelque chose.
- [ ] La mutation vise le passage du registre à chacun des deux gardes séparément — retirer le `mark` du re-slice doit rougir par un **ticket de frère défait**, pas par une ligne de log.

## Comments

- **Origine : passe transversale du 06/08/2026** (fenêtre [13]), question posée par le corollaire de [32] : *où est la liste des chemins, et est-ce que je l'ai lue ?* Ici la liste est le résultat de `grep -n failures_protect_tracker .claude/` — deux appelants — et [13] a instrumenté celui auquel il pensait.

  *Sonde D — un re-slice défait le marquage d'un frère.* `MAX_PARALLEL=2`, `01-alpha` et `02-beta`. La session `01-alpha` franchit la limite molle (`over-soft-limit` → classe `too-big` → re-slice) ; sa session de plan dort 6 s. La session `02-beta` est ordinaire et rapide.

  ```
  ralph: iteration 1: 01-alpha
  ralph: iteration 2: 02-beta
  ralph: session crossed the 150000-token soft limit (peak 1000009) — terminated
  ralph: gate: 02-beta: tests=green typecheck=green scope=green lang=green
  ralph: 02-beta: committed 1 path(s)
  ralph: 02-beta: folded onto the branch
  ralph: iteration 2: 02-beta -> resolved
  ralph: 01-alpha: the session edited the tracker — restored 1 ticket file(s), the iteration cannot be green
  ralph: 01-alpha: escalated to the human sink (too-big)
  ralph: frontier empty after 2 iterations

  exit 0     02-beta -> claimed (owner=pid:5414)     src/beta.txt dans HEAD: oui
  ```

  Le fichier restauré est `02-beta.md`, et la « session » accusée est la session de **plan** de `01-alpha`. Résultat : `02-beta` est livré, commité, replié — et remis `claimed` par le pid du pilote, un claim que personne ne relâchera. Le run rapporte `frontier empty`, `exit 0`, « ce run a broyé tout ce qu'il pouvait ». Au run suivant, `claim_reclaim_stale` verra un `owner=pid:<n>` mort, rendra le ticket à la frontière **en lui facturant un retry** ([26]) et la boucle rebroiera un ticket déjà livré.

  *Témoin — les mêmes deux sessions à `MAX_PARALLEL=1` :* `02-beta -> resolved`, pas de claim, aucune ligne d'édition du tracker.

  *Sonde E — un frère met en quarantaine les enfants d'un re-slice.* Même montage, mais le plan est valide (deux enfants) et c'est la session `02-beta` qui dort 8 s, donc dont la fenêtre couvre les créations :

  ```
  ralph: 01-alpha: too big -> re-sliced into 03-alpha-one 04-alpha-two
  ralph: 03-alpha-one: too big -> re-sliced into 05-alpha-one 06-alpha-two
  ralph: 02-beta: the session wrote the tracker itself — quarantined 03-alpha-one 04-alpha-two 05-alpha-one 06-alpha-two
  ralph: gate: 02-beta: tests=green typecheck=green scope=green lang=green
  ralph: 04-alpha-two: the session edited the tracker — restored 5 ticket file(s), the iteration cannot be green
  ralph: 04-alpha-two: escalated to the human sink (too-big)
  ralph: sterile run: 3 iterations resolved nothing — stopping

  01-alpha     -> ready-for-agent      (son escalade too-big : défaite)
  03-alpha-one -> ready-for-agent      (sa quarantaine : défaite)
  04-alpha-two -> ready-for-human (too-big)
  05/06        -> ready-for-agent      (leur quarantaine : défaite)
  ```

  Quatre tickets créés par les re-slices de deux autres itérations sont attribués à la session `02-beta`, qui n'a rien écrit dans le tracker, et escaladés au puits humain avec une note qui la nomme. Puis le garde de `04-alpha-two` restaure cinq fichiers de tickets écrits par ses frères, ce qui **défait les escalades** — y compris celle de `01-alpha` — et fait repartir la frontière avec des tickets que la boucle avait sortis du jeu. Personne n'a menti nulle part et l'état du tracker est arbitraire.

  *Témoin — le même re-slice à `MAX_PARALLEL=1` :* aucune ligne de quarantaine, aucune restauration croisée, les enfants arrivent `ready-for-agent` sur la frontière comme [07] les y met.

- **Ce que ça dit du registre, et c'est la vraie leçon.** [13] a eu la bonne idée — une définition partagée de « ceci n'est pas l'œuvre du jugé », placée dans le dispatcher parce que c'est le seul endroit par où toutes les écritures passent — et l'a câblée à un seul lecteur. Le producteur est commun, les consommateurs ne le sont pas. C'est le défaut de [25] (« combien d'endroits appellent ça ») retourné une fois de plus : la question n'est pas *où est la source* mais **qui la lit, et qui aurait dû**.

- **Piège attendu sur la quarantaine.** `failures__strays` compare des *ids*, pas des contenus, et le registre est lui aussi une liste d'ids. Exempter par id suffit pour les créations d'un re-slice ; ça n'exempte pas un ticket qu'une session aurait créé sous un id que la boucle a écrit par ailleurs dans la même fenêtre. Décider — et écrire — si l'exemption doit valoir pour la création comme pour l'édition, ou si la création demande une trace plus forte (qui l'a créé, et non seulement que la boucle a touché cet id).

- **Contrainte pour [13].** La granularité du registre est un id, donc « la boucle a écrit `X` » vaut pour *toute* modification de `X` dans la fenêtre. Une session qui édite un ticket que la boucle a touché en même temps échappe encore au garde, `MAX_PARALLEL=1` compris. Ce ticket ne le referme pas ; [40] retire le levier facile, celui-ci reste et doit être écrit dans le tableau.

- **Contrainte héritée de [40], livré le 06/08/2026.** `RALPH_TRACKER_LOG` n'est plus `export`é : le chemin du registre voyage par simple héritage de shell, et le mot-clé ne doit pas revenir. Ça ne coûte rien aux deux gardes que ce ticket câble — `failures_reslice` et `failures_quarantine_strays` tournent tous deux dans un sous-shell du pilote, comme `loop__iterate` — mais ça interdit une forme de correctif : passer le registre à un garde en le remettant dans l'environnement, ou l'écrire quelque part qu'un `env` d'une session atteindrait, rouvre le faux *livré* que [40] vient de fermer. Le témoin est dans `test/mutate.sh` (`40 the register is handed to the session in its environment`) et l'assertion sur la session de plan est dans `test/failures.bats`, test « the planning session is fresh » — si ce ticket touche `failures_reslice`, cette ligne est celle qui doit rester verte.

- **Contrainte pour [16] et [11].** Les deux chemins de réinjection écrivent dans `issues/` hors d'une itération. S'ils tournent pendant qu'un run broie, ils sont indiscernables d'une session pour ces deux gardes. Chacun doit dire, dans son propre ticket, s'il passe par `tracker__dispatch` — c'est ce qui l'inscrit au registre — ou pourquoi il n'a pas à le faire.
