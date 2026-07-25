# Artefact d'audit a posteriori par itération

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (équivalent léger du playthrough persisté Multiplyz). **Étend [04]/[08]**. Voir `ANALYSE-multiplyz-vs-odysseus.md` §6.4.

## Question

La boucle doit-elle produire un **reçu persistant par itération** permettant au propriétaire une **relecture asynchrone** — sans imposer le flux PR qu'Odysseus n'a pas ?

Contexte : Odysseus marque `resolved` **en local** [04], sans PR/diff/captures qu'un humain puisse relire après coup. Multiplyz s'appuie sur la **PR + captures** (relecture a posteriori) et sur le **playthrough persisté** (#164 : un reçu jetable en contexte est invérifiable). Le **journal de run [04]** existe mais est minimal (tâche/coût/tours/`is_error`) et non conçu pour la relecture.

À trancher :
- **Contenu du reçu** : diff (`git diff` de l'itération) + captures éventuelles [13] + résultats des 3 checks du gate [08] + coût/tours/horodatage.
- **Où il est committé/écrit** : dans le **projet cible** (`docs/receipts/<ticket>.md` ?) ? en **note de résolution sur le ticket** [04] ? un dossier `.scratch/<feature>/receipts/` ?
- **Rapport avec le journal de run [04]** : le reçu **est-il** le journal enrichi (une entrée = un reçu riche) ou un **artefact séparé** (journal = ligne compacte machine ; reçu = document humain) ? Rester cohérent avec « journal non-autoritaire ».
- **Sans flux PR** : le reçu remplace la PR comme **surface de relecture** ; le propriétaire audite quand il veut (le marquage n'attend pas — AFK préservé).
- **Rapport avec le playthrough [12]** : reçu = **par-itération** (léger, mécanique) ; playthrough = **par-feature** (lourd, narré). Complémentaires.

## Answer

Décision verrouillée (grilling HITL). **Étend [04]/[08]**, couplé à [16]. Reçu = surface de relecture asynchrone par-itération, substitut de PR (local) ou PR elle-même (distant).

**D1 — Artefact séparé ; stratification à 4 couches.** Séparé du journal [04] (fusionner tuerait la ligne machine compacte). Quatre couches, zéro redondance : **journal [04]** (ligne machine/itération, métriques, non-autoritaire, jamais relue) · **reçu [18]** (document humain/itération, relecture async) · **playthrough [12]** (narré/feature, acceptation durable `docs/playthroughs/`) · **LEARNINGS [11]** (leçons distillées, seulement quand il y a une leçon). Reçu = audit du « qu'est-ce qui a atterri » ; playthrough = acceptation du « la valeur est vécue ». **Résout le fog « articulation reçu/playthrough ».**

**D2 — Contenu (couche de valeur) + diff par référence.** Contenu backend-agnostique = **résumé** + **4 verdicts de gate [08]** (tests · typecheck · code-review Standards|Spec · fidélité [14]) + **preuves/captures [13]** + **méta** (ticket/coût/tours/retries/modèle/horodatage). Le **diff est TOUJOURS par référence, jamais inliné** : plage de commits (`<pre>..<post>`, local) / diff **natif de la PR** (distant). La valeur du reçu = la couche que ni un diff ni une PR nue ne donnent gratuitement (verdicts LLM code-review + fidélité, preuves, méta).

**D3 — Quand produit.** Sur **itération `resolved`** (audit de ce qui a atterri, le cœur) **et** sur **escalade finale `ready-for-human`** (l'humain voit la dernière tentative — diff + verdicts échoués — en plus de la branche `failed/<ticket>` [08]). **Pas** sur les retries intermédiaires ni les pauses budget. Coût quasi nul : la boucle a déjà toutes les données au marquage [04].

**D4 — Rendu par l'adaptateur [16] (`emit_receipt`), forme suivant le backend.**
- **`local`** : fichier `.scratch/<feature>/receipts/<NN>-<slug>.md` (artefact de process, **pas** le `docs/` produit) + référence commit du diff ; rétention ⚙️ (élaguable).
- **`github`/`gitlab`** : le reçu **est la PR** (description = couche de valeur ; diff = natif ; CI dessus [16] ; **mergée au gate-vert = `mark_resolved`**). Un seul artefact = PR = reçu = surface CI = unité d'intégration.
- **Conséquence** : le backend **façonne la forme d'intégration** — distant = flux **PR-par-itération + merge** (façon Multiplyz) ; local = **intégration sérialisée directe** [15].

### Contraintes créées ailleurs
- **[04]** : reçu = artefact séparé du journal (journal inchangé, ligne machine) ; produit par la boucle au marquage.
- **[06] control-flow** : au marquage `resolved`/escalade, appeler `emit_receipt` (rendu par l'adaptateur [16]) avec les données déjà en main (diff-ref, verdicts, preuves, méta).
- **[08] gate** : les 4 verdicts alimentent le reçu ; aucune exécution en plus (réutilisation des sorties du gate).
- **[16] adaptateur** : ajouter `emit_receipt` à l'interface — `local` écrit un fichier `receipts/`, `github`/`gitlab` ouvre/met à jour une **PR** (mergée au gate-vert, CI [16] dessus).
- **[09] form-factor** : dossier `.scratch/<feature>/receipts/` (local) + ⚙️ de rétention des reçus dans `ralph.config.sh`.
- **[11]/[12]/[13]** : couches complémentaires ; le reçu réutilise les captures [13] comme preuves.
