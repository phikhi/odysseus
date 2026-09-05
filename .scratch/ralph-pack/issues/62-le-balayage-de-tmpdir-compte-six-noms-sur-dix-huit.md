# 62 — `gate__tmp_leftovers` compte six des dix-huit noms que le pack pose dans `$TMPDIR`

**What to build:** Dériver la liste de `gate__tmp_leftovers` de son critère plutôt que de la recopier à la main, et écrire le résultat là où [19] le lira comme spécification de balayage.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** observability, gate

- [ ] La liste de `gate__tmp_leftovers` couvre **tous** les noms de premier niveau que le pack pose dans `$TMPDIR`, ou bien elle est dérivée d'un motif unique et le prix de ce motif est écrit (`$TMPDIR` est partagé avec d'autres dépôts et avec `ralph-test.*`).
- [ ] Un test qui **rougit quand un producteur est ajouté sans être couvert** — pas une liste de dix-huit assertions recopiée à côté de la liste du code, qui serait le même défaut une couche plus haut. La forme évidente est un balayage de `.claude/**` à la recherche des `mktemp` de premier niveau, comparé à ce que le contrôle attrape (modèle : `gate_config_keys` et ses 53 entrées).
- [ ] La phrase dit encore la vérité : elle annonce des « temporary director(ies) » et compte aussi des fichiers (`ralph-slot.writes.*` est déjà dans ce cas aujourd'hui).
- [ ] Entrée de mutation par garantie livrée, plus le témoin appairé.
- [ ] La note pour [19] est écrite **dans [19]**, pas seulement ici.

## Comments

- **Trouvé par la passe transversale du 05/09/2026** (`../passe-transversale-05-09.md`, §1). Sondes : `../sondes/passe-05-09/q1-*.bats`.

- **Le critère est dans la phrase, la liste est à côté.** Le message dit : « N temporary director(ies) **from earlier runs** are still in `$TMPDIR`: **a run killed mid-iteration leaves one behind**, and nothing here removes them ». La liste énumère cinq motifs — `ralph-gate.*`, `ralph-ignore.*`, `ralph-worktree.*`, `ralph-slot.*`, `ralph-frontier.*` — et `grep -rn mktemp .claude/` en donne dix-huit au premier niveau de `$TMPDIR`. Forme exacte de [31] (un scellement plus étroit que son critère) et de [45] (un reçu avec moins de producteurs que son critère).

- **Mesuré, un nom par run, vieilli de 25 h** (`q1` Q1a) — 6 vus, 12 non :

  | vu | nom | producteur |
  |---|---|---|
  | ✅ | `ralph-slot.*` | `loop.sh:1087` |
  | ✅ | `ralph-slot.writes.*` | `loop.sh:1396`, par le glob du précédent |
  | ✅ | `ralph-frontier.*` | `gate.sh:656` |
  | ✅ | `ralph-ignore.*` | `gate.sh:764` |
  | ✅ | `ralph-gate.*` | `gate.sh:3130` |
  | ✅ | `ralph-worktree.*` | `concurrency.sh:298` |
  | ❌ | `ralph-receipt.*` | `receipt.sh:100` — **un répertoire** |
  | ❌ | `ralph-retro.*` | `retro.sh:164` — **un répertoire** |
  | ❌ | `ralph-playthrough.*` | `playthrough.sh:699` — **un répertoire**, [11] |
  | ❌ | `ralph-spec.*` | `playthrough.sh:229` — le témoin du flux, [11] |
  | ❌ | `ralph-tracker.*` | `failures.sh:764` |
  | ❌ | `ralph-failed.*` | `failures.sh:1029` |
  | ❌ | `ralph-durable.*` | `failures.sh:1112` |
  | ❌ | `ralph-reslice.*` | `failures.sh:1259` |
  | ❌ | `ralph-index.*` | `gate.sh:2224` |
  | ❌ | `ralph-restore.*` | `gate.sh:2441` |
  | ❌ | `ralph-fold.*` | `concurrency.sh:533` |
  | ❌ | `ralph-refresh.*` | `concurrency.sh:652` |

- **Run réel** (`q1` Q1b) : un run tué au `KILL` pendant le gate laisse **neuf** entrées, le contrôle en compte **six**. Les trois muettes sont `ralph-receipt.*`, `ralph-retro.*` et `ralph-spec.*`. **Témoin appairé** (Q1c) : un run qui finit normalement laisse **zéro**, donc ce qui reste est bien ce que le critère décrit. Trois des muettes sont des **répertoires** — l'échappatoire « la phrase dit *director(ies)* » ne tient pas, elle en compte six et en laisse trois du même genre. Et deux des trois muettes du run réel sont des livraisons de **[11]** : la dérive est en train de se faire, ce n'est pas un héritage ancien.

- **Ce que ça coûte aujourd'hui, chiffré ailleurs.** Le balayage de `$TMPDIR` en fin de ticket est fait à la main dans ce dépôt (mesure du 03/09/2026 : `1,0 Go → 49 Mo`, environ 1 Go de résidus par ticket, dont l'essentiel vient du harnais de test et non du pack). Ce ticket ne balaie rien — `gate_leftovers` **dit et ne balaie pas**, c'est une décision écrite —, il rend le compte honnête.

- **Piège à ne pas répéter.** `-mtime +0` veut dire *strictement plus de 24 h* : un test qui pose un résidu et l'interroge tout de suite mesure `0` quelle que soit la liste. Vieillir avec `touch -t` (`date -v-25H`).

- **Ce que le motif unique coûterait, à mesurer avant de le choisir.** `ralph-*` attraperait aussi `ralph-test.*` (le répertoire du harnais de test lui-même) et les résidus des runs d'autres dépôts sur la même machine — ce qui est déjà vrai des six noms actuels et que le commentaire assume explicitement (« a directory nobody has touched in twenty-four hours belongs to no run that is still going »). Le choix à écrire est donc : dériver le motif, ou dériver la liste, et dans les deux cas ce qui rougit quand un producteur est ajouté.

- **Place dans la file, validée par Philippe le 05/09/2026 : deuxième**, après
  [63] et avant [65], [64], [18], [19]. La raison n'est pas l'arête vers [19] mais
  ce que ce ticket livre : **le contrôle qui rougit quand un producteur est ajouté
  sans être couvert**. Installé tôt, il travaille pour les quatre tickets qui
  suivent — [18] en particulier, qui a toutes les chances d'ajouter un `mktemp`
  (un backend distant qui cache des réponses). Installé juste avant [19] seulement,
  il arriverait après le producteur qu'il aurait dû attraper. `[19] Blocked by:`
  porte maintenant `62`.
