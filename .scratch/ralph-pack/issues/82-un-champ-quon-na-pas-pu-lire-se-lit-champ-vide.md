# 82 — Un champ qu'un tracker n'a pas pu lire se lit « ce ticket ne porte pas ce champ »

**What to build:** Que les lectures de l'interface d'adaptateur distinguent « ce ticket ne porte pas ça » de « je n'ai pas pu savoir », et que les consommateurs pour qui la différence décide quelque chose la lisent.

**Blocked by:** None

**Write-surface:** `.claude/lib/tracker.sh`, `.claude/lib/forge.sh`, `.claude/lib/gate.sh`, `.claude/lib/lenses.sh`, `.claude/lib/router.sh`, `test/tracker-remote.bats`, `test/gate.bats`, `test/mutate.sh`

**Status:** ready-for-agent

- [ ] `tracker_field` et `tracker_read_ticket` ont un code de retour pour « je n'ai pas pu savoir » distinct de celui pour « ce ticket n'a pas ce champ / n'existe pas », et l'interface l'écrit comme une clause, pas comme une habitude d'un adaptateur.
- [ ] La write-surface qu'un scope-guard juge n'est jamais une surface **vide obtenue sur un refus** : le refus est un verdict, pas un périmètre nul.
- [ ] Une lentille gatée par un tag ne devient pas « pas concernée » parce que le tracker n'a pas répondu.
- [ ] Le pin du drain distingue « ce champ était vide » de « ce champ n'a pas pu être lu », et `router__say_drift` cesse de pouvoir accuser une session routée de ce que le tracker a simplement fini par répondre.
- [ ] Le backend local garde exactement le comportement qu'il a : ses deux refus (ticket absent, id ambigu) sont des réponses et pas des « je n'ai pas pu savoir ».

## Comments

- **Trouvé à la passe transversale du 10/09/2026**
  (`../passe-transversale-10-09.md`, §4). Sondes :
  `../sondes/passe-10-09/q1-*.bats`, cas Q1a à Q1d.

- **La famille, et l'étage que personne n'a relu.** [59] a posé la règle (un refus
  n'est pas une réponse), [74] l'a fait lire au point d'entrée, [78] à
  l'ouverture, [79] la porte jusqu'aux appelants d'`open_unique`. Les quatre
  portent sur des **écritures** ou sur des **listes**. Les **lectures d'un champ**
  n'ont jamais été relues.

- **[71] a écrit *comment* une opération refuse — jamais ce qu'un refus veut
  dire.** L'en-tête de `lib/tracker.sh` porte « a refusal is a return code,
  non-zero, and the caller decides what it means », ce qui est exactement le
  problème : il y a **deux** choses à décider et un seul code.

      « ce ticket ne porte pas ce champ »   une réponse
      « je n'ai pas pu savoir »              un refus

  Mesuré sous la mise en scène de [78] (`FORGE_PAGE 2` + `FORGE_PAGES 1`, qui
  fait refuser tous les listings sans simuler de panne) :

  | | `tracker_field 1-alpha Status` (le ticket **existe**) | `tracker_field 999-nexistepas Status` |
  |---|---|---|
  | code | `1` | `1` |
  | valeur | vide | vide |

- **Vingt-huit sites, et tous écrasent les deux en la chaîne vide.**
  `|| status=''`, `2>/dev/null || true`, `[ "$(…)" = x ]`. Ce que le vide veut
  dire chez trois d'entre eux, mesuré :

  | Site | Ce que le vide veut dire | Verdict |
  |---|---|---|
  | `gate_write_surface` | « ce ticket ne déclare rien » | `src/alpha.txt`, que le ticket déclare, est **hors de sa propre surface** (Q1b) |
  | `lenses_has_tag` | « ce ticket ne porte pas ce tag » | la lentille gatée par `Tags: security` **ne voit pas** un ticket qui le porte (Q1c) |
  | `router_pin` | « ce champ était vide au moment du drain » | le pin est vide, et `router__say_drift` accusera la session routée d'avoir écrit ce que le tracker a fini par répondre |

  Témoin appairé Q1d, le même tracker sous un plafond qui tient : `rc=0
  ready-for-agent`, `surface=[src/alpha.txt]`, la lentille voit.

- **Le précédent est à deux lignes du défaut.** `gate__surface_owner` lit bien le
  refus depuis [18] — `ids="$(tracker_ids)" || return 2` — et rend `2` sous le
  même plafond (mesuré, Q1b), avec un appelant qui escalade au lieu de retenter.
  `gate_write_surface` est juste au-dessus dans le même fichier et ne le fait
  pas. La forme de la réparation existe donc déjà dans le dépôt ; ce qui manque
  est la **clause d'interface** qui dit qu'il y a trois réponses et pas deux.

- **Ce que ça ne coûte pas encore, écrit plutôt que laissé à découvrir.** Depuis
  [74], un tracker durablement au-dessus du plafond arrête le run en `4` avant la
  première itération : les trois lignes ci-dessus ne sont pas atteintes par
  *ce* chemin. Elles le sont par les trois que [78] a écrits — `MAX_PARALLEL > 1`
  avec des itérations en vol (`loop__reap 1; continue`), un tracker qui franchit
  le plafond pendant une session, un refus isolé après les réessais de
  `forge__api` — et par un quatrième que la passe ajoute : **le drain**, qui n'a
  pas de `loop__next_ticket` devant lui et qui lit cinq champs par ticket.

- **Le backend local n'a pas ce défaut et il ne faut pas lui en donner un.** Ses
  deux refus sont des réponses : le fichier n'existe pas, ou l'id est ambigu
  (`tracker_local__path`, [27], [48]). Une clause qui l'obligerait à distinguer
  un troisième cas lui ferait inventer un état qu'il n'a pas. Ce que la clause
  doit dire est l'inverse : *un backend qui ne peut pas savoir le dit ; un
  backend qui sait que le ticket n'a pas ce champ répond*.

- **`claim.sh` est le seul des vingt-huit qui distingue déjà les deux** —
  `status="$(tracker_field "$id" Status)" || continue`, donc un ticket dont le
  statut n'a pas pu être lu n'est pas repris. C'est le bon côté du fail-safe, et
  c'est un accident de forme plutôt qu'une décision : il n'y a pas de
  commentaire. Le lui écrire fait partie du ticket.

- **Contrainte que ce ticket crée pour [73]** : la remise du tracker distant lit
  cinq champs plus le corps par ticket et par fenêtre. Un champ qu'on n'a pas pu
  lire y devient « ce ticket ne portait rien », c'est-à-dire une remise qui
  **efface**. Écrit dans [73].

- **Piège de harnais, hérité de [74] et [78]** : `FORGE_PAGE` et `FORGE_PAGES`
  sont des clés déclarées, donc désarmées par `harness__clear_env` ;
  `set_config FORGE_PAGE 2` + `set_config FORGE_PAGES 1` sur un tracker qui porte
  au moins deux issues fait refuser **tous** les listings d'un run.

## Place dans la file

**Validée par Philippe le 10/09/2026, à la passe transversale du même jour.** La
file devient **[80] → [81] → [79] → [82] → [75] → [73] → [19]**. Le critère est
celui du dépôt — minimiser la reprise, jamais l'urgence — avec la seule exception
que ce dépôt s'autorise et qu'il a déjà payée : **un faux vert livré passe
devant**, comme [76] l'a fait à la passe du 08/09.

1. **[80]** — le faux vert livré du lot ([40] rouvert par un glob). Il tranche
   aussi ce qui reste à [81] : la seule chose que « recenser et vérifier » ne peut
   pas attraper.
2. **[81]** — même zone (`$TMPDIR`), et il consomme la décision de [80]. Livrés
   voisins, ils s'écrivent contre une seule relecture de `loop.sh` et de
   `gate.sh`.
3. **[79]** — petit, indépendant, position libre. Placé ici parce qu'il ferme le
   résidu de [78] avant que la file ne reparte sur un autre chantier.
4. **[82]** — la famille des refus de lecture, et il touche `forge.sh` comme [75].
5. **[75]** — le cache, qui donne son budget à la remise de [73].
6. **[73]** — la remise, qui hérite de la clause de [82] autant que du cache de
   [75].
7. **[19]** — l'installeur lit ce que les six autres décident.

**`Blocked by:` reste `None` pour [79], [80], [81] et [82], et c'est une
décision** — le précédent est celui que [78] a écrit : la position dans la file
est un choix d'ordonnancement, pas une dépendance, et écrire une fausse arête
ferait sortir un ticket de la frontière si son voisin était mis de côté. Les
arêtes réelles ne bougent pas : `[75] 77`, `[73] 74, 75, 77`,
`[19] 73, 74, 75, 76, 77`.
