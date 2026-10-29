# Sondes du tri de [112], 29/10/2026

Des **instruments**, pas des tests. Chaque cas finit par un `set -e; false`
volontaire : il rougit toujours, et ce qu'on lit est ce qu'il imprime avant.
Hors de `test/`, jamais compté par les deux gates. Rien touché hors `.scratch/` :
la baseline de [97] tient (`run.sh` 1145/0/6 skips, `mutate.sh` 1246/0).

    bash test/run.sh .scratch/ralph-pack/sondes/triage-112/<sonde>.bats </dev/null

Environ 12 s par cas, sur `main` à `9731780` (le code de [97], inchangé par le tri
de [111]). Gabarit du survivant : `../triage-111/q1` — planté par la première
livraison, ignore `TERM`, **ajoute tant que sa marque manque**. Les appels 1 et 2
du faux sont la même livraison.

## q1 — l'index après sa remise

L'entrée forgée est `- LR-0999 x9 learning-records/0999-forged.md — FORGED-INDEX …`
sous `## Working set` (`x9` pour viser la promotion, `LEARNINGS_PROMOTE_AT=3`).

| Cas | Ce qui arrive | Ce que le run dit |
|---|---|---|
| **P1** deux tickets, leçon | `FORGED-INDEX` au rétro 1, à la livraison 2, au rétro 2, dans `LEARNINGS.md` **sous `## Promoted`**. Une 2ᵉ entrée `FORGED-LATE`, ajoutée seulement une fois `LEARNINGS.md` écrit, arrive à la livraison 2, au rétro 2 et dans `LEARNINGS.md` | « put back » une fois (itération 1). Reçu de 01-alpha : *« a lesson this loop recorded was promoted to a standing rule (LR-0999, seen 9 time(s)) »*. Reçu de 02-beta : *« the lesson index in the working tree had been edited by something other than this loop … — no session of this run was ever handed the edited text »* — **fausse deux fois** : l'arbre n'a pas été touché, et les appels 4 et 5 avaient reçu l'entrée. `run.log` : *« LEARNINGS.md is not what this run last wrote — something outside this loop edited it »*. Run `0` |
| **P2** deux tickets, rétro `NOTHING` | `FORGED-INDEX` au rétro 1, à la livraison 2, au rétro 2. **`LEARNINGS.md` absent** : un rétro qui ne répond rien ne publie pas | « put back » une fois. Run `0` |
| **P3** `MAX_PARALLEL=2` | `FORGED-INDEX` à la livraison 2 (appel 3), aux deux rétros, dans `LEARNINGS.md` promu | *« … more than one iteration in flight: it is left as it stands »* ×2 ; promotion forgée annoncée au reçu. Run `0` |
| **P4** run 1 (un ticket, leçon) puis run 2 **sans survivant** (survivant tué, `02-beta` ajouté) | run 2 : `FORGED-INDEX` à sa livraison (appel 5) et à son rétro (appel 6), toujours dans `LEARNINGS.md` | run 2 : **rien**. `retro_open` prend `LEARNINGS.md` pour la ligne de base |
| **P5** sans toucher `index` : `work`, `prom` (de `retro__record_lesson`), `read.*/work` (de `retro_index`) | `FORGED-WORK` et `FORGED-PROM` dans `LEARNINGS.md` (promues), `FORGED-READ` dans les prompts de la livraison 2 et du rétro 2 | **aucune ligne sur l'index** ; deux reçus annoncent la promotion de `LR-0997`. Le recensement de [83] ne voit rien : ces fichiers vivent hors de la fenêtre d'une session. Reproduit 2/2 |

## q2 — l'index dans les heredocs (`heredoc_spy` du harnais)

Le tableau (ligne de [108]) dit déjà que les trente-trois `cat <<X` de prose sont un
fichier nommé un instant. L'espion réécrit en `x` tout heredoc dont une ligne
commence par un marqueur.

- **Q2a**, marqueur `You are the retro subagent` : les **deux prompts du rétro**
  arrivent au juge entièrement réécrits (93 lignes `x`). C'est l'objet de [111], et
  ça vaut pour son AC « le prompt n'a pas de nom » : un prompt rendu par
  `cat <<PROMPT` a un nom dans `/var/tmp/sh-thd-*` avant d'atteindre son canal.
- **Q2b**, marqueurs `# LEARNINGS` (`retro__render`, `cat <<'HEAD'`) et
  `## Lessons earlier iterations left` (`loop__prompt_lessons`, `cat <<LESSONS`) :
  1er passage, la tête réécrite aux **deux** publications — `LEARNINGS.md` en `x`,
  `## Working set` perdu **dans l'état** (le texte rendu est l'index suivant), la
  leçon de 02-beta écrite en double (`0002`) au lieu d'être comptée. 2ᵉ passage : la
  tête une fois, et le bloc des leçons du prompt de la livraison 2 arrivé en `x`.
  Lequel est attrapé varie ; que les deux soient atteignables, non.

**Piège** : l'espion ignore `TERM` et **survit au test** (90 s). Un second run
lancé dans la minute voit ses heredocs réécrits par l'espion du premier. D'où le
`kill -KILL "$PACK_BG_PID"` en fin de cas.

## q3 — le jumeau de [83] : un brief écrit après la fenêtre

**P6** : le survivant crée `ralph-retro.*/brief.02-beta` une fois `LEARNINGS.md`
écrit, c'est-à-dire pendant le rétro de l'itération 1, **après** `retro_state_note`
et avant le recensement de l'itération 2. Le prompt de la livraison de 02-beta
(appel 4) porte la ligne sous *« What the gate said about the previous attempt at
this ticket »* — un ticket jamais tenté. **Aucune ligne.** Ce que [83] écrit
(« ce qui les tient est la fenêtre ») est vrai d'une session et faux d'un survivant
d'une session précédente : il écrit entre deux fenêtres. Même forme pour
`capability.seen`, non mesurée.

## Ce que ces mesures ne disent pas

Ce qu'un **vrai** modèle fait d'une leçon forgée. Pour `LEARNINGS.md`, la promotion
annoncée au reçu et le run suivant, il n'y a pas de modèle dans la chaîne.
