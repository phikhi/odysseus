# 56 — un correctif humain non commité n'est jamais jugé, et la boucle l'accuse

**What to build:** Rendre vraie, ou cesser de dire, la promesse centrale du puits
humain. À la touche `r` le drain écrit « back on the frontier, retry budget
cleared — **a fresh session and the whole gate decide now** », et le prompt de la
session routée promet la même chose. Or la session routée écrit dans l'**arbre
principal**, rien ne commite, et depuis [13] une itération AFK tourne dans un
worktree créé au **tip de la branche** (`concurrency_worktree_add` :
`git worktree add --detach "$dir" "$(git rev-parse HEAD)"`). Ce qui n'est pas
commité n'est donc pas là. Le gate ne juge pas le correctif : il juge son
absence.

**Blocked by:** 55

**Write-surface:** `.claude/human-loop.sh`, `.claude/lib/router.sh`,
`test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** frontiere-de-confiance

- [ ] **Le drain sait ce que la session routée a laissé dans l'arbre**, et il le
      dit. Un correctif non commité n'est pas un détail d'usage : c'est l'état
      **par défaut** à la sortie d'une conversation avec `claude`.
- [ ] **La réinjection ne promet plus ce qu'elle ne fait pas.** Trois directions,
      en trancher une et écrire le prix : refuser `r` tant que l'arbre porte des
      modifications non commitées sur des chemins que le ticket nomme ; les
      commiter depuis le drain (et alors dire sous quel auteur, et ce que ça fait
      d'un arbre où l'humain travaillait *aussi* sur autre chose) ; ou garder la
      réinjection telle quelle et **changer la phrase**, en nommant le commit
      comme la condition qu'il est.
- [ ] **Le retour ne ment plus sur ce qui s'est passé.** Un ticket qui revient
      avec `Failures: 3` et `Escalation: failed-impl` après un correctif jamais
      vu envoie l'humain au guichet `implement`, dont la question est « Why is the
      code wrong » — à propos d'un code que le gate n'a pas lu.
- [ ] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.

## Ce que la passe du 31/08 a mesuré

Sondes conservées :
`.scratch/ralph-pack/sondes/passe-31-08/p2-le-correctif-humain-que-le-gate-ne-voit-pas.bats`.
Le gate est réduit à une seule question, `TEST_CMD='test -f src/human-note.txt'`,
et la session routée écrit ce fichier **hors** de la write-surface du ticket pour
que la session AFK ne le fabrique pas elle-même.

- **P2a — le correctif n'est pas commité** (l'état par défaut). Après le drain :
  `Status: ready-for-agent`, le fichier est bien là, `git status --porcelain` dit
  `?? src/`. Puis le run AFK :

      ralph: gate: 09-escalated: tests=red typecheck=green scope=green lang=green
      ralph: 09-escalated: gate-red -> fresh retry (1 of 2)
      ralph: gate: 09-escalated: tests=red typecheck=green scope=green lang=green
      ralph: 09-escalated: gate-red -> fresh retry (2 of 2)
      ralph: gate: 09-escalated: tests=red typecheck=green scope=green lang=green

  **Trois itérations, tout le budget de retries brûlé**, et le ticket revient au
  puits en `Failures: 3`, `Escalation: failed-impl`. Le correctif est toujours
  dans l'arbre principal, non suivi, jamais lu par aucune des trois sessions, et
  **aucune ligne ne le nomme** — ni au journal, ni au reçu.
- **P2b, témoin appairé** — le même correctif, commité à la main entre le drain et
  le run : `tests=green typecheck=green scope=green lang=green`,
  **`Status: resolved`**, dès la première itération.

La seule différence entre les deux est un `git commit` que rien dans le pack ne
demande, ne mentionne, ni ne vérifie.

## Ce que ça aggrave

`router_reinject` remet `Failures:` à zéro — c'est la réparation de [16] sur la
décision que [26] avait laissée ouverte, et elle est correcte. Conséquence
inattendue ici : le compteur repart de zéro, le run le remonte à 3, et **rien ne
distingue « le gate a jugé ton correctif et l'a refusé » de « le gate n'a jamais
vu ton correctif »**. Le second drainage présente un ticket qui a l'air d'avoir
été jugé loyalement.

## Une contrainte que [16] avait reçue et n'a pas dépensée

[13] l'avait écrite dans le ticket [16], en toutes lettres : « ce qu'un humain a
de non commité n'est plus jamais jugé, rollbacké ni commité par la boucle AFK ».
Elle est dans la liste des contraintes de [16], elle n'est **ni dans ses
décisions, ni dans son code, ni au tableau de frontière**, et la phrase que le
drain imprime dit le contraire. C'est la question 4 de CLAUDE.md dans sa forme
pure — et le rappel que la liste des contraintes d'un ticket n'est pas une liste
de choses faites.

## Pièges connus, pour celui qui livre

- **Ne pas commiter aveuglément.** L'arbre principal est celui de l'opérateur : un
  `git add -A` depuis le drain emporterait ce sur quoi l'humain travaillait à
  côté. C'est la raison pour laquelle [21] désindexe et pour laquelle
  `failures_make_durable` ne commite que des chemins approuvés.
- **Point de convergence avec [55]** : les deux tickets veulent que le drain sache
  ce que la session routée a fait — [55] dans le tracker, celui-ci dans l'arbre.
  Un seul instantané autour de `human_loop__session` répond aux deux ([46] : viser
  le point de convergence, pas deux mécanismes).
- **Une assertion sur `assert_success` ne prouve rien ici** : asserter les
  verdicts du gate et le `Status:` final, comme les sondes le font.
- **`session_writes` du harnais écrit la write-surface du ticket** : un fichier
  témoin posé *dans* cette surface serait fabriqué par la session AFK elle-même et
  la sonde serait verte des deux côtés.
