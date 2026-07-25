# Lentilles de revue au risque (sécurité & accessibilité)

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (**post-complétion** — gap relevé par le propriétaire). **Généralise/étend [08] et [14].** Multiplyz avait `reviewer-security` (auth / données sensibles / surface d'attaque) + l'a11y repliée dans le reviewer frontend ; Odysseus n'a que Standards\|Spec + Fidélité [14]. Cf. `ANALYSE-multiplyz-vs-odysseus.md` (rôles reviewers).

## Question

Le gate [08] doit-il passer d'un jeu de lentilles **fixe** (Standards\|Spec + Fidélité [14]) à un **registre de lentilles de revue au risque**, et y ajouter **sécurité** et **accessibilité** ?

À trancher :
- **Modèle** : registre de lentilles, chacune avec un **prédicat de déclenchement** (toujours-active vs gatée au risque) ? [14] devient la 1ʳᵉ instance gatée.
- **Déclencheurs AFK** : comment la boucle sait qu'un ticket exige sécu / a11y, **sans humain** (tag de discovery ? write-surface [15] ∩ chemins sensibles ? surface visible pour a11y) ?
- **Implémentation** : brief sur un subagent frais (façon [14]) ou skill substrat (`security-review`/`design-review`, absents) ? déléguer à un skill s'il existe ? refs projet optionnelles ?
- **Verdict** : bloquant (comme les autres axes) ; finding **contractuel** (la spec mandate un design non-sûr) → escalade [05] ?
- **Research ?** : le brief sécu doit-il être ancré dans un référentiel (OWASP…) — un fait — ou est-ce du contenu de design ?

## Answer

Décision verrouillée (grilling HITL). **Généralise [08]/[14]** en un registre de lentilles au risque, et ajoute sécurité & accessibilité.

**D1 — Registre de lentilles au risque (généralise [14]).** Le gate [08] passe d'un fan **fixe** à un **registre** où chaque lentille déclare sa **nature** (objective/jugement) et son **prédicat de déclenchement** (toujours-active / gatée au risque). Le fan = les lentilles dont le prédicat mord pour ce ticket.
- **Toujours-actives** : Standards, Spec (substrat `/code-review`).
- **Gatées au risque** : Fidélité [14] (**1ʳᵉ instance rétroactive du patron**), **Sécurité**, **Accessibilité**.
Extensible (un projet ajoute une lentille — perf, i18n — sans refondre le gate) ; coût honnête (une lentille LLM n'est payée que quand son prédicat mord).

**D2 — Déclencheurs AFK déterministes.**
- **Accessibilité** → **surface visible** (même signal que fidélité [14] / visuel [13]).
- **Sécurité** → **tag `security`** (posé par `to-tickets`/`triage`, façon `scope:` Multiplyz) **OU** **write-surface [15] ∩ `SECURITY_PATHS`** (globs ⚙️ : auth, secrets, modèle de données, frontières réseau/entrée).
- **Asymétrie de fail-safe** : fidélité/a11y **skippent** au doute (rien à juger sans surface) ; sécurité **fire** au doute (un trou de sécu coûte plus qu'un appel LLM). Prédicats = tags + disjonction de globs (zéro LLM).

**D3 — Implémentation, verdict, pas de research.**
- **Brief sur subagent frais** (façon [14]) : *sécu* = injection/authz/secrets/exposition de données/surface d'entrée ; *a11y* = clavier/ARIA/contraste/focus/sémantique. **Délègue à un skill substrat** (`security-review`/`design-review`) **s'il existe**, sinon le brief EST la lentille. Refs projet **optionnelles** (`SECURITY_REFS`/threat-model, façon `FIDELITY_REFS`).
- **Verdict bloquant** ([08] retry-N→escalade) ; finding **contractuel** (la spec mandate un design non-sûr/inaccessible) → **escalade `ready-for-human`** [05] (retenter ne corrige pas une spec).
- **Pas de research** : le brief est du contenu de design générique ; la sécu profonde est propre au projet (`SECURITY_REFS`), pas un fait générique.

**Renvoi → [24]** : ce registre est le **slot** extensible ; **quand** une nouvelle lentille/agent/skill devient nécessaire (au fil de l'évolution du projet) est décidé par le mécanisme de **revue de capacités [24]** (détecter-et-proposer, jamais créer en AFK).

### Contraintes créées ailleurs
- **[08] gate** : le fan devient un **registre** évalué par prédicat ; Standards/Spec toujours, Fidélité/Sécu/A11y gatées. *Resolved* = toutes les lentilles déclenchées sont vertes.
- **[14]** : rétro-cadrée comme la 1ʳᵉ lentille gatée du registre (aucun changement à sa décision).
- **[05]/[06]** : finding contractuel d'une lentille → escalade `ready-for-human` ; interne → retry.
- **[09] form-factor** : `SECURITY_PATHS` + `SECURITY_REFS` (optionnel) dans `ralph.config.sh` ; briefs sécu/a11y dans le pack ; délégation à `security-review`/`design-review` si présents.
- **[15]** : réutilise la write-surface pour le prédicat sécurité.
- **[24]** (à graduer) : le détecteur qui propose de **remplir** le registre au fil de l'eau.
