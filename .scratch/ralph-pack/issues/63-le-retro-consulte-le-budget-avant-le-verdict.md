# 63 — `retro_run` consulte le budget **avant** le verdict, et jette une leçon, un ADR, une escalade et la nuit

**What to build:** Mettre `retro_run` dans l'ordre que [43] a posé et que les deux autres paliers portent — le verdict prime sur l'événement — et donner au harnais le helper qui rendait ce cas inexprimable.

**Blocked by:** None

**Write-surface:** `.claude/lib/retro.sh`, `test/helpers/shims/claude`, `test/helpers/harness.bash`, `test/retro.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** budget, retro, observability

- [ ] `retro_run` ne consulte `budget_refused` que si la session **n'a rien répondu** — même critère que `lenses_refused_posture` (verdict `none` d'abord) et que `playthrough_close`. Un rétro qui a répondu enregistre sa leçon, son ADR, son escalade et sa capacité, **puis** peut encore faire remonter le posture au pilote si c'est ce qui est décidé (les deux moitiés sont séparables : ce qu'on jette et ce qu'on remonte).
- [ ] La phrase du reçu ne ment plus : « the API refused the retro session » ne doit être écrite que quand l'API a refusé la session.
- [ ] **`retro_rate_limit` dans le harnais** — un événement in-band **avec** une réponse, pendant du `playthrough_rate_limit` que [11] a ajouté pour son propre palier. Aujourd'hui `retro_refused` émet l'événement *et* `exit 1` sans réponse, et `claude_rate_limit` est global (il touche la session de livraison, dont le posture est justement ce que le pilote lit) : le cas ne pouvait pas s'écrire.
- [ ] Un test par chose perdue (leçon, ADR, escalade, capacité) et un test sur la nuit (`$slot/posture` n'est pas écrasé, le run continue), chacun avec son témoin appairé `allowed`.
- [ ] Entrée de mutation par garantie livrée. **Deux directions** pour l'ordre : une mutation qui remet `budget_refused` en premier, et une qui retire la garde du posture.
- [ ] La règle est écrite **une fois** quelque part que les trois paliers citent, plutôt qu'une quatrième fois en prose. C'est ce qui a laissé passer celle-ci.

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
