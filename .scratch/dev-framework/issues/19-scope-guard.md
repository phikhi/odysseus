# Scope-guard (l'itération ne touche que les fichiers de son ticket)

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (emprunt Multiplyz : hook scope-guard). **Étend [06]/[08]**. Voir `ANALYSE-multiplyz-vs-odysseus.md` §6.5.

## Question

Faut-il un **scope-guard** empêchant une session de **sortir du périmètre de fichiers** de son ticket — sachant que sandbox + session fraîche + snapshot/rollback [08] réduisent déjà le risque de drift ?

Contexte : Multiplyz l'impose par **hook `settings.json`** (l'agent dev ne touche que les fichiers de sa story) + review PO. Odysseus s'appuie aujourd'hui sur la **sandbox** [06/D1] + le **rollback `HEAD`** [08] + le fait que le ticket est auto-suffisant. La **valeur marginale** d'un scope-guard est donc à évaluer.

À trancher :
- **Expression du scope** : le ticket **déclare-t-il ses fichiers attendus** (globs) ? ou le scope est-il implicite (dérivé des AC) ?
- **Application** : **hook Claude Code `PreToolUse`** (bloque une écriture hors-scope en temps réel, dispo en headless) ? **vérification post-hoc au gate** [08] (`git diff --name-only` comparé au scope déclaré → échec si débordement) ? les deux ?
- **Réaction au débordement** : échec de gate (retry/escalade) ? warning loggé ? escalade `ready-for-human` (drift) ?
- **Valeur marginale réelle** : décision peut être **« non, la sandbox + rollback suffisent »** → fermer hors-scope ; ou **« oui, mais post-hoc léger seulement »**.
- **Rapport avec la ligne interne/contractuel [05]** : un débordement qui touche un AC d'un autre ticket = drift contractuel → escalade.

## Answer

Décision verrouillée (grilling HITL). **Étend [06]/[08]**, **bras d'application de la write-surface [15]**. Pré-câblé par [15] (« échoue au gate si écriture hors surface ») ; ce ticket fixe l'application et la réaction.

**D1 — Scope = la write-surface [15] ; guard = son intégrité (adopté, near-free).** Le scope est la **write-surface** du ticket (globs **explicites** déclarés par `to-tickets`, contrat [05]) — **une seule déclaration** pour la parallél-safety [15] ET le scope-guard. **Adopté** (pas fermé « sandbox+rollback suffisent ») car **[15]'s parallélisme en dépend** : si un ticket écrit hors surface, la disjonction anti-collision est **fausse**. Le guard **rend la déclaration honnête**. Coût marginal ~nul (`git diff --name-only`).

**D2 — Application : post-hoc au gate = autorité, hook `PreToolUse` = early-fail optionnel.** **Autorité** = check **post-hoc au gate [08]** : `git diff --name-only` (worktree) vs globs de la write-surface → débordement = gate rouge. **Déterministe, backend-agnostique, sans LLM** (tier objectif d'[08]). **Optionnel** = hook `PreToolUse` (`settings.json`, headless [09]) bloquant l'écriture hors-scope **en temps réel** (économise l'itération + le budget) — **efficience, pas autorité** (un hook mal câblé/évité ne doit pas laisser passer un débordement). Le post-hoc attrape **tout** ; le hook attrape **tôt**.

**D3 — Réaction : gate rouge → classification interne/contractuel [05].**
- **Débordement dans la write-surface d'un AUTRE ticket** (ou contrat partagé porteur d'AC) = **drift contractuel** → **escalade `ready-for-human` immédiate, sans retry** (conflit de scoping que la discovery tranche ; retenter briserait la disjonction [15]).
- **Débordement dans un fichier neutre non-déclaré** (surface trop étroite) = **interne** → **retry-N fresh** [08] ; si **répété sur le même fichier** → déclaration fausse → escalade `ready-for-human` (mal scopé), façon too-big [08].
- **Trace** : loggé au **reçu [18]** + alimente le **retro [11]** (scope mal délimité récurrent → leçon/promotion).

### Contraintes créées ailleurs
- **[15]** : la write-surface est **la même** déclaration ; le guard en est le verrou d'intégrité (condition de sûreté de la disjonction parallèle).
- **[08] gate** : ajouter le **check post-hoc de scope** (`git diff --name-only` vs write-surface) comme branche objective déterministe ; débordement = gate rouge → politique d'échec standard, avec la nuance drift-vs-interne (D3).
- **[06] control-flow** : hook `PreToolUse` optionnel (early-fail) dans la posture headless ; le post-hoc reste l'autorité.
- **[05]** : la classification débordement (autre-ticket = contractuel/escalade ; neutre = interne/retry) applique la ligne interne/contractuel.
- **[09] form-factor** : hook `PreToolUse` optionnel dans `settings.json` du pack ; flag ⚙️ pour l'activer.
- **[11]/[18]** : débordements tracés au reçu, récurrences → leçon.
