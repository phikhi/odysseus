# 108 — Chaque heredoc du pack est un fichier nommé, un instant, dans un répertoire que tout le monde énumère

**What to build:** Qu'aucune valeur sur laquelle le pack décide ne transite par un heredoc de bash 3.2 — ou que chaque site dise ce qu'il vaut. bash 3.2 matérialise un heredoc en **fichier nommé** `/var/tmp/sh-thd-<n>` (`P_tmpdir` sur darwin, et **pas** `$TMPDIR` : `sh_mktmpfd` est appelé sans `MT_USETMPDIR`) entre sa création et son délien, et un process du même utilisateur qui boucle sur ce répertoire le voit et peut y écrire avant que le lecteur ne lise. C'est la fenêtre de [103], pour un objet que le pack crée **cent quarante-neuf fois** dans son code (décompte grossier des `<<MOT` non cités) sans jamais l'avoir nommé.

**Blocked by:** None

**Write-surface:** à instruire — `.claude/loop.sh`, `.claude/lib/*.sh`, `test/*.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] Le recensement : quels heredocs portent une valeur sur laquelle le pack décide (un id, un chemin passé à `rm -rf`, un numéro de descripteur passé à `eval`, un verdict), et lesquels ne portent que du texte qu'un humain lit. Dérivé, pas listé ([91]) — le lexeur de `test/gate.bats` lit déjà les corps de heredoc non cités depuis [104].
- [ ] La mesure **dans le pack** : un survivant qui boucle sur `/var/tmp/sh-thd*` et réécrit ce qu'il trouve, contre un run réel. Le site le plus exposé lu en ouvrant ce ticket : `loop__reap` itérait `LOOP_SLOTS` par `done <<SLOTS` — le pilote y lit des pids, des chemins qu'il passe ensuite à `rm -rf` et à `concurrency_worktree_drop`. [98] l'a sorti du heredoc (voir le commentaire de [98] ci-dessous) ; les autres sites restent.
- [ ] La forme de la réparation, et son prix mesuré : une boucle par expansion de paramètres (`${rest%%$'\n'*}`) ne crée aucun fichier ; un `$( … )` non plus ; un heredoc **cité** (`<<'X'`) en crée un comme les autres — le contenu n'est simplement pas expansé.
- [ ] La ligne du tableau, et ce qui reste : sous Linux, bash ≥ 5.1 passe les petits heredocs par un tuyau ; bash 3.2 jamais.

## Comments

- **Ouvert en livrant [98] le 10/10/2026**, par la question 5 posée au chemin de la réponse d'une itération : *qu'est-ce qu'une session peut écrire que rien ne vérifie, entre le moment où l'itération sait et celui où le pilote décide ?* Le pack itère ses listes internes par `while read … done <<MOT` partout, et chacun de ces heredocs est un fichier.
- **Mesuré hors du pack** (`../sondes/ticket-98/f6-les-heredocs.sh`, bash 3.2.57, darwin 26) : 3 000 heredocs d'une ligne, un espion qui boucle sans dormir sur `/var/tmp/sh-thd*` voit **40 168** noms ; le même espion qui écrit `FORGED<TAB>forged` dans chaque fichier qu'il voit (`1<>`, sans tronquer) fait lire la ligne forgée **2 fois sur 3 000** — un espion naïf, qui écrit dès qu'il voit le nom et que l'écriture de bash recouvre le plus souvent. Un espion qui garde le descripteur et écrit après bash n'a pas été mesuré.
- **Ce que [98] en a fait, et pas plus** : le chemin de la réponse d'une itération au pilote ne porte aucun heredoc — l'accumulation des lignes de dérive dans l'itération, la réponse, la lecture du canal, la récolte de `LOOP_SLOTS` et la mise au journal des dérives passent par des boucles d'expansion de paramètres ; et un numéro de descripteur lu de `LOOP_SLOTS` est vérifié chiffre par chiffre avant l'`eval` qui le ferme. Les producteurs (`capability_drift`, `gate_path_drift`, `forensic_drift`) sont lus par `$( … )`. Tout le reste du pack est à ce ticket.
