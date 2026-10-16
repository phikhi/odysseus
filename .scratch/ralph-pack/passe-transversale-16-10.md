# Passe transversale du 16/10/2026

Dix-huitième passe. Faite sur `main` à `5d4eab9` (merge de [107]). **Cinq**
livraisons depuis celle du 09/10 : [106] `454fa8d`, [98] `121ba1d`, [99] `93888fe`,
[100] `e02bdc2`, [107] `5d4eab9`. Cinq sur cinq, la règle telle quelle
(`ralph-pack-cadence-des-passes`). Le compte repart à 0/5 après elle.

Sortie des rejeux et de leur verdict : `sondes/passe-16-10/README.md`. **Rien
touché hors `.scratch/`** → la baseline de [107] tient telle quelle (`run.sh`
**1113**/0/**7 skips**, `mutate.sh` **1205**/0) et les deux gates n'ont pas été
rejoués. Quatre sondes neuves (`g1`–`g4`) pour la trouvaille, en plus des rejeux.

---

## La racine

> **La série [101]–[107] a fermé un par un les descripteurs que le pack POSSÈDE :
> fds 3–255 pour tout ce qu'il lance ([101], [104], [105]), stdin pour les
> commandes de jeton qu'il évalue ([106]), et une borne de temps sur elles ([107]).
> Restent les deux canaux que le pack ne peut pas fermer parce qu'un usage
> LÉGITIME s'en sert — le stdin de git (git le lit) et le stderr de l'appelant
> (l'appelant y écrit ses diagnostics) — et sur chacun un tiers s'assoit.**
>
> [104] a fermé les fds de ce que git lance et a écrit, en toutes lettres,
> *« nothing a program git starts could inherit, whatever named it, at any
> MAX_PARALLEL »*. C'est vrai au-dessus de stderr, et faux de **fd 0** : git lit
> son stdin (des appelants pipent dedans — `check-ignore --stdin`), donc
> `proc_git` le garde, et le programme que git **lance** (un `core.fsmonitor`
> qu'une session écrit dans `~/.gitconfig`) en hérite. Dans les boucles
> `while read … done <<LIST` du pack, ce stdin est le **reste de LIST**.
>
> [107], de l'autre côté : il borne la commande de jeton, mais sa phrase « taken
> down » roule sur le stderr de l'appelant, et le premier appelant d'une itération
> (`tracker_cache_prime`) jette son stderr. La borne fonctionne et personne ne
> l'entend.

Le recensement, refait depuis ce qu'un programme lancé par le pack peut tenir —
non plus seulement les fds 3+, mais **les trois flux** :

| Flux | git lui-même | ce que git LANCE (fsmonitor/hook/filtre) | tenu par |
|---|---|---|---|
| fds 3–255 | fermés | **rien** | `proc_git` ([104]) |
| fd 2 (stderr) | l'appelant | l'appelant | — (va où va celui de l'appelant ; muet si jeté → §2) |
| fd 1 (stdout) | l'appelant | l'appelant (git lit la sortie du filtre/fsmonitor) | lu par git, pas par le pack |
| **fd 0 (stdin)** | l'appelant (git le lit) | **l'appelant aussi** — le reste de `<<LIST` dans une boucle | **rien → §1** |

Deux lignes manquent, une par canal partagé.

---

## §1 — Le stdin que `proc_git` garde pour git atteint les programmes que git lance (→ [110])

Sondes neuves `sondes/passe-16-10/g1`–`g4`, mesure hors pack
`scratchpad/fsmon/probe2.sh`.

**Le mécanisme, déterministe (hors pack).** Une boucle
`while read p; do git add -- ":(literal)$p"; done <<CHANGED` sous un
`core.fsmonitor` : le programme lancé par git hérite de fd 0 = le heredoc et
**avale `SENTINEL-line-b`/`SENTINEL-line-c`**. Le drain commence une itération
après la première (le 1er `git add` établit le token fsmonitor sans l'interroger,
le 2e l'interroge et draine tout le reste d'un coup) : lignes 1-2 de LIST toujours
traitées, 3+ sautées.

**Vif dans le pack** (`g1`) : une session écrit `core.fsmonitor` dans le
`~/.gitconfig` de l'opérateur (valeur qu'aucun `unset` du dépôt n'atteint, [104]) ;
sur une nuit, le programme lancé par git **tourne 136 fois et draine 166 lignes**
du stdin de git — des données réelles : la liste des chemins gardés + scellés que
la boucle `<<FORCED` de `gate.sh:3254` force-stage (`.claude/settings.local.json`,
`CLAUDE.md`, `.mcp.json`, `learning-records`, `.claude/agents`…).

**La garde de portée est défaite** (`g4`) : `GUARDED_PATHS` à trois répertoires,
la session écrit un fichier ignoré sous le **3e**. Témoin : `vendor/rogue` **nommé**
hors-surface et repris. Avec le plant : `vendor/rogue` **n'est plus nommé** — le
force-staging du 3e chemin est sauté, la garde ne le juge plus. Le force-staging
est précisément ce qui fait juger un chemin gardé ignoré (test de `gate.bats`
« an ignored file under a guarded path is caught … Without the forced add, git
add -A skips it … the ticket resolves and the file stays »). (`g2`/`g3` : lignes
1-2 — `.claude` et le 1er scellé — restent stagées, donc le sceau, qui lit les
scellés à part, tient ; le trou est sur la 3e ligne et au-delà.)

**Ce qui le tient encore debout — et la fragilité.** Dans `g4` la nuit reste
**rouge** (fichier repris, `ready-for-agent`), non par la garde de portée (défaite)
mais parce que **[46] attrape la clé** : `moved core.fsmonitor … could not put
back` → `delivery=red`. Toutes les clés que git exécute sur une op d'index —
`core.fsmonitor`, `filter.*.clean/smudge/process`, `hook.*` — sont dans
`gate_config_keys`. **Le force-staging de `<<FORCED` est donc tenu par [46], pas
par lui-même** : sa justesse est empruntée à une liste que [104] a appelée « a
thing that has to be right again tomorrow ». Un faux vert complet demande une clé
qui fasse exécuter un programme à git sur une op d'index, draine stdin, et ne soit
pas dans `gate_config_keys` — à trancher par [110]. Fermer stdin pour le programme
lancé rend le force-staging juste **sans** dépendre de cette liste.

La forme : un appelant `proc_git` qui ne pipe pas dans git lui donne `</dev/null`
(la forme de `proc_group_fork` pour `TEST_CMD`). Le seul qui pipe
(`gate_newly_hidden`, `check-ignore --stdin`) est un autre cas — git ET le
programme lancé se disputent le même tuyau — nommé dans [110].

---

## §2 — Une borne/un refus qui roule sur un stderr jeté est muet (matière écrite, PAS un ticket — décision de Philippe le 16/10)

Déjà mesuré et écrit par [107] (`proc.sh`, tableau), laissé non fermé. La phrase
« did not answer within Ns: taken down » et les refus de `forge__api` roulent sur
le stderr de l'appelant ; la **première** requête d'une itération,
`tracker_cache_prime`, fait `forge_cache_prime … >/dev/null 2>&1`, et beaucoup de
`tracker_field … 2>/dev/null`. Une borne qui tombe là ne laisse aucune trace sur
la nuit.

C'est la jumelle de §1 côté stderr : un canal que le pack partage avec un usage
légitime (l'appelant y met ses propres diagnostics) et sur lequel la voix du pack
se perd. **Sévérité honnête** : pas un faux vert ni une frontière franchie — de
l'observabilité, classe de [64] (un refus dit huit fois → une). **Philippe a
tranché le 16/10 : matière écrite, pas un ticket** — déjà au tableau et dans
`proc.sh` par [107], pas d'item d'observabilité dans la file. À rouvrir si une
borne muette coûte un diagnostic à un humain un matin.

---

## Ce que la passe a regardé et disculpé (ne pas re-sonder)

- **Le prix `/dev/tty` de [107] au drain** (matière 2) : déjà écrit par [107]
  comme un prix connu (une commande de jeton qui demande au terminal n'est plus
  servie, SIGTTIN d'un groupe d'arrière-plan). Rien pour l'AFK ; une perte au
  drain, nommée. Pas un ticket neuf.
- **La fenêtre `mktemp -d` → recensement** (matière 4, forme [103]) : le pin de la
  frontière est scellé dans `gate_frontier_pin` **avant** le recensement du pilote
  ([100], fenêtre courte — pas de claim ni de `worktree add` entre création et
  sceau) ; le dépôt-témoin du run est tenu par le sceau de [81]. Un recensement
  général des fenêtres `mktemp -d` → sceau n'est pas dérivé, nommé mais pas un
  ticket cette passe.
- **Le stdin tenu deux fois** (matière 5) : [107] en a trouvé un (une entrée de
  mutation VACUOUS, corrigée). Le cas est étroit (bash donne `/dev/null` à un
  `( ) &` forké depuis un sous-shell, un second porteur). La détection VACUOUS du
  gate de mutation est le filet ; pas de chasse exhaustive dans une passe.
- **Les rejeux des cinq tickets** tiennent tous (README) ; la seule chose non
  reproduite est le résidu `p2` de [100], **déjà ouvert en [109]**.

---

## Les tickets

| # | Ce qu'il ferme | Fichiers (à instruire) |
|---|---|---|
| **[110]** | le stdin que `proc_git` garde pour git atteint les programmes que git lance (boucles `while read … <<LIST; do proc_git <op d'index>`) | `proc.sh`, `gate.sh`, `test/proc.bats`, `test/gate.bats`, `test/mutate.sh`, tableau |

(§2 n'ouvre pas de ticket : Philippe l'a laissé en matière écrite le 16/10.)

### Ordre — **VALIDÉ par Philippe le 16/10/2026 : [108] → [110] → [109]**

File avant la passe : **[108] → [109]** (validée, aucune arête ; [97] hors file).
La passe insère **[110]** entre les deux. Arête neuve **108 → 110** (soft, pas de
`Blocked by` : les deux touchent les mêmes boucles `while read … <<LIST`, [108]
convertit les heredocs puis [110] donne la discipline de stdin sur leur forme
finale — voisins pour ne pas retoucher les mêmes lignes deux fois). [109]
(`gate_frontier_moved`) ne partage rien, reste en fin. [97] hors file.

**Prochaine passe** : après le cinquième ticket livré à partir d'ici (la file en a
trois — [108], [110], [109] — donc après deux de plus, à moins qu'ils ne s'ouvrent
en route).
