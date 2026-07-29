# 24 — La zone morte des fichiers ignorés par git

**What to build:** Fermer, ou déclarer explicitement, la zone que `.gitignore` soustrait à **tous** les contrôles du pack. `gate_tree_snapshot` sans argument fait `git add -A` **sans** `--force` : ce qu'un projet ignore n'entre pas dans le tree, donc le scope-guard ne le voit pas, le rollback ne le défait pas, et il survit d'itération en itération. Une session peut donc écrire hors de sa write-surface, garder son écriture après un gate rouge, et laisser derrière elle un fichier qui change le verdict des tickets suivants.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/lib/failures.sh`, `.claude/ralph.config.sh.example`, `test/gate.bats`, `test/failures.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Une session qui écrit un fichier couvert par `.gitignore`, hors de sa write-surface, ne rend pas une itération verte : soit le scope-guard le voit, soit le pack déclare la zone et dit qui la garde.
- [ ] Le rollback rend un verdict honnête sur cette zone : il la défait, ou il dit ce qu'il n'a pas défait. « L'arbre est remis où la session l'a trouvé » ne doit pas rester vrai à l'exception d'un ensemble de chemins que personne n'énumère.
- [ ] Le cas armé est couvert : un `.claude/settings.local.json` déposé par une session ne s'applique pas aux sessions suivantes du run — ou bien le pack le neutralise à chaque spawn, comme il le fait déjà pour `DISABLE_AUTO_COMPACT`.
- [ ] Le choix est écrit dans `ralph.config.sh.example` avec son coût : tirer les fichiers ignorés dans le snapshot ferait ressembler chaque build à un débordement, et c'est la raison pour laquelle `git add -A` est sans `--force` aujourd'hui.
- [ ] La ligne correspondante de `docs/frontiere-de-confiance.md` existe et ne dit pas « Rien » sans nommer son propriétaire.

## Comments

- **Origine : passe transversale 01→22, le 29/07/2026.** Trouvé en posant la question 5 sur `gate_tree_snapshot`, et sondé pour de vrai avec un projet portant un `.gitignore` — c'est-à-dire tout projet réel. Trois sondes, trois confirmations :

  - Une session écrit `src/alpha.txt` (dans sa surface) **et** `cache/payload` (hors surface, ignoré). Verdict du gate : `tests=green typecheck=green scope=green`, ticket `resolved`. Le scope-guard n'a rien vu.
  - Même session, `TEST_CMD` rouge donc rollback : `src/alpha.txt` est bien défait, `cache/payload` **reste**. Le rollback ne peut pas défaire ce que le snapshot ne contient pas.
  - Deux tickets à la suite. La session de `01-alpha` dépose `cache/unlock`. `TEST_CMD` du projet lit `cache/unlock` — ce que fait n'importe quelle suite qui dépend d'un `.env`, d'un cache de fixtures, d'une base de test ou de `node_modules`. `02-beta` passe au vert **grâce au fichier que 01 a laissé**, et les deux tickets sont marqués `resolved`. C'est la question 4 dans sa forme la plus pure : le défaut n'est faux dans aucun des deux tickets pris isolément.

- **Le cas armé, et c'est lui qui fait la gravité.** `.claude/settings.local.json` est ignoré par convention dans tout projet Claude Code. Sondé : une session écrit ce fichier avec un hook `PreToolUse`, le gate rend `scope=green`, le ticket est `resolved`, et le fichier est encore là. Toutes les sessions suivantes du run l'héritent — c'est-à-dire qu'une session peut configurer le harnais qui juge ses successeurs. Le commentaire de `session.sh` a déjà eu cette inquiétude pour un cas précis (« `DISABLE_AUTO_COMPACT` est posé ici *et* dans settings.json : la garantie ne doit pas dépendre d'un fichier de réglages que le projet cible pourrait écraser ») et la réponse était bonne pour l'auto-compact seul. Elle ne couvre ni les hooks, ni les permissions, ni le reste.

- **Ne pas « réparer » ça en mettant `--force` partout.** Le commentaire de `gate_tree_snapshot` dit exactement pourquoi le snapshot d'arbre entier est sans `--force` : tirer le build output d'un projet dedans ferait déclarer chaque itération en débordement. Le chemin avec arguments force déjà (`failures_tracker_tree` s'en sert, et c'est ce qui rend la protection du tracker de [21] insensible à un projet qui ignore `.scratch/`). Deux pistes plausibles, à trancher dans le ticket : un ensemble de chemins **sensibles** explicitement forcés dans le snapshot (`.claude/`, la config, ce que le projet déclare), ou un contrôle séparé qui compare la liste des fichiers ignorés avant et après la session. La seconde voit tout mais coûte un parcours ; la première ne voit que ce qu'on a pensé à nommer.

- **Contrainte pour qui livrera ça : le tracker vit dans la zone ignorée, en partie.** Le `.gitignore` de ce dépôt ignore `.scratch/*/run.log`, `.scratch/*/.run.lock/` et `.scratch/*/.session.*.jsonl`, et [19] les provisionne dans les projets cibles. Un contrôle qui rendrait « tout fichier ignoré » rouge ferait donc rougir chaque itération sur le journal de run et le flux de session, qui s'écrivent *pendant* la fenêtre surveillée. La zone à garder est « ignoré **et** hors du bookkeeping de la feature », et `gate_is_bookkeeping` est déjà l'endroit qui sait le dire.

- **Constaté au passage, à ne pas confondre avec ce ticket.** Le pack n'a aucun contrôle sur ce qu'une session écrit *hors du dépôt* — `$HOME`, `/tmp`, un autre dépôt sur la machine. C'est hors de portée d'un scope-guard qui diffe des trees git, ce n'est pas ce ticket, et le seul rempart est `--dangerously-skip-permissions` assumé au niveau du pack. À écrire dans le tableau de la frontière comme une limite, pas comme un trou à combler.
