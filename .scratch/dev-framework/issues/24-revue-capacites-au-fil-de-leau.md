# Revue de capacités au fil de l'eau (auto-extension bornée)

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (**post-complétion** — proposition du propriétaire). Le **détecteur** qui remplit le registre extensible de [23] : au fil de l'évolution du projet (discovery **et** delivery), repérer si de nouvelles **lentilles de revue [23] / agents / skills** deviennent nécessaires. Étend [11] d'un cran : leçons→règles ([11]) devient **besoins→capacités**.

## Question

À quels **moments** et selon quelle **règle** le framework détecte-t-il qu'une nouvelle **capacité** (lentille [23] / agent / skill) est nécessaire — et **qui la crée** ?

À trancher :
- **Checkpoints** : sortie de wayfinder/grilling (discovery) ? retro [11] + clôture de feature (delivery) ? autres moments pertinents ?
- **Détecter ≠ créer** : créer une capacité change le contrat du framework (gate/coût) = **contractuel** [05] → HITL (discovery) ou escalade (delivery), **jamais auto-créé en AFK**. Confirmer/raffiner la frontière.
- **Barre anti-prolifération** : quel seuil avant de *proposer* (récurrence ? classe de concern qu'**aucune** capacité existante ne couvre) — éviter la génération de complexité (l'anti-valeur d'Odysseus).
- **Qui détecte / propose** : le retro [11] (delivery) ? un pas explicite en sortie de wayfinder (discovery) ?
- **Forme de la proposition** : ticket `ready-for-human` (delivery) / entrée de charting (discovery) ; format.
- **Rapport avec [11]** : même moule (détection + anti-bruit + promotion) ; [11] = leçons→règles, [24] = besoins→capacités.

## Answer

Décision verrouillée (grilling HITL). Le **détecteur** qui remplit le registre [23] (et propose agents/skills). Étend [11] : besoins→capacités. (Méta : **ce ticket décrit ce qui vient de se passer** — un gap de capacité repéré par le proprio a gradué en [23]+[24].)

**D1 — 2 checkpoints ; création toujours HITL (détecter ≠ créer).**
- **Discovery — sortie de wayfinder/grilling** : pas explicite « faut-il une nouvelle lentille [23] / agent / skill ? » quand une nouvelle **classe de préoccupation** surgit. HITL → **la création se décide ici** (gradue comme une décision de charting normale — comme [23]/[24]).
- **Delivery — retro [11] + clôture de feature [12]** : le retro **détecte et propose**, jamais ne crée.
- **Invariant** : créer une capacité change le contrat du framework (gate/coût) = **contractuel** [05] → en delivery **escalade `ready-for-human`** ; en discovery, tranché avec l'humain. **Aucune auto-création en AFK.**

**D2 — Barre anti-prolifération + réutiliser-avant-créer.**
- **Proposer seulement si** : **récurrence** (≥ K tickets/features, compteur [11]) **OU** **classe non couverte** (concern qu'aucune capacité existante n'adresse, même une fois si fort enjeu — cas sécu/a11y → [23]).
- **Réutiliser-avant-créer** (le vrai frein) : toute proposition argumente d'abord pourquoi l'existant ne suffit pas. Ordre : (1) **élargir le brief d'une lentille existante** (~0 coût), (2) réutiliser un **skill substrat**, (3) en dernier, **créer** neuf. Défaut = étendre, pas engendrer.

**D3 — Détecteur, forme, rapport [11].**
- **Détecteur** : delivery = le **retro [11]** (remit étendu : « leçon ? » + « ADR ? » + « **gap de capacité ?** » selon la barre D2 ; aucun nouvel agent — réutiliser-avant-créer s'applique à [24] lui-même). Discovery = un **pas explicite du playbook** en sortie de charting.
- **Forme** : delivery → **issue `ready-for-human`** (gap + argument réutiliser-avant-créer + esquisse ; durable, anti-#77). Discovery → **ticket de charting** normal.
- **Rapport [11]** : même moule. [11] = leçons→règles à **deux tiers** (autonome-interne / escaladé-contractuel). [24] = besoins→capacités, **toujours contractuel** → **seul le tier escaladé/HITL** ; jamais d'auto-application. [24] = « l'étage escaladé de [11], appliqué aux capacités ».

### Contraintes créées ailleurs
- **[11] retro** : remit **étendu** — flagge aussi un **gap de capacité** (barre D2) → issue `ready-for-human`.
- **Playbook discovery / `CLAUDE.md`** : ajouter un **pas de revue de capacités en sortie de charting** (sans modifier le skill substrat wayfinder — via la guidance du framework).
- **[23] registre** : [24] est son détecteur ; le registre reçoit les lentilles que [24] fait valider.
- **[05]/[06]** : capacité = contractuel → escalade `ready-for-human` en delivery (jamais auto-créé).
- **[09] form-factor** : les capacités créées (briefs de lentille, skills, agents) se déposent dans le pack ; documenter le pas de revue.
