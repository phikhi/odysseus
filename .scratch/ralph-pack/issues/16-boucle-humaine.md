# 16 — Boucle humaine (`human-loop.sh`)

**What to build:** La 2ᵉ boucle bash HITL, sœur de la ralph loop, qui **draine le puits `ready-for-human`**, route chaque ticket par sa raison d'escalade vers le bon traitement, et **réinjecte** le résultat en `ready-for-agent`. Ferme le cycle escalade → drain → réinjection.

**Blocked by:** 07

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/router.sh`, `test/human-loop.bats`

**Status:** ready-for-agent

- [ ] `human-loop.sh` draine `ready-for-human` et route par `Escalation:` : `decision`→grilling, `too-big`→to-tickets, `failed-impl`→implement/pair (amorcé `failed/<ticket>` + reçu), `spec-gap`→to-spec, `sign-off`→approbation.
- [ ] Anti-faux-vert : tout code corrigé repasse le gate via réinjection `ready-for-agent` ; jamais de `resolved` direct sauf `sign-off`.
- [ ] Exclusion mutuelle avec l'AFK via le verrou de run (on broie **ou** on draine).
- [ ] L'ordre de traitement = impact de déblocage puis NN.

## Comments

- **Contrainte posée par [07] : ce qui arrive réellement dans le puits, et avec quoi.** Trois raisons sont posées par la boucle AFK, sur la ligne `Escalation:` : `failed-impl` (gate rouge ou crash au-delà de `RETRY_N`, avec `Failures:` à l'appui), `decision` (débordement **contractuel** — la session a écrit dans la write-surface d'un autre ticket ; deux tickets sont dessinés sur le même fichier et c'est un arbitrage de découpage, pas une implémentation à refaire), `too-big` (la session a franchi la limite molle **et** aucun découpage préservant les AC n'a pu être produit). `spec-gap` et `sign-off` ne sont posées par personne aujourd'hui.
- **Chaque escalade est accompagnée d'une branche `failed/<ticket>`** qui contient l'arbre exact de la tentative, tracker retiré, commitée sur le `HEAD` pré-session. C'est l'amorce prévue par l'AC `failed-impl` — elle existe pour les trois raisons, pas seulement celle-là. Elles ne sont jamais nettoyées : les recycler ou les supprimer à la réinjection est du ressort de cette boucle.
- **Remettre `Failures:` à zéro en réinjectant.** Le compteur est porté par le ticket et n'est pas remis à zéro par [07] (c'est la mémoire de ce qui s'est passé). Un ticket réinjecté en `ready-for-agent` avec `Failures: 3` et `RETRY_N=2` sera donc **réescaladé à sa première tentative**, sans retry. `tracker_mark_ready` efface `Escalation:` mais pas `Failures:` — à faire ici, explicitement.
- **`to-tickets` est utilisable ici, et nulle part ailleurs dans le pack.** Le skill existe (`.agents/skills/to-tickets/`), mais son frontmatter porte `disable-model-invocation: true` — seul un humain le déclenche — et son étape 5 **publie directement** dans `.scratch/<feature>/issues/`. Les deux sont disqualifiants pour la boucle AFK ([07] explique pourquoi et implémente le contrat en ligne) et parfaitement légitimes ici : un humain invoque, relit, publie. Attention tout de même à un point : ce que le skill publie n'a **pas** traversé la validation de découpage de [07] (write-surface incluse dans celle du parent, AC préservées). C'est la relecture humaine qui en tient lieu.

- **`too-big` → to-tickets : la boucle AFK a déjà essayé.** Le re-slice autonome de [07] tourne avant l'escalade ; un ticket arrivant ici en `too-big` est un ticket qu'une session fraîche n'a pas su découper en préservant les AC, ou dont le plan élargissait la write-surface. Le format de plan attendu par la boucle (`--- ticket: <slug> | <title> ---`, write-surface incluse dans celle du parent) est dans `failures__reslice_prompt` — le même contrat vaut pour un découpage humain.
