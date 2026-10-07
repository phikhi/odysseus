# Sondes ouvertes en livrant [105] (07/10/2026)

Des **instruments**, pas des tests : chaque cas finit par `set -e; false` pour que
microbats imprime ce qu'il a mesuré. Hors du verdict des deux gates.

    bash test/run.sh .scratch/ralph-pack/sondes/ticket-105/t1-la-commande-du-jeton.bats

## t1 — la commande de jeton de l'opérateur (→ matière de la passe transversale)

La question 5 posée à côté de `proc_curl` : `forge__http` évalue
`TRACKER_TOKEN_CMD` par `$(eval …)` dans le shell de l'itération, qui tient le
canal du reçu ([96]). [101] l'a écartée de `proc_exec_bare` comme « commande de
l'opérateur ». Mais ce qu'elle lance peut vivre dans le `HOME` qu'une session
écrit. Mise en scène : l'opérateur a écrit
`TRACKER_TOKEN_CMD='bash "$HOME/bin/forge-token"'` ; la session réécrit
`~/bin/forge-token` pour lancer le forgeur du harnais, puis imprimer le jeton.

    C1   la session réécrit le script   6 exécutions, fd 5 écrivable 5 fois,
                                        4 lignes `- FORGED-BY-THE-TOKEN-COMMAND`
                                        dans le reçu, rc=0, `resolved`
    C0   témoin, script intact          aucune

Non fermé par [105] (règle de session : une trouvaille pendant un ticket s'écrit,
elle ne devient pas un second chantier). La phrase de provenance du reçu la nomme
comme exception, le tableau aussi (ligne de `curl`). `USAGE_TOKEN_CMD` est évaluée
dans le pilote, qui ne tient aujourd'hui aucun canal de reçu — ce que [98] change.
