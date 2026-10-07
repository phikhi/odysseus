# Sondes ouvertes en commençant [98] (29/09/2026)

Des **instruments**, pas des tests : `f2` finit chaque cas par un `set -e; false`
volontaire, et `f1` est un script bash nu, hors du harnais. Ni l'un ni l'autre ne
compte dans le verdict des deux gates.

    bash .scratch/ralph-pack/sondes/ticket-98/f1-les-copies-de-sauvegarde.sh
    bash test/run.sh .scratch/ralph-pack/sondes/ticket-98/f2-le-canal-herite.bats
    bash test/run.sh -f L3 .scratch/ralph-pack/sondes/ticket-98/f2-le-canal-herite.bats

## Ce qu'elles ont rendu, sur `main` à `b6f9079`

**f1 — les enveloppes de fermeture laissent une copie au programme lancé** (→ [101]).

    A. forme de gate__command_branch (receipt_shut gate_notes_shut proc_group_fork '' cmd)
       fd10w -> reçu      fd11r -> reçu      fd12w -> notes du gate   fd13r -> notes du gate
    B. forme de session_spawn (receipt_shut_exec claude &, dans une fonction)
       fd10w -> reçu      fd11r -> reçu
    C. programme lancé sans enveloppe (témoin)
       fd4r / fd5w -> reçu   fd8r / fd9w -> notes du gate

Les numéros 5/4 et 9/8 sont bien fermés, et c'est tout ce que les tests de [94] et
de [96] demandent. Les copies que bash a faites pour pouvoir les rouvrir au retour
de la fonction ne le sont pas.

**f2 L1 — la session jugée forge son propre reçu** (→ [101]). Écrivable depuis la
session : **fd 10**, et lui seul. Dans le reçu déposé : `- FORGED-BY-THE-SESSION`,
sous la section des notes. Le document porte toujours sa phrase de provenance
(« neither the session this receipt is about nor anything it left running could
reach it »).

**f2 L2 — la commande de test du projet aussi** (→ [101]). Écrivable depuis
`TEST_CMD` : **fd 12 et 14**, à chacun de ses trois passages.

*Les chiffres de L1/L2 écrits d'abord ici (« 10 et 12 », « 10, 12, 14 ») venaient
d'une sonde en `printf` builtin, qui a un artefact : `printf x >&N` sur un N fermé
réussit quand N est le plus petit numéro libre ≥ 10, parce que bash sauvegarde
d'abord fd 1 sur N. La sonde est maintenant en perl (`open ">&="` + `syswrite`) —
la même que `fd_forger` du harnais — et les chiffres ci-dessus sont les siens.*

**f2 L3 — un hook posé par la session tourne pour le pack** (→ [102]). La session du
ticket 01 écrit `reference-transaction` et `post-checkout` dans
`$(git rev-parse --git-common-dir)/hooks/`. Mesuré : `reference-transaction` tourne
à chaque `git update-ref` du pack (préparation, validation, commit — et `aborted` sur
un fold refusé) avec le fd 5 de l'itération ouvert ; `post-checkout` tourne au
`git worktree add` du pilote, dans l'arbre de process du pilote. Le hook écrit
`- FORGED-BY-A-HOOK-ON-FD-5` six fois dans le reçu de **01** et trois fois dans celui
de **02**, dont la session n'a rien posé : il survit à l'itération qui l'a écrit, et
au run.

Un fait de plomberie mesuré hors du pack, pour [102] : `git update-ref` est de la
plomberie et lance quand même `reference-transaction` ; `-c core.hooksPath=/dev/null`
l'éteint.

## Ce qu'elles ont décidé

File revalidée par Philippe le 29/09/2026 : **[101] → [102] → [98] → [99] → [100]**,
arêtes 101 → 98 et 102 → 98. `f1` et `f2` L1/L2 sont la mesure de **[101]**, `f2` L3
celle de **[102]**. Rejouées après la livraison de chacun, elles doivent rendre :
`f1` inchangée (elle rejoue la forme **hors** du pack, c'est un instrument de bash
et pas du pack) ; `f2` L1/L2 **aucun** descripteur écrivable et aucune ligne forgée
après [101] ; `f2` L3 aucun hook lancé après [102].

**Rejouées sur la branche de [101]** : `f2` L1 et L2 ne trouvent plus **aucun**
descripteur écrivable et le reçu n'a plus de ligne forgée ; L3 (hooks) inchangée,
c'est [102].


## f3 — la fenêtre de création (→ [103])

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-98/f3-la-fenetre-de-creation.bats

Trouvée par le **second** `run.sh` complet de [101] : le test de [96] « a process
the session left behind finds no workspace to forge » a rougi une fois, sur
`refute_file_exists receipt.saw`, alors que [101] n'avait pas touché
`receipt_open`. Le nom du fichier du canal existe entre son `mktemp` et son `rm -f`
(un `rm` externe, une ou deux millisecondes) ; le survivant du test dormait 10 ms
entre deux regards et tombait de temps en temps dans cet instant.

`f3` pose la question sans hasard : un survivant qui boucle **sans dormir**, ouvre
le fichier qu'il trouve (`exec 7>>`) et écrit dessus ensuite. Rendu :

    sur les libs de main (b6f9079)   12 fenêtres gagnées, 270 lignes forgées dans le reçu
    sur la branche de [101]          12 fenêtres gagnées, 341 lignes forgées

Même forme, par construction, pour les notes du gate et le prompt d'une lentille
(`mktemp` dans `ralph-gate.*`), et pour le canal que [98] prévoyait. File
revalidée par Philippe le 29/09 : **[101] → [102] → [103] → [98] → [99] → [100]**.

**Rejouée sur la branche de [103] (06/10/2026)** : **12 fenêtres gagnées, 0 ligne
forgée** dans le reçu. Le survivant ouvre toujours le fichier dans l'instant où il a
un nom ; le canal n'est plus servi — l'ouvreur partagé (`proc_channel_open`) demande
à `lsof +L1`, après le délien, qui le tient, et refuse. Défaut connu de l'instrument :
`exec 7>>` recrée un nom délié entre le glob et l'ouverture, et le tour suivant le
revoit — le canari de [103] n'essaie chaque nom qu'une fois.


## f4, f5 — la configuration de `curl` (→ [105])

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-98/f4-le-curlrc.bats
    bash .scratch/ralph-pack/sondes/ticket-98/f5-le-curlrc-hors-du-pack.sh

Ouvertes le 07/10/2026 en recommençant [98], par la question 5 de la DoD posée au
canal que ce ticket va ouvrir : le pilote tiendra un bout lecteur par itération en
vol, chaque itération son bout écrivain pendant toute sa vie — qu'est-ce que le pack
lance pendant ce temps, et qu'est-ce qui le configure ? `git` passe par `proc_git`
([104]), `claude` et `lsof` par `proc_exec_bare` ([101], [103]). **`curl`, lancé nu
et sans `-q`, lit `~/.curlrc`**, qu'une session écrit (même `HOME` que l'opérateur).

`f5`, hors du pack, sur le vrai `curl` de la machine (8.7.1, darwin) et un canal
délié de la forme du pack, la requête de la ligne de commande échouant toujours
(port 9) :

    (a)   output= vers un bout écrivain hérité, -o sur la ligne   le canal reçoit la ligne forgée
    (a-q) la même chose, curl -q en premier argument              rien
    (b)   url= sans output                                        le corps forgé arrive sur stdout (rc=7)
    (c)   data-binary=@ un bout lecteur                           vidé : le lecteur légitime ne lit plus rien
    (d)   output= vers un bout lecteur                            curl: (23), rien d'écrit (darwin)

`f4`, dans le vrai pack, backend `github` : le faux `curl` du harnais est enveloppé
pour lancer aussi le vrai `/usr/bin/curl` à la place exacte où le pack lance `curl`
(donc avec ses descripteurs et le `HOME` du test), puis rendre la main au faux qui
sert la forge. La session écrit `~/.curlrc` (`url = "file://…/forged.txt"`,
`output = "/dev/fd/5"`) :

    C1   ~/.curlrc posé par la session   4 lignes `- FORGED-BY-CURLRC-ON-FD-5` dans le reçu
                                         (la description de la requête), rc=0, `resolved`
    C0   témoin appairé, sans ~/.curlrc  aucune

File revalidée par Philippe le 07/10/2026 : **[105] → [98] → [99] → [100]**, arête
105 → 98. Rejouée après [105], `f4` C1 doit rendre **aucune** ligne forgée ; `f5`
reste un instrument de `curl` et pas du pack, et ne change pas.

**Rejouée sur la branche de [105] (07/10/2026)** : `f4` C1 rend **0 ligne forgée**
(C0 : 0), `rc=0`, `resolved`. Le wrapper de `f4` lance le vrai curl avec ses propres
arguments, sans le `-q` du pack : ce rejeu mesure donc la moitié **descripteurs**
seule (`proc_curl` ferme 3..255 avant l'`exec`). La moitié **configuration** est
mesurée par la suite : `harness_real_curl` lance le vrai curl **avec les arguments
du pack**, `-q` compris (`test/budget.bats`, `test/canary.bats`).
