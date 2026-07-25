# Vérification visuelle des surfaces UI (vrai art + non-occlusion)

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (leçon Multiplyz #170/#180). **Étend [08]/[05]** : « e2e si surface visible » est insuffisant. Voir `ANALYSE-multiplyz-vs-odysseus.md` §5.4.

## Question

Comment durcir « e2e inclus si surface visible » [05] en **preuve visuelle réelle**, sachant que le framework se dépose sur des stacks arbitraires ?

Contexte : Multiplyz a durement appris (#170/#180) qu'un **panel de tests verts sur un front jamais rendu visible** (élément recouvert, ou capture d'un **fixture** au lieu du **vrai asset**) = **DoD non satisfait**. Correctifs : capture systématique **sur les vrais assets** + **garde de non-occlusion** (`boundingClientRect`) pour tout élément superposé.

À trancher :
- **Capture sur les VRAIS assets** : comment garantir que la vérif regarde l'art/les données de prod et **pas un fixture de test** ? (Multiplyz a dû livrer une infra « servir le vrai art en dev/CI » avant de rendre la règle contraignante.)
- **Garde de non-occlusion** : exiger, pour tout élément à impact visuel superposé (overlay/badge/`absolute`), une assertion type `boundingClientRect` (élément réellement visible, bon endroit, non recouvert). Généralisable comment hors Playwright ?
- **Où** : dans le **gate par-ticket [08]** (surface touchée par ce ticket) ou le **gate feature [12]** (parcours complet) — ou les deux ?
- **Qui juge la capture** : check objectif automatisable (assertion géométrique) vs jugement — rôle de l'**axe fidélité [14]** ?
- **Généricité / dégradation** : que devient l'exigence sur un projet **sans surface visible** (CLI/lib) → no-op ; et sur un projet visible **sans outil de capture** → escalade `ready-for-human` ou exigence de fournir la commande dans `ralph.config.sh` ?

Peut faire graduer un ticket **research** (outillage de vérif visuelle générique multi-stack) si la décision attend un fait.

## Answer

Décision verrouillée (grilling HITL). [13] = la **couche visuelle objective** de l'échelle de valeur (cf. [12] D6) : prouver la **présence effective** d'une surface, pas juger son goût.

**D1 — Couche objective/mécanisée, par-ticket [08], machinerie partagée [12].** [13] prouve *« l'élément est réellement rendu, dans le viewport, non recouvert, sur le vrai asset »* — **assertions géométriques déterministes, sans LLM** (complaisance impossible, tier tests/typecheck d'[08]). Check **par-ticket dans le gate [08]** (surface touchée par le ticket) ; **même machinerie** (pilotage navigateur + captures configuré [09]/[12]) **réutilisée par le playthrough [12]** au niveau feature — une mécanique, deux points d'appel. Le jugement esthétique « ça rend bien / la valeur passe » est **[14]** (fidélité) + la narration [12], **pas** [13].

**D2 — Non-occlusion : règle Odysseus + outil stack.** Dès qu'un ticket livre un **élément visuel superposé** (overlay / badge / `absolute` / z-index), son **e2e [05] DOIT inclure une assertion géométrique** (présent, dans le viewport, non recouvert, au point attendu) — pas d'overlay sans ça → gate rouge. C'est une **spécialisation de l'e2e d'[05]** (« e2e si surface » → *pour un superposé, l'e2e inclut la non-occlusion*), pas une machinerie parallèle. L'**outil** (Playwright `boundingBox`, Cypress, Selenium, capture+pixel) est **spécifique au stack, configuré** ; Odysseus impose l'exigence, pas l'implémentation (cohérent avec `TEST_CMD`/`TYPECHECK_CMD` configurables [08]/[09]).

**D3 — Absence d'outil : réglée en discovery [09], jamais au runtime.** La boucle AFK ne **découvre jamais** l'absence d'outil (ce serait faux-vert ou blocage sauvage). Le wizard [09] **auto-détecte** et **force une décision humaine** (anti-faux-vert, pattern `TEST_CMD`). Trois états **configurés avant la boucle** : (a) **outil présent & confirmé** → [13] mord ; (b) **absent mais vérif voulue** → l'humain **provisionne l'outil en discovery** (ajouter une dépendance = **contractuel** [05], **jamais auto-installé en AFK** ; le framework suggère, n'installe pas) sinon les tickets UI sont **`ready-for-human` dès le contrat** ; (c) **absent & vérif renoncée** (CLI/lib, ou renoncement explicite) → `VISUAL_CMD` **vide = déclaré indisponible**, checks visuels **no-op mais enregistrés** (reçu [18]/LEARNINGS : « vérif visuelle désactivée par config »). Au runtime, la boucle ne voit qu'un état déjà tranché.

**D4 — Vrais assets, pas de fixtures.** Un check visuel n'est **certifiant que s'il a tourné sur les vrais assets** (mode **confirmé en discovery [09]**, flag sur `VISUAL_CMD`) ; **fixture ≠ vert** (no-op explicite ou rouge, jamais pass silencieux — échec Multiplyz #170/#180). Si l'env ne peut servir que des fixtures (infra vrais-assets absente, situation #323) → soit les tickets UI concernés sont **`ready-for-human`**, soit **« servir les vrais assets » devient un ticket-prérequis** qui débloque la règle. Outil de pilotage **et** vrais assets = deux facettes de la **fidélité de l'environnement de vérif**, confirmée au bootstrap.

**D5 — Pas de ticket research.** La décision est un **contrat de design** (règle + config + split machine/jugement) — elle n'attend aucun fait ; l'outil concret par-stack est l'affaire du projet cible, configuré. Le « peut graduer un research » (conditionnel) ne se déclenche pas.

### Contraintes créées ailleurs
- **[05] contrat** : (a) **spécialisation e2e** — un élément superposé exige une assertion de non-occlusion ; (b) un ticket UI **non AFK-vérifiable** (pas d'outil / pas de vrais assets) est **`ready-for-human` dès le contrat**, jamais `ready-for-agent` ; (c) « servir les vrais assets » peut être un **ticket-prérequis** (à la #323).
- **[08] gate** : les assertions visuelles tournent dans le **gate par-ticket** (tier e2e/tests), **déterministes, sans LLM**.
- **[09] form-factor** : le wizard auto-détecte l'outillage visuel ; `VISUAL_CMD` (+ flag vrais-assets) en **confirmation forcée** (anti-faux-vert) ; **vide = déclaré indisponible** (no-op enregistré) ; **jamais d'auto-install** de dépendance.
- **[12] playthrough** : réutilise la machinerie [13] au niveau feature ; son « escalade si non-pilotable » est la **conséquence runtime** des états configurés en [09].
- **[14] fidélité** : [13] fournit l'objectif « c'est réellement là » ; [14] juge « la valeur passe-t-elle » — la **capture est preuve partagée**.
- **[18] reçu / [11] LEARNINGS** : consigner « vérif visuelle désactivée par config » quand applicable.
