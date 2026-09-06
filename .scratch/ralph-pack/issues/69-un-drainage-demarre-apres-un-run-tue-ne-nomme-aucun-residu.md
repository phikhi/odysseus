# 69 — Un drainage démarré après un run tué ne nomme aucun résidu

**What to build:** `loop_main` dit au démarrage ce que les runs précédents ont laissé dehors (`gate_leftovers`) et dedans (`concurrency_leftovers`). `human_loop_main` n'appelle ni l'un ni l'autre — alors qu'un drainage démarré après un run tué est exactement la situation où un humain vient voir ce qui s'est passé.

**Blocked by:** None

**Write-surface:** `.claude/human-loop.sh`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** human-loop, observability

- [ ] Un drainage démarré après un run tué nomme ce que ce run a laissé : `$TMPDIR` ([62]), les gardes d'exclusion morts ([49]), le marqueur de successeur ([53]), les worktrees encore enregistrés ([13]).
- [ ] Le choix est **explicite** : `human_loop_preflight` est écrit comme *une liste et pas une délégation*, donc ce qui est ajouté l'est ligne par ligne, jamais par un appel à `loop_preflight`.
- [ ] Ce qui est ajouté ne **refuse** rien : ces lignes comptent, elles ne jugent pas — même posture que dans `loop_main`, et un drain qui refuserait de démarrer sur un résidu empêcherait un humain de venir regarder.
- [ ] Une entrée de mutation par garantie livrée, plus le témoin appairé.

## Comments

- **Le constat était ouvert dans [16]** et il a été qualifié par la passe transversale du 06/09/2026 (`../passe-transversale-06-09.md`, §5). Sondes : `../sondes/passe-06-09/q4-*.bats`.

- **Mesuré** (`q4`), run réel tué au `KILL` pendant le gate :

  | | |
  |---|---|
  | Q4a — un drainage démarré sur ce décor | décor : **9** entrées dans `$TMPDIR`, un marqueur de successeur, **1** worktree encore enregistré. Le drain en nomme **0** |
  | Q4b — témoin appairé, un run AFK sur le même décor | il en nomme **3** : les 9 entrées comptées **9**, le marqueur, le worktree |

- **Inerte, et c'est pour ça que c'est le moins cher des quatre** : un silence, pas un faux vert. Mais c'est un silence dans la seule situation où le pack a un humain qui regarde — un run tué, un puits qu'on vient vider le matin — et le pack a un document sur ce qu'il ne regarde pas.

- **Même racine que [55]/[56]/[57]** : une garantie qui est une propriété de `loop.sh` et pas du pack. La liste des choses que `loop_main` fait au démarrage et que `human_loop_main` ne fait pas a été mesurée en entier par la passe ; ce qui reste après ce ticket est délibéré (`budget_*`, `concurrency_cap`, `claim_reclaim_stale`, `playthrough_*`, `retro_*`, `capability_witness` — un drain ne spawne pas d'itération, ne juge rien et ne clôt aucune feature).

- **Contrainte pour [19].** Le commentaire de `gate_leftovers` désigne l'installeur comme le composant entitled à balayer, et [62] a fait de `gate_tmp_names` la spécification de ce balayage. Ce ticket ajoute un **second lecteur** de `gate_leftovers` : ce que [19] balaye sera nommé par deux points d'entrée, et une divergence entre les deux serait deux vérités sur le même disque.

- **Piège de sonde.** Un ticket `ready-for-human` ne fait pas démarrer un gate : une sonde qui veut tuer un run doit semer un ticket `ready-for-agent` en plus. Et un run tué garde ses verrous — `rm -rf "$(run_lock_dir)" "$(tree_lock_dir)"` avant de démarrer quoi que ce soit derrière lui.
