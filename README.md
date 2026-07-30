# odysseus

Un pack déposable dans n'importe quel projet, **100 % bash + markdown**, qui fait broyer la phase de **delivery sans humain** (AFK) : vous validez des tickets le soir, la boucle les implémente pendant la nuit, et ne vous réveille que pour ce qui relève de votre jugement.

> ⚠️ **En construction.** 7 tickets sur 20 sont livrés. La boucle tourne de bout en bout, le gate décide vraiment — palier objectif *et* palier de jugement — et un échec ne laisse plus le dépôt sale, mais il manque encore le budget d'usage, la boucle humaine et le reçu d'audit — voir [État](#état). Ne le lâchez pas encore sur un dépôt qui compte.

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
| **Ça marche** | verrou de run (par tracker) et verrou d'arbre (par arbre de travail) · scan de frontière sans mémoire · claim atomique, et réclamé au balayage quand son propriétaire est mort · session fraîche surveillée · marquage par la boucle après le gate · journal de run · filet smart-zone (auto-compact coupé, SIGTERM au seuil mou) · gate objectif en parallèle (tests, typecheck, scope-guard) avec délai par branche, jugeant tous un arbre pris avant le fan · échecs typés (re-slice, retry-N, escalade avec raison) · rollback précis et commit sur vert · tracker inviolable (les tickets sont snapshotés au spawn, une édition de session est annulée avant le gate) · chemins gardés (ce que `.gitignore` couvre sous `GUARDED_PATHS` est jugé et rollbacké quand même) et configuration du harnais scellée (aucune write-surface ne peut la couvrir) · **palier de jugement** : un registre de lentilles de revue (Standards et Spec sur tout ticket ; Fidélité, Accessibilité, Sécurité déclenchées par tag ou par write-surface) dans une phase à part après le palier objectif, chaque lentille étant un `claude` frais en lecture seule dont ce qu'il écrirait dans l'arbre est mesuré et remis en place |
| **Ça manque** | budget d'usage · boucle humaine · reçu d'audit · concurrence · installeur · gate de langue |
| **Failles connues** | une session qui pend sans émettre un token n'est bornée par rien, le filet bornant le contexte et non le temps — et depuis [28](.scratch/ralph-pack/issues/28-attente-de-la-session.md) elle est attendue jusqu'au bout, donc une session qui ignore le TERM du filet fait pendre le run plutôt que de laisser un orphelin derrière lui ([23](.scratch/ralph-pack/issues/23-timeout-session.md)) · rien ne garde `run.log` ni les flux de session · ce que `.gitignore` couvre **hors des chemins gardés** n'est jugé par rien et défait par rien : la boucle le nomme à chaque itération sans pouvoir le juger, donc un ticket peut passer au vert grâce à un fichier ignoré qu'une session antérieure a laissé ([13](.scratch/ralph-pack/issues/13-concurrence-par-ticket.md) le referme par l'isolation) · `Failures:` n'est remis à zéro que par une livraison verte, donc un ticket réinjecté par la boucle humaine sera escaladé à sa première tentative ([16](.scratch/ralph-pack/issues/16-boucle-humaine.md)) · un ticket renommé laisse deux fois le même `NN` ([27](.scratch/ralph-pack/issues/27-ticket-renomme.md)) · ce que les branches du gate écrivent pendant qu'elles jugent n'est jugé par rien et défait par rien — l'arbre jugé est figé avant le fan, donc ce n'est plus imputé à la session, mais l'artefact reste dans l'arbre et la boucle se contente de le nommer ([29](.scratch/ralph-pack/issues/29-arbre-juge-pendant-le-gate.md) ; ce que les **lentilles** écrivent est en revanche mesuré et remis en place, [06](.scratch/ralph-pack/issues/06-registre-lentilles-revue.md)) · **le verdict d'une lentille est la parole d'un modèle et rien ne le vérifie** : l'absence de verdict compte rouge, mais un `pass` complaisant est indistinguable d'un vrai — et le diff jugé entre dans le prompt du juge, donc une session peut y écrire une ligne qui s'adresse à sa lentille ([06](.scratch/ralph-pack/issues/06-registre-lentilles-revue.md)) · une session choisit ce que le pack peut voir : une règle ajoutée à `.git/info/exclude` n'a besoin d'aucune write-surface et aucun contrôle ne regarde `.git/` ([30](.scratch/ralph-pack/issues/30-frontiere-de-visibilite-ecrivable.md)) · une lentille lit `CONTEXT.md`, `docs/adr/` et le code autour du diff dans l'arbre du jugé, donc le texte qu'une session vient d'écrire atteint son juge — la posture de spawn ferme ce qui s'exécute ou se lit au démarrage, pas ce que la lentille va chercher elle-même ([31](.scratch/ralph-pack/issues/31-scellement-plus-etroit-que-son-critere.md), [06](.scratch/ralph-pack/issues/06-registre-lentilles-revue.md)) · un chemin scellé ne peut plus jamais être livré par la boucle, `CLAUDE.md` compris : c'est un choix, et il déplace la promotion autonome de leçon de [14](.scratch/ralph-pack/issues/14-auto-apprentissage-adr.md). Le tableau de [`docs/frontiere-de-confiance.md`](docs/frontiere-de-confiance.md) dit qui devrait garder quoi |

Livrés : [01](.scratch/ralph-pack/issues/01-fondation-squelette-harnais.md) fondation et harnais · [02](.scratch/ralph-pack/issues/02-adaptateur-local-modele-etat.md) adaptateur `local` et modèle d'état · [03](.scratch/ralph-pack/issues/03-ralph-loop-tracer-bullet.md) tracer bullet de la boucle · [04](.scratch/ralph-pack/issues/04-filet-smart-zone.md) filet smart-zone · [05](.scratch/ralph-pack/issues/05-gate-qa-objectif.md) gate QA objectif · [06](.scratch/ralph-pack/issues/06-registre-lentilles-revue.md) registre de lentilles de revue · [07](.scratch/ralph-pack/issues/07-echecs-types-rollback.md) échecs typés et rollback · [12](.scratch/ralph-pack/issues/12-claim-liveness.md) liveness du claim · [20](.scratch/ralph-pack/issues/20-contrat-claude-reel.md) contrat contre le vrai binaire `claude` · [21](.scratch/ralph-pack/issues/21-tracker-inviolable.md) tracker inviolable · [22](.scratch/ralph-pack/issues/22-un-run-par-arbre.md) un run par arbre de travail · [24](.scratch/ralph-pack/issues/24-fichiers-ignores.md) fichiers ignorés par git · [25](.scratch/ralph-pack/issues/25-arret-gracieux-pendant-le-gate.md) arrêt gracieux pendant le gate · [26](.scratch/ralph-pack/issues/26-compteur-echecs.md) compteur d'échecs · [28](.scratch/ralph-pack/issues/28-attente-de-la-session.md) l'attente de la session · [29](.scratch/ralph-pack/issues/29-arbre-juge-pendant-le-gate.md) l'arbre jugé, pris avant le gate · [31](.scratch/ralph-pack/issues/31-scellement-plus-etroit-que-son-critere.md) scellement dérivé de son critère et posture de lentille.

Le reste est dans [`.scratch/ralph-pack/issues/`](.scratch/ralph-pack/issues/), chaque ticket portant ses critères d'acceptation et, une fois résolu, les décisions et les pièges rencontrés.

## Essayer

Il n'y a pas encore d'installeur (c'est le ticket 19). Aujourd'hui, dans un dépôt git de test :

```bash
# Déposer le pack — les scripts et les libs, rien d'autre. `cp -R .claude`
# embarquerait aussi .claude/skills/, dont les 22 entrées sont des liens vers
# .agents/ et arrivent cassées chez l'hôte.
mkdir -p .claude/lib
cp -R /chemin/vers/odysseus/.claude/loop.sh .claude/
cp -R /chemin/vers/odysseus/.claude/settings.json .claude/
cp -R /chemin/vers/odysseus/.claude/ralph.config.sh.example .claude/
cp -R /chemin/vers/odysseus/.claude/lib/*.sh .claude/lib/

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

`TEST_CMD` et `TYPECHECK_CMD` ne sont pas optionnelles : la boucle refuse de démarrer tant qu'elles sont vides, parce qu'un gate qui ne vérifie rien est vert pour la mauvaise raison. Un projet réellement sans typecheck le déclare par `TYPECHECK_CMD=none`. À chaque itération, la boucle lance en parallèle les tests, le typecheck et le **scope-guard** — qui compare ce que la session a écrit (commité ou non) à la write-surface déclarée du ticket. L'arbre que toutes ces branches jugent est pris **une fois, avant de lancer la première** : deux d'entre elles sont les commandes du projet, donc écrivent dans l'arbre qu'elles jugent, et un contrôle qui fige son entrée pendant que d'autres processus écrivent ne rend pas un verdict mais un tirage. *resolved* n'est prononcé que si toutes les branches déclenchées sont vertes ; une branche qui pend au-delà de `GATE_TIMEOUT` est tuée et compte rouge.

Les branches ci-dessus sont le **palier objectif**. Quand elles sont toutes vertes, le gate joue une seconde phase, le **palier de jugement** : les **lentilles de revue** nommées par `LENSES` que le ticket déclenche. Standards et Spec répondent de tout ticket ; Fidélité et Accessibilité demandent une surface visible (tag `visible`, ou write-surface rencontrant `VISIBLE_PATHS`), Sécurité un tag `security` ou `SECURITY_PATHS`. Chacune est un `claude` frais qui relit le diff — pas l'état de l'arbre, le diff, qui arrive dans son prompt parce qu'elle n'a pas de quoi lancer `git` — et termine sur une ligne `RALPH-LENS-VERDICT: pass|fail`. Tout ce qui n'est pas un `pass` explicite compte rouge : une lentille morte, tuée pour contexte, dépassée par le délai ou qui répond de la prose n'a rien jugé. Ajouter une lentille à soi, c'est un nom dans `LENSES` et deux fonctions dans `.claude/lib/lenses.sh` ; un nom que rien ne sait exécuter est refusé au démarrage plutôt que sauté en silence.

Trois choses valent d'être dites sur ce palier, parce qu'elles ne sont pas des détails d'implémentation. Il est une **phase** et pas trois branches de plus : une lentille tourne dans l'arbre qu'elle juge, et ce qu'elle y écrirait n'est attribuable — donc défaisable — que si les commandes du projet n'écrivent pas en même temps. Il **ne tourne pas** sur un gate déjà rouge, parce qu'aucun verdict de lentille ne changerait l'issue et qu'une lentille coûte une vraie session sur votre abonnement (comptez `1 + n` sessions par itération verte). Et une lentille est spawnée en **lecture seule** — `--tools Read,Grep,Glob`, qui retire les outils d'écriture au lieu de leur refuser la permission — puis l'arbre est rediffé autour de la phase et remis en état s'il a bougé : de ces deux mécanismes, seul le second est une garantie que le pack vérifie lui-même. Ce qui n'est vérifié par rien, et c'est assumé : **le verdict lui-même**. Voir [`docs/frontiere-de-confiance.md`](docs/frontiere-de-confiance.md), qui dit exactement ce que le pack tient et ce qu'il se contente de demander.

Un diff git ne voit pas ce que git ignore, et c'est le projet cible qui écrit son `.gitignore`. Les chemins nommés par `GUARDED_PATHS` (défaut `.claude`) entrent donc dans le snapshot **par force** : le scope-guard les juge et le rollback les défait, ignorés ou pas. La configuration du harnais — `.claude/settings.local.json`, `.claude/settings.json`, `.claude/ralph.config.sh` — est en plus **scellée** : aucune write-surface ne peut la couvrir, parce que c'est ce qu'un `claude` frais lit au démarrage et ce que le run suivant source. Le reste de la zone ignorée n'est jugé par rien, et le run le **nomme** à chaque itération (`N ignored path(s)`) au lieu de le taire : forcer l'arbre entier ferait déborder chaque itération sur le build output du projet.

### Ce que fait la boucle quand ça échoue

Un échec n'est pas une seule chose. Une session coupée pour cause de contexte est une **tranche trop grosse** : une session de planification la redécoupe en tickets plus petits, la boucle vérifie que le découpage ne perd aucun critère d'acceptation ni n'élargit la write-surface, et les met en frontière. Un débordement dans la write-surface d'un **autre ticket** est un arbitrage de découpage : escalade directe, sans consommer de retry. Un gate rouge ou une session morte achète jusqu'à `RETRY_N` sessions fraîches, puis part vers `ready-for-human` avec un compteur `Failures:` et une raison `Escalation:`. Ce compteur est un **budget, pas un historique** : une livraison verte le remet à zéro, et un claim réclamé n'y compte que s'il appartenait à un run du pack — un ticket qu'un humain s'était assigné revient en frontière quand `CLAIM_TTL` tombe, mais sans payer de retry pour l'attente.

Dans tous les cas le dépôt revient où la session l'a trouvé — les fichiers qu'elle a ajoutés sont supprimés, ceux qu'elle a modifiés ou supprimés sont restaurés, un commit qu'elle aurait fait est défait. Le rollback est **exactement aussi large que le diff de la session** : ni `git reset --hard`, ni `git clean -fd`, pour ne pas emporter le travail non commité de quelqu'un d'autre. Ses trois exceptions sont énumérées et non déduites : le tracker, qu'il laisse à dessein, la zone ignorée hors chemins gardés, et ce que les branches du gate ont écrit **après** l'arbre qu'elles jugeaient — un rapport de couverture, un snapshot de test mis à jour. Les deux dernières, il les **nomme** au lieu de prétendre les avoir défaites, la troisième nette de ce qu'il a effectivement remis. Avant une escalade, la tentative est conservée sur une branche `failed/<ticket>`. Et chaque itération verte est **commitée** avant la suivante : sans ça, un rollback ultérieur détruirait le travail déjà gaté.

Codes de sortie de `loop.sh` : `0` la frontière a été drainée par ce run · `1` un autre run tient le tracker de cette feature, ou cet arbre de travail · `2` refus de démarrer (config absente, `FEATURE` vide ou pointant sur rien, config qui viderait le gate de son sens) · `4` arrêt sur une garde (stop demandé, cap d'itérations, run stérile, verrou que ce run ne tient plus) · `5` rien à broyer, la frontière était déjà vide au démarrage.

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

RALPH_REAL_CLAUDE=1 bash test/run.sh test/contract-claude.bats   # réseau + quota
```

Aucune dépendance : le runner (`test/helpers/microbats.bash`) interprète la syntaxe bats en bash pur, et les mêmes fichiers restent lisibles par bats-core. La suite est vérifiée sans node ni homebrew sur le `PATH`.

`test/mutate.sh` est le gate qui compte : il supprime une garantie à la fois et vérifie que le test censé la couvrir rougit. Seize tests de ce dépôt sont passés au vert alors que la propriété qu'ils prétendaient couvrir avait été supprimée — un test qui courait après une fenêtre de quelques microsecondes, un test qui assertait un message que la boucle imprime de toute façon, un test qui lisait le shell du développeur plutôt que le code, deux refutations du canari qui visaient la sortie du `run` précédent, et un test de seuil qui comparait à une valeur du même côté de la ligne que la constante qu'il devait exclure. Un `VACUOUS` est un faux vert dans un pack dont le métier est de refuser les faux verts.

Le gate lui-même peut mentir, et il l'a fait : douze de ses éditions contenaient un `$var` non échappé, que perl interpole en chaîne vide — elles **cassaient** le fichier au lieu d'en retirer la garantie, et rapportaient `ok` en prouvant seulement que la suite remarque un script cassé. Trois tests vacuous vivaient derrière. Deux gardes le refusent maintenant : `perl -Mstrict`, qui ne compile pas une variable non déclarée, et un `bash -n` sur le fichier muté. Le verdict s'appelle `BROKEN`.

`test/layering.bats` garde la pile : `loop.sh` au-dessus, `lib/*.sh` en dessous, chaque module propriétaire de ses internes `<module>__`. Un lib qui appelle l'interne d'un voisin ou qui remonte dans la boucle rougit — et le fichier plante lui-même une violation pour vérifier que la règle a des dents, parce qu'un contrôle qui ne matche rien ressemble à un pack propre.

`test/canary.bats` est l'autre : un run contre le monde tel qu'il est — sessions qui écrivent vraiment leur write-surface, une qui commit tout, une dont le flux arrive coupé au milieu d'une ligne, par-dessus un tracker en CRLF, déjà sale et portant le claim de quelqu'un d'autre. Presque tous les défauts livrés jusqu'ici vivaient dans l'écart entre un fake trop coopératif et une vraie session.

`test/contract-claude.bats` est le pont vers le réel. Toute la suite pilote un faux `claude` : vert ne prouve donc que la cohérence du pack avec **nos propres hypothèses** sur l'interface de Claude Code. Ce fichier tient un jeu d'assertions unique — NDJSON une ligne par événement, `system/init` en premier avec `bypassPermissions`, `result` en dernier lisible par l'extracteur du pack lui-même, `usage` sur les événements `assistant` (c'est de là que vient le signal du filet smart-zone, *pendant* la session), `rate_limit_event` pour le budget, et le marqueur du prompt dans la réponse — appliqué au flux du fake à chaque run, et à celui du vrai binaire sous `RALPH_REAL_CLAUDE=1`. Il attrape la dérive dans les deux sens : un shim qui invente, et une release de Claude Code qui déplace le format sous le pack. La moitié réelle skippe bruyamment par défaut, et un test structurel refuse qu'un `contract_spawn_real` non gardé se glisse dans la suite hermétique.

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
    state.sh               écriture atomique, verrous de run et d'arbre, guards
    claim.sh               test-and-set du claim, liveness, reclaim
    session.sh             le spawn : le seul endroit qui lance `claude`
    proc.sh                attendre un enfant malgré le trap du stop gracieux
    monitor.sh             filet smart-zone
    gate.sh                gate objectif (tests, typecheck, scope-guard) et lentilles
    lenses.sh              registre des lentilles de revue
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
