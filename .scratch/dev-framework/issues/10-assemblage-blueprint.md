# Assemblage du blueprint final

Type: task
Status: resolved
Blocked by: 03, 04, 05, 06, 07, 08, 09, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21

> **Ré-élargi — durcissement v2.** L'assemblage doit désormais intégrer les révisions du durcissement Multiplyz ([11]→[21]) en plus des décisions v1 ([03]→[09]). Re-bloqué sur les nouveaux tickets. Voir `map.md` + `ANALYSE-multiplyz-vs-odysseus.md`.

## Question

Consolider les décisions verrouillées ([03]→[09] **et [11]→[21]**) en **un document blueprint gelé unique**, prêt au handoff `/to-spec` → `/to-tickets` pour la **construction** du framework (loop.sh + lib + installeur npx + moteur bash + settings + conventions). **Zéro code produit ici** — c'est la synthèse gelée, pas l'implémentation.

À faire :
- **Synthétiser** les `## Answer` des tickets [03]→[09] (+ recherches [01]/[02] comme sources) en un blueprint cohérent, sans re-décider : la carte reste l'index, le blueprint est le document consolidé.
- **Structurer** autour de : unité de tâche & filet 200K [03] · modèle d'état & tracker autoritaire + journal de run [04] · contrat discovery→delivery [05] · control-flow de la ralph loop [06] · budget 5h/hebdo [07] · gate QA & gestion des échecs [08] · form-factor & installeur [09].
- **Intégrer les préconditions d'environnement** (pas fournies par le pack) : exécution **sandboxée** de la delivery (D1/[06]), **projet git** dans l'env cible (rollback + branches `failed/` [08]), commandes test/typecheck configurables [08].
- **Trancher/documenter le résidu d'observabilité** (replié depuis le fog) : le *surfacing* du `run.log` à l'humain (tail ? dashboard ?) — substrat et champs déjà décidés ([04]/[06]/[07]), reste la forme d'exposition + le **cron/launchd optionnel** de reprise post-`pause-hebdo` [07].
- **Livrable** : `.scratch/dev-framework/blueprint.md` (ou via `/to-spec`), gelé, prêt à `/to-tickets`.

Note : le prototype jetable [`../prototype-form-factor/`](../prototype-form-factor/) incarne déjà la forme cible (arborescence + `init.sh` + `ralph.config.sh` + `loop.sh`) — matière première pour le blueprint, pas du code de prod.

## Answer

Assemblé. Livrable gelé : [`blueprint.md`](../blueprint.md) — consolidation des **24 décisions** ([03]→[09] v1 + [11]→[26] v2 ; sources [01]/[02]/[22]) en **18 sections** : nature/destination · 2 boucles · substrat & préconditions · unité 200K · état & 4 couches · contrat discovery→delivery · control-flow AFK · budget & successeur · gate & registre de lentilles · gate valeur feature · concurrence par-ticket · apprentissage & ADR · revue de capacités · langues · backend tracker · boucle humaine · form-factor & installeur · **surface de config `ralph.config.sh`** · handoff.

**Zéro nouvelle décision** (synthèse pure). Résidu d'observabilité v1 **résorbé** (reçu [18] = surface humaine, journal [04] = machine ; la forme d'exposition du `run.log` = détail d'implémentation laissé au build). **Hors périmètre** rappelé dans le blueprint : déploiement · réconciliation quota §5.3 · multi-provider. **Prêt pour `/to-spec` → `/to-tickets`.**
