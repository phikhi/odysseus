# 59 — Un refus de `git add` est lu comme un arbre, et le refus documenté n'existe pas

**What to build:** Rendre à `gate_tree_snapshot` le refus que son propre
commentaire décrit, et qui n'a jamais été en vol. Le commentaire (l. 2131-2136 de
`.claude/lib/gate.sh`) écrit, pour la branche à pathspec :

> No `|| true`, unlike the branch below, and the asymmetry is the whole point …
> `set -e` takes the function down, the caller gets no tree, and that is the
> refusal it needs — **a tracker guard handed an empty tree instead would read it
> as "the session changed nothing"**.

Ce refus repose sur `set -e`. Or les **onze** appelants de cette fonction
l'invoquent tous sous la forme `x="$(gate_tree_snapshot …)" || x=""`, et un
`||` **suspend errexit sur toute l'extension dynamique** de ce qu'il encadre
(mesuré, pas déduit : un `false` au milieu de la fonction ne la tue pas). La
fonction va donc jusqu'au bout, `git write-tree` rend l'arbre vide ou un arbre
amputé, `[ -n "$tree" ]` le trouve non vide, et l'appelant reçoit **rc=0 et un
arbre** là où il croit recevoir un refus.

Ce que ça donne dépend de la branche, et les deux sont mesurées :

- **branche sans pathspec** — `git add -A` échoue **WHOLE** sur un fichier
  illisible et laisse l'index **vide** ; seul le forçage de `GUARDED_PATHS`
  (`|| true`) remet quelque chose. L'arbre jugé ne contient plus que `.claude/`,
  donc **tout le reste du dépôt a l'air supprimé par la session**.
- **branche à pathspec** — un pathspec qui ne matche rien, ou un fichier de
  ticket illisible, rend l'**arbre vide** avec rc=0, c'est-à-dire exactement ce
  que le commentaire décrit comme impossible.

**Blocked by:** None

**Write-surface:** `.claude/lib/gate.sh`, `.claude/loop.sh`,
`.claude/lib/failures.sh`, `test/gate.bats`, `test/failures.bats`,
`test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** securite, frontiere-de-confiance

- [ ] **Un arbre que git n'a pas pu construire n'est plus rendu comme un arbre.**
      Le refus doit voyager par le **code de retour** et pas par `set -e`, parce
      que la forme d'appel qui suspend errexit est celle de tous les appelants et
      qu'il n'y a aucune raison de leur demander de changer ([53] a déjà consigné
      la règle : *un refus rendu par substitution de commande passe par le code
      de retour, pas par une variable*). Décider explicitement entre : rendre
      non-zéro quand un `git add` a échoué, ou rendre l'arbre en disant ce qui
      manque — et écrire le prix de l'option retenue.
- [ ] **Le faux livré est fermé.** Mesuré : sous une write-surface qui couvre les
      chemins que l'arbre amputé prétend supprimés, l'itération sort
      `scope=green`, `failures_make_durable` ne trouve rien à enregistrer (les
      chemins refusés laissent `newtree == head^{tree}`), `concurrency_integrate`
      rend 0 sur un fold qui n'a rien à faire, et **le ticket est marqué
      `resolved` sans que `HEAD` bouge et sans que la livraison réelle de la
      session soit nulle part**. C'est le défaut de [35] par une porte que [35] ne
      couvre pas : `gate__nothing_delivered` compare `base` à l'arbre jugé, et
      l'amputation *est* une différence.
- [ ] **La fausse accusation cesse.** Mesuré sous une surface étroite : trois
      itérations `scope=red` disant `wrote CONTEXT.md, outside the declared
      write-surface` — la session n'a **pas écrit** ce fichier, elle l'a rendu
      illisible — budget de retries brûlé, `Escalation: failed-impl`, et le
      guichet `implement` qui demande à un humain « Why is the code wrong » à
      propos d'un code qu'aucun gate n'a lu. **Aucune ligne ne nomme la cause**
      (0 occurrence de `unreadable` / `permission` dans toute la sortie).
- [ ] **Le garde du tracker aussi.** Mesuré : un seul fichier de ticket illisible
      fait rendre l'arbre vide à `failures_tracker_tree`, donc
      `diff-tree before after` marque **tous** les tickets `D`, donc
      `failures_protect_tracker` les restaure tous et refuse le vert en accusant
      une session qui n'a rien écrit — la panne de [49], reproduite par l'autre
      bout.
- [ ] **Le cas qui échappe même à un refus, nommé plutôt que tu.** Un
      *répertoire* en mode 000 fait rendre `git add -A` **rc=0** avec un simple
      `warning: could not open directory`, et les chemins dessous manquent
      silencieusement de l'arbre. Un correctif fondé sur le code de retour ne
      l'attrape pas ; dire qui garde ce cas, ou avouer que personne.
- [ ] **Chercher les autres appelants qui comptent sur `set -e` sous un `||`.**
      La forme est générale, pas locale à cette fonction : `x="$(f)" || x=""`
      désarme tout ce que `f` refuse par errexit. Un balayage, et ce qu'il trouve
      écrit ici.
- [ ] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.

## Comments

- **Origine : passe transversale du 01/09/2026.** Sondes conservées :
  `.scratch/ralph-pack/sondes/passe-01-09/q2-l-arbre-juge-est-vide-quand-un-fichier-est-illisible.bats`
  (Q2a à Q2g), avec le témoin appairé pour chaque cas.

- **Ce que la mesure a rendu, textuellement.**

      Q2a  arbre jugé = 16403f7…  entries=24  top-level=.claude
           HEAD                    entries=26  top-level=.claude .scratch CONTEXT.md
      Q2b  témoin, tout lisible    entries=27
      Q2f  gate_tree_snapshot "no/such/path" → 4b825dc… (l'arbre vide), rc=0
      Q2g  un ticket illisible → after=4b825dc…, diff-tree rend D sur les DEUX tickets

- **Ce qui rend le déclencheur atteignable sans rien d'hostile.** Un fichier que
  l'utilisateur ne peut pas ouvrir dans un arbre non ignoré : un montage qui pose
  un fichier appartenant à un autre propriétaire, un outil qui écrit en mode 000,
  un `chmod` dans un script de build. La zone **ignorée** est hors de portée
  (`git add -A` ne l'ouvre pas), ce qui borne le déclencheur sans le fermer. Le
  fichier n'a pas besoin d'être dans la write-surface du ticket ni d'avoir été
  écrit par la session : il suffit qu'il soit dans l'arbre au moment du snapshot.

- **La fenêtre exacte compte, et elle explique pourquoi ce n'est pas [34].**
  [34] a fermé « une mesure refusée n'est pas une livraison vide » **du côté du
  scope-guard**, qui refuse quand l'arbre est illisible. Ici l'arbre n'est pas
  illisible : il est *construit*, et il est faux. Le contrôle de [34] n'a rien à
  voir avec quoi rougir.

- **Ce que ce ticket laisse à [11], et il faut l'y écrire.** Le gate de valeur
  ajoute une branche qui lira l'arbre jugé. Tant que l'arbre jugé peut être un
  arbre amputé rendu avec rc=0, une branche de plus est une opinion de plus sur
  un objet faux.
