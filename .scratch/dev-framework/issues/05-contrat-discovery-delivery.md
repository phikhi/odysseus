# Contrat de handoff discovery → delivery

Type: grilling
Status: resolved
Blocked by: —

## Question

Que doit **produire** la phase discovery (HITL) pour que la ralph loop puisse broyer la delivery sans humain ? Définir le **contrat**.

À trancher :
- Artefacts de sortie de discovery : un `spec.md` validé + des tickets `to-tickets` avec arêtes de blocage. Suffisant, ou faut-il plus (critères d'acceptation par ticket, `CONTEXT.md`, ADRs) ?
- **Porte de validation** : quel signal humain fait passer un ticket de « conçu » à « broyable » (ex. état triage `ready-for-agent`) ? Qui/quand valide ?
- Chaînage des skills en amont : `grilling`/`domain-modeling` → `to-spec` → `to-tickets` → `triage`. Ordre et points d'arrêt humains.
- Chaque ticket porte-t-il tout ce qu'une session fraîche doit savoir (auto-suffisance), puisqu'il n'y a pas de contexte hérité ?
- Que se passe-t-il si la boucle découvre en delivery un manque de discovery (ambiguïté) : elle stoppe et rend au humain, ou improvise ? (lié au gate QA, ticket 08)

## Answer

Décision verrouillée (grilling HITL). Constat de fond : **le chaînage discovery du substrat produit déjà quasiment tout le contrat** — le ticket ne réinvente rien, il *nomme* la sortie standard comme contrat et pose sa barre de complétude.

**Composition du contrat (D1).** Le contrat = **la sortie standard du substrat, validée** :
- `spec.md` (via `to-spec`) : Problem/Solution, User Stories, Implementation Decisions, **Testing Decisions (seams, ce qui fait un bon test, prior art)**, Out of Scope.
- Tickets `to-tickets` : slices tracer-bullet, chacune avec *What to build* + **critères d'acceptation** + *Blocked by* + `ready-for-agent`.
- `CONTEXT.md` (glossaire) + ADRs : **ambiants**, maintenus en continu par `domain-modeling` — non reproduits, mais le contrat exige qu'ils soient à jour pour le vocabulaire/les décisions dures de la zone touchée.
- Aucun artefact neuf inventé. **Seule exigence ajoutée** : les critères d'acceptation doivent être **vérifiables par machine** (c'est ce que le gate QA [08] mesurera). **Amendement utilisateur** : les *Testing Decisions* ne se limitent pas à l'unitaire + l'intégration — elles doivent prévoir des tests **e2e dès qu'il y a une surface visible/utilisateur**.

**Porte de validation (D2).** **Une seule porte** au boundary : l'approbation du découpage dans le quiz de `to-tickets`, matérialisée par `ready-for-agent` sur les tickets (`to-spec` fait de même sur le spec après la vérif des seams). Lancer `loop.sh` est l'acte opérationnel « go », **pas** une validation de plus. Un ticket `ready-for-agent` mais bloqué attend simplement (la frontière exige `unblocked ∧ ready-for-agent`, cf. [04]). Pas de re-validation par-ticket : le set approuvé *est* le contrat, la delivery tourne en autonomie ensuite.

**Injection & auto-suffisance (D3).** « Aucun contexte hérité » ≠ « tout dans le ticket ». La session fraîche est un agent Claude Code avec accès fichiers. La boucle injecte **le ticket (What to build + AC) + les chemins du contexte permanent** (`spec.md`, `CONTEXT.md`, ADRs, dossier de tests) ; la session **lit à la demande** les slices pertinentes. Amorçage minimal → budget 200K préservé (cf. [03], « garder le contexte injecté minimal et pertinent »). **Auto-suffisance = ticket + contexte permanent du repo**, pas duplication dans le ticket (ce qui contredirait `to-tickets`, qui proscrit chemins/snippets).

**Gap de discovery en delivery (D4).** **Escalade sur l'ambiguïté contractuelle, décision libre sur l'interne.** Si le flou touche le **comportement observable / un critère d'acceptation** (les promesses du contrat) → la session **ne devine pas** : rétrograde le ticket en `ready-for-human` avec une note sur ce qui manque, et la boucle saute au ticket suivant. Si c'est un **choix d'implémentation interne sans impact sur les AC** → la session tranche et continue (trace en commit). Cohérent avec « les agents draftent, les humains décident » et l'escalade propose-puis-valide de [03], sans tuer l'autonomie sur les mille micro-décisions. Le *mécanisme* précis (enregistrement, retry ou escalade immédiate, comptage comme échec) appartient au gate QA [08] ; [05] fixe la **politique** et minimise ces gaps en amont via la barre de complétude du contrat.

**Chaîne & points d'arrêt (D5).** `grilling`/`domain-modeling` (en boucle, maintient `CONTEXT.md`/ADRs) → *(optionnel)* `/prototype` quand « à quoi ça ressemble / comment ça se comporte » est la question clé (ses snippets peuvent s'inliner dans le spec) → `to-spec` → `to-tickets`. `triage` = **outil de réparation à la demande** (étoffer un ticket sous-spécifié / écrire un agent brief), **pas** une étape obligatoire (`to-tickets` pose déjà `ready-for-agent` par construction). **Deux points d'arrêt humains** seulement : (1) vérification des seams dans `to-spec` ; (2) approbation du découpage dans `to-tickets` (= la porte, D2).

**Contraintes créées ailleurs :**
- **Gate QA [08]** : implémenter le mécanisme d'escalade du gap contractuel (→ `ready-for-human` + note ; décider s'il compte comme échec/retry) ; le gate mesure des AC qui, par ce contrat, sont machine-vérifiables — **e2e inclus dès qu'il y a une surface visible**.
- **Form-factor [09]** : le framework doit *embarquer/câbler* la chaîne discovery (skills du substrat) et exposer **où sont configurés les chemins injectés** (spec.md, CONTEXT.md, ADRs, dossier de tests) que la boucle passe à chaque session.
- **Control-flow [06]** : le template de prompt d'amorçage doit implémenter l'injection **ticket + pointeurs** (D3) ; note « scout » (sous-agents) déjà déposée sur [06].

**Effet sur la carte** : 05 ne bloque aucun ticket → laisse **06 (Control-flow)** seul sur la frontière. Aucun fog gradué, aucun ticket neuf, `CONTEXT.md` inchangé (*Contrat/Discovery/Delivery* déjà exacts).
