# odysseus

Un pack déposable dans n'importe quel projet, **100 % bash + markdown**, qui fait broyer la phase de **delivery sans humain** (AFK) : vous validez des tickets le soir, la boucle les implémente pendant la nuit, et ne vous réveille que pour ce qui relève de votre jugement.

> ⚠️ **En construction.** 6 tickets sur 20 sont livrés. La boucle tourne de bout en bout, le gate objectif décide vraiment et un échec ne laisse plus le dépôt sale, mais il manque encore les lentilles de revue, le budget d'usage et la boucle humaine — voir [État](#état). Ne le lâchez pas encore sur un dépôt qui compte.

## Le problème

Une session Claude Code interactive, laissée à elle-même sur une longue phase de delivery :

- **se compacte** dès que le contexte grossit, et tombe en *dumb zone* où la qualité de raisonnement chute ;
- **crame le budget d'usage** sans s'en rendre compte, puis s'arrête net au milieu du travail ;
- ne peut pas tourner **sans humain** en confiance : rien ne garantit qu'une tâche « verte » soit réellement livrée, ni qu'une décision engageant le contrat ne soit prise en douce ;
- n'est **pas réutilisable** d'un projet à l'autre.

## L'idée

Une **itération = une tâche = une session fraîche**. Jamais de compaction : quand une tâche est finie, la session meurt et la suivante repart d'un contexte neuf, reconstruit en relisant le tracker. Le contexte reste sous le seuil où le modèle raisonne à pleine capacité — la *smart zone*.

```
      ┌──────────────────── la ralph loop ────────────────────┐
      │                                                       │
      ▼                                                       │
  scan de la frontière  →  claim  →  session fraîche  →  gate ─┘
  (open ∧ unblocked         (atomique)   (claude -p,      (tests, revue)
   ∧ ready-for-agent                      surveillée)          │
   ∧ non-claimed)                                              ▼
      ▲                                                   marquage
      │                                                  + journal
      └───────────── frontière vide → exit succès ────────────┘
```

Deux boucles partagent un tracker et s'excluent mutuellement : `loop.sh` broie en autonomie, `human-loop.sh` (à venir) draine ce qui a été escaladé vers vous, et le réinjecte. Le tracker markdown est la **seule autorité d'état** : rien n'est hérité entre deux itérations.

Le vocabulaire complet est dans [`CONTEXT.md`](CONTEXT.md).

## État

| | |
|---|---|
| **Ça marche** | verrou de run · scan de frontière sans mémoire · claim atomique · session fraîche surveillée · marquage par la boucle après le gate · journal de run · filet smart-zone (auto-compact coupé, SIGTERM au seuil mou) · gate objectif en parallèle (tests, typecheck, scope-guard) avec délai par branche · échecs typés (re-slice, retry-N, escalade avec raison) · rollback précis et commit sur vert |
| **Ça manque** | lentilles de revue (Standards/Spec/Sécurité…) · budget d'usage · boucle humaine · reçu d'audit · concurrence · installeur |

Livrés : [01](.scratch/ralph-pack/issues/01-fondation-squelette-harnais.md) fondation et harnais · [02](.scratch/ralph-pack/issues/02-adaptateur-local-modele-etat.md) adaptateur `local` et modèle d'état · [03](.scratch/ralph-pack/issues/03-ralph-loop-tracer-bullet.md) tracer bullet de la boucle · [04](.scratch/ralph-pack/issues/04-filet-smart-zone.md) filet smart-zone · [05](.scratch/ralph-pack/issues/05-gate-qa-objectif.md) gate QA objectif · [07](.scratch/ralph-pack/issues/07-echecs-types-rollback.md) échecs typés et rollback.

Le reste est dans [`.scratch/ralph-pack/issues/`](.scratch/ralph-pack/issues/), chaque ticket portant ses critères d'acceptation et, une fois résolu, les décisions et les pièges rencontrés.

## Essayer

Il n'y a pas encore d'installeur (c'est le ticket 19). Aujourd'hui, dans un dépôt git de test :

```bash
cp -R /chemin/vers/odysseus/.claude .            # déposer le pack
cp .claude/ralph.config.sh.example .claude/ralph.config.sh
$EDITOR .claude/ralph.config.sh                  # FEATURE, MODEL, TEST_CMD, TYPECHECK_CMD

mkdir -p .scratch/<feature>/issues               # écrire un ticket ready-for-agent
bash .claude/loop.sh
```

Un ticket est un fichier markdown auto-suffisant — aucun contexte n'étant hérité, il doit se lire seul :

```markdown
# 01 — Titre

**What to build:** ce qu'il faut construire, et pourquoi.

**Blocked by:** None

**Write-surface:** `src/fichier.ts`

**Status:** ready-for-agent

- [ ] Un critère d'acceptation vérifiable par machine.
```

`TEST_CMD` et `TYPECHECK_CMD` ne sont pas optionnelles : la boucle refuse de démarrer tant qu'elles sont vides, parce qu'un gate qui ne vérifie rien est vert pour la mauvaise raison. Un projet réellement sans typecheck le déclare par `TYPECHECK_CMD=none`. À chaque itération, la boucle lance en parallèle les tests, le typecheck et le **scope-guard** — qui compare ce que la session a écrit (commité ou non) à la write-surface déclarée du ticket. *resolved* n'est prononcé que si toutes les branches déclenchées sont vertes ; une branche qui pend au-delà de `GATE_TIMEOUT` est tuée et compte rouge.

### Ce que fait la boucle quand ça échoue

Un échec n'est pas une seule chose. Une session coupée pour cause de contexte est une **tranche trop grosse** : une session de planification la redécoupe en tickets plus petits, la boucle vérifie que le découpage ne perd aucun critère d'acceptation ni n'élargit la write-surface, et les met en frontière. Un débordement dans la write-surface d'un **autre ticket** est un arbitrage de découpage : escalade directe, sans consommer de retry. Un gate rouge ou une session morte achète jusqu'à `RETRY_N` sessions fraîches, puis part vers `ready-for-human` avec un compteur `Failures:` et une raison `Escalation:`.

Dans tous les cas le dépôt revient où la session l'a trouvé — les fichiers qu'elle a ajoutés sont supprimés, ceux qu'elle a modifiés ou supprimés sont restaurés, un commit qu'elle aurait fait est défait. Le rollback est **exactement aussi large que le diff de la session** : ni `git reset --hard`, ni `git clean -fd`, pour ne pas emporter le travail non commité de quelqu'un d'autre. Avant une escalade, la tentative est conservée sur une branche `failed/<ticket>`. Et chaque itération verte est **commitée** avant la suivante : sans ça, un rollback ultérieur détruirait le travail déjà gaté.

Codes de sortie de `loop.sh` : `0` la frontière a été drainée par ce run · `1` un autre run tient le verrou · `2` refus de démarrer (config absente, `FEATURE` vide ou pointant sur rien, config qui viderait le gate de son sens) · `4` arrêt sur une garde (stop demandé, cap d'itérations, run stérile) · `5` rien à broyer, la frontière était déjà vide au démarrage.

`0` et `5` sont distincts à dessein : un run qui n'a rien broyé — mauvais `FEATURE`, tickets encore en triage, tracker que le pack n'arrive pas à lire — ne doit jamais ressembler à une nuit de travail terminée.

## Tests

```bash
bash test/run.sh                       # toute la suite
bash test/run.sh test/smoke.bats       # un fichier
bash test/run.sh -f "frontier"         # par motif
bash test/run.sh --bats                # via bats-core, s'il est installé

bash test/mutate.sh                    # le gate de mutation (~20 min)
bash test/mutate.sh -f "07 "           # les garanties d'un ticket
bash test/mutate.sh -l                 # lister les garanties couvertes
```

Aucune dépendance : le runner (`test/helpers/microbats.bash`) interprète la syntaxe bats en bash pur, et les mêmes fichiers restent lisibles par bats-core. La suite est vérifiée sans node ni homebrew sur le `PATH`.

`test/mutate.sh` est le gate qui compte : il supprime une garantie à la fois et vérifie que le test censé la couvrir rougit. Onze tests de ce dépôt sont passés au vert alors que la propriété qu'ils prétendaient couvrir avait été supprimée — un test qui courait après une fenêtre de quelques microsecondes, un test qui assertait un message que la boucle imprime de toute façon, un test qui lisait le shell du développeur plutôt que le code. Un `VACUOUS` est un faux vert dans un pack dont le métier est de refuser les faux verts.

`test/canary.bats` est l'autre : un run contre le monde tel qu'il est — sessions qui écrivent vraiment leur write-surface, une qui commit tout, une dont le flux arrive coupé au milieu d'une ligne, par-dessus un tracker en CRLF, déjà sale et portant le claim de quelqu'un d'autre. Presque tous les défauts livrés jusqu'ici vivaient dans l'écart entre un fake trop coopératif et une vraie session.

Les tests pilotent les **vrais scripts comme des process**, dans un environnement entièrement injecté — tracker jetable en tmpdir, `claude`/`curl`/`at` remplacés par des shims scriptables, commandes de test stubbées — et n'observent que l'état du tracker et les fichiers produits. Le flux du faux `claude` est calqué sur une capture réelle : le filet smart-zone et le budget lisent ce flux, un flux inventé les ferait concevoir contre une fiction.

## Structure

```
.claude/
  loop.sh                  la ralph loop
  ralph.config.sh.example  le seul fichier à régler par projet
  settings.json            posture headless (auto-compact coupé)
  lib/
    tracker.sh             interface d'adaptateur de tracker
    tracker-local.sh       backend local (markdown)
    select.sh              scan de frontière
    state.sh               écriture atomique, verrou de run, guards
    monitor.sh             filet smart-zone
    gate.sh                gate objectif (tests, typecheck, scope-guard)
    failures.sh            échecs typés, rollback, commit sur vert
test/                      harnais, fixtures et suites
docs/agents/               conventions de tracker et de triage
.scratch/<feature>/        le tracker : spec + issues/NN-*.md
```

## Documents

- [`CONTEXT.md`](CONTEXT.md) — le vocabulaire du domaine, à respecter partout.
- [`.scratch/ralph-pack/spec.md`](.scratch/ralph-pack/spec.md) — la spec du pack.
- [`.scratch/dev-framework/blueprint.md`](.scratch/dev-framework/blueprint.md) — le design gelé et le pourquoi de chaque décision.
- [`docs/agents/`](docs/agents/) — conventions de tracker et libellés de triage.

## Langues

Le contenu du pack (`.claude/`, `test/`) est en **anglais** : il est déposé dans des projets de n'importe quelle langue. Les artefacts de ce dépôt — spec, tickets, ADR, commits — sont en **français**. En éditant un fichier, matchez sa langue.
