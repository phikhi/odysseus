# 88 — Le prompt de session promet un cran de plus que le contrôle qui le tient

**What to build:** Que chacune des règles de `loop_session_prompt` vienne du module qui la tient, comme les règles de langue viennent de `lang.sh` — à commencer par la phrase sur le tracker, qui dit `.scratch/` là où le désindexage fait `issues/`.

**Blocked by:** 86

**Write-surface:** `.claude/loop.sh`, `.claude/lib/tracker.sh`, `.claude/lib/tracker-local.sh`, `.claude/lib/gate.sh`, `test/loop-happy-path.bats`, `test/tracker-local.bats`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] La phrase du prompt sur le tracker est **produite par le module qui tient la promesse**, pas tapée dans le heredoc de `loop_session_prompt` — la forme est celle de `$(lang_session_rules)`, et le nom que la phrase donne est celui que le contrôle désindexe et restaure vraiment.
- [ ] Un test lit la phrase du prompt et le périmètre du contrôle sur un run réel, et rougit si les deux divergent. Un test qui ne lirait que la phrase mesurerait la phrase.
- [ ] Ce que la phrase **ne** promet pas est dit dans la phrase elle-même : `spec.md` et le reste de `.scratch/<feature>/` sont une zone morte nommée ([24] : *une zone qu'on ne peut pas fermer, on la nomme à chaque tour*), pas une garantie implicite.
- [ ] Les deux autres règles tapées du prompt — la write-surface, le statut du ticket — sont passées au même crible : soit elles n'ont pas de liste à dériver et le prompt le dit, soit elles en ont une et elle est demandée. La réponse « pas de liste » est un résultat à écrire, pas un silence.
- [ ] Une entrée de mutation par garantie livrée, avec le témoin appairé.
- [ ] La ligne « Ne jamais stager ni commiter le tracker » de `docs/frontiere-de-confiance.md` dit ce que le prompt promet **et** ce que le contrôle couvre, maintenant que les deux ne sont plus la même phrase par accident.

## Comments

- **Ordre validé par Philippe le 14/09/2026** : **[87] → [86] → [88] → [89]**.
  Le critère est celui d'habitude — minimiser la reprise, jamais l'urgence. [87]
  devant parce qu'il ne touche que `test/` et qu'il pose le filet de source sous
  le heredoc de prose que [86] va réécrire ; [88] derrière [86] parce qu'il
  généralise une forme dont [86] livre le précédent ; [89] en dernier, sans arête.

- **Ouvert par la passe transversale du 14/09/2026** (`../passe-transversale-14-09.md`,
  §4). Sonde : `../sondes/passe-14-09/q3-le-prompt-dit-scratch-le-controle-fait-issues.bats`.

- **L'écart, lu et confirmé par le tableau.** Le prompt dit : « *Never stage or
  commit the tracker (`.scratch/`). It is the loop's own state, and a commit taken
  mid-iteration freezes it in a state that was never true.* » Ce qui le tient est
  `git -C "$root" reset -q -- "$(tracker_local__issues_relpath)"` dans
  `tracker_local_snapshot_moved` : **`issues/` et rien d'autre**. Le tableau porte
  déjà la vérité — *le désindexage de `issues/`* — donc la phrase du prompt promet
  un cran de plus que la ligne du tableau, et la différence est `spec.md`, que
  `gate_is_bookkeeping` (`.scratch/$FEATURE/*`) retire **et** du rapport du
  scope-guard **et** du rollback.

- **La règle que ce ticket applique est déjà écrite, par [17], au-dessus de la
  fonction qu'il modifie** : *« the sentence a session is asked to follow and the
  check that keeps it live in one file, so the prompt cannot go on promising a
  guarantee the day the check moves. It says "checked" only where it is. »* Elle a
  exactement deux applications dans tout le pack — `$(lang_session_rules)` ici, et
  `$(gate_sealed_paths)` dans `playthrough.sh`. Ce ticket en pose une troisième et
  généralise la forme ; c'est pour ça qu'il vient **après** [86], qui en livre une
  quatrième dans l'installeur : un précédent vaut mieux qu'un principe.

- **Quelle réparation, et la passe n'a pas tranché.** Élargir le désindexage à
  `.scratch/<feature>/` entier est probablement **faux** : `spec.md` est une zone
  morte nommée, le drain l'épingle depuis [68] (`router_pin` sur un `cksum`), et
  `gate_is_bookkeeping` l'exclut à dessein pour que `run.log` et les flux ne soient
  pas rapportés comme des écritures de session. Élargir le désindexage sans
  élargir la restauration donnerait une troisième frontière, ce qui est la faute
  que la passe du 03/08 a nommée (*deux contrôles qui se répartissent un ensemble
  doivent s'accorder sur ce qu'est un élément*). La direction par défaut est donc :
  **faire dire au prompt ce que le pack tient**, pas l'inverse — et si la décision
  est l'inverse, l'écrire ici avec ce qu'elle coûte aux trois contrôles.

- **Contrainte de couche.** `loop_session_prompt` vit dans `loop.sh`, au-dessus de
  `lib/` ; `lang_session_rules` est publique de `lang.sh`. La phrase du tracker
  appartient donc au dispatcher (`tracker.sh`) ou au backend (`tracker-local.sh`),
  et **pas** à `gate.sh` : le périmètre désindexé est celui du backend, et il n'y
  a pas de raison qu'il soit le même sur une forge, où il n'y a pas d'index du tout.
  Un `tracker_session_rule` sur le dispatcher, avec une réponse par backend, est la
  forme qui survit à [76]/[73]. `test/layering.bats` refusera un lib qui appelle
  `loop_` et un `__` de voisin : la fonction doit être **publique**.

- **Piège de heredoc.** Le prompt est un `cat <<PROMPT` non cité, et [61] a payé un
  ticket pour un backtick de prose au même endroit. Le texte actuel écrit déjà
  `\`.scratch/\`` échappé ; toute phrase déplacée dans un lib doit garder cet
  échappement ou être produite dans un heredoc cité. `test/layering.bats` tient
  cette règle sur `lib/*.sh` et `loop.sh` — donc ici, contrairement à [86]/[87],
  le filet existe déjà.

- **Piège de test.** Un test qui compare « la phrase » et « le périmètre » en
  lisant deux fois la **même** fonction est vacuous par construction. Le côté
  contrôle doit être mesuré sur un run : une session qui stage `spec.md` et une
  session qui stage un ticket, et l'assertion porte sur ce qui reste dans l'index
  après le retour de la garde — pas sur le code qui l'aurait fait.

- **Ce que le ticket suivant hérite.** Si la forme retenue est une fonction
  publique par module qui rend « la phrase que le prompt met, et que ce module
  tient », alors le recensement de ces fonctions est la question de [85] un étage
  plus haut : *quelle règle du prompt n'a pas de propriétaire ?* Ne pas la fermer
  ici, l'écrire.

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
