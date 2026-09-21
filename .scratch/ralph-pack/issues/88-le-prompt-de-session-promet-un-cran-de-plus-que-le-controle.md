# 88 — Le prompt de session promet un cran de plus que le contrôle qui le tient

**What to build:** Que chacune des règles de `loop_session_prompt` vienne du module qui la tient, comme les règles de langue viennent de `lang.sh` — à commencer par la phrase sur le tracker, qui dit `.scratch/` là où le désindexage fait `issues/`.

**Blocked by:** 86

**Write-surface:** `.claude/loop.sh`, `.claude/lib/tracker.sh`, `.claude/lib/tracker-local.sh`, `.claude/lib/gate.sh`, `test/loop-happy-path.bats`, `test/tracker-local.bats`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** resolved

- [x] La phrase du prompt sur le tracker est **produite par le module qui tient la promesse**, pas tapée dans le heredoc de `loop_session_prompt` — la forme est celle de `$(lang_session_rules)`, et le nom que la phrase donne est celui que le contrôle désindexe et restaure vraiment.
- [x] Un test lit la phrase du prompt et le périmètre du contrôle sur un run réel, et rougit si les deux divergent. Un test qui ne lirait que la phrase mesurerait la phrase.
- [x] Ce que la phrase **ne** promet pas est dit dans la phrase elle-même : `spec.md` et le reste de `.scratch/<feature>/` sont une zone morte nommée ([24] : *une zone qu'on ne peut pas fermer, on la nomme à chaque tour*), pas une garantie implicite.
- [x] Les deux autres règles tapées du prompt — la write-surface, le statut du ticket — sont passées au même crible : soit elles n'ont pas de liste à dériver et le prompt le dit, soit elles en ont une et elle est demandée. La réponse « pas de liste » est un résultat à écrire, pas un silence.
- [x] Une entrée de mutation par garantie livrée, avec le témoin appairé.
- [x] La ligne « Ne jamais stager ni commiter le tracker » de `docs/frontiere-de-confiance.md` dit ce que le prompt promet **et** ce que le contrôle couvre, maintenant que les deux ne sont plus la même phrase par accident.

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

- **Ce que [90] laisse sous ce ticket, livré le 15/09/2026.** Ce ticket sort de la
  prose d'un heredoc pour la faire **produire par un module** — donc elle va
  arriver sous la forme que [90] vient de garder, et pas sous celle que [61]
  gardait. `layering_quoted_prose` (cinquième règle de `test/layering.bats`, zone
  dérivée de [87], les 24 libs et les 3 points d'entrée) refuse toute backtick non
  échappée dans une **chaîne entre guillemets doubles** et dans un **mot non
  quoté**. Concrètement, pour une phrase rendue par `tracker_*` ou `gate_*` à la
  façon de `lang_session_rules` :
  - `printf '%s\n' "… the \`Status:\` field …"` est la forme correcte — backtick
    échappée ; `printf '%s\n' '… the `Status:` field …'` l'est aussi, et c'est la
    convention de fait du pack (des centaines de sites). Les deux sont plantées
    comme témoins appairés et ne sont signalées ni l'une ni l'autre.
  - Un heredoc **cité** (`<<'RULES'`) reste la seule forme qu'aucun paragraphe
    futur ne peut casser, et c'est ce que `router_prompt` fait depuis [61].
  - Ce qui reste **non tenu** et vaut pour la phrase de ce ticket : un `$mot` de
    prose qui désigne une variable **définie** est substitué en silence dans les
    deux formes. Un nom de champ du tracker écrit `$Status` arriverait vide sans
    un mot sur stderr.

- **Ce que [86] laisse sous ce ticket, livré le 18/09/2026, et il y a une
  contrainte dure dedans.** [86] livre le précédent que ce ticket généralise :
  deux fonctions publiques de `init.sh` rendent une phrase, et deux lecteurs la
  prennent au lieu de la retaper — `init_sealed_prose` demande
  `gate_sealed_paths` et rend « `Sealed paths: …` » pour le bloc `CLAUDE.md` ;
  `init_tracker_prose <backend> <feature>` rend « où vivent les tickets de ce
  projet » et est lue **par le `init__note` du rapport et par le heredoc du
  bloc**, avec un test qui compare la phrase imprimée et le paragraphe déposé
  octet pour octet, sans en garder de copie dans le test. Trois choses qui
  s'appliquent directement ici :
  - **La contrainte dure.** `init_tracker_prose` porte un `case` sur
    `TRACKER_BACKEND` — exactement la forme que le commentaire « contrainte de
    couche » ci-dessus prévoit pour `tracker_session_rule` sur le dispatcher. Le
    jour où ce ticket crée une fonction publique de `tracker.sh` qui dit *où
    vivent les tickets* par backend, **`init_tracker_prose` doit la consommer**
    au lieu de garder son `case`, sinon le pack a de nouveau deux rédactions du
    même fait — la faute que [86] vient de réparer, une couche plus bas.
    `init.sh` source les libs du pack et appelle déjà leurs recensements publics,
    donc rien ne s'y oppose ; ce qui s'y opposait est la write-surface de [86],
    qui ne portait pas `.claude/lib/tracker.sh`. Celle de ce ticket-ci la porte.
    Attention au sens de la phrase, elles ne disent pas le même fait :
    `init_tracker_prose` dit *où sont les tickets* (markdown sous
    `.scratch/<feature>/` ou issues d'une forge), la phrase du prompt dira *ce que
    la boucle désindexe et restaure*. Une fonction qui rend les deux serait une
    troisième frontière ; la consommation porte sur la moitié commune.
  - **Le piège de forme, mesuré en écrivant [86].** La convention de fait du pack
    — un format `printf '…'` en guillemets **simples**, où la backtick est de la
    prose que le shell ne lit jamais — a un coût que rien ne documentait : une
    **apostrophe** dans la phrase ferme la chaîne et casse le fichier au
    `bash -n`. C'est bruyant, donc sans danger, mais ça interdit « the loop's own
    state » dans une phrase écrite sous cette forme. Les deux sorties sont
    d'écrire la phrase sans apostrophe, ou de passer en guillemets doubles avec
    `\`` échappée. Les deux passent `layering_quoted_prose`.
  - **Le test qui vaut d'être copié.** Le côté « deux lecteurs d'une phrase » ne
    se teste pas en relisant la fonction : `test/install.bats` lit le paragraphe
    **dans le fichier déposé** et le cherche dans la sortie du processus, donc
    une fonction qui rendrait la phrase et ne serait pas appelée par l'un des
    deux rougit. C'est le même geste que le piège de test ci-dessus demande pour
    le périmètre : mesurer sur le produit, jamais sur le code qui l'aurait fait.

- **Livré le 21/09/2026.** Write-surface réellement touchée : `.claude/loop.sh`,
  `.claude/lib/tracker.sh`, `.claude/lib/tracker-local.sh`, `.claude/lib/gate.sh`,
  `test/loop-happy-path.bats`, `test/tracker-local.bats`, `test/gate.bats`,
  `test/mutate.sh`, `docs/frontiere-de-confiance.md` — **plus quatre chemins
  au-delà de la surface déclarée** : `.claude/lib/forge.sh`,
  `.claude/lib/tracker-github.sh`, `.claude/lib/tracker-gitlab.sh` et
  `test/tracker-remote.bats`. L'élargissement n'est pas un confort, il est
  **imposé par un test du pack** — voir « le dispatcher répond quand le backend ne
  répond pas » ci-dessous — et la consigne du ticket le prévoyait explicitement
  (*« c'est une write-surface à élargir ou un ticket à ouvrir, pas un silence »*).
  `init.sh` n'a **pas** été touché : voir la contrainte de [86] plus bas.

  **Ce que le code ne dit pas.**

  - **Trois producteurs et pas quatre, parce que deux règles sont un seul
    contrôle.** Le statut du ticket et le stagé du tracker étaient deux phrases
    tapées ; ce qui les tient est le **même** garde (`failures_protect_tracker`,
    qui demande `tracker_snapshot*`). Les séparer en deux producteurs aurait
    recréé l'accident que le ticket enlève — deux rédactions d'un fait. Elles
    sortent donc ensemble de `tracker_session_rule`. Le décompte du prompt passe
    de quatre règles tapées (dont une dérivée) à trois producteurs :
    `gate_session_rule`, `lang_session_rules`, `tracker_session_rule`.

  - **Le dispatcher répond quand le backend ne répond pas, et c'est une décision —
    mais aucun backend livré ne prend cette branche, et c'est un test qui l'a
    imposé.** `tracker_session_rule` est dispatché. La première version ne
    l'implémentait que sur `tracker-local.sh` et laissait les deux forges au
    repli, avec un ticket ouvert pour leur phrase ; **le premier `run.sh` complet
    l'a refusé** — `test/tracker-remote.bats` « both remote backends implement
    every operation the dispatcher routes » est un recensement dérivé de [18] qui
    lit les `tracker__dispatch <op>` de `tracker.sh` et exige que les **trois**
    backends livrés répondent. C'est la bonne règle et c'est le genre de trouvaille
    que ce dépôt cherche : le ticket a donc élargi sa write-surface plutôt que
    d'ouvrir un ticket, et le ticket n° 91 rédigé pendant la session a été
    supprimé avant tout commit — le numéro 91 est donc libre. Le repli **reste**, et il est toujours atteignable — un
    backend qu'un projet écrit lui-même est exactement le lecteur qui n'a pas
    encore écrit sa phrase — mais il n'est plus la réponse d'un backend livré. Il
    imprime **la moitié que l'interface doit sur tout backend depuis [73]** (instantané pris avant la session, ce qui a bougé remis) suivie
    de l'aveu que l'autre moitié est une phrase que ce backend ne rend pas. Deux
    raisons de ne pas composer cette seconde moitié dans le dispatcher à partir de
    `tracker_tickets_dir`, essayée et jetée : le dispatcher affirmerait que la
    boucle **désindexe** ce répertoire, ce que seul `tracker-local.sh` sait ; et
    la branche « il y a un répertoire et le backend ne dit rien » n'est atteignable
    par aucune configuration livrée, donc intestable. La ligne du dispatcher qui
    dit `does not implement` est jetée (`2>/dev/null`) : elle serait imprimée une
    fois par itération pendant toute une nuit.

  - **La write-surface n'a pas de liste à dériver, et c'est le résultat écrit que
    l'AC 4 demande.** Le périmètre est le ticket que le prompt porte déjà. Ce que
    `gate_session_rule` dérive à la place, c'est **le champ** que le lecteur
    demande vraiment au tracker : `GATE_SURFACE_FIELD`, lu par `gate_write_surface`
    et nommé par la phrase. Les deux listes que `gate.sh` tient sont délibérément
    hors du prompt : `gate_is_bookkeeping` est nommée par la phrase du tracker
    (c'est la même zone), et `gate_sealed_paths` est déjà rédigée une fois, par
    `init_sealed_prose` dans le bloc `CLAUDE.md` que l'installeur dépose ([86]).
    La retaper dans le prompt aurait été la troisième rédaction — exactement la
    faute que [86] venait de réparer. **Ce que ça laisse ouvert et qui n'est pas
    refermé ici** : une session d'un projet où `init.sh` n'a jamais tourné
    n'apprend les chemins scellés de nulle part. Ce n'était pas vrai non plus
    avant ce ticket, et c'est une question pour `init.sh`, pas pour le prompt.

  - **La contrainte dure de [86] ne se déclenche pas, et il faut le dire plutôt
    que de la laisser croire honorée.** [86] demandait : le jour où `tracker.sh`
    publie une phrase publique « où vivent les tickets » par backend,
    `init_tracker_prose` doit la consommer au lieu de garder son `case`.
    `tracker_session_rule` **ne dit pas ce fait-là** : elle dit ce que la boucle
    désindexe et remet, pas où vivent les tickets. Les deux phrases se recoupent
    sur un chemin (`.scratch/<feature>/issues/`) et divergent sur tout le reste —
    l'une parle à un opérateur qui installe, l'autre à une session qui va écrire,
    et sur une forge la première a un répertoire d'issues et la seconde n'a pas
    d'index du tout. Fabriquer une fonction qui rend les deux aurait créé la
    troisième frontière que [86] met en garde contre. **Donc `init.sh` garde son
    `case`, et la contrainte de [86] reste ouverte pour le ticket qui publiera
    vraiment « où vivent les tickets ».**

  - **Le test qui compte est le run, et il mesure les deux sens.**
    `test/loop-happy-path.bats` « the path the prompt names is the one the loop
    takes out of the index, and no more » : une session stage **un ticket et
    `spec.md`** dans l'index du dépôt principal (jamais celui du worktree, [13]),
    écrit ce qu'elle a stagé dans l'état du shim, et le test compare ce qui a
    quitté l'index avec le nom que la phrase du prompt a donné — extrait du prompt
    par `sed`, jamais relu du producteur. Les deux sens sont assertés : rien hors
    du nom ne quitte l'index, rien sous le nom n'y reste. Deux garde-fous de
    non-vacuité : la sonde doit avoir stagé quelque chose **des deux côtés** du
    nom, sinon le test échoue en le disant. La mutation
    « the de-index is wider than the name the prompt gives » est celle qui prouve
    que le test mesure le contrôle et pas la prose.

  - **Le test unitaire de `tracker-local.bats` ne mesure pas la phrase contre le
    périmètre** — ce serait le vacuous par construction que le ticket annonce. Il
    mesure autre chose : que le nom est *celui de ce backend* et bouge avec son
    stockage, et que le nom du backend local n'est pas prêté à un backend qui ne
    garde rien (`refute_output_contains ".scratch/demo/issues/"` sous `github`).

  - **Un global de pack de plus, hors du namespace `RALPH_*`** :
    `GATE_SURFACE_FIELD`. Assigné sans condition au `source`, donc conforme à la
    règle de [40]. Écrit dans [89], dont l'AC 2 veut que le **critère** du
    recensement soit dans le test : un critère écrit « les noms `RALPH_*` » ne le
    voit pas, ni `INIT_CLAUDE_OPEN`, ni `LOOP__FINDINGS`, ni
    `ROUTER__PINNED_SURFACE`.

  - **Un `DRIFTED` payé, et la leçon de harnais qu'il porte.** Ajouter
    `session_rule` à la liste des lectures de `tracker__dispatch` a déplacé
    l'ancre de l'entrée de mutation « 10 writing a receipt counts as writing the
    ticket », qui épingle cette case-list **entière**. Le `-n` de la famille
    `88 ` ne l'a pas vu — il ne regarde que les entrées filtrées — et le défaut
    est sorti au bout d'une heure de gate complet. **Éditer une ligne qu'une
    entrée d'un autre ticket épingle exige un `bash test/mutate.sh -n` sur tout
    le fichier**, qui coûte trente secondes. L'entrée a été ré-ancrée (la
    garantie sous test est inchangée : c'est toujours `emit_receipt` qu'elle
    retire) et repassée `ok`.

  - **`session_rule` est dans la liste des *lectures* de `tracker__dispatch`**,
    par le critère de [31] et pas par ce qu'elle fait aujourd'hui : une opération
    qui n'écrit aucun ticket n'a pas à entrer dans le registre de [13]. Ce
    n'est pas mutable séparément — l'opération ne prend pas d'argument, donc
    `tracker__note_write ""` ne écrit rien de toute façon — et c'est dit ici
    plutôt que couvert par une entrée qui serait VACUOUS.

  - **Ce qui n'est pas touché et le reste à dessein** : `router_prompt`
    (`router.sh`) porte sa propre règle « ne change pas le statut de ce ticket ».
    Ce n'est pas une seconde rédaction du même fait — ce que tient cette phrase-là
    est l'épinglage du drain ([68], [70]) et pas `failures_protect_tracker`, et
    elle vit déjà à côté de son contrôle. Elle dit d'ailleurs explicitement ce
    qu'elle **ne** tient pas, ce qui est la forme que ce ticket généralise.

  - **La phrase des deux forges, `forge_session_rule`.** Elle dit l'inverse de
    celle du backend local, et c'est pour ça qu'elle ne pouvait pas être la même :
    rien du tracker n'est dans ce dépôt, donc il n'y a **aucun index à tenir** et
    une règle « ne stage pas le tracker » n'y nommerait rien. Ce qu'elle nomme à
    la place est la seule zone de cet arbre qu'une session peut écrire ici — le
    sidecar de [77], `forge_sidecar_path`, demandé et jamais recomposé — et elle
    dit que rien ne le désindexe et que rien ne le remet. Le témoin est
    `test/tracker-remote.bats`, qui compare la phrase au chemin que **le backend**
    rend et non à une chaîne tapée dans le test.

  - **Ce que le test des forges ne mesure pas, dit plutôt que sous-entendu.** Le
    côté « rien ne quitte l'index » n'est pas sondé sur un run distant : c'est une
    négation, et le run qui la rendrait fausse est celui où quelque chose du
    tracker serait dans l'arbre — ce que `tracker_github_tickets_dir` refuse par
    construction. Ce qui est mesuré sur un run réel, c'est l'égalité du backend
    local (`test/loop-happy-path.bats`), et la mutation
    « a forge stops answering the session rule » fait rougir le recensement dérivé
    de [18] plutôt qu'une assertion de prose.
