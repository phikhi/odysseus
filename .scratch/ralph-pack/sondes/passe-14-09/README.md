# Sondes de la passe transversale du 14/09/2026

Des **instruments**, pas des tests. Chacune se termine par un `set -e; false`
volontaire : elle rougit toujours, et ce qu'on lit est ce qu'elle imprime avant.
Elles ne sont pas dans `test/` et `test/run.sh` sans argument ne les ramasse pas —
elles ne doivent jamais compter dans le verdict des deux gates.

Les faire tourner, une par une ou par nom :

    bash test/run.sh .scratch/ralph-pack/sondes/passe-14-09/q1-la-prose-deposee-retape-la-liste-scellee.bats
    bash test/run.sh -f Q2b .scratch/ralph-pack/sondes/passe-14-09/q2-aucune-regle-de-source-ne-voit-linstalleur.bats

Elles pilotent le pack tel qu'il est livré. Q1 et Q2b font tourner `init.sh`
comme un processus contre un dépôt git neuf, exactement comme `test/install.bats` ;
Q2b est la seule à appliquer une édition, et elle l'applique à une **copie** de
`init.sh` dans le répertoire de test. Aucune n'écrit dans `.claude/`, `test/` ni
à la racine du dépôt. La passe qui les a écrites est dans
`../../passe-transversale-14-09.md`.

**Lire la sortie de microbats** : il sépare ses cas en `\r`, donc
`LC_ALL=C tr '\r' '\n' < sortie.log`.

| Sonde | Ce qu'elle demande | Verdict, mesuré le 14/09/2026 |
|---|---|---|
| `q1` Q1a | ce que `gate_sealed_paths` rend, et ce que le bloc `CLAUDE.md` que `init.sh` dépose en nomme | **12 entrées contre 5 nommées telles quelles.** `.claude/commands`, `.claude/skills` et `.claude/hooks` ne sont là que par leur basename nu ; `.claude/settings.local.json`, `CLAUDE.local.md`, `LEARNINGS.md` et `learning-records` ne sont pas là du tout. Et `loop_session_prompt` n'en nomme **aucune** : dans un projet installé, ce bloc est tout ce qu'une session apprend de la liste |
| `q1` Q1b | ce que le bloc dit du tracker quand `TRACKER_BACKEND=github` | l'installeur **lit** la clé et imprime la bonne phrase à la console (`TRACKER_BACKEND=github needs TRACKER_REPO…`), puis écrit « Issues and specs are markdown under `.scratch/demo/` … the feature spec in `spec.md` » dans le fichier que chaque session lit, et provisionne `.scratch/demo/issues` qui ne recevra jamais rien. `init_claude_block` ne prend que `$feature` : la phrase **ne peut pas** varier |
| `q2` Q2a | la zone des quatre règles de source de `test/layering.bats`, et où vivent les points d'entrée | les quatre bouclent sur `"$dir"/lib/*.sh "$dir"/*.sh` (`layering_upward` sur `lib/` seul) avec `$dir="$RALPH_PACK_ROOT/.claude"`. `init.sh` est à la racine : **hors des quatre**. Il porte neuf heredocs, dont deux non cités qui écrivent de la prose dans le projet cible |
| `q2` Q2b | ce que coûte un backtick de prose dans `init_claude_block` | la règle `layering_heredoc_prose`, **extraite de `test/layering.bats` sans être recopiée**, l'attrape quand on l'y pointe (`init.sh:834`). L'installeur, lui, sort en **0** : une ligne `docs/agents/: is a directory` passe dans un rapport de quarante lignes, et le projet garde pour toujours un `CLAUDE.md` qui dit « The conventions are in . ». Témoin appairé : le pack livré et `init.sh` tel quel rendent tous deux `rc=0` |
| `q3` | les quatre règles de `loop_session_prompt`, et ce qui tient chacune | une seule est dérivée du module qui la tient (`$(lang_session_rules)`, [17]). Deux n'ont pas de liste. La quatrième dit « Never stage or commit the tracker (`.scratch/`) » alors que le désindexage est `git reset -q -- "$(tracker_local__issues_relpath)"`, c'est-à-dire `issues/` : `spec.md` n'est ni désindexé ni restauré, et `gate_is_bookkeeping` le retire du rapport du scope-guard **et** du rollback |
| `q4` Q4a | le namespace `RALPH_*` du pack, et ce que `harness__clear_env` en connaît | **42 noms**, dont **6** dans la liste écrite à la main du harnais. Les clés de configuration, elles, sont dérivées du `.example` juste au-dessus. Cinq noms sont assignés par leur lib en `${X:-}` au `source`, donc **préservent** une valeur héritée : `RALPH_PLAYTHROUGH_SPEC`, `RALPH_PLAYTHROUGH_OPENED`, `RALPH_RECEIPT`, `RALPH_TRACKER_SAID`, `RALPH_RETRO_STATE` |
| `q4` Q4b | ce qu'une valeur héritée survit à traverser | les trois valeurs exportées traversent le `source` des vingt-quatre libs intactes, et `retro_guards` — le recensement de zones que [85] vient de dériver — rend `…/inj/state/index.guard`, c'est-à-dire un répertoire choisi par l'environnement |
