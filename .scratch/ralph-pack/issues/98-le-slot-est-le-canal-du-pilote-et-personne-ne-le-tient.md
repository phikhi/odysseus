# 98 — Le slot est le canal du pilote, et personne ne le tient

**What to build:** Qu'une itération cesse de rendre ses réponses au pilote par des fichiers nommés dans un répertoire de `$TMPDIR` dont le pack publie lui-même le glob — ou que chacune des sept réponses dise ce qu'elle vaut. Les deux bornes que le tableau nomme chaque fois qu'il accepte un signal qu'une session peut écrire, `STERILE_K` et `BUDGET_MAX_PAUSE`, sont lues là.

**Blocked by:** None

**Write-surface:** `.claude/loop.sh`, `.claude/lib/budget.sh`, `test/loop-happy-path.bats`, `test/concurrency.bats`, `test/budget.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] **`$slot/outcome`** n'est plus lu dans un fichier qu'un process extérieur à l'arbre du pilote peut réécrire. C'est le poste qui décide de `sterile` — donc de `STERILE_K`, la borne que `failures_handle` et la ligne 64 du tableau nomment tous les deux comme **ce qui borne une session qui forge cette classe** — et aussi de `tracker_unclaim` (`iteration-lost`, `pilot-gone`) et de deux `stop_code=4`.
- [ ] **`$slot/posture`** de même, et il a **deux** lecteurs : le pilote (`loop.sh:1460` → `budget_check` → pause / `stop_code=6` / armement d'un successeur) et l'itération elle-même (`loop.sh:1005`, `1029`, `1202` → `budget-pause`, *« given back with no retry consumed »*). Un seul des deux fermé ne ferme rien.
- [ ] **`$slot/rollback-failed`** de même (`stop_code=4`).
- [ ] **`$slot/drift`** de même, et c'est le seul des sept où il n'y a **aucune course** — **mesuré sans survivant**, la session écrivant le fichier elle-même pendant sa fenêtre : le pack ne l'écrit que sur une dérive de capacité, de `PATH` ou de forensique, donc un fichier créé par une session y est lu tel quel et chaque ligne devient `loop_journal_append "$sujet" "$outcome"` avec un sujet arbitraire. Conséquence à écrire dans la réparation : ces lignes sont écrites par le **pilote**, donc elles entrent dans `RALPH_JOURNAL_WITNESS` et `loop_journal_verify` ne voit aucun écart — **le témoin de [10] est silencieux parce que le pilote a écrit la ligne lui-même.**
- [ ] **`$slot/turns` `cost` `tokens` `action` `n`** : ce ne sont pas des verdicts, c'est la comptabilité que l'humain lit le matin. Même décision ou aveu écrit, comme [97] le fait pour les faits du reçu.
- [ ] **`$slot/done`** est tranché : `loop__reap` lit `[ -e "$slot/done" ] || ! kill -0 "$pid"` puis appelle `proc_collect`, qui attend — donc un `done` forgé ne récolte pas une itération vivante, il fait **attendre** le pilote. C'est un déni et pas une forge, et un déni est un défaut ([94] l'écrit pour un `mktemp`) : à trancher, avec la mesure.
- [ ] La ligne du tableau est écrite. Aucune ligne ne parle aujourd'hui du slot ; la ligne 64 en parle **par erreur**, en écrivant que « ce qu'il coûte au pire est borné par `BUDGET_MAX_PAUSE` et `STERILE_K`, que rien de ce répertoire ne déplace » — vrai de `.scratch/`, faux du pack.
- [ ] Témoin appairé et survivant réel, comme [92], [94] et [96]. Le canari reçoit le cas qui décide (une nuit dont le compteur `sterile` ne monte jamais).
- [ ] Une entrée de mutation par garantie livrée, avec son témoin appairé.

## Comments

- **Ouvert par la passe transversale du 29/09/2026** (`../passe-transversale-29-09.md`, §1). Sonde : `../sondes/passe-29-09/q1-le-slot-du-pilote.bats`.

- **Mesuré**, quatre tickets, `MAX_PARALLEL=1`, un `nohup` avec `trap "" TERM` planté par la session qui réécrit un fichier du slot en boucle à 10 ms (la fenêtre du pilote est confortable : `loop__reap` dort 0,2 s entre deux passes, et l'itération écrit `outcome` puis `done` juste avant) :
  - **témoin** — aucune session ne livre, rien de planté : 3 appels `claude`, `sterile run: 3 iterations resolved nothing — stopping`, exit 4 ;
  - **`$slot/outcome` = `resolved`** : **9 appels `claude`**, 8 itérations, `iteration cap reached (8) — stopping`, et le journal dit **7 `resolved`** sur une nuit où aucune session n'a écrit une ligne. `ITER_CAP` était mis à 8 pour la sonde ; à sa valeur livrée (50), c'est une nuit de cinquante sessions au lieu de trois ;
  - **`$slot/posture` = `blocked weekly 0`**, itérations vertes : exit **6** après **un** ticket, *« the weekly usage limit blocks this run (weekly, said by the stream) »*, les trois autres tickets intacts — et la phrase nomme la **mauvaise source**, le flux n'ayant pas été touché ;
  - **`$slot/rollback-failed` = `1`**, itération verte : *« the rollback could not put this iteration's tree back — stopping rather than grinding on an instrument that is already closed »* ;
  - **`$slot/drift` écrit par la session, sans survivant et sans attendre quoi que ce soit** : deux lignes dans le `run.log` du matin, sujet et outcome arbitraires, indiscernables de celles du pack, run exit 0 — `FORGED-SUBJECT<TAB>capability-drift` et `../../../etc/passwd<TAB>forged-outcome` — et le témoin de [10] muet.

- **La fenêtre est celle de [83] mot pour mot**, et c'est ce qui rend la réparation de repli disponible tout de suite : rien dans le pack n'écrit dans ce répertoire entre le premier et le dernier octet d'une session — `n` est posé par le pilote avant le fork, tout le reste après le gate. Donc l'option « recensement dérivé pris dans la mémoire de l'itération avant sa session, question posée après » est exactement `retro_hold_state` / `retro_state_note` transposé. Ce n'est **pas** la seule option et probablement pas la meilleure : voir le point suivant.

- **Le mécanisme de [94]/[96] s'applique ici et c'est la première fois qu'il s'applique du pilote vers son fork.** Un fichier **ouvert deux fois puis délié avant le premier octet** (`eval "exec N>\"\$f\" M<\"\$f\""` puis `rm -f`), ouvert par le **pilote** avant `loop__iterate … &` : le fork hérite des deux descripteurs, un étranger ne peut pas trouver l'inode. C'est la forme la plus pure du motif — écrit une fois par un fork, lu une fois par son parent, contrairement au registre de [80]. Les faits de plomberie sont dans `../../../.claude/lib/gate.sh` (`gate__notes_open`) et dans la mémoire `ralph-pack-ticket-94-le-canal-dune-branche`. **Trois choses à reprendre avec** :
  - **la borne de longueur est obligatoire**, et c'est une garantie de sécurité et pas de l'hygiène : 8 écrivains, lignes de 1000 o → 480/480 entières, 4000 o → **147/480**, et la queue d'une valeur coupée arrive **comme une ligne**, signée du nom par lequel elle commence. `GATE_NOTE_MAX=512` et un **refus**, jamais une troncature ;
  - **les numéros de descripteurs sont pris** : `monitor_watch` = **3** (un littéral), `receipt` = 5/4, prompt de lentille = 7/6, notes du gate = 9/8. Le recensement est de la prose, dans un commentaire de `receipt.sh:129`. Un cinquième canal doit l'y lire et l'y écrire ;
  - **et il faut le fermer autour des `exec`** : `session_spawn` (le seul point de passage de `claude`) et `gate__command_branch` (les deux commandes du projet). Le recensement qui dit qu'il n'y a pas de quatrième site est celui de [95] et rien ne le dérive à nouveau.

- **Ne pas rouvrir [80] au prétexte de ce ticket.** `ralph-slot.writes.*` est la même famille de nom et ce n'est pas un oubli : ses lecteurs ne sont pas le process qui écrit, donc un canal délié n'y marche pas, et [80] a rendu le registre moins payant à la place. La raison que [80] a écrite — *« an unlinked descriptor does not reopen the same way on every platform »* — est vraie pour un registre relu par des frères et fausse pour le slot. Dire la différence dans le code plutôt que la redécouvrir.

- **Contrainte héritée par [99]** : `loop__finish` finit par `rm -rf "$slot"` et ce `rm` est le déclencheur mesuré du défaut de [99]. Si ce ticket fait disparaître le répertoire, il fait disparaître le déclencheur **et pas la classe** — [99] doit alors trouver une mise en scène qui ne dépende pas du slot. C'est la bonne contrainte : la classe n'a jamais été celle du slot.

- **Ce que `MAX_PARALLEL` change, à instruire plutôt qu'à supposer** : chaque itération a son propre slot, donc contrairement à [80] et [81] la réparation n'a pas d'aveu « et jamais au-dessus de `MAX_PARALLEL=1` » à écrire pour le slot lui-même. Mais un canal ouvert par le pilote et hérité par **plusieurs** forks est un canal partagé — c'est exactement la mesure d'atomicité ci-dessus, et c'est pour ça qu'elle est citée ici.
- **Ordre VALIDÉ par Philippe le 29/09/2026** : **[98] → [99] → [100]**. Arête unique **[98] → [99]** ; [100] n'est bloqué par rien et passe en dernier parce qu'il ne partage rien avec les deux autres (autre répertoire, autre module, autre ligne du tableau). [97] reste hors file.
  **Premier de la file** : il change la forme du canal entre une itération et le pilote, et [99] doit savoir si `rm -rf "$slot"` existe encore.
