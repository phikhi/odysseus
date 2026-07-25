# Produire des ADR pendant la delivery

Type: grilling
Status: resolved
Blocked by: 11

> Durcissement v2 (discipline ADR Multiplyz). **Étend [05]/[08]**, **couplé à [11]** (apprentissage). Voir `ANALYSE-multiplyz-vs-odysseus.md` §6.6.

## Question

Quand une session **delivery** prend une **décision d'architecture non triviale**, faut-il la **capturer en ADR** — et comment cet ADR **nourrit-il les sessions suivantes** (d'où le blocage sur [11]) ?

Contexte : Odysseus traite les ADR comme **contexte ambiant de discovery** [05] ; la **delivery n'en produit pas**. Le substrat fournit le format (`domain-modeling`/ADR-FORMAT). Multiplyz produit des ADR systématiquement et distingue **« dans le contrat » (accepté en autonomie)** vs **« drift » (sign-off humain)**. Sans mémoire durable [11], un ADR produit en delivery serait perdu pour la session suivante — d'où **Blocked by: 11**.

À trancher :
- **Seuil « non trivial »** : quand un ADR est-il requis vs juste un commit (Multiplyz : modifie une spec contrat / le modèle de données / ajoute une dépendance / transverse) ?
- **Qui l'écrit** : la session delivery elle-même ? la boucle ? un subagent à contexte frais ?
- **Où** : `docs/adr/` du projet cible (format existant du substrat).
- **Comment il nourrit la suite** : via le **canal d'apprentissage [11]** (pointeur ADR dans le contexte ambiant relu par chaque session fraîche) — d'où le couplage.
- **Rapport avec interne/contractuel [05]** : une décision **contractuelle** (touche les AC/décisions verrouillées) = **escalade `ready-for-human`**, pas un ADR autonome ; une décision **interne** = ADR autonome + apprentissage. Cohérence avec la ligne [05].

## Answer

Décision verrouillée (grilling HITL). **Étend [05]/[08]**, **débloqué par [11]** (canal d'apprentissage + rédacteur). ADR en delivery = décisions d'archi **internes non-triviales** uniquement.

**D1 — Seuil + porte interne/contractuel [05].**
- **Contractuel** (touche AC / spec contrat / décision verrouillée, **ou ajoute une dépendance externe**) → **PAS d'ADR autonome** → **escalade `ready-for-human`** (drift) ; l'humain tranche et **acte l'ADR** s'il accepte (façon « owner accepte l'ADR » Multiplyz). La boucle ne grave jamais une décision contractuelle seule.
- **Interne** (dans le scope, ne touche ni AC ni contrat ni dep) **+ non-triviale** → **ADR autonome**.
- **Seuil non-trivial** : choix de structure / pattern / forme de données interne qu'une **session future aurait besoin de connaître** et **non évident à la lecture du code**. En-dessous → juste un commit (anti-bruit, comme le retro auto-suppressif [11]).

**D2 — Rédacteur, emplacement, feed-forward.**
- **Rédacteur** : le **subagent retro [11]** (post-gate, frais, Haiku, auto-suppressif) — il produit l'ADR au même titre qu'un record de leçon (même créneau, même « seulement si non-trivial »). Ni la session delivery (no self-report [04]), ni la boucle (aucun jugement).
- **Où** : `docs/adr/` du projet cible (format substrat `domain-modeling`/ADR-FORMAT) — record d'archi durable du produit.
- **Feed-forward** : via le **contexte ambiant d'[05]** — `docs/adr/` est **déjà injecté** aux sessions fraîches (les ADR de discovery y vivent) ; l'ADR de delivery rejoint le même pool, relu sans machinerie neuve.
- **ADR ≠ record de leçon** (deux artefacts distincts, tous deux écrits par le retro) : ADR = décision d'archi (`docs/adr/`, ambiant [05]) ; record de leçon [11] = piège/insight de process (`learning-records/`, index [11]).

### Contraintes créées ailleurs
- **[05]** : la ligne interne/contractuel classe la décision d'archi (interne → ADR autonome ; contractuel/dep → escalade) ; `docs/adr/` reste le pool ambiant injecté (delivery + discovery).
- **[08]/[11]** : le **retro post-gate [11]** est étendu pour écrire aussi un ADR (pas seulement un record de leçon) sur décision interne non-triviale ; auto-suppressif.
- **[06] control-flow** : sur décision d'archi contractuelle → escalade `ready-for-human` (comme un drift), pas de marquage resolved.
- **[09] form-factor** : `docs/adr/` provisionné dans le projet cible (déjà attendu par [05]).
