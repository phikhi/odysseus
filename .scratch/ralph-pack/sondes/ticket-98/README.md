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
session : fd 10 et fd 12. Dans le reçu déposé : `- FORGED-BY-THE-SESSION-ON-FD-10`,
sous la section des notes. Le document porte toujours sa phrase de provenance
(« neither the session this receipt is about nor anything it left running could
reach it »).

**f2 L2 — la commande de test du projet aussi** (→ [101]). Écrivable depuis
`TEST_CMD` : fd 10, 12 et 14, à chacun de ses trois passages. Dans le reçu :
`- FORGED-BY-TEST-CMD-ON-FD-12` sous les notes, et trois lignes forgées citées sous
les constats.

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
