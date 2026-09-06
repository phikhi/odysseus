# 66 — Le desk du puits est choisi par une ref git qu'une session routée écrit, et efface

**What to build:** Épingler `refs/heads/failed/<id>` avec les trois champs que `router_pin` épingle déjà, et faire dire au drain ce qu'une session routée a laissé **hors de l'arbre de travail et hors de `issues/`** — les deux endroits que le garde nommé pour ça ne regarde pas.

**Blocked by:** 67

**Write-surface:** `.claude/lib/router.sh`, `.claude/human-loop.sh`, `test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** human-loop, trust-boundary

- [ ] `router_pin` épingle l'existence **et** la cible de `refs/heads/failed/<id>` avant que le dossier soit montré, comme il épingle `Escalation:` ([55]) et `Failures:` ([61]).
- [ ] `router_desk` et `router_dossier` décident et racontent sur la valeur épinglée, jamais sur l'état du dépôt au moment de la lecture.
- [ ] Une session routée qui **crée** une ref `failed/<id>` est nommée. Une session routée qui en **efface** une l'est aussi, et la phrase dit que la preuve est perdue — pas seulement qu'un chemin a bougé.
- [ ] `router_tree_note` (ou son successeur) cesse d'être nommé comme le garde de « ce qu'une session a laissé hors de `issues/` » tant qu'il ne l'est pas : soit il couvre les refs et la zone de bookkeeping, soit le commentaire de `router_desk` cesse de le nommer et dit qui garde vraiment.
- [ ] Une entrée de mutation par garantie livrée, plus le témoin appairé (une session qui n'écrit pas de ref ne doit rien faire dire au drain).

## Comments

- **Trouvé par la passe transversale du 06/09/2026** (`../passe-transversale-06-09.md`, §1). Sondes : `../sondes/passe-06-09/q1-*.bats`.

- **C'est [61] par l'autre bout, et [61] est cité dans le commentaire qui laisse la ref dehors.** `router_desk` distingue les trois arrivées de `decision` par deux preuves : l'existence de `refs/heads/failed/<id>` et la valeur de `Failures:`. [55] a épinglé `Escalation:` ; [61] a épinglé `Failures:` après avoir **mesuré** qu'une session routée qui s'ajoute `**Failures:** 1` envoyait la session suivante du même ticket de `admit` à `triage-host` — « two desks on one ticket, the second chosen by the first ». Le commentaire écrit ensuite, mot pour mot :

  > The `failed/<id>` ref is still read as it stands, and that is the boundary: pinning a git ref is a different mechanism, a routed session that writes one has left a branch behind it in the repository, and **`router_tree_note` is what looks at what a session left outside `issues/`**.

  `router_tree_note` lit `router__tree_dirt`, qui est `git diff --name-only HEAD` plus `git ls-files --others`, **moins `gate_is_bookkeeping`**. Une ref n'est pas un chemin de l'arbre de travail. La phrase nomme un mécanisme qui ne fait pas le travail.

- **Mesuré** (`q1`), session routée qui n'écrit **que** la ref, dans un drain réel :

  | | |
  |---|---|
  | Q1a — `git update-ref refs/heads/failed/20-decision HEAD` | desk **`admit` → `arbitrate`** ; le dossier suivant dit « branch failed/20-decision — the tree of the attempt, as it was. `git log -p failed/20-decision` » ; le drain a nommé **0 chemin** |
  | Q1b — témoin appairé, la même session sans la ref | desk **`admit`**, « branch there is none. nothing ever ran on this ticket » |
  | Q1c — `git update-ref -d` sur la ref d'une tentative **réellement jugée** | desk **`arbitrate` → `admit`** ; le dossier affirme « **there is none. nothing ever ran on this ticket** » ; **0 chemin nommé** |

- **Les deux sens ne coûtent pas la même chose, et c'est ce qui doit décider de la réparation.** Q1a est une **fausse route** : un humain envoyé au guichet `arbitrate`, avec la question, le traitement et le prompt de la session suivante qui vont avec — exactement le défaut de [61], réparable par un épinglage. Q1c est une **destruction de preuve** : la branche forensique est ce que le reçu envoie lire quand un ticket a vieilli dans le puits (`router_dossier` : « `failed/<id>` is a ref: it survives, and it is what to lean on for a ticket that has been in this sink for a while »), et un épinglage ne la rend pas. Ce qu'un épinglage achète sur Q1c est **de le dire** — le drain sait qu'il y avait une ref au début du ticket et qu'il n'y en a plus.

- **Ce que le tableau de frontière dit aujourd'hui** (ligne « Ce qu'une session écrit dans `.git/` ») : « le reste de `.git/` — refs, objets, `config` au-delà des clés que ces deux mécanismes épinglent — n'est vérifié par rien : le rempart est l'isolation de l'hôte ». C'était suffisant tant que **rien ne lisait une ref pour décider**. Depuis [16], une ref est l'entrée d'un contrôle. La ligne est à élargir en livrant.

- **Une session AFK atteint les mêmes refs**, et c'est à écrire plutôt qu'à découvrir : un worktree d'itération partage le répertoire git commun, donc `git -C <worktree> update-ref` écrit les mêmes refs que le pilote. Ce qui borne le cas AFK est que le gate juge l'arbre et pas les refs — donc l'itération n'en devient pas verte — mais la ref, elle, survit au rollback comme tout ce qui est dans `.git/`. Décider ici si la garantie visée est « le drain décide sur ce qu'il a épinglé » (suffisant) ou « les refs `failed/*` sont gardées » (plus large, et ce serait un ticket à soi).

- **Contrainte pour [18].** [18] porte déjà la remarque « `router_desk` distingue les trois arrivées de `decision` par les preuves […] la branche est une **ref git locale** ; sur un backend distant elle peut vivre ailleurs, et un ticket dont l'arbre de tentative est une PR fermée sera routé sur le guichet `admit` (« aucun run n'a jamais jugé ceci »), ce qui est faux. Si ce ticket déplace la trace forensique, il possède la question de savoir comment le routeur la trouve. » Ce ticket-ci ajoute la moitié qui manquait : **et qui l'épingle**. Un backend distant qui rend la trace forensique par une requête rend une preuve écrite par ce qu'une session peut appeler.

- **Piège de sonde.** Un drain rend 3 (« stdin ended ») dès que le script de réponses est épuisé — ce n'est pas un refus, ne pas asserter dessus. Et `printf '%s' "$out" | grep -c journal` compte le libellé du dossier : pour mesurer un silence il faut chercher la phrase exacte.
