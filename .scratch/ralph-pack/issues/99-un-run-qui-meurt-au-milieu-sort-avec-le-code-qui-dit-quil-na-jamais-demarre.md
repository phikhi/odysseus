# 99 — Un run qui meurt au milieu sort avec le code qui dit qu'il n'a jamais démarré

**What to build:** Que le garde de sortie de [72] convertisse aussi les codes qu'aucune des deux boucles n'a décidés. Il ne touche que `0` ; une mort sous `errexit` rend le statut de la commande qui a échoué, c'est-à-dire `1` pour à peu près tout ce qu'un shell lance — et `1` est documenté aux deux points d'entrée comme « could not start — another run holds this feature's tracker, or this working tree ». Le discriminant existe déjà et n'est pas consulté.

**Blocked by:** 98

**Write-surface:** `.claude/loop.sh`, `.claude/human-loop.sh`, `test/loop-happy-path.bats`, `test/human-loop.bats`, `test/mutate.sh`

**Status:** needs-triage

- [ ] `loop__on_exit` distingue « un code que cette boucle a décidé » de « un code que quelque chose en dessous a rendu ». Le discriminant existe : `LOOP__REACHED_THE_END` est posé à `1` juste avant chaque `exit` décidé (`loop.sh:2154`, `2218`) et n'est lu que dans la branche `rc = 0`. Un `rc` non nul avec `LOOP__REACHED_THE_END != 1` est un **7**, avec la phrase que [72] a déjà écrite.
- [ ] `human_loop__on_exit` reçoit la même décision. Il porte la même phrase — *« Only a `0` is touched, so no other exit of this file passes through anything »* — le même discriminant (`HUMAN_LOOP__REACHED_THE_END`), et le drain documente lui aussi `1` comme *« could not start — a run, or another human, holds this feature's tracker »* et `6` comme *« ended in the middle »*. **Forme de [55]/[56]/[57]** : un garde qui est une propriété d'un point d'entrée et pas du pack.
- [ ] Les deux tableaux de codes de sortie en tête de `loop.sh` et de `human-loop.sh` disent ce qui a changé. Aujourd'hui le commentaire de `loop__on_exit` énumère « 1, 2, 4, 5 et 6 » comme « every exit this loop decided on », ce qui est faux de `1` dès qu'`errexit` tire, et faux de `2` dès qu'un `grep` ou un `bash -n` échoue.
- [ ] **Ce que ça ne doit pas casser** : un `1` que la boucle a vraiment décidé (verrou refusé) reste un `1`. C'est le cas qui distingue une réparation d'un renommage, et c'est le test appairé obligatoire.
- [ ] `state_locks_release` continue de tourner dans tous les cas : c'est ce qui fait survivre le garde aux `trap … EXIT` que les deux verrous posent.
- [ ] Une entrée de mutation par garantie livrée, avec son témoin appairé. Attention : le commentaire de `loop.sh:2213` dit *« No mutation aims at this line: no test could go red for it »* à propos de `LOOP__REACHED_THE_END=1` sur le chemin `0` — ce ticket rend cette phrase fausse, puisque la même variable devient porteuse sur le chemin non nul.

## Comments

- **Ouvert par la passe transversale du 29/09/2026** (`../passe-transversale-29-09.md`, §2). Sonde : `../sondes/passe-29-09/q1-le-slot-du-pilote.bats`, cas **Q1f** (et **Q1d**, où le défaut est apparu mélangé à celui de [98]).

- **Mesuré.** Déclencheur : `loop__finish` finit par `rm -rf "$slot"`, et un `rm -rf` dont le répertoire se repeuple entre la marche et le `rmdir` rend ENOTEMPTY. Un survivant qui écrit dans le slot **sans `sleep`** un nom que `loop__finish` ne lit même pas donne :

      ralph: iteration 1: 01-plain -> resolved
      rm: …/tmp/ralph-slot.gU9nuj: Directory not empty

  …et rien d'autre. **exit 1**, la nuit finit après le premier ticket, les trois autres restent `ready-for-agent`, et rien n'a tourné derrière : ni `loop_journal_verify`, ni `retro_close`, ni le gate de valeur, ni la ligne « frontier empty ». À 10 ms (cas **Q1e**) la course n'est pas gagnée — c'est **une course**, pas une certitude, et c'est la seule chose qui la borne aujourd'hui.

- **Le défaut n'est pas le `rm`.** Le `rm` est ce qui rend la classe atteignable ; la classe est que `1` veut dire deux choses opposées. Le commentaire de `loop__on_exit` le dit lui-même, et sa portée est exacte : *« It converts, it does not rescue … **Only a `0` is touched**, so every exit this loop decided on — 1, 2, 4, 5 and 6 — passes through untouched. »* Le raisonnement n'a jamais été posé sur l'autre côté, y compris à la ligne 2213 où il l'est une fois de plus pour le seul `0`.

- **Qui lit ce code.** Un opérateur le matin, et le planificateur de [09] : `scheduler_outcome` et `loop__arm_successor` dépendent de `stop_code`, et un run mort sous `errexit` n'atteint ni l'un ni l'autre. Un `1` lu comme « un autre run tient le verrou » envoie chercher un verrou qui n'existe pas.

- **Ce que [98] change à ce ticket, écrit ici plutôt que découvert** : [98] fait probablement disparaître `$slot`, donc le `rm -rf` de ménage, donc le **déclencheur mesuré** — pas la classe. La mise en scène devra alors venir d'ailleurs (n'importe quelle commande du pilote qui échoue sous `errexit` fera l'affaire ; une fonction de lib à laquelle on fait rendre `1` dans un test est la forme la moins artificielle). C'est pour ça que ce ticket est **Blocked by: 98** : écrit avant, son test viserait un `rm` qui va disparaître.

- **Piste à instruire et pas solution** : rendre `7` pour tout `rc` non décidé est le geste évident, mais il faut vérifier les deux exits **signal** (`130`, `143`, posés par les traps INT/TERM du drain) et le `4`/`6` posés par un chemin qui passe par `continue` — un `exit` décidé passe forcément par la ligne qui arme `REACHED_THE_END`, et c'est la propriété à asserter plutôt qu'à supposer.
