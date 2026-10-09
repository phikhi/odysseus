# 107 — Rien ne borne dans le temps une commande de jeton

**What to build:** Qu'une commande de jeton (`TRACKER_TOKEN_CMD`, `USAGE_TOKEN_CMD`) qui ne rend jamais la main ne tienne pas l'itération ou le pilote indéfiniment — ou que le pack dise qu'il l'attend, et combien. Depuis [106] la ligne est évaluée par `proc_eval_bare` : elle ne tient plus rien au-dessus de stderr et lit `/dev/null`, mais rien ne la borne. Un script sous `$HOME` qu'une session a réécrit en `sleep` tient la nuit aussi sûrement qu'un `cat` sur stdin la tenait avant [106].

**Blocked by:** None

**Write-surface:** `.claude/lib/proc.sh`, `.claude/lib/forge.sh`, `.claude/lib/budget.sh`, `test/proc.bats`, `test/tracker-remote.bats`, `test/budget.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] **Le cas mesuré** (`../sondes/ticket-106/s1-le-stdin-de-la-commande.bats`, C3, mesuré sur la branche de [106]) a une réponse : un run dont la commande de jeton attend tient ce que le pack a promis — un AFK borné.
- [ ] La borne est **dérivée d'une borne existante** (`FORGE_TIMEOUT` pour la forge, le `--max-time 10` de l'endpoint d'usage) ou une clé neuve, tranché et écrit avec son prix : un gestionnaire de mots de passe qui déverrouille lentement (1Password, une clé matérielle) ne doit pas faire échouer chaque requête de la nuit.
- [ ] Ce que la borne fait d'une commande qui ne rend pas la main est dit : tuée (et ce qu'elle a laissé derrière elle — un process de la ligne survit aujourd'hui au sous-shell, hors de tout groupe balayé), ou abandonnée, et la requête part sans jeton ou ne part pas.
- [ ] Témoin appairé, une entrée de mutation par garantie, la ligne du tableau « Ce que tient une ligne de la configuration que le pack évalue » mise à jour (la borne non tenue y renvoie à ce ticket).

## Comments

- **Ouvert en livrant [106] le 09/10/2026**, laissé là par décision (« ok » de Philippe le 09/10) : [106] ferme ce que la ligne **tient** (descripteurs, stdin) ; le **temps** est une autre propriété, de la classe d'un `core.fsmonitor` lent du `~/.gitconfig` de l'opérateur, que rien ne borne non plus. Mesuré à l'ouverture de [106] (`s1`, C2, code de `main` à `618106e`) : un tuyau tenu 40 s sur le stdin d'un script réécrit → run de 44 s. Depuis [106] ce chemin-là est fermé (stdin = `/dev/null` ; `s1` C2b, la boucle chronométrée seule sous le même tuyau : 9 s). Un `sleep` dans le script ne l'est pas — **mesuré sur la branche de [106]** (`s1` C3) : le script réécrit dort 20 s une fois → boucle de 29 s, témoin 8 s. Attention en reprenant `s1` : C2 mesure la durée du tuyau (`{ sleep 40; } | bash loop.sh` attend les deux côtés), pas celle de la boucle.
- **Où ça tombe** : `forge__http` (chaque opération d'un backend distant, du pilote et de l'itération) et `budget__request` (le pilote, avant chaque claim). Le `--max-time` des deux `curl` ne couvre que la requête, pas l'évaluation du jeton qui la précède.
- **Pistes, non instruites** : la forme de `proc_countdown` (un process qui attend et tue), comme le chien de garde du gate ; ou évaluer la ligne en arrière-plan et la collecter par `proc_collect` sous échéance. Attention aux pièges de [95] et [92] (une échéance est un process qui survit à qui l'a armée ; `wait` interrompu par un signal).
- **Question voisine, laissée à la passe suivante et non mesurée** : le stdin des programmes que **git** lance pour le pack (un `core.fsmonitor`, un hook configuré) — `proc_git` garde le stdin de l'appelant, et plusieurs boucles `while read … done <<X` du pack appellent git.
- **Ordre VALIDÉ par Philippe le 09/10/2026, à la livraison de [106] : [98] → [99] → [100] → [107]**, en fin de file, aucune arête. Une propriété de vivacité (un AFK non borné), pas un faux vert : ni ligne forgée ni verdict. Une échéance écrite ici serait du code du pack (`proc_countdown`), qui peut tenir les bouts lecteurs de [98] sans conséquence — pas de reprise dans un sens ni dans l'autre. Les deux autres options posées — en tête de file, hors file comme [97] — ont été écartées.
