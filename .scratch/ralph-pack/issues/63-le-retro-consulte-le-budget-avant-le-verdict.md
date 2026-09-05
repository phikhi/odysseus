# 63 — `retro_run` consulte le budget **avant** le verdict, et jette une leçon, un ADR, une escalade et la nuit

**What to build:** Mettre `retro_run` dans l'ordre que [43] a posé et que les deux autres paliers portent — le verdict prime sur l'événement — et donner au harnais le helper qui rendait ce cas inexprimable.

**Blocked by:** None

**Write-surface:** `.claude/lib/budget.sh`, `.claude/lib/lenses.sh`, `.claude/lib/playthrough.sh`, `.claude/lib/retro.sh`, `test/helpers/shims/claude`, `test/helpers/harness.bash`, `test/retro.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

**Tags:** budget, retro, observability

- [x] `retro_run` ne consulte `budget_refused` que si la session **n'a rien répondu** — même critère que `lenses_refused_posture` (verdict `none` d'abord) et que `playthrough_close`. Un rétro qui a répondu enregistre sa leçon, son ADR, son escalade et sa capacité, **puis** peut encore faire remonter le posture au pilote si c'est ce qui est décidé (les deux moitiés sont séparables : ce qu'on jette et ce qu'on remonte).
- [x] La phrase du reçu ne ment plus : « the API refused the retro session » ne doit être écrite que quand l'API a refusé la session.
- [x] **`retro_rate_limit` dans le harnais** — un événement in-band **avec** une réponse, pendant du `playthrough_rate_limit` que [11] a ajouté pour son propre palier. Aujourd'hui `retro_refused` émet l'événement *et* `exit 1` sans réponse, et `claude_rate_limit` est global (il touche la session de livraison, dont le posture est justement ce que le pilote lit) : le cas ne pouvait pas s'écrire.
- [x] Un test par chose perdue (leçon, ADR, escalade, capacité) et un test sur la nuit (`$slot/posture` n'est pas écrasé, le run continue), chacun avec son témoin appairé `allowed`.
- [x] Entrée de mutation par garantie livrée. **Deux directions** pour l'ordre : une mutation qui remet `budget_refused` en premier, et une qui retire la garde du posture.
- [x] La règle est écrite **une fois** quelque part que les trois paliers citent, plutôt qu'une quatrième fois en prose. C'est ce qui a laissé passer celle-ci.

## Comments

- **Trouvé par la passe transversale du 05/09/2026** (`../passe-transversale-05-09.md`, §2). Sondes : `../sondes/passe-05-09/q2-le-retro-consulte-le-budget-avant-le-verdict.bats`.

- **La règle, écrite deux fois et fausse la troisième.** [43] l'a posée, [11] l'a réécrite en toutes lettres dans `playthrough_close` : « **The verdict outranks the event, in that order and not the other way round** » — le signal in-band peut annoncer `blocked` pour la fenêtre *suivante* pendant que la session en cours répond parfaitement ; une session qui a répondu a **regardé**, et ce qu'elle a dit tient.

  | module | ordre |
  |---|---|
  | `lenses_refused_posture` | `[ verdict = none ] \|\| return 1` **puis** `budget_refused` |
  | `playthrough_close` | `[ "$verdict" = none ] && budget_refused …` |
  | `retro_run` | **`budget_refused "$posture"` d'abord**, les `retro__said` après |

- **Mesuré, run réel** (`q2` Q2a). Le rétro répond `LESSON` + `WHY` + `ADR` + `DECISION` + `BECAUSE` + `ESCALATE`, son flux porte `blocked` (`seven_day`), la session de livraison dit `allowed` :

  ```
  rc du run                 : 6
  LEARNINGS.md              : NON
  docs/adr/                 : (vide)
  Status 01-alpha / 02-beta : resolved / ready-for-agent
  le reçu dit               : « no lesson was distilled from this iteration:
                                the API refused the retro session (seven_day) »
  ralph: the weekly usage limit blocks this run (seven_day, said by the stream) — stopping
  ```

  **Témoin appairé** (`q2` Q2b), le même rétro avec `allowed` : leçon `LR-0001` dans `LEARNINGS.md` et `learning-records/`, `docs/adr/0001-who-owns-the-flow-document.md`, ticket `03-retro-add-a-lint-that-fails-when-the-flow-is-not-wired` sur le puits humain, et le run continue jusqu'au bout de la file (4 itérations).

- **Cinq choses perdues, sur une session qui a répondu.**
  1. **La leçon** — `LEARNINGS.md` et `learning-records/`, le quatrième palier d'observabilité, celui qui est lu *dans le prompt de chaque session suivante* ([14]).
  2. **La décision d'architecture** — `docs/adr/`, lue par toutes les sessions et par la lentille Standards.
  3. **L'escalade** — le ticket sur le puits humain, la seule façon dont ce pack demande une règle qu'il ne construit pas lui-même.
  4. **La capacité** ([15]) — `capability_review` n'est jamais atteint, le `return 0` est au-dessus.
  5. **La nuit** — `RALPH_RETRO_QUOTA` écrase `$slot/posture` (`loop.sh:958`), `budget_may_spawn` lit le mur in-band, le run s'arrête et arme un successeur. `02-beta` n'est jamais tenté.

- **Et le reçu ment.** « the API refused the retro session » alors que la session a répondu six lignes taggées, présentes dans le flux que le pack vient de `rm -rf`. C'est la famille de [10] : un reçu est assemblé par le process qui a mesuré, et ici il rapporte une mesure que personne n'a faite.

- **Pourquoi personne ne l'a vu : le harnais ne sait pas exprimer le cas.** [11] a ajouté `playthrough_rate_limit` en se posant exactement cette question pour son palier. Le rétro n'a que `retro_refused` (événement + `exit 1`, sans réponse). Le shim n'a pas de branche `retro.rate_limit`. La sonde a dû passer par un `script_claude` qui reconnaît le rétro à `RALPH-RETRO-NOTHING` dans le prompt — comme le shim lui-même — et émet son propre NDJSON. **Un helper manquant est un cas non couvert, pas une couverture manquante :** c'est la trouvaille, pas un détail d'outillage.

- **Piège** : un `script_claude` installé fait taire `retro_call_count` (le shim écrit `claude.retros/calls` *après* le `exec`). Une sonde qui a besoin de savoir que le rétro a tourné pose son propre témoin.

- **Ce qui reste à décider dans le ticket.** Faut-il quand même remonter le posture au pilote quand le rétro a répondu ? L'argument de [08] (« ça peut ajouter une raison d'être prudent et jamais en retirer une ») dit oui ; l'argument de [43] dit que l'événement parle de la fenêtre *suivante* et que le pilote a déjà l'endpoint pour ça. Les deux moitiés sont séparables et le ticket doit trancher les deux séparément — jeter la réponse est faux dans tous les cas, arrêter la nuit est une question ouverte.

- **Place dans la file, validée par Philippe le 05/09/2026 : premier.** Aucune
  arête — `retro.sh` et `test/helpers/` ne sont touchés par aucun autre ticket de
  la file. C'est le seul **faux livré** des quatre trouvailles de la passe, et le
  `retro_rate_limit` qu'il ajoute au harnais profite aux trois suivants. Ordre
  complet retenu : [63] → [62] → [65] → [64] → passe transversale → [18] → [19].

## Livraison (05/09/2026)

- **Sondes rejouées avant d'écrire**, et le défaut reproduit tel qu'il est décrit :
  `q2a` rc=6, pas de `LEARNINGS.md`, `docs/adr/` vide, `02-beta` jamais tenté, reçu
  « the API refused the retro session (seven_day) », run arrêté sur
  « the weekly usage limit blocks this run » ; témoin `q2b` avec `allowed` : leçon
  `LR-0001`, `docs/adr/0001-who-owns-the-flow-document.md`, ticket `03-retro-…` sur
  le puits, quatre itérations. Les sondes restent en place, elles ne sont pas des
  tests (elles finissent par un `false` volontaire).

- **La règle est une fonction, pas une quatrième phrase.**
  `budget_refused_silence VERDICT POSTURE` dans `.claude/lib/budget.sh` : vrai
  seulement si la session **n'a rien dit** (`none` ou vide) **et** que la raison est
  un refus de l'API. Les trois paliers l'appellent — `lenses_refused_posture`,
  `playthrough_close`, `retro_run` — et les commentaires des deux premiers ne
  recopient plus la règle, ils la citent. C'était l'AC la plus importante : le
  défaut n'est pas une ligne mal écrite, c'est une règle connue en trois
  exemplaires recopiés à la main, dont un était faux (même racine que la passe du
  05/09 dans son ensemble).

- **Les deux moitiés, tranchées séparément, comme demandé.**
  1. *Jeter la réponse* — faux dans tous les cas, corrigé : `budget_stream_posture`
     et la garde sont désormais **après** les sept `retro__said` et le
     `capability_said`, donc leçon, ADR, escalade et capacité sont enregistrés
     avant que le budget soit consulté, et `capability_review` est atteint.
  2. *Remonter le posture au pilote quand le rétro a répondu* — **non**, et c'est la
     décision du ticket. Trois raisons : (a) c'est ce que font déjà les deux autres
     paliers — `lenses_refused_posture` ne rend un posture que sur un verdict
     `none`, et `playthrough_close` ne touche à rien quand le verdict existe, donc
     dire oui ici remettrait une asymétrie dans le palier qui vient d'en sortir ;
     (b) l'événement porte sur une **fenêtre**, pas sur cet appel — une session qui
     a répondu a été servie, et `blocked` y annonce la fenêtre suivante, que ce run
     ne dépensera peut-être jamais ; (c) l'argument de [08] (« ajouter une raison
     d'être prudent, jamais en retirer une ») reste tenu par deux canaux que ceci ne
     touche pas : le posture de la **session de livraison**, qui est la première
     mesure du mur par ce run, et l'endpoint que `budget_check` redemande — avec
     `force=1` précisément quand un posture dit refusé. Ce qui est refusé ici, c'est
     qu'un événement lu dans le flux d'une session **qui a répondu** arrête la nuit.
     `RALPH_RETRO_QUOTA` reste écrit, mais uniquement sur la branche du vrai refus.

- **`retro_rate_limit` dans le harnais** (`test/helpers/harness.bash` +
  branche rétro du shim, jumeau exact de `playthrough_rate_limit`). C'est ce qui
  rend le cas *écrivable* : `retro_refused` est un événement **sans** réponse
  (`exit 1`), `claude_rate_limit` touche aussi la session de livraison — dont le
  posture est justement ce que le pilote lit — donc un test écrit avec lui aurait
  mesuré un run en pause. Le shim n'exécute cette branche que sur un prompt qui
  porte `RALPH-RETRO-NOTHING`, comme pour les lentilles et le gate de valeur.

- **Le trou de non-vacuité que le témoin appairé ne bouche pas, et le test qui le
  bouche.** Après correctif, un rétro qui répond produit *la même chose* que
  l'événement dise `blocked` ou `allowed` — c'est la garantie. Donc un shim qui
  ignorerait silencieusement `retro.rate_limit` laisserait les cinq tests verts en
  ne mettant rien en scène : exactement la forme de faux vert de [06] (compteur du
  fake) et de [11]. Le test « said nothing readable and was refused says so, event
  and all » ferme ça : même helper, même événement, sur une session dont la réponse
  n'est pas lisible — là l'événement **est** la raison, le reçu doit le dire, et
  l'entrée de mutation `63 the retro's stream never carries the event a test staged`
  vise le shim.

- **Quatre entrées de mutation ajoutées**, les deux directions de l'ordre comprises :
  `63 the retro asks the budget before it reads the answer` (l'ordre remis à
  l'envers : `budget_refused_silence none "$posture"`), `63 a retro that answered
  raises a posture the pilot has an answer for` (la garde du posture retirée :
  `RALPH_RETRO_QUOTA` écrit inconditionnellement), `63 the ordering holds for the
  tier that reads it, not the tier that wrote it` (la garde partagée retirée dans
  `budget.sh`, **visée contre `test/playthrough.bats`** et non contre le rétro : ce
  qui doit tenir, c'est que la règle est *une seule* règle), et l'entrée shim
  ci-dessus.

- **Six entrées ré-ancrées** (`DRIFTED` sinon, leçon 3) : les deux de [43] sur
  `lenses.sh` — dont une **déménage vers `$BUDGET`**, puisque la question du
  posture n'est plus posée dans `lenses.sh` —, les deux de [11] sur
  `playthrough.sh`, et les deux de [14] sur `retro.sh` (`answered` ne vaut plus
  `0`/`1` mais `none`/`said`, pour que le premier argument de
  `budget_refused_silence` soit du même vocabulaire chez les trois paliers).
  Toutes rejouées pour de vrai, pas seulement en `-n`.

- **Piège hérité, confirmé** : la sonde passait par `script_claude` et devait poser
  son propre témoin, parce que le shim écrit `claude.retros/calls` *après* le
  `exec`. Les tests livrés n'utilisent pas `script_claude` — ils passent par la
  branche rétro du shim — donc `retro_call_count` y est fiable, et deux d'entre eux
  l'assertent (`= 2`) pour prouver que les deux itérations ont bien eu leur rétro.

- **Les deux gates, mesurés d'un bloc sur le code livré** : `bash test/run.sh` =
  **719 tests, 0 failures, 6 skips** (712 + 7 nouveaux ; les 6 skips sont les
  opt-in réseau/binaire réel, aucun dans le canari) et `bash test/mutate.sh` =
  **712 mutations, 0 not ok** (708 + 4). Arbre propre après coup, aucun défaut
  planté. Nouvelle baseline pour le ticket suivant.

- **Contraintes écrites ailleurs** : [43] (la règle est maintenant du code, un
  quatrième palier doit appeler la fonction), [11] (`playthrough_close` passe par
  elle ; `playthrough_rate_limit` a un jumeau), [08] (la direction « une raison de
  plus, jamais une de moins » ne passe plus par le rétro qui a répondu, et par quoi
  elle passe à la place), [14] (`answered` change de vocabulaire).
