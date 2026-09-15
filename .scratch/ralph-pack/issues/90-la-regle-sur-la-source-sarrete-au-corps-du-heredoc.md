# 90 — La règle sur la source s'arrête au corps du heredoc, et la prose du pack est surtout ailleurs

**What to build:** Que la règle de [61] couvre la forme sous laquelle le pack écrit réellement le plus de prose — une chaîne entre guillemets doubles — et pas seulement le corps d'un heredoc non cité.

**Blocked by:** None

**Write-surface:** `test/layering.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`
— **tenue sans écart** : rien de `.claude/**`, rien de `init.sh`. C'était une règle
à écrire et pas une migration, et la sonde préalable le disait (aucune backtick non
échappée en contexte double dans le pack livré) ; l'empreinte du template de la suite
n'est donc pas périmée par ce ticket.

**Status:** resolved

- [x] Une règle de `test/layering.bats` lit la **source livrée** et refuse une backtick non échappée à l'intérieur d'une chaîne entre **guillemets doubles** (et d'un mot non quoté), comme `layering_heredoc_prose` le fait pour le corps d'un heredoc non cité. La zone est celle que [87] dérive : les vingt-quatre libs et les trois points d'entrée, `init.sh` compris.
- [x] Les deux **témoins appairés** sont plantés à côté de la violation, et ce sont les deux formes qui corrigent le défaut : la backtick échappée (`\``) dans une chaîne double, et la même phrase avec les mêmes backticks dans une chaîne **simple**, où la backtick est de la prose que le shell ne lit jamais. Une règle qui signalerait l'une des deux signalerait les deux formes qui la réparent — c'est l'argument que `layering_heredoc_prose` porte déjà pour lui-même.
- [x] La frontière de la règle est **écrite et assertée**, parce que c'est là que le coût est : un scanner qui ne suit pas l'état de citation compte 380 backticks dans le pack et il n'y en a que 52 qui comptent. Les cas à trancher explicitement, chacun avec son témoin : une chaîne simple ouverte sur une ligne et fermée sur une autre (le corps d'un `awk '...'`, `lang.sh:176`), une substitution `$( ... )` qui ré-ouvre une citation à l'intérieur d'une chaîne double (`gate.sh:3081`), et un commentaire.
- [x] La ligne « *Une règle écrite dans un prompt arrive au modèle telle qu'elle est écrite* » de `docs/frontiere-de-confiance.md` dit ce que la règle couvre après ce ticket, et **corrige l'asymétrie qu'elle décrit** : elle écrit que « les deux points d'entrée » portent `set -euo pipefail`, donc qu'un `$mot` de prose tue le run. Il y en a trois, et le troisième (`init.sh`) porte `set -uo pipefail` **sans `-e`**, à dessein et documenté à `init.sh:39`. Mesuré : sous `set -u` seul, un `$NOPE` dans un `cat <<BLOCK` écrit « unbound variable » sur stderr, fait rendre 1 au `cat`, et **le script continue**. Ce qui rattrape ça dans `init.sh` n'est pas errexit, c'est le `|| init__die` que chaque étape mutante porte.
- [x] Une entrée de mutation par garantie livrée, avec le témoin appairé qui distingue « le test ment » de « la ligne porteuse a bougé ».

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

- **Ordre validé par Philippe le 15/09/2026** : **[90] → [86] → [88] → [89]**.
  [87] est livré (`726e62c`) et a ouvert [90] en route. La place retenue pour
  [90] est **devant [86]**, par le critère habituel — minimiser la reprise,
  jamais l'urgence — et c'est mot pour mot l'argument qui avait mis [87] devant
  [86] : l'AC 4 de [86] veut que le paragraphe du tracker soit **la même phrase**
  que celle que `init_preflight` imprime à la console, or cette phrase-là vit dans
  un `init__note "…"`, une chaîne entre guillemets doubles que [87] ne garde pas
  et que [90] garde. Livré devant, [90] est le filet sous cette moitié-là de la
  réécriture ; livré derrière, il constate après coup et peut coûter une seconde
  passe sur `init.sh`. [88] derrière [86] parce qu'il généralise une forme dont
  [86] livre le précédent ; [89] en dernier, sans arête.

## Livré le 15/09/2026 — `6f2a077`

- **Ce qui est livré, en une phrase.** `layering_quoted_prose`, cinquième règle de
  `test/layering.bats`, sur la zone dérivée par [87] (24 libs, 3 points d'entrée) :
  toute backtick non échappée dans une chaîne entre **guillemets doubles** ou dans
  un **mot non quoté** est un constat. Gates : `run.sh` **962 / 0 / 6 skips**
  opt-in (961 avant, +1 test), `mutate.sh` **993 / 0** (983 avant, +10 entrées).

- **La décision qui portait tout le ticket : la frontière est une garantie, pas
  une précaution.** Un heredoc a un délimiteur ; une chaîne n'en a pas. Le scanner
  livré est une machine à états qui suit `'`, `"`, `\` et `$( )` **d'une ligne à
  l'autre**, saute les commentaires et les corps de heredoc. Les quatre formes de
  la frontière sont plantées **avec une vraie violation de l'autre côté** — perdre
  l'état est alors un test rouge, jamais un silence :
  - un `awk '…'` ouvert sur une ligne et fermé sur une autre (`lang.sh:176`) ;
  - un `$( … )` qui ré-ouvre une citation dans une chaîne double (`gate.sh:3081`) ;
  - un commentaire, dont la backtick est de la prose et dont l'apostrophe n'ouvre
    rien ;
  - un corps de heredoc, qui appartient à la règle de [61] et est sauté ici.

- **Ce que les mutations mesurent, et c'est là que le ticket a gagné sa confiance :
  quatre des dix entrées ont pour témoin le pack livré lui-même.** Retirer une
  pièce de la machine à états et relancer le scanner sur les 27 fichiers :
  l'échappement → **42** constats, le suivi des guillemets simples → **185**, les
  commentaires → **1566**, les corps de heredoc → **28**, l'état qui ne survit pas
  à la ligne → **2** (exactement `lang.sh:176` et `:178`), le `$( )` qui ne ré-ouvre
  pas dans une chaîne double → **3** (`gate.sh:3081`, `failures.sh:1406`,
  `forge.sh:1492`). Tous faux. C'est la mesure du prix d'une règle approximative :
  elle ne rate pas, elle **hurle**, et elle se fait contourner.

- **Le piège d'assertion, et comment il est fermé.** Un constat est
  `fichier:ligne: <forme>` — jamais le texte de la ligne fautive —, donc la seule
  façon de refuser un témoin appairé est de le nommer **par son numéro de ligne**.
  Un offset compté à la main aurait dérivé au premier ajout dans une sonde. D'où
  `layering__probe_body`, qui lit le numéro dans le fichier planté par nom de
  fonction, et une assertion d'**ensemble** (les cinq lignes signalées dans
  `state.sh`, ni plus ni moins) plutôt qu'un simple compte : un compte attrape la
  règle qui signale tout, l'ensemble attrape en plus celle qui signalerait la copie
  échappée **à la place** de la nue. Une sonde disparue fait rougir avant, par
  `grep -c .` sur l'ensemble attendu.

- **Le constat quand la machine ne sait pas lire.** Un fichier dont la citation ne
  revient pas au sommet, ou dont un corps de heredoc ne rencontre jamais son
  délimiteur, donne un constat et pas une réponse propre — même raison que le
  `!`-préfixe de [87] : un scanner désynchronisé se lirait sinon exactement comme
  un pack propre. Planté (`.claude/lib/unbalanced.sh`) et son entrée de mutation.

- **Disculpé avant d'écrire, et c'est ce qui a fait de ce ticket une règle et pas
  une migration** : aucune backtick non échappée en contexte double dans le pack
  livré. Les centaines d'autres vivent dans des `printf '…'` entre guillemets
  simples. Les trois « violations » qu'un scanner ligne à ligne signale sont le
  cahier des charges de la frontière, pas des défauts.

- **Ce qui reste non tenu, et s'élargit plutôt qu'il ne rétrécit.** Un `$mot` de
  prose qui désigne une variable **définie** (`$HOME`, `${LANG_ARTIFACT:-en}`) est
  substitué en silence dans une chaîne entre guillemets doubles exactement comme
  dans un heredoc. Aucun propriétaire. Et un `$( … )` écrit dans de la prose est du
  code légitime que cette règle ne signale pas — c'est voulu : la classe de défaut
  est « du markdown lu comme du shell », et une backtick s'écrit par accident là où
  un `$( )` ne s'écrit pas.

- **Frontière de confiance, question posée avant d'écrire.** Ce qui tient cette
  règle est un test qui lit l'arbre de travail — donc une zone qu'une session
  écrit, `test/` n'étant pas dans `gate_sealed_paths`. Ce qui l'y garde est le
  contrôle de write-surface, qui vaut pour `test/**` comme pour le reste : retirer
  la règle demande de déclarer `test/layering.bats`, et un humain le lit. C'est la
  position de [87], inchangée et pas élargie par ce ticket — mais elle vaut d'être
  écrite une fois de plus, parce que la règle livrée ici est *la seule chose* qui
  sépare la prose déposée dans un projet d'une substitution de commande silencieuse.

- **L'asymétrie corrigée, et ce n'est pas cosmétique.** `docs/frontiere-de-confiance.md`
  et le commentaire de `layering_heredoc_prose` disaient tous deux que « les deux
  points d'entrée » portent `set -euo pipefail`, donc qu'un `$mot` de prose tue le
  run. Il y en a **trois**, et `init.sh` porte `set -uo pipefail` **sans `-e`**, à
  dessein et écrit à `init.sh:39`. Mesuré : sous `set -u` seul, un `$NOPE` dans un
  `cat <<BLOCK` écrit « unbound variable » sur stderr, fait rendre 1 au `cat`, et
  **le script continue**. Ce qui rattrape ça dans l'installeur est le `|| init__die`
  de chaque étape mutante, pas errexit — donc le filet du fichier le plus dense en
  prose du pack est le plus faible des trois.

- **Ce que [86] et [88] en héritent** est écrit dans leurs tickets (`89fe7f8`), pas
  seulement ici.
