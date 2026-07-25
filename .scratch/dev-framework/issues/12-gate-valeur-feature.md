# Gate de valeur produit bout-en-bout au niveau feature (playthrough)

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (leçon Multiplyz). **Étend [08]/[05]** : le gate est par-ticket, jamais par-feature. Voir `ANALYSE-multiplyz-vs-odysseus.md` §5.2.

## Question

Qu'est-ce qui prouve qu'une **feature** (pas juste un ticket) est **vécue bout-en-bout** par l'utilisateur, et comment ce gate s'insère-t-il dans une ralph loop qui est **ticket-par-ticket** ?

Contexte : le gate d'Odysseus [08] (tests + typecheck + code-review 2 axes) prouve qu'une **slice est verte**, pas que la feature **s'assemble et atteint l'utilisateur**. C'est littéralement l'échec `AUDIT-2026-07-20` de Multiplyz : 8 épics « clos », tous les tickets verts, mais navigation cassée / art jamais affiché / économie absente. Réponse Multiplyz : **gate « parcours d'acceptation »** + **playthrough narré persisté** + **canari E2E full-loop**.

À trancher :
- **Quand se déclenche-t-il** : à **frontière vide** d'une feature (tous les tickets `resolved`) ? un ticket terminal spécial ? Comment la boucle sait-elle qu'une *feature* (≠ tâche) est close ?
- **Qui le pilote** : une session dédiée qui **joue le vrai flux sur les vrais assets** (pas un fixture), suit la spec comme l'utilisateur, produit un verdict.
- **Artefact persisté** (non jetable en contexte, sinon reçu invérifiable — cf. Multiplyz #164) : où (`docs/playthroughs/<feature>.md` du projet cible ?), quel format (narration + captures analysées + verdict).
- **Comment il gate** : bloque la « clôture de feature » ? produit un `ready-for-human` si rouge ? Comment ré-injecter du travail si le playthrough révèle un trou (story de câblage consommateur manquante) ?
- **Générique multi-stack** : Odysseus se dépose sur n'importe quel projet — pas de Playwright garanti. Quel équivalent minimal (CLI ? navigateur ? capture) exigible partout, et quoi est optionnel selon la surface ?
- **Rapport avec « e2e si surface » [05]**, la **vérif visuelle [13]** et l'**axe fidélité [14]** (par-ticket) vs playthrough (par-feature) : redondants ou complémentaires ?

## Answer

Décision verrouillée (grilling HITL). Gate de **valeur bout-en-bout au niveau feature**, terminal, distinct du gate par-ticket [08].

**D1 — Déclencheur : gate terminal sur frontière-vide.** Feature = tracker (`.scratch/<feature>/`, une feature par dossier). « Feature close » = **frontière vide** (tous les tickets delivery `resolved`, aucun `ready-for-human`). Le playthrough s'exécute dans la **branche « tout résolu » d'[06]**, **avant** l'exit succès du run. Pas de ticket terminal spécial : la détection de frontière vide existante est l'ancrage.

**D2 — Pilote : subagent frais contre le flux du `spec.md`.** Un **subagent frais isolé** (idiome retro [11] / code-review [08] — jugement hors delivery, regard neuf), lancé par la boucle, rejoue le **flux utilisateur bout-en-bout du `spec.md`** [05] **comme l'utilisateur**, sur les **vrais assets** (jamais un fixture), et produit **narration + verdict**. Ni la boucle bash (aucun jugement), ni une session delivery (auto-report + pas de vue d'ensemble), ni les AC des tickets (justement ce qui a menti chez Multiplyz).

**D3 — Généricité multi-stack : minimum universel + dégradation qui escalade.** Exigible partout : la feature **lançable par une commande documentée** (`RUN_CMD`, `ralph.config.sh`) + le flux du `spec.md` **exécutable/observable**. Pilotage **spécifique au stack** : surface visible → navigateur + captures (machinerie [13]) ; CLI/API → exécuter le flux + asserter les sorties ; lib pure sans flux → **no-op** (le gate [08] suffit). **Aucun outil pour piloter une surface visible → escalade `ready-for-human`** : **jamais de faux-vert** (anti-faux-vert [08], dégradation [13]).

**D4 — Échec (rouge) : hybride autonome-d'abord, borné.** Le verdict du playthrough **classe** le trou :
- **Interne** (spécifiable depuis le `spec.md` existant, sans toucher aux AC) → **re-injection autonome** d'un **ticket de câblage** (via `to-tickets`, intention préservée) en frontière `ready-for-agent` ; la boucle **continue de broyer**, la frontière n'est plus vide → le gate terminal **re-tourne** après résolution. Loggé. Même forme qu'[08] (« too-big → re-slice autonome préservant les AC »), au niveau feature.
- **Contractuel** (`spec.md` muet/ambigu sur le flux, ou fermer le trou toucherait une AC/décision verrouillée) → **escalade `ready-for-human`** + artefact playthrough + trou identifié.
- **Borne anti-boucle** : cap `PLAYTHROUGH_REINJECT_MAX` (⚙️, défaut 1-2) ; au-delà, toujours rouge → **escalade `ready-for-human`** (pas de re-inject infini). Analogue au détecteur de run stérile / retry-N [06]/[08].

**D5 — Artefact persisté (condition matérielle de clôture).** `docs/playthroughs/<feature>.md` dans le **projet cible** (versionné, durable comme un ADR) + **pointeur de contexte** dans le tracker ; assets de preuve dans `docs/playthroughs/<feature>/`. Format : narration du flux vécu + preuve (captures UI / sorties CLI) + verdict + classification du trou si rouge. **La feature ne se clôt pas tant que l'artefact n'existe pas sur disque** (leçon Multiplyz #164 : un reçu jetable en contexte est invérifiable). Distinct du reçu d'audit [18] (par-itération, mécanique).

**D6 — Composition : échelle de défense en profondeur + canari.** Complémentaires, non redondants :
- **Niveau ticket** (par itération, gate [08]) : [05] e2e-in-AC · [13] vérif visuelle · [14] axe fidélité — attrapent les défauts **par-slice**.
- **Niveau feature** (terminal, [12]) : le playthrough — attrape les **trous d'assemblage cross-ticket** qu'aucun check par-ticket ne voit.
- **Canari (#326)** = un **e2e full-loop maintenu vert** dans la suite de tests du gate **[08]** (tourne à chaque itération, sentinelle machine continue), **pas** une machinerie [12]. Guidance sur [08], pas de ticket dédié.

### Contraintes créées ailleurs
- **[05] contrat** : le `spec.md` doit porter un **flux utilisateur bout-en-bout explicite** (« ce que l'utilisateur vit de A à Z »), pas seulement des AC par-ticket — sinon le playthrough n'a rien contre quoi valider. Exigence nouvelle sur la sortie de discovery.
- **[06] control-flow** : la branche « tout résolu » **lance le playthrough avant l'exit succès** ; sur trou interne, la boucle **re-injecte un ticket de câblage** (frontière non vide → boucle continue) ; sur contractuel / borne dépassée, **escalade `ready-for-human`**.
- **[08] gate** : ajouter la **guidance canari** (garder un e2e full-loop maintenu vert dans la suite de tests) ; le playthrough lui-même est **terminal [06]**, pas dans le gate par-ticket.
- **[09] form-factor** : `ralph.config.sh` porte `RUN_CMD` + type de surface / outil de pilotage + `PLAYTHROUGH_REINJECT_MAX` ⚙️ ; le pack provisionne `docs/playthroughs/` dans le projet cible.
- **[13]/[14]** : leur place dans l'échelle est fixée (niveau ticket) ; le détail de leur câblage dans le gate reste à leur propre résolution.
