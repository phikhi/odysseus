# 91 — Le shell qui porte le verdict n'est pas surveillé

**What to build:** Que ce que le run épingle du `PATH` couvre le nom par lequel passent les quatre commandes du projet — `bash` — et que le premier mot de ces quatre commandes soit tranché plutôt qu'omis par défaut.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/scheduler.sh`, `test/gate.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] `bash` entre dans ce que `gate_path_programs` publie, et un test **dérive** de la source livrée les noms que le pack lance par leur nom nu plutôt que de recopier la liste — la dette que le tableau nomme aux deux endroits (`gate_config_keys`, `gate_path_programs`) est payée sur celle-ci, et le critère de la dérivation est écrit dans le test ([62], [85]).
- [ ] Le premier mot de `TEST_CMD`, `TYPECHECK_CMD`, `RUN_CMD` et `VISUAL_CMD` est **tranché** : soit il entre dans le manifeste (dérivé de la configuration, pas retapé), soit la ligne du tableau dit que le pack ne surveille pas le programme dont il croit le code de sortie, et pourquoi. Une réponse « c'est le programme du projet » n'en est pas une — c'est le programme dont le verdict décide de tout.
- [ ] `scheduler_command` ne résout plus le shell du successeur avec `command -v` : le commentaire de `gate__path_where` interdit cette fonction en toutes lettres, et la ligne mise en file s'exécute des heures plus tard.
- [ ] Un test met en scène un `bash` planté en tête de `PATH` sur une itération réelle et asserte **ce qui a changé** : le nom apparaît dans le témoin, une ligne le nomme, le successeur n'est pas armé. Jamais `assert_success` seul.
- [ ] Une entrée de mutation par garantie livrée, avec le témoin appairé.

## Comments

- **Ouvert par la passe transversale du 22/09/2026** (`../passe-transversale-22-09.md`,
  §1). Sonde : `../sondes/passe-22-09/q2-le-verdict-passe-par-un-nom-non-surveille.bats`.

- **Les quatre sites, mesurés sur le pack livré** : `gate.sh:3814`
  (`bash -c "$TEST_CMD"`), `gate.sh:3821` (`bash -c "$TYPECHECK_CMD"`),
  `playthrough.sh:291` (`bash -c "$cmd"` pour `RUN_CMD` et `VISUAL_CMD`),
  `scheduler.sh:510` (`command -v bash`, figé dans la ligne du successeur).

- **Le compte** : `gate_path_programs` rend **32** noms, `gate_path_witness`
  écrit **32** lignes, aucune ne dit `bash`. Un `bash` enregistreur en tête de
  `PATH` voit **13** passages sur une itération verte, dont les **4** qui portent
  un verdict (`-c stub-cmd tests`, `-c stub-cmd typecheck`, `-c stub-cmd run`,
  `-c stub-cmd visual`). Le run sort `0`, le ticket est `resolved`, rien n'est dit.

- **Ce n'est pas la dette nommée par le tableau.** Celle-ci dit *« un site d'appel
  ajouté au pack dans un programme absent de la liste rouvre le trou »* : elle
  parle d'une dérive. Les quatre sites sont **antérieurs** à [52] — la liste était
  incomplète le jour où elle a été écrite.

- **Ce que [52] a posé et qu'il ne faut pas défaire.** Ce qui est surveillé n'est
  pas les *répertoires* du `PATH` (bruit sur un canal dont la conséquence est de
  refuser un successeur) mais la **résolution et le contenu** des noms. Les
  builtins de bash sont absents par critère et non par oubli. La recherche est
  faite à la main sur `PATH` (`gate__path_where`) et jamais demandée à
  `command -v` — c'est le piège que [52] a trouvé en livrant. Le prix est écrit :
  un `bash` mis à jour en pleine nuit coûtera le successeur, comme un `git` mis à
  jour le coûte déjà.

- **Contrainte pour [92]** : un `bash` planté rend inutile toute réparation faite
  à l'intérieur du gate, puisqu'il possède l'interpréteur des quatre commandes.
  Ce ticket est le plancher de l'autre, et c'est pour ça qu'il passe devant.
