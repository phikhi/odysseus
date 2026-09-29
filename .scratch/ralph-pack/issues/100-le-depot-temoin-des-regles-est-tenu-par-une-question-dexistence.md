# 100 — Le dépôt-témoin des règles est tenu par une question d'existence

**What to build:** Que le dépôt-témoin de [30] — le `mktemp -d "$TMPDIR/ralph-ignore.XXXXXX"` qu'une itération reçoit, et contre lequel tous les contrôles du gate posent la question « ces règles auraient-elles caché ce chemin ? » — soit tenu par son **contenu** et plus seulement par son **existence**. La ligne 40 du tableau raisonne trois fois sur sa destruction et jamais sur sa réécriture.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] Le **manifeste** du pin (`$pin/manifest`) n'est plus cru sur parole. `gate_newly_hidden` sort tout de suite sur `gate_frontier_moved >/dev/null || return 0`, qui est la différence symétrique entre le manifeste courant et celui du pin : un manifeste remis au digest courant fait dire « la frontière n'a pas bougé » et rend le forçage vide. Le digest est calculable par qui veut — `gate__digest` est `cksum <f | awk '{ print $1 "." $2 }'`.
- [ ] La **copie des règles** (`$pin/rules/**`) non plus : c'est contre elle que `git check-ignore` répond dans `gate_newly_hidden`, et c'est d'elle que `gate__frontier_restore` **remet** `.git/info/exclude` et l'attributes de [46]. Un pin réécrit ne remet donc pas la frontière, il installe celle de la session.
- [ ] Le contrôle existant n'est pas retiré : `gate__frontier_pin_broken` demande `[ -f "$pin/manifest" ] && [ -d "$pin/rules/.git" ]` et **détruire** le pin ferme bien le contrôle (sondé le 03/08 et écrit dans la ligne 40, [34] pour le tour d'après). Ce ticket ajoute la question du contenu, il ne remplace pas celle de l'existence.
- [ ] La **fenêtre**, et c'est la question qui décide de la forme. Le pin est pris par le pilote **par itération** (`loop.sh:2178`, `gate_frontier_pin`), donc après le sceau de [81] et hors de ses trois racines (`loop.sh:1865`) — [83] dit pourquoi ça ne peut pas venir du pilote. Mais le pack **écrit** dans le pin pendant l'itération (`gate__frontier_restore` y lit, `ledger-seen` y est mis à jour), donc l'argument « rien n'écrit là pendant la fenêtre » de [83] doit être vérifié avant d'être réutilisé, pas recopié.
- [ ] La ligne 40 du tableau est réécrite. Elle porte aujourd'hui, sur le témoin, uniquement la phrase de destruction : *« Le témoin lui-même vit dans `$TMPDIR` : une session qui le détruit ne rouvre pas le trou, elle ferme le contrôle … »*
- [ ] Témoin appairé et forge faite **par la session elle-même** (pas besoin de survivant : la session est dans la fenêtre, et tout se joue avant le gate). Une entrée de mutation par garantie livrée.

## Comments

- **Ouvert par la passe transversale du 29/09/2026** (`../passe-transversale-29-09.md`, §4). Sonde : `../sondes/passe-29-09/q5-le-temoin-des-regles-recrit.bats`.

- **Mesuré**, `01-alpha` (write-surface `src/alpha.txt`), la session appendant `src/backdoor.txt` au `.git/info/exclude` **partagé** du dépôt principal et écrivant derrière la règle :
  - **témoin appairé, pin intact** : `scope red`, deux constats — *« moved the ignore frontier in .git/info/exclude, which decides what every check here can see — no write-surface may cover it (put back) »* et *« wrote src/backdoor.txt, outside the declared write-surface »* — puis `scope overflow on 01-alpha: internal`, `rolled back 2 path(s) the session touched`, deux itérations, et **la règle ne survit pas au run** ;
  - **le même geste plus la réécriture du pin** (la même règle appendue à `$pin/rules/.git/info/exclude`, et la ligne `dir<TAB>.git/info/exclude` du manifeste remise au digest courant) : `tests=green typecheck=green scope=green lang=green`, **une** itération, ticket `resolved`, et **la règle survit au run**.
  - La seule trace dans le second cas est la ligne de zone de [24] — *« nothing in this gate judged 1 ignored path(s): src/backdoor.txt »* — que le pack imprime à chaque itération pour chaque chemin ignoré, c'est-à-dire la ligne qu'un lecteur du matin apprend à sauter.

- **Ce que ça achète dépasse l'itération.** La ligne 40 écrit que l'élargissement qui survit à un run est le **blanchiment en deux coups** que [34] a refermé, et elle ne l'admet que pour un run **tué** : *« un run tué ne passe par aucune de ces trois portes, donc son élargissement survit au run — le témoin meurt avec lui dans `$TMPDIR` et le run suivant épingle la frontière élargie. Rien dans le pack ne peut le refermer. »* La sonde y arrive sans tuer personne, sur un run qui sort en **0**.

- **La réparation est peut-être un appel de plus.** `gate__frontier_pin_broken` interroge déjà `gate_witness_moved "$common"` pour le répertoire témoin **du run**. Ce qui manque est la même question posée du pin, et l'obstacle n'est pas la technique mais la place : le sceau vit dans une variable du **pilote** et le pin naît après lui, donc le recensement doit être pris par l'itération, dans sa propre mémoire, comme `retro_hold_state`. Le commentaire de `gate__frontier_pin_broken` raconte déjà cette histoire une fois — *« And "these" was four names typed out here until [81], where the directory held nine »* — pour l'autre répertoire.

- **Angle à ne pas confondre** : `ralph-ignore.*` est publié par `gate_tmp_names` comme les seize autres globs, et ce n'est pas le défaut. Le défaut est qu'aucune question n'est posée sur le contenu ; la publication du glob est délibérée depuis [62] et un installeur en dépend.
