# Boucle d'auto-apprentissage durable (LEARNINGS + promotion)

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (leçon Multiplyz). **Révise [04]** : le journal de run y est *non-autoritaire* et n'apprend rien. Voir `ANALYSE-multiplyz-vs-odysseus.md` §5.1.

## Question

Comment câbler une **mémoire de leçons durable** dans la ralph loop, sachant que le pari « session fraîche par tâche » est **précisément** celui qui en a le plus besoin — sans elle, l'itération N+1 ignore ce qui a cassé à l'itération N ?

Contexte : le **journal de run [04]** est append-only mais **non-autoritaire** (jamais lu pour choisir/marquer), purement observabilité — il n'apprend rien. Le substrat fournit déjà le skill `teach` (formats LEARNING-RECORD / GLOSSARY) mais il n'est **pas câblé** dans la boucle. Multiplyz : `LEARNINGS.md` versionné + skill `retro` + **promotion** des leçons récurrentes en règles dures.

À trancher (via `/grilling` + `/domain-modeling`) :
- **Où vit le fichier de leçons** : un `LEARNINGS.md` par projet cible ? par feature (`.scratch/<feature>/`) ? racine ? Non-autoritaire pour la sélection (le scan tracker [04] reste seul juge) mais **lu comme contexte** par chaque session fraîche.
- **Comment la session fraîche le lit** : pointeur injecté dans le prompt template [05/06] (comme le ticket + `CONTEXT.md`/ADRs) ? lecture à la demande ?
- **Quand une leçon est écrite** : à l'échec de gate [08] ? mini-rétro post-`resolved` (façon `retro`) ? par qui (la session ? la boucle ? un subagent dédié à contexte frais, hors budget 200K) ?
- **Mécanisme de promotion** : une leçon **récurrente** → règle dure. Dans un pack bash/markdown, cible = `CLAUDE.md` du projet cible, une **commande de gate** supplémentaire [08], ou un flag `ralph.config.sh`. Promotion **autonome** ou **escaladée** (`ready-for-human`) ?
- **Rapport avec le journal [04]** : le LEARNINGS remplace-t-il le journal, s'y ajoute-t-il, ou le journal reste-t-il l'observabilité brute et le LEARNINGS la couche « apprise » ?
- **Anti-bruit** : signal only (le `retro` de Multiplyz insiste là-dessus) — éviter un LEARNINGS qui gonfle en bruit (cf. 477 Ko chez Multiplyz).

Couplé à **[20]** (ADR en delivery : une décision d'archi tracée nourrit les sessions suivantes via ce même canal → [20] est bloqué par ce ticket).

## Answer

Décision verrouillée (grilling HITL). Artefact distinct du journal [04], posé sur le **format** `teach`/LEARNING-RECORD (le format seul est réutilisé — le skill `teach` entier vise l'enseignement d'un humain).

**D1 — Artefact séparé du journal [04].** Le journal de run [04] reste inchangé : machine, append-only, **non-autoritaire**, jamais relu par une session. Le **LEARNINGS** est un artefact **distinct**, *decision-grade*, écrit **seulement quand il y a une leçon** (pas à chaque itération) et **relu comme contexte** par chaque session fraîche. Précise le D1 de [04] : le journal n'apprend rien ; la couche apprise vit dans le LEARNINGS — **non-autoritaire pour la sélection** (le scan tracker reste seul juge) mais **lue comme contexte**.

**D2 — Portée par-projet.** Un LEARNINGS **à la racine du projet cible**, entrées **taguées par feature/ticket**. Pas par-feature (une leçon de stack apprise en feature A doit servir en feature B), pas global cross-projet (sur-partage + casse « le pack vit dans le projet »).

**D3 — Forme : index + records** (idiome map/ticket d'Odysseus). `LEARNINGS.md` = **index compact** (une ligne par record actif : gist + pointeur), petit by design → toujours injectable. `learning-records/NNNN-slug.md` = **records complets** (format teach : titre + 1-3 phrases + `Status` optionnel), **un fichier par leçon**, écriture atomique `temp+mv` (append concurrents sûrs sous [15]). Répertoire créé *lazy* (au premier record).

**D4 — Capture = subagent `retro` frais, post-gate, auto-suppressif.** À chaque frontière d'itération, **après le gate [08]**, la boucle spawn un **subagent frais isolé** (hors du 200K de la delivery) sur **tier bon marché (Haiku)**. Il lit le diff + le verdict de gate + les notes d'échec et **n'écrit un record que s'il y a une leçon decision-grade** (défaut : rien — « coverage is not learning »). En pratique : échec/retry/re-découpage → quasi toujours une leçon ; succès propre → le plus souvent rien. **Ni la session delivery** (no self-report [04]/D3 + budget), **ni la boucle bash** (aucun jugement LLM). Reprend l'idiome du `code-review` d'[08] : le jugement vit dans une session séparée.

**D5 — Lecture : index inline (obligatoire) + records à la demande.** La boucle injecte l'**index complet actif** **inline** dans le prompt template [06], **au rang du ticket**, cadré **lecture obligatoire avant d'agir** (un pointeur seul serait sauté — leçon Multiplyz). La session **zoome un record à la demande** (idiome CONTEXT.md/ADRs) si une ligne paraît pertinente. **Aucun filtrage par feature à la lecture** ; la taille est gouvernée par l'anti-bruit (D7).

**D6 — Promotion à deux étages** (ligne interne/contractuel [05]). Le retro détecte la **récurrence** (Kᵉ apparition d'un thème dans l'index) et promeut :
- **Autonome (interne)** : ajoute une **guidance dans le `CLAUDE.md`** du projet cible + un record de promotion. N'altère pas le contrat → la boucle le fait seule, loggé.
- **Escaladé (`ready-for-human`)** : toute promotion en **gate bloquant / lint / hook** (change la définition de *resolved* [08]) **ou** touchant une AC/spec → **ticket `ready-for-human` durable** dans le tracker (équivalent Odysseus du `needs-owner`), avec preuve de récurrence + règle proposée. **Jamais en silence** (leçon Multiplyz #77 : promotion passive invisible = jamais appliquée).

**D7 — Anti-bruit : trois drains + backstop.** L'index injecté à chaque session **doit** rester petit. (1) **Dedup à l'écriture** : quasi-doublon → incrémente la récurrence (alimente D6) au lieu d'ajouter du bruit. (2) **Supersession** : un record plus récent qui contredit/approfondit → l'ancien passe `superseded`, sort de l'index actif. (3) **Drain-par-promotion** (principal) : une leçon promue (D6) est **retirée de l'index actif** (`Status: promoted → <cible>`) car appliquée ailleurs. → L'index est un **working set de leçons actives non-promues**, pas un log append-only (≠ le fichier unique 477 Ko de Multiplyz). **Backstop** : cap ⚙️ (`ralph.config.sh`) sur les lignes d'index ; au dépassement, passe de curation par le retro. Défaut haut.

### Contraintes créées ailleurs
- **[06] control-flow** : (a) le prompt template injecte l'index `LEARNINGS.md` **inline** (rang du ticket) ; (b) **nouvelle étape post-gate** = spawn du subagent retro, puis application de la **promotion autonome** (append `CLAUDE.md`) ou **ouverture du ticket escaladé** — c'est la boucle qui agit, jamais la session.
- **[08] gate** : le retro est **post-gate** (consomme verdict + diff), **hors** du gate (qui reste tests+typecheck+code-review). Le tier Haiku du retro relève du tiering budget.
- **[04]** : D1 **précisé** — journal inchangé ; LEARNINGS ajouté comme couche apprise (non-autoritaire pour la sélection, lue comme contexte). Nouveaux termes au glossaire (`CONTEXT.md`).
- **[09] form-factor** : le pack embarque `LEARNINGS.md` (index vide) + `learning-records/` (lazy) ; `ralph.config.sh` porte le **cap d'index ⚙️** + le **tier du retro ⚙️** ; documenter la lecture obligatoire.
- **[15] parallélisme** (fog) : records atomiques `temp+mv` = OK concurrent, mais l'**index (fichier unique) est un point de contention** sous N itérations // → à trancher dans [15] (retro sérialisé par la boucle, ou lock d'index façon [21]).
- **[20] ADR en delivery** : **débloqué** — ce canal (record + index + promotion) est le véhicule par lequel un ADR de delivery nourrit les sessions suivantes ; [20] décide *quand* un ADR est produit et *comment* il pointe dans l'index.
