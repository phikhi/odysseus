# 90 — La règle sur la source s'arrête au corps du heredoc, et la prose du pack est surtout ailleurs

**What to build:** Que la règle de [61] couvre la forme sous laquelle le pack écrit réellement le plus de prose — une chaîne entre guillemets doubles — et pas seulement le corps d'un heredoc non cité.

**Blocked by:** None

**Write-surface:** `test/layering.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Une règle de `test/layering.bats` lit la **source livrée** et refuse une backtick non échappée à l'intérieur d'une chaîne entre **guillemets doubles** (et d'un mot non quoté), comme `layering_heredoc_prose` le fait pour le corps d'un heredoc non cité. La zone est celle que [87] dérive : les vingt-quatre libs et les trois points d'entrée, `init.sh` compris.
- [ ] Les deux **témoins appairés** sont plantés à côté de la violation, et ce sont les deux formes qui corrigent le défaut : la backtick échappée (`\``) dans une chaîne double, et la même phrase avec les mêmes backticks dans une chaîne **simple**, où la backtick est de la prose que le shell ne lit jamais. Une règle qui signalerait l'une des deux signalerait les deux formes qui la réparent — c'est l'argument que `layering_heredoc_prose` porte déjà pour lui-même.
- [ ] La frontière de la règle est **écrite et assertée**, parce que c'est là que le coût est : un scanner qui ne suit pas l'état de citation compte 380 backticks dans le pack et il n'y en a que 52 qui comptent. Les cas à trancher explicitement, chacun avec son témoin : une chaîne simple ouverte sur une ligne et fermée sur une autre (le corps d'un `awk '...'`, `lang.sh:176`), une substitution `$( ... )` qui ré-ouvre une citation à l'intérieur d'une chaîne double (`gate.sh:3081`), et un commentaire.
- [ ] La ligne « *Une règle écrite dans un prompt arrive au modèle telle qu'elle est écrite* » de `docs/frontiere-de-confiance.md` dit ce que la règle couvre après ce ticket, et **corrige l'asymétrie qu'elle décrit** : elle écrit que « les deux points d'entrée » portent `set -euo pipefail`, donc qu'un `$mot` de prose tue le run. Il y en a trois, et le troisième (`init.sh`) porte `set -uo pipefail` **sans `-e`**, à dessein et documenté à `init.sh:39`. Mesuré : sous `set -u` seul, un `$NOPE` dans un `cat <<BLOCK` écrit « unbound variable » sur stderr, fait rendre 1 au `cat`, et **le script continue**. Ce qui rattrape ça dans `init.sh` n'est pas errexit, c'est le `|| init__die` que chaque étape mutante porte.
- [ ] Une entrée de mutation par garantie livrée, avec le témoin appairé qui distingue « le test ment » de « la ligne porteuse a bougé ».

## Comments

- **Ouvert le 15/09/2026 par la sonde de frontière de confiance de [87]** (étape 5
  de la definition of done, posée *après* écriture parce que la règle livrée par
  [87] est précisément ce qui rendait la question mesurable). [87] a mis `init.sh`
  dans la zone des quatre règles de source ; la question suivante — *qu'est-ce que
  cette zone, une fois élargie, ne voit toujours pas ?* — a une réponse mesurée.

- **Ce qui est mesuré, sur un vrai run de l'installeur.** Une seule backtick
  dé-échappée dans `init__note` à `init.sh:375` (sur une **copie**) :
  - l'opérateur lit `·  is not on this PATH. Every session, review lens, retro
    and value gate is a \`claude\` process…` — le mot `claude` a disparu, exactement
    le trou de [61] ;
  - l'installeur sort en **0** ;
  - un seul `command not found` sur stderr, perdu dans un rapport de quarante
    lignes ;
  - et `layering_heredoc_prose`, tel que [87] vient de le livrer, est **vert** sur
    ce fichier : le défaut est dans un argument entre guillemets doubles, pas dans
    un corps de heredoc.

  Le mécanisme du silence est celui de [61], mot pour mot : une substitution qui
  échoue à l'intérieur d'un argument écrit sur stderr, rend une chaîne vide, et ne
  change pas le statut de la commande.

- **La taille de la surface, et pourquoi elle est plus petite qu'elle n'en a
  l'air.** Backticks échappées (`\``) sur des lignes non commentées, hors corps de
  heredoc — c'est-à-dire les endroits où l'échappement est porteur :

  | fichier | sites |
  |---|---|
  | `init.sh` | 30 |
  | `.claude/lib/forge.sh` | 12 |
  | `.claude/lib/capability.sh` | 6 |
  | `.claude/human-loop.sh` | 2 |
  | `.claude/lib/router.sh` | 2 |
  | **total** | **52** |

  Les centaines d'autres backticks du pack vivent dans des `printf '…'` **entre
  guillemets simples**, où le shell ne les lit pas : c'est la convention de fait
  du pack et c'est ce qui fait que ce ticket est une **règle** et pas une
  migration. Sondé dans les deux sens : un scanner suivant l'état de citation ne
  trouve **aucune backtick non échappée en contexte double** dans le pack livré —
  les trois lignes qu'il signale (`gate.sh:3081`, `lang.sh:176`, `lang.sh:178`)
  sont des faux positifs d'un scanner ligne-à-ligne, et sont le cahier des charges
  de la frontière à écrire.

- **Le coût réel est le scanner, pas la règle.** `layering_heredoc_prose` est
  facile parce qu'un heredoc a un délimiteur : on sait quand on est dedans. Ici il
  faut suivre `'`, `"`, `\` et `$( )` sur des chaînes qui traversent les lignes.
  Une règle qui se trompe dans ce suivi est pire que pas de règle : elle
  signalerait la forme qui corrige le défaut, et serait contournée plutôt
  qu'obéie. C'est pour ça que la frontière est une AC à part, avec ses témoins.

- **Ce que ce ticket ne fait pas.** Le résidu que [61] a nommé reste intact et
  s'élargit à `init.sh` : un `$mot` de prose qui désigne une variable **définie**
  (`$HOME`, `$LANG_ARTIFACT`) est substitué en silence, dans un heredoc comme dans
  une chaîne double, et ce qui sépare ça d'un fichier déposé est un relecteur. La
  ligne du tableau le porte déjà pour le reste du pack ; l'AC 4 y ajoute
  `init.sh`, où le filet est plus faible qu'ailleurs parce qu'il n'y a pas
  d'errexit.
