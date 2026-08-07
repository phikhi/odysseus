# 42 — Les deux gardes du tracker ne lisent pas tous le registre

**What to build:** Donner le registre de [13] aux deux gardes qui manipulent `issues/` et ne l'ont pas. `failures_protect_tracker` a **deux** appelants : celui de `loop.sh`, à qui [13] a passé le `mark`, et celui de `failures_reslice`, qui l'appelle sans — donc avec `ours=" "`, donc en traitant tout ce que la boucle a écrit pendant la fenêtre du re-slice comme l'œuvre de la session de plan. Et `failures_quarantine_strays`, qui garde le même répertoire contre les tickets qu'une session s'accorde, ne consulte le registre **nulle part** : les tickets qu'un re-slice voisin vient de créer sont des ids qui n'étaient pas là, donc des intrus. Les deux gardes se démolissent mutuellement dès `MAX_PARALLEL>1`, et le symptôme est celui que [13] décrit pour son propre défaut : un ticket `resolved` et son voisin coincé `claimed`.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/tracker.sh`, `test/failures.bats`, `test/concurrency.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Un re-slice qui tourne pendant qu'un frère est marqué ne défait pas ce marquage : le frère reste `resolved`, sans claim, et le re-slice n'est pas refusé au motif d'une édition qu'il n'a pas faite.
- [x] Une itération dont la fenêtre couvre la création des enfants d'un re-slice voisin ne les met pas en quarantaine : les enfants entrent sur la frontière, la note « the session wrote these tickets into the tracker itself » ne nomme que ce que *sa* session a écrit.
- [x] Les deux gardes lisent la **même** définition de « ceci n'est pas l'œuvre du jugé », lue au même endroit — la primitive du dispatcher — plutôt qu'une seconde liste tenue à côté. Un troisième garde ajouté plus tard doit hériter de la définition, pas la recopier.
- [x] Le témoin appairé pour chacun des deux : le même scénario à `MAX_PARALLEL=1` laisse le frère `resolved` et les enfants sur la frontière. Sans lui, un test vert ne dit pas si le correctif a fait quelque chose.
- [x] La mutation vise le passage du registre à chacun des deux gardes séparément — retirer le `mark` du re-slice doit rougir par un **ticket de frère défait**, pas par une ligne de log.

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

- **Livré le 06/08/2026.** Les deux sondes ont d'abord été rejouées telles quelles et rendent mot pour mot ce que ce ticket décrit — sonde D : `02-beta` livré, commité, replié puis `claimed (owner=pid:83299)`, `01-alpha` escaladé `too-big` sans enfants ; sonde E : `02-beta: the session wrote the tracker itself — quarantined 03-alpha-one 04-alpha-two`, les deux enfants `ready-for-human`, plus une ligne `could not claim 03-alpha-one — someone else has it` que le ticket ne mentionnait pas (le pilote essaie de claim un enfant que la quarantaine d'un frère escalade au même instant). Après correctif, chacune rend exactement l'état de son témoin à `MAX_PARALLEL=1`.

- **Ce que le correctif touche, et un écart de write-surface.** `failures__register_since` / `failures__in_register` dans `failures.sh` sont la définition partagée, un appel au-dessus de `tracker_writes_since` ; les deux gardes ne portent plus aucune connaissance de la forme du registre. `failures_reslice` prend son repère **avant** ses deux instantanés et le passe aux deux gardes. **`.claude/loop.sh` a été édité alors qu'il n'est pas dans la write-surface déclarée ci-dessus** : passer le repère à la quarantaine se fait chez son appelant, il n'y avait pas d'autre endroit. Deux lignes y changent — l'argument `"$mark"` et l'ordre de prise du repère.

- **Le repère est pris avant `seen`, et rien ne le teste.** Ordre d'origine : `seen` puis `mark`. Un frère qui crée un ticket entre les deux le rend invisible des deux côtés — pas dans `seen`, donc intrus ; écrit avant le repère, donc hors du registre — soit une quarantaine sur un ticket de la boucle. La fenêtre est de deux substitutions de commandes et aucun test ne peut la viser sans mesurer la machine, donc c'est un durcissement décidé et non couvert : c'est écrit ici parce que le prochain qui déplacera ces trois lignes n'aura que ce commentaire.

- **Le piège attendu sur la quarantaine, tranché : l'exemption par id vaut pour la création comme pour l'édition, et la raison n'est pas que l'id soit une trace forte.** C'est *quelles entrées peuvent atteindre la comparaison* : un intrus est un id que le tracker ne portait pas au spawn, donc une entrée du registre ne peut en matcher un qu'en nommant un ticket que la boucle a **créé** dans la fenêtre — toute autre entrée nomme un ticket déjà là, et un ticket déjà là n'est jamais un intrus. Cette équivalence n'était pas vraie avant : le dispatcher notait le **slug** passé à `tracker_open_ticket` et non l'id rendu, donc (a) l'id créé n'était dans le registre par aucun chemin et (b) une ligne du registre nommait quelque chose qui n'est le nom d'aucun ticket — une session qui aurait créé `alpha-one.md` pendant qu'un re-slice voisin découpait en `alpha-one` serait passée. Le dispatcher note maintenant l'id **produit** par `open_ticket` et les **deux** ids de `renumber` (le fichier bouge : un numéro cesse d'exister, un autre commence).

- **Ce que ça laisse ouvert, et c'est pour [13].** La granularité reste l'id, donc trois choses restent vraies et sont dans le tableau : une session qui édite un ticket que la boucle touche au même instant échappe encore au garde ; un enfant de re-slice arrive maintenant sur la frontière (c'est le correctif) et ce qu'une session hostile y écrirait en le voyant apparaître dans `issues/` y resterait ; et un ticket **créé puis supprimé** dans une même fenêtre n'est dans aucun des deux arbres comparés ni dans aucune liste d'ids — il part sans un mot et laisse son parent bloqué sur un id qui n'existe plus (celui-là est antérieur à ce ticket et ne change pas avec lui). Les trois demandent la même chose : une trace **de contenu** plutôt que d'id. Non construite ici — ce ticket est un câblage, et changer la forme du registre changerait ses deux lecteurs et l'entrée de mutation de [40] avec.

- **Et la rançon du câblage, dite là où on décide** : le registre éteint désormais *deux* gardes. Une session qui en connaîtrait le chemin ne s'achèterait plus seulement une édition non défaite mais un ticket à elle sur la frontière, sous la write-surface qu'elle s'est accordée. Rien ne s'est ouvert — [40] a retiré le seul canal — mais l'entrée de mutation `40 the register is handed to the session in its environment` vaut plus cher qu'avant, et c'est écrit ici et dans [40].

- **Gates.** `test/mutate.sh` gagne trois entrées ([42], une par garde plus celle du dispatcher) et quatre entrées existantes ont dû être ré-ancrées, toutes vérifiées `ok` après : `07 a session's own tickets reach the frontier`, `07 a plan is read even from a session that wrote the tracker`, `21 a plan is read from a session that edited the tracker` (l'argument `"$mark"` s'ajoute à leur ancre) et `13 the tracker guard does not know what the loop wrote` (son assignation a fondu dans le lecteur partagé — l'ancre porte maintenant la ligne suivante, parce que la **même** assignation existe dans les deux gardes et qu'une ancre qui matche les deux mutait le premier en rapportant VACUOUS sur un test sain).

- **État final mesuré.** `bash test/run.sh` : **394 tests** (388 avant, six neufs : quatre dans `concurrency.bats` — les deux sondes et leurs témoins — et deux dans `failures.bats` pour la quarantaine au niveau lib), **1 rouge**, `a run killed mid-session leaves a claim…`, le symptôme de [44]. L'autre rouge connu (`a stop request lets the iterations in flight finish`, famille [38]) est passé sur ce run et avait rougi sur le run précédent : la liste des noms reste celle du briefing, le nombre varie, comme [38] le dit. `bash test/mutate.sh` complet : **359 entrées, 1 `not ok`**, `23 a TERM nobody answers hangs the run for ever`, VACUOUS — l'entrée attendue.

- **Une régression attrapée par le pack sur lui-même, et elle vaut d'être gardée.** Les deux helpers partagés s'appelaient d'abord `failures__loop_writes` et `failures__is_loop_write` : `test/layering.bats` les a lus comme un lib appelant `loop.sh`, parce qu'il cherche `loop_[a-z0-9_]*` dans les libs et qu'un nom de fonction *contenant* le préfixe d'un autre module est indistinguable d'un appel vers lui. Renommés `failures__register_since` / `failures__in_register`. La leçon n'est pas le nom : c'est qu'un préfixe de module est un espace de noms réservé **à l'intérieur des identifiants**, pas seulement en tête.
