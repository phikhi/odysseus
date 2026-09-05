# 65 — La borne du gate de valeur est comptée sur un espace de noms qu'une session écrit

**What to build:** `PLAYTHROUGH_REINJECT_MAX` doit borner ce que **le pack** a ouvert, pas ce qui **porte un nom**. Aujourd'hui trois fichiers déposés par une session dans `issues/` éteignent définitivement la réinjection du gate de valeur pour cette feature.

**Blocked by:** None

**Write-surface:** `.claude/lib/playthrough.sh`, `test/playthrough.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** playthrough, tracker, security

- [ ] Le compte que `PLAYTHROUGH_REINJECT_MAX` borne vient d'une source qu'une session n'écrit pas. Le registre d'écritures du pilote ([13]/[40], `RALPH_TRACKER_LOG`, un `mktemp` jamais exporté) est la forme évidente ; le ticket doit dire pourquoi celle-là et pas une autre, et ce qu'elle coûte au « a variable resets, a tracker does not » qui a justifié le scan.
- [ ] La déduplication de `tracker_open_unique` sur le slug est regardée par le même bout : une session qui pose un ticket portant *exactement* le slug que le gate utiliserait fait ouvrir **rien** au gate. Même direction, même silence.
- [ ] Quand la borne est atteinte ou que la dédup mord, la phrase dit **qui** a mis les tickets là si le pack le sait. Aujourd'hui elle nomme la borne (« past the 2 re-injection(s) `PLAYTHROUGH_REINJECT_MAX` allows this feature ») et jamais la contrefaçon.
- [ ] **Attention à la condition d'arrêt.** Les deux mutations écrites en livrant [11] retiraient déjà la borne dans la direction qui **termine encore** ; toute entrée neuve doit faire pareil, sinon `mutate.sh` reste bloqué avec un défaut planté dans l'arbre.
- [ ] Entrée de mutation par garantie livrée, plus le témoin appairé.

## Comments

- **Trouvé par la passe transversale du 05/09/2026** (`../passe-transversale-05-09.md`, §4). Sonde : `../sondes/passe-05-09/q3-…bats`, cas `Q3e`.

- **Le commentaire dit pourquoi il lit le tracker, jamais qui l'écrit.** `playthrough__injected` compte les ids contenant `PLAYTHROUGH_SLUG_PREFIX` (`playthrough-wiring`), « read off the tracker rather than counted in the run, for the reason the header gives: **a variable resets, a tracker does not** ». C'est vrai et c'est insuffisant : `issues/` a deux écrivains.

- **Mesuré, run réel** (`q3` Q3e). Une session de livraison dépose trois fichiers `60/61/62-playthrough-wiring-forged.md` dans `issues/`. La quarantaine de [07] les voit, les **nomme** et leur **laisse leur nom** :

  ```
  ralph: 01-alpha: the session wrote the tracker itself — quarantined
         60-playthrough-wiring-forged, 61-…, 62-…
  ```

  Après le run :

  ```
  tickets présents      : 01-alpha.md 60-…-forged.md 61-…-forged.md 62-…-forged.md
  playthrough__injected : 3
  ```

  Avec le défaut `PLAYTHROUGH_REINJECT_MAX=2`, cette feature ne rouvrira **plus jamais** un ticket de câblage : chaque playthrough rouge part droit au puits humain par `playthrough__why_human`.

- **La direction est sûre, et ce n'est pas une excuse.** Le compte ne peut que monter — une session ne peut pas supprimer un ticket, [21] restaure —, donc l'effet est « un humain est demandé plus tôt » et jamais un faux vert. Ce qui est perdu est **l'autonomie de la nuit** : le palier que [11] a construit pour se réparer tout seul est éteint par une session, en silence, et la phrase que l'humain lit accuse la borne.

- **C'est la question 5 du CLAUDE.md dans sa forme canonique** — *un contrôle qui lit un fichier que la session peut écrire n'est pas un contrôle* ([21], [55]) — appliquée à une **borne** plutôt qu'à un champ. La famille est celle de [55] (`Escalation:` lu sur le ticket) et de [42] (les deux gardes du tracker qui ne lisaient pas le registre) ; la réparation de [42] est exactement le registre qu'il faut réutiliser ici.

- **Ce que [18] hérite.** [11] avait déjà écrit dans [18] que `playthrough__injected` lit le slug **dans l'id** et qu'un backend numérotant côté serveur casse la borne. Cette trouvaille l'élargit : la borne ne lit pas seulement un id, elle lit un espace de noms **à deux écrivains**. Si ce ticket passe avant [18], [18] écrit contre un compteur réparé ; sinon [18] hérite des deux problèmes à la fois.

- **Piège rencontré en sondant.** `$FEATURE` n'est pas dans l'environnement du faux `claude` : une sonde qui veut écrire dans `issues/` depuis une session prend le répertoire par un glob (`ls -d "$root"/.scratch/*/issues`), jamais par `$FEATURE`. Et un `pack_run` écrase `$status`/`$output` — copier la sortie du `run_loop` avant.

- **Place dans la file, validée par Philippe le 05/09/2026 : troisième**, avant
  [64] et [18]. `[18] Blocked by:` porte maintenant `65` : si ce ticket répare la
  borne en cessant de scanner le tracker (registre d'écritures du pilote,
  [13]/[40]), la contrainte que [11] avait écrite dans [18] — « un backend qui
  numérote côté serveur casse la borne » — disparaît avec le scan au lieu d'être
  une obligation de plus. Ordre complet retenu : [63] → [62] → [65] → [64] →
  passe transversale → [18] → [19].
