# 21 — Protéger le tracker des écritures de session

**What to build:** Le tracker est la seule autorité d'état du système, et une session peut aujourd'hui l'éditer sans que rien ne le voie. Rendre cette écriture **détectable et annulable**, et faire lire au scope-guard la write-surface telle qu'elle était au démarrage de la session — pas telle qu'elle est au moment du gate.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/gate.sh`, `.claude/loop.sh`, `test/canary.bats`, `test/failures.bats`, `test/helpers/assert.bash`, `test/mutate.sh`

**Status:** resolved

- [x] Toute écriture d'une session dans `.scratch/<feature>/issues/**` est détectée, **avant** que le gate ne lise quoi que ce soit du tracker.
- [x] Une modification d'un ticket existant est annulée (restaurée depuis le snapshot pré-session), et une itération qui a réécrit le tracker ne peut pas être verte.
- [x] Le scope-guard juge la session contre la write-surface qui était déclarée **au moment du spawn**.
- [x] Un ticket créé par une session reste mis en quarantaine (livré par [07]) : la garantie est étendue des créations aux éditions.
- [x] Le test `skip` du canari (« a session cannot widen its own write-surface ») est levé.

## Comments

- **Faille vivante, trouvée en livrant [07] et reproduite.** Le scope-guard lit la write-surface **sur le disque, au moment du gate** (`gate_write_surface` → `tracker_field`), c'est-à-dire *après* la session. Or trois mécanismes s'accordent pour rendre une écriture de session dans le tracker invisible :

  1. `gate__drop_bookkeeping` écarte `.scratch/<feature>/` du diff jugé par le scope-guard ([05], à raison : le claim, le journal et le flux de session vivent là) ;
  2. le rollback de [07] exclut le même préfixe (à raison aussi : sans quoi le compteur `Failures:` retomberait à zéro à chaque tentative et rien ne serait jamais escaladé) ;
  3. la quarantaine de [07] ne compare que des **ids** : elle voit un ticket créé, pas un ticket modifié.

  Conséquence : une session qui réécrit la ligne `**Write-surface:**` de son propre ticket en `*` obtient un scope-guard **vert** sur n'importe quelle écriture. C'est un faux vert avec un mécanisme, pas un hasard — exactement ce que ce pack existe pour refuser. Variante de la même faille : une session qui met `Status: resolved` sur un *autre* ticket le fait sortir de la frontière définitivement, et le run le rapporte comme une nuit normale.

  **Reproduit** (une session qui écrit `src/alpha.txt`, `src/rogue.txt`, modifie `CONTEXT.md`, et remplace sa write-surface par `*`) :

  ```
  exit=0
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green
  statut: resolved
  rogue.txt encore là: OUI
  write-surface après le run: `*`
  ```

  Le test est dans `test/canary.bats`, marqué `skip` (« a session cannot widen its own write-surface ») et il porte les attentes d'après-correctif : scope rouge jugé contre la surface du spawn, édition annulée, rien de résolu. **Le lever est un critère d'acceptation de ce ticket.**

- **Ce qui protège aujourd'hui** : le prompt de session l'interdit explicitement, et [07] met en quarantaine les tickets *créés*. C'est tout. Une consigne de prompt non vérifiée n'est pas une garantie — c'est le constat qui a produit le scope-guard lui-même.

- **Piste de correctif** (à valider en l'implémentant) : un snapshot du seul répertoire `issues/` autour du spawn (`GIT_INDEX_FILE` jetable + `git add -A -- .scratch/<feature>/issues` + `write-tree`, bien moins cher qu'un parcours complet), comparé après la session. La fenêtre est propre : entre le snapshot pré-spawn et le retour de la session, la boucle n'écrit **rien** dans `issues/` — le claim est antérieur, le marquage, le `Failures:` et le journal sont postérieurs. Donc tout delta est l'œuvre de la session. Ajouts → quarantaine (déjà fait) ; modifications et suppressions → restauration depuis le snapshot, et l'itération ne peut pas être verte.

- **Ordre** : ce ticket n'est pas bloqué, et il porte un faux vert. Il passe donc devant [20] et [06] si le critère « aucun faux vert » reste prioritaire.

- **Quatrième variante de la même frontière, vérifiée le 28/07/2026 : sur le chemin **vert**, le commit du tracker par une session reste.** Sonde : une session qui écrit sa write-surface puis `git add -A && git commit` obtient `exit 0`, ticket `resolved`, et **deux commits touchant le ticket** dans l'historique du projet cible, où il figure à l'état `claimed` — « un état qui n'a jamais été vrai », exactement ce qu'annonçait [03]. Sur un échec, le `reset --mixed` de [07] le défait ; sur un succès, rien. Asymétrique et non vérifié. À traiter avec le reste de ce ticket : le contrôle proposé (delta de `issues/` autour du spawn) le voit aussi, puisqu'un commit de la session laisse le fichier modifié dans l'arbre.

  **Cette dernière phrase était fausse, et c'est la première chose que la livraison a corrigée.** Un commit ne modifie pas l'arbre de travail : les deux snapshots — pris par `git add -A` + `write-tree`, donc sur l'arbre de travail et non sur `HEAD` — sont *identiques* de part et d'autre d'un `git add -A && git commit`, et le delta de `issues/` ne voit rien. Le contrôle de detection et le commit sur vert sont deux problèmes distincts, réglés par deux mécanismes distincts (voir la livraison).

---

## Livraison (28/07/2026)

- **Le contrôle est un tree object de `issues/` pris autour du spawn, pas un nouveau parcours d'arbre.** `gate_tree_snapshot` accepte désormais un pathspec ; `failures_tracker_tree` l'appelle sur `.scratch/<FEATURE>/issues`. Le cas normal coûte **une comparaison de sha** — deux hashes égaux et la fonction rend la main. La fenêtre est bien propre, comme la piste le supposait : entre le snapshot et le retour de la session, la boucle n'écrit rien sous `issues/` (le claim est antérieur ; le marquage, `Failures:` et le journal sont postérieurs).

- **`--force` sur le snapshot, et c'est une sonde qui l'a décidé.** Un `git add -A -- <path>` ordinaire respecte le `.gitignore` du projet cible. Or beaucoup de projets gitignorent leur répertoire de scratch — et [19] provisionne précisément ça pour `run.log` et les flux. Sans `--force`, les deux snapshots seraient vides, le delta toujours nul, et l'exploit reviendrait **sans que rien ne dise que le garde a renoncé**. Le test `a project that keeps its scratch out of git is guarded all the same` pin le comportement, et la mutation correspondante retire le `--force`. Symétriquement, le snapshot *sans* pathspec ne force pas : y faire entrer la sortie de build ignorée d'un projet ferait ressembler chaque itération à un débordement.

- **AC3 est portée par la restauration, pas par un paramètre passé au gate.** Restaurer `issues/` avant `gate_run` rend le disque conforme au spawn, ce qui est **plus fort** que passer une seule surface : `gate__surface_owner` lit aussi les surfaces des *autres* tickets pour distinguer un débordement contractuel d'une écriture parasite, et celles-là sont couvertes du même coup. C'est aussi pourquoi un échec de restauration doit rougir : la garantie repose sur elle.

- **La restauration remet les tickets modifiés et laisse les tickets créés.** Les deux contrôles devaient s'accorder explicitement : restaurer tout le répertoire aurait *supprimé* un ticket créé, donc détruit la seule copie de ce qu'il demandait, alors que [07] a décidé qu'une création part en quarantaine et qu'un humain tranche. Une addition seule n'est donc **pas** un échec (l'itération peut être `resolved`, comme [07] l'avait posé) ; une modification ou une suppression l'est. Le test `a ticket the session created is quarantined, not quietly restored away` tient cette frontière, et la mutation qui fait tomber le cas `A` dans le cas général la fait rougir. C'est le troisième corollaire ajouté à `docs/frontiere-de-confiance.md`.

- **Un outcome de journal à part, `tracker-write`, classé comme `gate-red`.** Le comportement est identique (retry-N en session fraîche, puis `failed-impl`) mais le journal dit ce qui s'est passé : dans le scénario livré, les trois branches du gate sont **vertes** et le tracker est la seule chose fautive. Un `gate-red` dans le reçu enverrait un humain lire des tests qui passent. `failures_classify` traite `gate-red | tracker-write` dans le même cas, donc un débordement contractuel simultané escalade toujours directement.

- **Le commit sur vert, réglé séparément.** `failures_make_durable` reçoit maintenant le `HEAD` pré-spawn et, si la session a commité, fait `git reset --mixed` dessus avant de rebâtir le commit à partir des seuls chemins que le scope-guard a approuvés. Symétrique du chemin rouge ([07]), même compromis assumé sur l'index. Gain concret mesuré par le canari : l'itération 2 y fait `git add -A && git commit` depuis toujours, et **personne ne l'assertait** — tout `.scratch/` partait dans l'historique du projet cible, flux de session compris. Deux assertions nouvelles le refusent (`log --name-only <pre-run>..HEAD -- .scratch` vide, et le sujet du commit de la session absent).

- **Deux assertions du canari étaient vacuous, trouvées en y touchant.** Dans « three iterations against a hostile world », `refute_output_contains "scope=red"` et `refute_output_contains "gate-red"` venaient **après** un `run bash -c "grep -c …"` : `$output` valait `"3"`, qui ne contient jamais `scope=red`. Deux refutations qui ne pouvaient pas échouer, dans le fichier dont le métier est de refuser les faux verts. La sortie du run est désormais gardée dans `loop_output` et restaurée dans `output` avant les refutations. À connaître pour tout test qui enchaîne des `run` : **chaque `run` écrase `$output`**, et une assertion négative qui vise la mauvaise sortie passe toujours.

- **Écart de write-surface.** Déclarée à l'ouverture : `failures.sh`, `gate.sh`, `test/canary.bats`, `test/failures.bats`. Réellement écrite : + `loop.sh` (un contrôle que la boucle n'appelle pas est du code mort : le snapshot pré-spawn, l'appel de la protection avant le gate, l'outcome, le `pre` passé au commit durable, et la règle du prompt qui dit désormais qu'elle est vérifiée), + `test/helpers/assert.bash` (`refute_file_contains`, qui manquait — et qui exige que le fichier existe, sinon un test assertant sur un fichier absent passerait pour la mauvaise raison), + `test/mutate.sh` (le gate de mutation). La ligne `Write-surface:` ci-dessus a été corrigée pour dire la vérité, comme l'ont fait [01], [03], [05] et [07].

- **Ce que la protection ne couvre pas, et pourquoi elle ne peut pas.** Elle s'arrête à `issues/`. Élargir à tout `.scratch/<FEATURE>/` est **impossible** avec ce mécanisme : le flux `.session.*.jsonl` s'écrit *pendant* la fenêtre surveillée, donc chaque itération aurait un delta légitime énorme. Restent donc non gardés — sondé et vérifié le 28/07/2026, une session qui fait `git add -A` laisse `.run.lock/pid`, `.run.lock/since`, `.session.<pid>.jsonl`, son `.prompt` et son `.tokens` **dans l'index du projet cible**, prêts à partir avec le prochain commit d'un humain :

  - `run.log` — une session peut le réécrire, et c'est [10] qui va le lire pour fabriquer le reçu d'audit ;
  - `.run.lock/` — le supprimer laisserait un second run démarrer ([12]/[13]) ;
  - les flux de session — des dizaines de Mo dans l'index.

  Le propriétaire naturel du dernier point est le `.gitignore` de [19] : gitignoré, `git add -A` ne le stage pas du tout. Le test `a tracker the session staged does not stay staged` **pin l'état actuel des deux côtés** (le ticket désindexé, le flux encore stagé), pour que le jour où [19] le provisionne, la ligne dise ce qui a changé. Contraintes écrites dans [10], [12], [13], [19], et lignes ajoutées au tableau de `docs/frontiere-de-confiance.md`.

- **Le backend distant n'a aucune protection, et rien dans le code ne le dit.** Le contrôle est un chemin de fichiers plus git — intrinsèquement le backend `local`. Sur un backend distant ([18]), le répertoire n'existe pas, les deux snapshots sont vides, et la protection est **transparente** : pas d'erreur, pas de log, pas de garde. C'est exactement le corollaire « un contrôle qui exclut une zone doit dire qui garde cette zone ». Contrainte consignée dans [18].

- **Deux gardes non testées, assumées comme telles.** Le pathspec passé à `git diff-tree` est redondant avec un snapshot déjà borné aux tickets — il reste parce que cette boucle **écrase des fichiers**, et qu'elle ne doit jamais être à un mauvais snapshot d'écrire hors du tracker. Et un fichier créé par une session dans `issues/` qui ne finit pas en `.md` n'est vu ni par la quarantaine (qui liste `*.md`) ni par la restauration (c'est une addition) : inerte, parce que `tracker_local_ids` et `tracker_local_frontier` ne globent que `*.md` — mais inerte n'est pas gardé.

- **Sonde hostile passée : une session qui fait `rm -rf` sur `issues/`.** C'est le pire cas du mécanisme — le tracker étant la seule autorité d'état, ce n'est pas un ticket perdu mais tous, claim de l'itération en cours compris, et la boucle continue de tourner derrière. Vérifié : `git checkout-index -f` **recrée les répertoires manquants** (sondé isolément avant de s'y fier), donc les trois tickets reviennent avec l'état qu'ils avaient au spawn, l'itération est rouge, et le run marque et journalise normalement au lieu de mourir sur un fichier absent. Test `a session that deletes the whole tracker gets it back`.

- **13 mutations vérifiées rouges pour ce ticket** (protection absente, protection non appelée, édition non restaurée, snapshot pris après la session, itération verte malgré l'édition, outcome fondu dans `gate-red`, ticket créé restauré au lieu d'être quarantiné, ticket supprimé traité comme un ticket créé, snapshot soumis au `.gitignore`, snapshot illisible qui passe, tracker laissé stagé, plan lu après une édition, commit de session qui survit au vert), plus les entrées [05] et [07] repointées sur les lignes qui ont bougé.

- **Coût sur la suite** : 151 → 160 tests, 1 `skip` → 0, 79 → 92 mutations. Verte sous le bash 3.2 de macOS. Le surcoût par itération est d'un `git add -A --force` borné à `issues/` plus un `write-tree`, et d'une comparaison de sha quand rien n'a bougé — soit tout le temps.

- **Ce que le ticket suivant hérite.** `gate_tree_snapshot` prend un pathspec optionnel — [06] et [10] peuvent s'en servir pour ne snapshoter qu'une zone. `failures_make_durable` a une signature de plus (`pre` en 2ᵉ position). Et l'invariant nouveau, sur lequel [06] et [10] peuvent compter : **au moment où le gate tourne, `issues/` est exactement ce qu'il était au spawn** — sauf les tickets qu'une session a créés, qui sont là et déjà escaladés.

- **Réponse à la question transversale, et c'est la trouvaille la plus lourde du ticket : cette protection et la concurrence [13] sont incompatibles en l'état.** Le snapshot porte sur *tout* `issues/`, et en concurrence la boucle écrit légitimement dans `issues/` **pendant** la fenêtre de surveillance d'une autre itération — le claim de B, son `Failures:`, son marquage. L'itération A verrait ces écritures comme un delta, **restaurerait le ticket de B** (claim effacé, compteur remis à zéro, résolution annulée) et se déclarerait elle-même non verte pour une faute qu'elle n'a pas commise. Le worktree git par itération ne sauve pas ce cas, contrairement au rollback et au commit sur vert : le tracker est partagé *par construction*, c'est l'autorité d'état commune. Deux issues, toutes deux à trancher en [13] : restreindre le snapshot au seul ticket réclamé — ce qui perd la variante « une session marque le ticket d'un autre `resolved` », la plus coûteuse des deux — ou sérialiser les écritures de la boucle dans `issues/` avec les fenêtres de surveillance. Contrainte écrite dans [13]. **Rien ne rougit aujourd'hui** (`MAX_PARALLEL` n'existe pas encore), et c'est exactement la forme du pire bug du projet : faux dans aucun ticket pris isolément.

- **Trou trouvé par la passe transversale du 29/07/2026, ouvert en [27] : le renommage.** Le troisième corollaire posé par ce ticket — « un contrôle qui restaure doit dire ce qu'il ne restaure pas » — pointait plus loin qu'on ne l'a lu. Un renommage de fichier de ticket est un `D` plus un `A` : la protection restaure le supprimé (correct) et laisse le créé à la quarantaine (correct), et le résultat est deux fichiers portant le même `NN`. `tracker_local__path` refuse alors le numéro nu, et **tout ticket portant `Blocked by: NN` quitte la frontière définitivement**. Sondé : tracker final `01-alpha.md` + `01-alpha-v2.md` + `03-blocked.md`, `tracker_field 01` illisible, `03-blocked` perdu. Les deux décisions de ce ticket restent les bonnes prises séparément ; c'est leur composition sur un même ticket qui n'avait pas de cas.
