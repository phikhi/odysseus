# 76 — La première page est tout le tracker d'un backend distant

**What to build:** Une lecture de tracker distant qui rend le tracker entier, et un faux de suite capable de servir plus d'une page — sans quoi rien de tout ça n'est mesuré.

**Blocked by:** None

**Write-surface:** `.claude/lib/forge.sh`, `test/tracker-remote.bats`, `test/helpers/shims/forge-api`, `test/helpers/harness.bash`, `test/mutate.sh`

**Status:** ready-for-agent

- [ ] `tracker_ids`, `tracker_frontier`, `read_ticket` et `field` rendent le tracker **entier** quand il tient sur plusieurs pages.
- [ ] Deux pages ne se recouvrent pas : un enregistrement est identifié par ce que la forge lui donne, jamais par sa place dans un tableau.
- [ ] Le faux de la suite sert plus d'une page pleine, et un test lit un tracker de plus de cent tickets.
- [ ] Une lecture qui s'arrête sur une borne du pack (le plafond de pages) le **dit** au lieu de rendre une liste courte.
- [ ] `per_page` et la borne à laquelle le compte est comparé sont un seul nombre, écrit une fois.

## Comments

- **Ouvert par la passe transversale du 08/09/2026** (`../passe-transversale-08-09.md`,
  §1 ; sondes `../sondes/passe-08-09/q1-*.bats`). Deux défauts empilés, et le
  second est caché par le premier.

- **Le premier : la borne ne compte jamais le premier enregistrement d'une page.**

  ```sh
  count="$(printf '%s' "$body" | LC_ALL=C awk -F'\t' '
    { split($1, f, "."); if (f[1] != last) { n++; last = f[1] } }
    END { print n + 0 }')"
  [ "${count:-0}" -ge "${FORGE_PAGE:-100}" ] || break
  ```

  `f[1]` sorti de `split()` est un **strnum** (« 0 » ressemble à un nombre) et
  `last` n'est pas initialisée, donc awk compare **numériquement** : `0 == 0` est
  vrai, le premier enregistrement n'est pas compté, et `last` n'est même pas
  affectée. **Mesuré** : `1` sur une page de deux enregistrements, `99` sur une
  page pleine de cent. `99 >= 100` est faux. **La page deux n'est donc jamais
  demandée, sur aucun tracker.**

  Ce n'est pas une hypothèse de laboratoire : `state=all` est la bonne décision
  de [18] — un ticket résolu revendique sa write-surface autant qu'un ouvert —
  et elle garantit que n'importe quel dépôt un peu vécu dépasse cent issues.

- **Le second : deux pages se recouvrent.** `forge__records` reconstruit un
  enregistrement par **indice de tableau** (`rec = substr(p, 1, dot - 1)`), et
  `forge_json` numérote les éléments de **chaque document**. La première issue de
  la page deux est `0.number` comme celle de la page une : elle l'écrase.
  **Mesuré** (Q1c, avec `FORGE_PAGE=1` pour franchir la borne faussée) : un
  tracker de quatre issues servi deux par page rend `3-gamma` et `4-delta`, et
  `1-alpha` se lit « pas de ticket ». Réparer la borne seule échangerait un
  tracker tronqué contre un tracker **faux** : les deux moitiés se livrent
  ensemble.

  Attention à la variante silencieuse : une clé absente d'un enregistrement de la
  page deux ne remplace pas celle de la page une (`who[rec]`, l'assignee, est la
  seule qui manque en pratique), donc un enregistrement peut aussi être un
  **mélange** de deux issues.

- **Ce que la troncature coûte, en descendant les consommateurs.** À vérifier en
  livrant, parce que c'est ce qui dit si le correctif suffit :
  - le **scope-guard** — c'est l'AC 5 de [18] atteinte par l'autre bout : un
    débordement dans la write-surface d'un ticket perdu par le listing est classé
    débordement interne, donc **retry au lieu d'escalade**, en boucle (mesuré,
    Q1d) ;
  - la **frontière** — les tickets de la page deux ne sont jamais travaillés, et
    une frontière vide est ce qui déclenche le gate de valeur terminal ;
  - **`Blocked by:`** — `forge__is_unblocked` fait bloquer un id qui ne pointe sur
    rien, et c'est le bon fail-safe : tout ticket bloqué par un ticket de la page
    deux quitte la frontière **pour de bon** ;
  - **`claim_reclaim_stale`** et **`failures_quarantine_strays`** — un claim de
    run mort posé sur un ticket de la page deux n'est jamais balayé ;
  - le **drain** — `router__tracker_state` et `router_unblocks` lisent la même
    liste.

- **Le piège qui explique pourquoi personne ne l'a vu, et il est à réparer ici.**
  Le faux `curl` de la suite le dit lui-même : « Page two and beyond are empty:
  this fake holds fewer tickets than a page. » Aucun test de ce dépôt n'a jamais
  fait tourner la boucle de pagination, et `FORGE_PAGE` n'apparaît dans aucun
  test. Un correctif livré contre ce faux-là serait vert sans rien prouver : la
  première AC de ce ticket est le faux, pas le pack. La sonde `q1` montre la
  forme minimale — un `curl` qui lit `page=` dans l'URL, rend un tableau par page
  et `[]` ensuite, en terminant par `\n200` parce que `forge__http` lit le statut
  comme dernière ligne.

- **Et la mutation qui doit rougir** (obligation 1 de la definition of done) : la
  garantie n'est pas « le compte est juste », c'est « le tracker rendu est le
  tracker ». Une entrée qui remet le `!=` numérique doit faire rougir un test qui
  lit un tracker de **plus d'une page pleine** ; une entrée qui remet
  l'identification par indice doit faire rougir un test qui lit un ticket de la
  **première** page alors qu'il y en a deux. Deux entrées, deux témoins, parce
  qu'un seul test verrait les deux défauts comme une seule absence de ticket.

- **Question transversale à poser en le livrant** : ce que ce ticket répare est
  une lecture qui rend **moins** que ce qu'on lui demande sans le dire. Le pack a
  la même forme ailleurs — le plafond de vingt pages, et `FORGE_PAGE` comparé à un
  `per_page=100` écrit dans un autre fichier. Une lecture bornée qui se tait est
  exactement ce que [59] a fermé pour les refus de git ; ici la valeur n'est pas
  un refus, c'est une liste courte, et aucun appelant ne peut faire la différence.
