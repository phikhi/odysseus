# Configuration des langues (interaction & artefacts)

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (**post-complétion** — proposition du propriétaire). Découpler, **configurable à l'install [09]** et pour **n'importe quelle langue**, (a) la langue d'**interaction** (l'agent parle/répond à l'humain) et (b) la langue des **artefacts** (documents du projet que l'agent écrit). Aujourd'hui : figé en français + couplé.

## Question

Comment configurer et câbler **deux langues indépendantes** — interaction vs artefacts — pour n'importe quelle langue ?

Cas d'usage :
- (a) interaction FR + artefacts FR (comportement actuel).
- (b) interaction FR + artefacts EN (codebase/docs partageables en anglais).

À trancher :
- **Deux axes découplés** : `LANG_INTERACT` (parole à l'humain) vs `LANG_ARTIFACT` (écrits durables), config [09], toute langue.
- **Périmètre de `LANG_ARTIFACT`** : quels écrits suivent la langue d'artefact ? (tracker/docs : spec, tickets, map, CONTEXT, ADR, LEARNINGS, playthroughs, reçus ; + commentaires de code / messages de commit / texte de PR ?) ; identifiants de code ? édition d'un doc existant ? fichiers du pack lui-même ?
- **Câblage** : `ralph.config.sh` + `CLAUDE.md` généré ; les sessions AFK (sans humain) n'utilisent que `LANG_ARTIFACT` ; `LANG_INTERACT` ne vaut que pour le HITL.

## Answer

Décision verrouillée (grilling HITL). Découpler la langue d'interaction et la langue des artefacts, configurables à l'install [09], pour toute langue. Remplace le « répondre en français » figé et couplé.

**D1 — Deux axes découplés.** `LANG_INTERACT` (l'agent parle/répond à l'humain) ⟂ `LANG_ARTIFACT` (écrits durables dans le projet), indépendants, toute langue. Cas (a) = fr/fr ; cas (b) = fr/en. **Une session AFK n'a pas d'humain → n'utilise que `LANG_ARTIFACT`** ; `LANG_INTERACT` ne vaut que pour le **HITL** (discovery, grilling, human-loop [25]).

**D2 — Périmètre de `LANG_ARTIFACT`.** Gouverne **toute prose durable que l'agent rédige dans le projet cible** : tracker & docs (spec, tickets, map, CONTEXT, ADR, LEARNINGS/records, playthroughs, reçus [18]) **+** prose code-adjacente (commentaires, messages de commit, descriptions de PR / `Escalation:`). **Ne suit PAS** : les **identifiants/le code** (→ conventions du code existant = axe **Standards [08]**) ; les **fichiers du pack/framework** (skills, `lib/*.sh`, `loop.sh` — internes, inchangés). **Édition d'un doc existant → matche sa langue** (pas de doc bilingue) ; `LANG_ARTIFACT` = défaut pour les **nouveaux** artefacts.

**D3 — Câblage.** `LANG_INTERACT` + `LANG_ARTIFACT` dans `ralph.config.sh`, **confirmation forcée** au bootstrap [09] (défaut proposé = même langue pour les deux, cas a). Le wizard **remplace** le « répondre en français » figé du `CLAUDE.md` par la double consigne (*« interagis en `LANG_INTERACT` ; rédige les artefacts en `LANG_ARTIFACT` »*), lue par chaque session. Les **prompt templates [06]** la portent : AFK → `LANG_ARTIFACT` seul ; HITL → `LANG_INTERACT` (parole) + `LANG_ARTIFACT` (écrits). **Doublé d'un gate de validation de langue** (D4) : le framework préférant les gates déterministes aux consignes molles ([08]/[19]), la consigne `CLAUDE.md` ne suffit pas seule.

**D4 — Gate de validation de langue (amendement).** Le framework préfère les gates déterministes aux consignes molles ([08]/[19]) → la consigne `CLAUDE.md` (D3) est **doublée d'un check objectif**. **Post-hoc au gate [08]** (patron scope-guard [19]) : **détection de langue sur la prose rédigée** du diff (docs/tracker + commentaires + commit + PR ; **pas** le code/identifiants → Standards). **Langue attendue par fichier** : nouvel artefact → `LANG_ARTIFACT` ; **édition** → langue **existante du fichier** (cohérent D2, anti-faux-positif legacy). **Tolérance** : langue **dominante** au-dessus d'un seuil ⚙️ (pas mot-à-mot ; termes/identifiants étrangers cités OK). Détection = **utilitaire léger déterministe** (type `langdetect`) de préférence, lentille LLM cheap en secours. **Réaction** : gate rouge → **retry-N** [08] (réécriture) ; récurrent → escalade. Mauvaise langue = **interne/fixable**, pas contractuel. **Place** : une **lentille objective du registre [23]**, prédicat = « l'itération a rédigé de la prose ».

### Contraintes créées ailleurs
- **[09] form-factor** : `LANG_INTERACT` + `LANG_ARTIFACT` dans `ralph.config.sh` (confirmation forcée, défaut = langues identiques) ; le `CLAUDE.md` généré porte la double consigne (remplace le « répondre en français » figé) ; **`LANG_CHECK` on/off + seuil ⚙️** (D4).
- **[06] control-flow** : les prompt templates injectent la consigne selon le mode — AFK = `LANG_ARTIFACT` ; HITL = les deux.
- **[08] gate** : nouveau **check objectif de langue** (post-hoc, par-fichier, tolérant, déterministe de préférence) → gate rouge = retry-N ; le code/les identifiants restent hors périmètre (axe **Standards**).
- **[23] registre** : gagne une **lentille objective « langue »**, déclenchée sur « a rédigé de la prose ».
- **[24]** : la calibration de la lentille langue (seuil, faux positifs) relèverait de la revue de capacités — mais la lentille elle-même est **gravée ici**.
