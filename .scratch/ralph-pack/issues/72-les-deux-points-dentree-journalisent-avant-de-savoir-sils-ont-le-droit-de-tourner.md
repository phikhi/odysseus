# 72 — Les deux points d'entrée journalisent avant de savoir s'ils ont le droit de tourner

**What to build:** `loop_main` et `human_loop_main` prennent leur base de journal, puis appellent leur préflight — qui **journalise** les constats du tracker depuis [64] — et **seulement ensuite** demandent les deux verrous. Celui qui perd le verrou a donc déjà écrit dans le `run.log` de l'autre, et le témoin de l'autre ([10] côté run, [67] côté drain) l'accuse d'avoir réécrit son journal. Le refus « un seul écrivain ici » tombe après l'écriture qui le suppose, dans les deux sens.

**Blocked by:** None

**Write-surface:** `.claude/loop.sh`, `.claude/human-loop.sh`, `test/human-loop.bats`, `test/loop-happy-path.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** human-loop, journal, concurrency

- [ ] Un point d'entrée qui n'obtiendra pas les verrous n'écrit **aucune ligne** dans `run.log`. Ce qu'il a à dire des constats du tracker, il le dit à l'écran comme aujourd'hui.
- [ ] Le témoin de l'autre point d'entrée ne se déclenche pas : un run qui tourne pendant qu'un humain essaie de drainer finit sans accuser personne, et réciproquement.
- [ ] La règle est écrite là où un lecteur la cherchera : *ce qui, dans le préambule d'un point d'entrée, a le droit d'écrire avant les verrous.* Les deux fichiers portent aujourd'hui un commentaire qui explique où la **base** est prise et rien sur ce qui **écrit**.
- [ ] Le témoin appairé est livré avec : le même run, sans point d'entrée concurrent, ne dit rien.
- [ ] Une entrée de mutation par garantie livrée.

## Comments

- **Trouvé par la passe transversale du 07/09/2026** (`../passe-transversale-07-09.md`, §4). Sondes : `../sondes/passe-07-09/q4-*.bats`.

- **Mesuré** (`q4`), sur un tracker portant deux tickets sur le numéro `20` — l'état que [27] et [47] existent parce qu'il arrive :

  | | |
  |---|---|
  | Q4a — un run AFK tourne, un humain lance un drainage | le drain écrit `20 ambiguous-id … action=drain`, **puis** découvre que l'arbre est tenu (`rc=1`, « another run already holds this working tree »). Le run finit en disant « the run journal does not hold exactly the 3 line(s) this run wrote … **do not believe it about this run** » |
  | Q4b — témoin appairé, le même run sans drainage à côté | **0** accusation |
  | Q4c — l'autre sens, un drainage tient les verrous et un run AFK démarre | le run écrit `20 ambiguous-id … action=none` **puis** refuse (`rc=1`) ; c'est `router_journal_verify` qui accuse, même phrase |

- **Inerte sur les décisions, pas sur le lecteur.** [10] et [67] tiennent tous deux que le journal n'est une autorité pour personne, donc rien n'est marqué de travers. Ce qui est perdu est le signal lui-même : c'est le corollaire du 24/08 — *une ligne qui dit « je n'ai pas pu » doit être nette de ce qu'elle a pu* — lu sur le mécanisme le plus cher du pack. Un humain qui a vu cette phrase une fois pour rien ne la relira plus, et elle est le seul endroit où le pack dit « une session a réécrit ton journal ».

- **Le déclencheur est le geste le plus banal qui soit** : lancer le drainage pendant que le run tourne. Le pack le refuse *correctement* — c'est [22] et c'est ce que les deux verrous sont — et le refus arrive après l'écriture.

- **Ce qui est en cause n'est pas la base, c'est l'écriture.** Le commentaire des deux fichiers explique très bien pourquoi la base est prise avant le préflight (« a base read on the first append is already past whatever went missing before it »), et cette raison-là tient. Ce que personne n'a posé est que le préflight, depuis [64], **écrit**. Les deux moitiés sont séparables : garder la base là où elle est et déplacer la journalisation derrière les verrous suffirait, à condition de dire ce que devient le constat quand le point d'entrée refuse de tourner — il doit rester dit à l'écran, sinon un humain perd la seule phrase qui explique pourquoi sa frontière est vide.

- **La règle à écrire est plus large que le correctif**, et c'est ce que [70] réutilise : *le préambule d'un point d'entrée s'exécute avant que le pack sache s'il a le droit de toucher cet arbre.* Tout ce qu'on y ajoute — un constat, un épinglage, un balayage — hérite de ça. [69] a déjà ajouté deux lignes à ce préambule (les résidus) et elles sont, elles, purement lisantes ; c'est une chance et pas une propriété.

- **Contrainte pour [70]** : c'est ici que se décide **où** le préambule de `loop_main` a le droit d'écrire et d'épingler. [70] pose un témoin dans ce même préambule ; livré derrière ce ticket, il place son épinglage sous une règle déjà écrite.

- **Contrainte pour [64]** : le constat qu'il a fait journaliser par les deux points d'entrée est exactement ce que ce ticket déplace. Sa garantie — « une fois par run **et** par drain, dans `run.log` et à l'écran » — doit rester vraie pour un point d'entrée qui tourne vraiment, et devenir « à l'écran seulement » pour celui qui refuse.

- **Piège de sonde.** Il faut deux processus vivants en même temps. Côté run : un faux `claude` qui touche `$RALPH_SHIM_STATE/in-session` puis attend `$RALPH_SHIM_STATE/go`. Côté drain : un **fifo** sur son stdin (`mkfifo` + `exec 9>`), sinon il sort immédiatement sur « stdin ended » et ne tient jamais les verrous.

- **Place dans la file, validée par Philippe le 07/09/2026 : deuxième.** Délié (`Blocked by: None`), deux fichiers, un seul mécanisme — et il tranche où le préambule de `loop_main` a le droit d'écrire, ce dont [70] a besoin pour placer son épinglage une seule fois. Ordre retenu : [71] → [72] → [70] → [18] → [19].
