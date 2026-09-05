# 14 — Auto-apprentissage + ADR en delivery

**What to build:** Le **subagent retro frais** post-gate (tier bon marché, auto-suppressif) qui capte la connaissance apprise : un record de leçon (+ index LEARNINGS injecté inline) et/ou un ADR interne, avec anti-bruit sur l'index et promotion jamais silencieuse.

**Blocked by:** 05, 10

**Write-surface:** `.claude/lib/retro.sh`, `.claude/lib/receipt.sh`, `.claude/lib/lenses.sh`, `.claude/lib/gate.sh`, `.claude/loop.sh`, `.claude/ralph.config.sh.example`, `test/retro.bats`, `test/helpers/harness.bash`, `test/helpers/shims/claude`, `test/loop-happy-path.bats`, `test/smoke.bats`, `test/mutate.sh` — plus les artefacts du dépôt (`CONTEXT.md`, `docs/frontiere-de-confiance.md`, les tickets)

**Status:** resolved

- [x] Après le gate, un subagent retro frais (auto-suppressif) n'écrit un record de leçon (`learning-records/NNNN`, format `teach`) **que** s'il y a une leçon ; sinon rien.
- [x] L'index `LEARNINGS.md` reste un working set borné, injecté inline dans les sessions fraîches ; anti-bruit par dedup / supersession / drain-par-promotion.
- [x] Une décision d'archi **interne** non-triviale est gravée en ADR (`docs/adr/`) ; une décision **contractuelle** escalade au lieu d'un ADR autonome.
- [x] La promotion d'une leçon récurrente est soit **autonome** (section « standing rules » de l'index — voir la décision 1 ci-dessous), soit **escaladée** (gate/lint/hook → `ready-for-human`) — jamais silencieuse.
- [x] Écriture atomique (temp + `mv`) des records et de l'index.

## Comments

- **Contrainte posée par [31], livré le 30/07/2026 : `CLAUDE.md` est scellé, donc l'AC de promotion autonome ne peut pas s'écrire comme elle est rédigée.** Le scellement couvre désormais tout ce qu'un `claude` frais lit au démarrage, `CLAUDE.md` et `CLAUDE.local.md` compris, et **aucune write-surface ne peut couvrir un chemin scellé** : un ticket qui déclare `CLAUDE.md` est rouge à chaque tentative, définitivement. La décision a été prise en connaissance de ce coût — la boucle n'édite pas les règles qui la jugent — donc c'est ce ticket qui doit s'adapter, pas le scellement.

  Deux issues, à trancher ici et à écrire :

  1. **La promotion autonome va dans `LEARNINGS.md`**, qui est déjà le mécanisme de ce ticket (index borné, injecté inline dans les sessions fraîches). Une guidance promue y vit et atteint chaque session sans toucher un chemin scellé. C'est la voie qui préserve l'AC « jamais silencieuse » sans rien coûter.
  2. **Ou la promotion vers `CLAUDE.md` devient une escalade** — `ready-for-human`, un humain édite. Cohérent avec l'autre moitié de l'AC (« gate/lint/hook → escalade »), et cohérent avec [15], qui refuse déjà toute création de capacité en AFK.

  Le piège à ne pas rouvrir : contourner le scellement en écrivant la guidance dans un fichier *non* scellé que le prompt irait lire ensuite. Ce serait recréer exactement le canal que [31] vient de fermer, sous un autre nom — et cette fois sans qu'aucun contrôle le remarque.

- **Contrainte posée par [10], livré le 07/08/2026 : la moitié du trou de [06] est refermée, et l'autre moitié est ici.** Les findings d'une lentille rouge survivent maintenant à l'itération — `gate__aggregate` les copie hors du répertoire temporaire du gate avant que `gate_run` ne le détruise, et le reçu les porte en entier (`RECEIPT_MAX_LINES`, 200 lignes par défaut, ce qui est retiré est compté). Ce qui **n'existe toujours pas** est le canal de retour : rien ne remonte ces findings vers le prompt de la session suivante, donc une session retryée après une lentille rouge peut réécrire exactement le même code et se faire rougir à l'identique jusqu'à `RETRY_N`. C'est le record de leçon de ce ticket, et il a maintenant une source à lire qui n'est ni un stdout ni un fichier qu'une session peut écrire. Deux précautions à porter : la source est le **reçu**, pas `run.log` (une session peut réécrire le journal, cf. `docs/frontiere-de-confiance.md`) ; et un reçu n'existe que pour une itération *finale*, donc les findings d'un retry intermédiaire ne sont **nulle part** — si la leçon doit être injectée entre deux tentatives du même ticket, c'est un canal que ce ticket doit ouvrir, pas un reçu à aller lire.

- **Contrainte posée par [45], livré le 24/08/2026 : le canal du reçu a deux sections, et une seule est de la matière à leçon.** [45] a relu les producteurs du reçu contre le critère écrit dans `receipt.sh` et en a câblé quatre familles de plus. Trois choses pour ce ticket :

  1. **`receipt_note` et `receipt_gap` ne disent pas la même chose.** Les notes sont de la **couverture** — ce que rien n'a jugé, présent sur chaque itération, verte comprise. Les gaps sont ce que le pack allait faire et n'a pas fait : un arbre non remis, une branche `failed/<ticket>` que git a refusée, un split qui n'a pas eu lieu. Une leçon ne se tire pas d'un gap : « git a refusé d'écrire une ref » n'est pas une chose qu'une session suivante peut faire différemment, et l'injecter dans un prompt apprendrait à un modèle à compenser une panne d'infrastructure.
  2. **La liste des routes qui produisent un document s'est élargie** : livré, escaladé, `not-integrated`, et un rollback qui n'a pas pu agir. Les deux dernières ne sont **pas** des jugements sur le code — un gate vert dont le travail a disparu, une itération dont l'arbre n'est pas revenu — donc un lecteur qui promeut des leçons doit les sauter, ou il apprendra du bruit d'infrastructure. Le discriminant est dans le document et pas à deviner : l'outcome et la ligne de verdicts.
  3. **Une partie du texte d'une ligne de reçu vient de la session** (un nom de chemin, un slug de plan). Le rendu markdown est neutralisé par construction — chaque ligne est préfixée `- ` — mais un canal qui **réinjecte** du reçu vers un prompt de session redonne à une session le droit d'écrire dans le prompt de la suivante, ce qui est la frontière que ce dépôt documente. À traiter comme de la donnée citée, jamais comme de l'instruction.

## Livré le 24/08/2026

Le module est `.claude/lib/retro.sh`. Il possède la **quatrième couche** de [10] : journal, reçu, playthrough, LEARNINGS.

### La décision qui commande toutes les autres

**Un fichier inliné dans le prompt d'une session *est* le prompt.** Tout découle de là :

1. **La promotion autonome va dans l'index** (issue 1 du commentaire de [31]), section `## Promoted` de `LEARNINGS.md`. L'issue 2 n'a pas été retenue : escalader *toute* promotion aurait rendu la moitié autonome de l'AC inatteignable, et [15] ne refuse que la création de **capacité**, pas l'écriture d'une observation. `CONTEXT.md` a été révisé en conséquence — sa définition de **Promotion** nommait encore `CLAUDE.md`.
2. **`LEARNINGS.md` et `learning-records/` sont scellés**, ajoutés à `gate_sealed_paths`. Ce n'est pas une ceinture-bretelles : sans ça, ce ticket rebâtissait exactement le canal que [31] a fermé, sous un autre nom. Le critère de la liste — « ce qu'un `claude` frais lit au démarrage » — ne demande pas *par quelle route*. Prix assumé et identique à celui de `CLAUDE.md` : aucun ticket ne livrera jamais l'index ni un record.
3. **Le subagent n'écrit rien.** Il est spawné avec la posture de [06] (`lenses_posture`, réutilisée et pas recopiée) et répond en **lignes taguées** que le pack parse. Le modèle propose, le pack dispose : forme du document, emplacement, bornes, numérotation appartiennent à `retro.sh`. Un subagent qui écrirait écrirait dans un arbre que rien ne juge, et ce qu'il aurait écrit atteindrait le prompt suivant.
4. **Ce qu'un prompt reçoit vient d'une copie du pilote**, prise dans `$TMPDIR` sous un `mktemp` jamais exporté, **avant qu'aucune session n'existe**. `LEARNINGS.md` vit dans l'arbre principal, qu'une session sait retrouver (`git worktree list`) et qu'aucun scope-guard ne regarde. Servir depuis la copie fait qu'une réécriture en cours de run n'atteint aucun prompt de ce run — c'est de la **préemption**, là où le témoin de `run.log` ([10]) ne peut que détecter.

### Le canal entre deux tentatives, que [10] a laissé ouvert

C'est un **canal et pas un document** : un reçu n'existe que pour une itération finale, donc une tentative intermédiaire n'en a aucun. `retro_keep_brief` copie, à la fin d'une itération dont la politique a décidé un `retry:`, ce que les branches rouges ont dit — lu dans la copie que le reçu a faite *pendant* que le répertoire du gate existait encore, jamais dans `run.log`. `loop__prompt_brief` le rend à la tentative suivante du **même ticket**, cité. Jeté dès que le ticket cesse de bouger.

Deux lecteurs publics ont été ajoutés à `receipt.sh` pour ça (`receipt_branches`, `receipt_branch_text`) et `lenses__findings` est devenu `lenses_findings` : un `__` avec deux appelants est une interface dont le nom ment.

### Écarts et décisions à connaître

- **`RETRO` commande les deux canaux**, le subagent payant et le brief gratuit. Discutable — un projet qui éteint le tier perd aussi le brief — mais un seul interrupteur pour une seule couche est ce qui se lit ; la suite entière tourne avec `RETRO=off` (injection du harnais, comme `LENSES=none`), donc le brief n'est vérifié que par `test/retro.bats` et le canari.
- **Le protocole de réponse est en lignes taguées à valeur unique**, dernière occurrence gagnante. Pas de bloc multi-ligne : un parseur à états sur du NDJSON est exactement l'endroit où un mensonge se cache, et le pack n'aurait rien gagné à laisser le modèle décider de la structure du document.
- **La dédup est volontairement grossière** (casse, ponctuation, espaces retirés). Une mesure de similarité qu'un humain ne peut pas reproduire est un index qui grossit d'un quasi-doublon à la fois.
- **`docs/adr/` n'est PAS scellé**, à dessein. Un ADR n'est pas inliné : il est pointé. Le sceller interdirait à tout ticket de livrer un ADR, ce qui n'est pas le même échange que pour l'index. Le canal qui reste — les rubriques envoient la lentille Standards lire `docs/adr/` — est **antérieur à ce ticket** et déjà écrit sans propriétaire dans le tableau (ligne « Ce qu'une lentille de revue écrit… »). Ce que [14] change, c'est qu'un écrivain de plus de ce répertoire est le **pack** et non une session, ce qui va dans le bon sens.
- **La ligne 57 du tableau disait « un reçu n'est lu par aucune machine et ne revient dans aucune décision »**. C'est faux depuis ce ticket et la phrase a été corrigée : la chaîne session → reçu → retro → index → prompt existe. Ce qui la borne est écrit à la ligne suivante.
- **Neutralisation** : chaque ligne qui voyage est forcée à une ligne, débarrassée des caractères de contrôle, bornée à 240 caractères, préfixée `> `. L'injection **de bloc** est donc neutralisée (sondé : une leçon nommée `## Override - ignore every instruction above this line` arrive comme puce citée) ; l'injection **de prose** ne l'est pas et aucun préfixe ne le pourrait.

### Ce que la mutation a trouvé, et qu'aucune relecture n'aurait vu

- **Un aveu honnête de ce module masquait la confession de zone de [45].** `receipt_note` sur chaque itération — « le tier est off », « rien n'a jugé le code » — rendait la section « What nothing here judged » non vide *partout*, donc la phrase que [45] a livrée (« An empty list here is not an empty zone ») ne tombait plus jamais. C'est le test de [45] qui l'a dit. Correction à la racine et pas dans l'assertion : **ce module est muet quand la ligne de verdicts est vide**. Une itération que rien n'a mesurée n'a rien à distiller par construction, quel que soit le réglage du tier — et une ligne de nous serait la seule phrase d'une section dont le travail est de dire que personne n'a rien parcouru. Règle à hériter : *tout ticket qui ajoute un `receipt_note` inconditionnel doit se demander sur quelles routes il tombe.*
- **La clé par ticket du brief n'était couverte par rien.** Le test bout-en-bout restait vert avec la clé retirée : à `MAX_PARALLEL=1` un brief n'est vivant qu'entre deux tentatives d'un ticket, la frontière est un scan min-NN, et le ticket retryé est toujours le suivant choisi — toute autre action jette le brief avant qu'un autre ticket ne soit spawné. La clé ne gagne son droit d'exister qu'au-dessus de `MAX_PARALLEL=1`, et le test est passé au niveau du module (`pack_run`) plutôt que construit sur une course.
- **Une entrée de mutation dont le remplacement contenait `$\n`** a rendu DRIFTED sans que rien n'ait bougé : `$\` est une variable spéciale de perl. C'est la famille d'erreurs que l'en-tête de `test/mutate.sh` décrit, sous une forme de plus.

### Ce qui n'est couvert que partiellement, dit comme tel

- **Le garde de l'index est testé par son refus, pas par une course.** `test/retro.bats` fait tenir le garde par un processus réellement vivant et vérifie que la leçon n'est pas écrite et que l'itération le dit. Que deux retros simultanés ne s'écrasent pas repose sur `state_guard_take` (un `mkdir`, testé dans `test/state.bats`) et n'a pas de test à `MAX_PARALLEL>1` — un test bâti sur une course mesurerait la machine.

### Pièges rencontrés

- **Le fake `claude` ne peut pas répondre au retro sans le reconnaître.** Il le reconnaît par `RALPH-RETRO-NOTHING` dans le prompt, comme il reconnaît une lentille par `RALPH-LENS-VERDICT` : dérivé de ce que le pack envoie, jamais de l'index de l'appel. `retro_answer_nth` existe parce que deux itérations doivent pouvoir dire deux choses différentes (supersession, deux leçons distinctes).
- **Une sonde d'injection markdown doit choisir un titre que le prompt ne porte pas déjà.** Le premier essai utilisait `## Rules`, qui est une section du prompt de session : le test comptait 1 et accusait la neutralisation.
- **Une mutation `s{}{}` dont le remplacement contient une accolade non appariée casse le parseur perl** et sort `BROKEN` en accusant autre chose. Délimiteur `!` pour tout remplacement qui contient du bash.
- **Le test de « la copie gagne » doit écrire dans l'arbre une entrée *bien formée***. Une ligne hostile qui ne parse pas comme une entrée d'index serait ignorée par le lecteur quel que soit le fichier lu, et le test passerait sans rien exercer.
- **`session_spawn` écrase `RALPH_SOFT_LIMIT_HIT` et `RALPH_SESSION_TIMEOUT`** dans le shell de l'itération. `retro_run` est appelé après le dernier lecteur de ces deux variables ; un ticket qui déplacerait l'appel plus haut casserait la classification de l'outcome en silence.

### État des deux gates au merge, et comment disculper chacun

- **`bash test/run.sh` = 485 tests, 1 failure, 6 skips opt-in.** 450 avant, +35 dont les 34 de `test/retro.bats`. Le rouge est `a stop request lets the iterations in flight finish` (`concurrency.bats`), le flaky connu de [38]. Disculpé en isolé : **branche ✗✗✗✗✓✓, main ✗✗✗✗✗✗** dans un `git worktree add --detach` sur `main`, six passes chacun, machine chaude. La branche est donc *moins* rouge que main sur ce test ; ce n'est pas une régression de [14].
- **`bash test/mutate.sh` complet = 456 mutations, 2 not ok** (425 avant, +31). Les deux sont VACUOUS et **aucun des deux n'est celui qui était attendu** :
  - `23 the grace is hard-coded` — le **jumeau** de l'un des deux VACUOUS historiques, même filtre de test (`smart-zone.bats -f "killed after the grace"`). Disculpé par 3 rejeux `ok` en isolé.
  - `06 a lens that never returns is left to hang` (`lenses.bats -f "deadline of its own"`) — **nouveau, pas dans la liste connue**. Disculpé par 4 rejeux `ok` en isolé. Ce n'est pas [14] : le seul changement de `gate.sh` livré ici est la liste de `gate_sealed_paths`, et `lenses.bats` tourne avec `RETRO=off`, donc aucune session retro n'est spawnée dans ce fichier. Le test porte son propre commentaire sur la cause — son `sleep 120` doit dépasser les 60 s que le test donne au run, et une passe complète chargée déplace ce rapport. **C'est une troisième entrée de la même famille : une garantie de terminaison dont la mutation ne ment que sous la charge d'une passe complète.**

### Contraintes créées ailleurs

Écrites aussi dans les tickets concernés :

- **[19]** provisionne `learning-records/` et devra balayer les `ralph-retro.*` de `$TMPDIR` avec le reste.
- **[15]** hérite d'un canal d'escalade déjà construit (`retro-<slug>`, `ready-for-human`) : ne pas en bâtir un second.
- **[18]** : l'index et les records sont écrits **directement dans l'arbre du projet**, pas par l'adaptateur de tracker. Un backend distant reçoit son reçu en PR et garde ses leçons en local.
- **[09]** : la copie de l'index est **par run**. Un run successeur relit la ligne de base depuis le fichier, donc la préemption du point 4 ne traverse pas un redémarrage. **Tranché par [09], livré le 29/08/2026 : la limite est assumée telle qu'écrite, et le successeur ne reçoit rien.** L'autre sortie — transmettre la copie par un fichier nommé sur la ligne de commande du job programmé — a été refusée sur l'argument de [40] : `at -c` imprime cette ligne à tout ce qui tourne sous cet utilisateur, donc le nom de ce fichier serait un nom qu'une session peut apprendre, et une ligne de base qu'une session peut écrire n'est pas une ligne de base. Le test de [09] refuse toute mention de `ralph-retro` (et des trois autres répertoires secrets du run) dans la commande mise en file, donc un futur ticket qui voudrait rouvrir la question cassera un test au lieu de le faire en silence.
- **[16]** : un humain qui vide `ready-for-human` verra des tickets `retro-*` qu'aucune discovery n'a écrits.

- **Contrainte posée par [15], livré le 25/08/2026 : la *forme* du ticket d'escalade a déménagé, la garantie non.** Le commentaire ci-dessus demandait à [15] de décider s'il passait par ce canal ou en construisait un autre. Il a fait le premier, et pour éviter deux producteurs avec deux formats il a mis la forme dans `capability_propose` (`capability.sh`) : le `**Status:** ready-for-human`, l'ouverture par l'adaptateur de tracker et la dédup contre `tracker_ids`. `retro__escalate` l'appelle et ne garde que ce qui le distingue — le préfixe `retro-` et le corps qui dit pourquoi une règle n'est pas une leçon. Deux conséquences à connaître avant de toucher à ce module : les deux entrées de mutation de ce ticket (`14 an escalated rule lands on the frontier…`, `14 an escalation waiting for a human…`) ancrent maintenant dans `$CAPABILITY` et nomment toujours `test/retro.bats` — rejouées `ok` le 25/08/2026 ; et `retro__prompt` porte une quatrième famille de tags (`RALPH-RETRO-CAPABILITY`), fournie par `capability_prompt` et parsée par `capability.sh`, donc la clause de silence de `retro_run` compte une réponse de plus (`capability_said`) sous peine de rapporter comme muette une session qui a répondu.

- **Contrainte posée par [63], livré le 05/09/2026 : `answered` change de
  vocabulaire, et la question du budget descend de vingt lignes.** `retro_run`
  consultait `budget_refused` **avant** les `retro__said` : un rétro qui répondait
  `LESSON` + `ADR` + `ESCALATE` + `CAPABILITY` sur un flux annonçant `blocked` pour
  la fenêtre suivante perdait la leçon, l'ADR, le ticket d'escalade, la revue de
  capacité et la nuit — et le reçu écrivait « the API refused the retro session »
  pour une session qui avait répondu six lignes taguées. Le `budget_stream_posture`
  et sa garde sont maintenant **après** les sept `retro__said` et le
  `capability_said`, à travers `budget_refused_silence` (`.claude/lib/budget.sh`),
  qui est l'endroit unique où vit l'ordre de [43]. Pour que le premier argument
  parle le même vocabulaire chez les trois paliers, la variable locale `answered`
  vaut désormais `none` / `said` et non `0` / `1` : l'entrée de mutation
  `14 a retro that answered nothing reads as one that found nothing` est ré-ancrée
  dessus, et `14 a retro the API refused is a lesson that was not there` sur le
  nouvel appel. Les deux rejouées `ok`. Le harnais a gagné `retro_rate_limit`
  (événement in-band **avec** réponse, jumeau de `playthrough_rate_limit`) — sans
  lui le cas n'était pas exprimable, `retro_refused` étant l'événement *plus*
  `exit 1`.
