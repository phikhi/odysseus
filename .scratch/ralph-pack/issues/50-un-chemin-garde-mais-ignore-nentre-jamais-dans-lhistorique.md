# 50 — Un chemin gardé qu'un projet ignore est approuvé, puis jamais commité

**What to build:** Décider ce que le pack fait d'un chemin que le gate **approuve** et
que `git add` **refuse**, et le tenir. Le cas armé n'a rien d'exotique : un projet qui
`gitignore` un répertoire que son propre `GUARDED_PATHS` nomme. `gate_tree_snapshot`
le force dans l'arbre jugé — c'est le contrat de [24] — le scope-guard le juge et
l'approuve, puis `failures_make_durable` fait `git add` sans `-f`, que git refuse pour
un chemin ignoré. L'itération est **verte**, le ticket `resolved`, et le fichier
n'est pas dans l'historique. Le défaut par défaut du pack sur lui-même : un projet
qui ignore `.claude/` — la convention de tous les projets Claude Code — ne reçoit
jamais le code que la boucle lui livre.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/gate.sh`,
`.claude/lib/concurrency.sh`, `test/failures.bats`, `test/gate.bats`,
`test/concurrency.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] Un chemin gardé qu'un projet ignore, écrit par une itération verte et approuvé
      par le scope-guard, **arrive dans l'historique** — ou bien l'itération n'est pas
      verte. Pas les deux moitiés actuelles : approuvé *et* absent. *Première branche.
      `failures_make_durable` stage en `git add -A --force`, donc le commit durable
      passe par la lentille qui a servi à **juger** l'arbre.*
- [x] La décision est écrite avec son prix, pas seulement le correctif. `--force` sur
      les seuls chemins approuvés est la réponse courte, et il faut dire ce qu'elle
      engage : le commit durable se met à écrire dans l'historique du projet cible
      des chemins que ce projet a explicitement dits hors de son historique, sur la
      foi d'un `GUARDED_PATHS` qui est une clé du projet lui-même. Refuser le vert
      est la réponse symétrique, et elle refuse indéfiniment le seul ticket honnête
      dont la surface tombe dans la zone ignorée — la même impasse que [35] a déjà
      nommée pour `gate__nothing_delivered`. *Écrit dans la ligne « Ce que le commit
      durable d'une itération verte contient vraiment », avec les trois bornes du
      prix, les deux qui n'en sont pas, et la raison du refus de l'autre branche.*
- [x] Le `git reset` du même bloc et celui de `concurrency__refresh` sont relus sous
      la même question : ce qui n'a pas pu être stagé n'a pas non plus à être
      désindexé, et l'arbre principal doit refléter ce qui a réellement été commité.
      *Le vrai défaut était un cran avant le `git reset` : le `rm -f`. Voir la
      livraison.*
- [x] La ligne « Ce que le commit durable d'une itération verte contient vraiment »
      de `docs/frontiere-de-confiance.md` est réécrite avec ce qui tient réellement.
      Elle a été posée par [39] et dit aujourd'hui *nommé, pas commité*.

## Comments

- **Origine : livraison de [39], le 27/08/2026.** Trouvé en cherchant une observation
  pour la vérification que [39] venait d'ajouter (« ce que le gate a approuvé et qui
  n'est pas dans ce commit »), pas en cherchant ce défaut-ci. Le test qui le stage est
  dans le dépôt : `test/failures.bats`, « a path the gate approved and git would not
  stage is named, not dropped » — `GUARDED_PATHS=vendor`, `.gitignore` porte
  `vendor/`, la surface du ticket porte `vendor/*`. Résultat asserté aujourd'hui :
  `run_loop` réussit, `01-alpha` est `resolved`, la ligne de gap nomme
  `vendor/thing`, et `git ls-tree HEAD` ne le contient pas.

- **Ce que [39] a livré et ce qu'il a refusé de livrer.** Livré : la **vérification de
  résultat**. `failures_make_durable` ne se contente plus de lancer `git add` sous un
  `|| true` — il compare l'arbre qu'il s'apprête à commiter à l'arbre que le gate a
  jugé, netté contre la liste approuvée, et **nomme** chaque chemin manquant. Refusé :
  forcer. Ajouter `--force` change ce qu'une itération verte commite dans *tout*
  projet à `.gitignore` fourni, ce qui est une décision à prendre pour elle-même et
  pas en passant dans un ticket sur les noms de fichiers non-ASCII.

- **Pourquoi ce n'est pas seulement `vendor/`.** `GUARDED_PATHS` vaut `.claude` par
  défaut, et `.claude/settings.local.json` est ignoré par convention dans tous les
  projets Claude Code — c'est le cas armé de [24], mot pour mot. Un projet qui ignore
  `.claude/` en entier (ce que font des projets réels pour ne pas versionner leur
  configuration locale) reçoit donc une boucle qui juge le pack, approuve les
  éditions du pack, et ne les commite jamais. Sonder ce cas-là avant d'écrire : c'est
  lui qui décide si `--force` est un élargissement ou une réparation.

- **Le troisième forçage à ne pas oublier.** Ce que `gate_tree_snapshot` force dans
  l'arbre jugé n'est pas seulement `GUARDED_PATHS` : c'est aussi tout ce qu'une règle
  d'ignore écrite **pendant** l'itération vient de cacher ([30], `gate_newly_hidden`).
  Un fichier que la session a écrit puis caché par un `.gitignore` de son cru est donc
  jugé, potentiellement approuvé — et tombe exactement dans le même trou. Celui-là est
  moins innocent, et il vaut la peine de demander si le forcer dans l'historique est
  bien ce qu'on veut : la réponse peut différer des deux autres.

## Livraison, le 30/08/2026

**La décision : forcer.** `failures_make_durable` stage en `git add -A --force`, et
l'argument n'est pas « c'est la réponse courte » mais une **symétrie** : le commit
durable stage à travers la lentille par laquelle l'arbre a été *jugé*. Un chemin
ignoré ne peut être dans la liste approuvée que parce que `gate_tree_snapshot` l'y a
forcé, et il ne force que deux familles — `GUARDED_PATHS` ([24]) et ce qu'une règle
écrite pendant l'itération vient de cacher ([30]). Tout le reste de la zone ignorée a
été sauté par le `git add -A` ordinaire en tête de ce snapshot, n'est dans aucun arbre
d'ici, et **ne peut pas atteindre cette ligne**. Le `--force` n'élargit donc rien : il
rend cohérent un pack qui jugeait ces deux familles, les approuvait, les rollbackait
sur rouge, et sur vert — le seul verdict où le travail est censé survivre — ne faisait
rien.

**Ce que la sonde a changé dans la façon de poser la question.** Le ticket demandait
de sonder le cas par défaut avant d'écrire ; il est pire que ce que le ticket
décrivait. `sondes/ticket-50/p1-le-cas-par-defaut-du-pack-sur-lui-meme.bats`, P1a — un
projet qui ignore `.claude/`, `GUARDED_PATHS` au défaut, un ticket dont la surface est
`.claude/lib/thing.sh` :

    ralph: gate: 01-alpha: tests=green typecheck=green scope=green lang=green
    ralph: 01-alpha: .claude/lib/thing.sh was approved by the gate and could not be staged
    ralph: iteration 1: 01-alpha -> resolved

Pas de ligne `committed`, pas de ligne `folded onto the branch`. Le seul chemin changé
étant refusé, l'arbre reconstruit **égalait celui de `HEAD`**, le retour anticipé
« tout ce que le gate a approuvé est déjà dans HEAD » tirait, et il n'y avait aucun
commit du tout — ni fold. Le pack ne pouvait pas se livrer à lui-même, et ce n'est pas
une configuration exotique : c'est la convention de tout projet Claude Code.

**La famille de [30] tranche dans le même sens, et plus fort.** P1b : une session
écrit `build/out.txt` puis ajoute `build/` au `.gitignore`, tous deux dans sa surface.
Vert, `resolved`, la règle commitée et le fichier absent. Sans le forçage, une session
s'achète un faux livré **en deux lignes**, ce qui est plus délibéré que le cas gardé.
Forcer y rend exactement ce qui serait arrivé sans la règle de la session — c'est le
miroir de [30] : « une session ne peut pas élargir l'angle mort dans lequel elle est
jugée » devient « une session ne peut pas changer ce que son itération commite en
écrivant une règle d'ignore ». Le ticket demandait si la réponse pouvait différer pour
cette famille ; elle ne diffère pas, et la raison de forcer y est meilleure.

**Le troisième AC visait le `git reset` et le vrai défaut était un cran avant, dans le
`rm -f`.** `concurrency__refresh` ne posait qu'une question — ce chemin est-il dans
`HEAD` — et lisait « non » comme « l'itération l'a supprimé ». Un chemin que le commit
venait de dire irrecevable répond exactement comme une suppression. Sondé
(`sondes/ticket-50/p2-…`) : le `.claude/cache/keep.txt` de l'arbre principal est
supprimé, et `rmdir -p` emporte `.claude/cache/` avec lui — un fichier qu'aucun run
n'avait jamais commité, détruit par le run qui venait d'annoncer qu'il ne pouvait pas
le commiter. La question est maintenant posée contre le **tip d'avant le fold** : ce
que le fold a retiré de la branche y était il y a un instant, et ce qui n'était
d'aucun côté est laissé intact — dans l'arbre **et** dans l'index, un
`git reset -- <chemin>` désindexant l'édition d'un humain aussi sûrement qu'un `rm` la
supprime.

**Le `--force` est double et les deux moitiés sont une seule décision.** Le second
`git add` — celui qui remet le vrai index d'aplomb après le commit — devait le
recevoir aussi : un index qui ne peut pas prendre le chemin que le commit vient de
prendre décrit ce chemin comme **supprimé**, c'est-à-dire exactement l'état que ce
bloc existe pour éviter, réintroduit en réparant l'autre bout. Vérifié à la main en
retirant le seul second `--force` : `git diff --cached` rend `vendor/thing`.

**La ligne de gap de [39] lit maintenant deux choses au lieu d'une, et c'est une
réparation et pas un ajout.** Elle nettait le **résultat** contre la liste approuvée.
Le résultat seul accuse la suite de tests du projet : `TEST_CMD` tourne après que
l'arbre a été jugé, donc un fichier livré qu'elle réécrit diffère de l'arbre jugé tout
en étant dans le commit avec des octets plus récents — une trouvaille, mais celle de
`gate_unjudged_changes`, qui la nomme déjà à chaque itération et à qui le pack refuse
explicitement d'en faire un verdict. Le **statut** seul accuse un chemin que la
session a supprimé d'un arbre jamais commité, ce que [39] avait raison de refuser. Les
deux ensemble disent la seule chose que cette ligne porte. Deux tests neufs tiennent
les deux moitiés, et deux entrées de mutation les retirent chacune séparément.

### Écarts et pièges

- **La write-surface du ticket ne contenait pas `.claude/lib/concurrency.sh` alors que
  son troisième AC nomme `concurrency__refresh`.** Ajoutée, avec `test/concurrency.bats`.
  Contradiction du ticket, pas du livrable — mais elle aurait fait rougir le
  scope-guard sur une itération honnête si la boucle avait pris ce ticket elle-même.
- **La sonde P2 cesse d'être une sonde une fois le forçage livré**, et c'est la forme
  de faux vert que ce dépôt collectionne : après le `--force`, `.claude/cache/keep.txt`
  est **commité**, donc `checkout-index` l'écrit et l'assertion « le fichier existe
  encore » passe sans que le garde de `concurrency__refresh` ait quoi que ce soit à
  voir avec ça. Le test livré est donc au **module** — la première rédaction passait
  des deux côtés du correctif. Il couvre les trois réponses de la partition (sur la
  branche maintenant, sur la branche il y a un instant, d'aucun côté), parce que la
  trouvaille est qu'il y en a trois et que la marche n'en connaissait que deux.
- **La suppression livrée n'avait aucun test de bout en bout avant ce ticket.** C'est
  par là que la marche a pu lire « pas dans HEAD » comme « supprimé » pour tout le
  monde. `a path the iteration deleted goes out of the tree the run was started in`
  comble ça, et c'est aussi le seul témoin de l'argument `$tip` au site d'appel.
- **Un premier jet des deux entrées de mutation de [39] est sorti VACUOUS sur un test
  sain, pour une raison purement mécanique** : recalibrées en rejoignant la liste en
  un mot (`$(printf '%s' "$changed" | tr '\n' ' ')`), or **ce join est un no-op sur une
  liste à un seul élément** — `$changed` n'a pas de saut de ligne final, et le test
  module qui nomme cette entrée ne change qu'un chemin. Les deux sont revenues à la
  forme d'origine (remplacer la boucle par un `git add -- $changed` qui découpe en
  mots), et le commentaire de `failures.sh` a été déplacé **au-dessus** de la boucle
  pour que le corps reste une forme ancrable. À retenir : une mutation « qui applique »
  n'est pas une mutation qui retire quelque chose.
- **Ce que le ticket suivant hérite** : le commit durable écrit désormais dans
  l'historique du projet des chemins que ce projet ignore. Contrainte écrite dans [19]
  (l'installeur provisionne le `.gitignore` et doit dire ce que ça implique), et notes
  dans [24], [30] et [39].
- **Trouvé en passant, pas réparé ici** : `concurrency__replay` interroge
  `git ls-tree "$commit^{tree}" -- "$path"` **sans `:(literal)`**, donc un chemin livré
  nommé `src/zone[1].txt` ne matche rien et le fold le **retire** de l'arbre replayé.
  Famille de [33], visible seulement au-dessus de `MAX_PARALLEL=1`, hors de la surface
  de ce ticket : c'est [54].
