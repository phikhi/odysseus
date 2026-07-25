# Axe de revue « fidélité » (3ᵉ axe du gate)

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (leçon Multiplyz : rôles PO / game-design). **Étend [08]** : `/code-review` deux axes → trois. Voir `ANALYSE-multiplyz-vs-odysseus.md` §5.5.

## Question

Faut-il un **3ᵉ axe de revue « fidélité »** au-delà des deux axes actuels (`Standards` = conventions du repo, `Spec` = conformité à l'issue/AC) [08] ?

Contexte : l'axe `Spec` vérifie la **conformité au ticket** ; il ne vérifie **pas** que *la valeur atteint l'utilisateur*. Multiplyz a un **Product Owner** + **game-design** (lecture seule, verdict `APPROVED`/`CHANGES_REQUESTED`) dont le rôle est exactement d'attraper la classe de bug que l'ingénierie **approuve à tort** (mécanisme livré mais jamais câblé jusqu'à l'écran).

À trancher :
- **Ce qu'il vérifie** : « ce mécanisme est-il réellement **consommé / câblé jusqu'à l'écran** ? la valeur du ticket est-elle **vécue** ? » — formulation **générique** (Odysseus n'a pas de specs produit type PRODUCT/ENGINE spécifiques).
- **Comment il s'ajoute** : 3ᵉ sous-agent du `/code-review` (qui fane déjà en Standards|Spec) ? subagent séparé dans le gate [08] ? Impact budget (un axe de plus = un appel LLM de plus par ticket).
- **Sur quoi il s'appuie** : le ticket + `CONTEXT.md`/ADRs ambiants [05] suffisent-ils pour juger la fidélité générique, ou faut-il un pointeur produit optionnel dans `ralph.config.sh` ?
- **Rapport avec le gate feature [12]** : l'axe fidélité est **par-ticket** (ce mécanisme est-il câblé), le playthrough [12] est **par-feature** (le flux entier est-il vécu) — complémentaires. Éviter la redondance.
- **Verdict bloquant** : un `CHANGES_REQUESTED` de l'axe fidélité déclenche-t-il le retry/escalade [08] comme les autres axes ?

## Answer

Décision verrouillée (grilling HITL). [14] = le **jugement par-ticket** de l'échelle de valeur (cf. [12] D6, [13]) : *« la valeur est-elle câblée/consommée jusqu'à l'utilisateur »*.

**D1 — Ce qu'il vérifie & positionnement.** Brief : *« ce mécanisme est-il **consommé / câblé jusqu'à l'écran** ? la valeur du ticket est-elle **vécue**, pas seulement présente ? »* — **générique** (aucune spec produit requise). Distinct de : l'axe **Spec** d'[08] (« construit ce que le ticket demandait / AC » — justement ce qui a menti chez Multiplyz) ; **[13]** (présence objective, géométrique, sans LLM) ; **[12]** (flux assemblé par-feature). [14] = le filet **jugement, précoce, par-slice**.

**D2 — Implémentation : lentille peer dans le fan du gate [08], gating au risque.** Le skill substrat `/code-review` fane **en interne** Standards|Spec — on ne le réinvente pas [09]. La fidélité est une **lentille séparée (subagent frais)** lancée **en parallèle** dans le gate [08], à côté de tests / typecheck / `/code-review` (logiquement « 3ᵉ axe », mécaniquement une branche parallèle de plus). **Gating au risque** (fan-out-au-risque [07]) : elle **ne tourne que si le ticket porte une valeur user-facing** ; ticket **purement interne** (refacto/infra sans surface) → **skip** (comme le no-op [13]). **Tier Sonnet** (jugement).

**D3 — Grounding.** Par défaut : **ticket** + **`CONTEXT.md`/ADRs** [05] + **`spec.md`** (qui porte le flux bout-en-bout depuis [12]) — suffisant partout. **Enrichissement optionnel** : pointeur produit `FIDELITY_REFS` (`ralph.config.sh`) pour les projets à specs produit riches (équivalent du PO de Multiplyz). Non requis.

**D4 — Verdict bloquant & échec.** Axe **bloquant** : `CHANGES_REQUESTED` fidélité = échec de gate ; *resolved* exige **tous** les axes verts (fidélité incluse quand elle s'applique). Échec → **retry-N fresh** [08] (câbler-jusqu'à-l'écran est **dans le scope** du ticket → une session fraîche peut le câbler) puis `ready-for-human`. **Pas de re-slice** au niveau ticket (le re-câblage cross-ticket est l'outil feature-level de [12]) ; si câbler exige de sortir du scope → remonte comme trou d'assemblage au playthrough [12].

### Contraintes créées ailleurs
- **[08] gate** : ajouter une **4ᵉ branche parallèle** = lentille fidélité (subagent frais, Sonnet), **gatée au risque** (skip si pas de surface) ; *resolved* = tous axes verts, fidélité incluse ; échec fidélité → retry-N→escalade standard. Le fan du gate passe de 3 à **4 branches** (tests · typecheck · `/code-review` Standards|Spec · fidélité).
- **[05]/[09]** : `FIDELITY_REFS` optionnel dans `ralph.config.sh` ; par défaut la lentille juge sur ticket + ambiant + `spec.md`.
- **[12]/[13]** : échelle complète — [13] objectif « c'est là » · [14] jugement « ça passe » (par-ticket) · [12] playthrough « le flux est vécu » (par-feature). La **capture [13] est preuve partagée** avec [14].
