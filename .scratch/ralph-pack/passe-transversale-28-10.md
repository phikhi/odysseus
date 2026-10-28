# Passe transversale du 28/10/2026

Dix-neuvième passe. Faite sur `main` à `e95e885` (merge de [109]), à **3/5** —
[108] `1f7f1fd`, [110] `ffb5fc7`, [109] `e95e885` — **sous 5 par décision de
Philippe le 28/10** : la file était épuisée et le tracker n'avait plus qu'un
ticket ouvert hors file ([97], `needs-triage`). Mêmes précédents que les 23/09 et
29/09. Le compte repart à 0/5 après elle.

Sortie des rejeux : `sondes/passe-28-10/README.md`. **Rien touché hors
`.scratch/`** → la baseline de [109] tient telle quelle (`run.sh`
**1128**/0/**7 skips**, `mutate.sh` **1232**/0) et les deux gates n'ont pas été
rejoués.

---

## Ce que disent les rejeux

Les sondes « run réel » des trois tickets, plus `g1`/`g4` de la passe du 16/10
(qui ont ouvert [110]), rejouées sur `e95e885` : **toutes rendent la colonne
« branche » de leur README**, rien n'a bougé entre la livraison et `main`. Détail
dans le README des rejeux. Les deux sondes de la passe du 16/10 ont changé de
verdict comme prévu : `g1` passe de 166 lignes drainées à 0 (291 lancements du
programme), `g4` nomme et reprend `vendor/rogue` avec le plant comme sans lui.

---

## Question 4 — ce que chaque ticket laisse au suivant

**[110] → tout git du pack.** Retirer le stdin de `proc_git` aurait rendu muet,
sans rien faire échouer, tout git du pack qui *lisait* son stdin : il aurait reçu
une entrée vide et répondu comme sur une liste vide. L'ouverture de [110] nommait
trois lecteurs (`check-ignore --stdin`, `update-index --index-info`,
`hash-object --stdin`). Relu : **seul `check-ignore` existait**, et c'est le foyer
de `proc_git_fed`. Les cinq `commit-tree` du pack passent leur message par `-m`
(`concurrency.sh:660`, `failures.sh:991`, `:994`, `:1139`, `:1142`) ; aucun
`hash-object`, `mktree`, `update-index --index-info` ni autre `--stdin`. Rien n'a
été rendu muet. Le recensement de [110] (aucun tuyau ni redirection vers
`proc_git`) tient cette réponse pour demain.

**[109] → une source de frontière par itération seulement.** [109] a écrit que
sur un pin détruit, une source portée par le témoin d'itération **seul** ne serait
pas comparée. Relu : aucune n'existe aujourd'hui. `gate__frontier_pin_manifest`
(`gate.sh:959`) écrit la moitié arbre vivante, puis recopie `$common/manifest`, le
manifeste du **témoin du run**. La moitié partagée du pin est donc, par
construction, celle du run. La contrainte reste écrite dans [109] pour le jour où
quelqu'un ajoutera une source au pin seul.

**[108] → les 33 `cat <<X` de prose.** Ils restent matérialisés en fichiers
nommés. Aucun ne porte une valeur que le pack relit pour décider. Les jetons de
verdict qu'ils citent (`RALPH-LENS-VERDICT`, `RALPH-PLAYTHROUGH`, `RALPH-RETRO`,
`CAPABILITY`) sont des constantes du pack, pas des secrets. Le corps de
proposition de `capability.sh:546` devient un corps de ticket, mais un process
capable de le réécrire écrit déjà le tracker directement. Ce corps ne lui donne
donc rien de plus. Pas un ticket.

## Question 5 — ce qu'une session écrit que rien ne vérifie

Regardé sur les canaux que les trois tickets ont touchés :

- **Le stdin de la session elle-même** : `session_spawn` lance `claude -p` avec
  `<"$promptfile"`. La session ne reçoit ni le stdin du run, ni, au drain, les
  réponses de l'humain. [110] a fermé le même canal pour git. Les deux bouts sont
  maintenant tenus.
- **Les écritures de `forge__http`** : `--data-binary "$data"` prend ses deux
  charges de `forge__create_payload` et `forge_append_note`. Ce sont des objets
  JSON construits par le pack, qui commencent toujours par `{`. curl les envoie
  tels quels.

Rien de neuf trouvé dans la portée de ces trois tickets.

---

## Les tickets

**Aucun.** La passe n'ouvre rien. La file reste **vide**, et [97] reste hors file
(`needs-triage`). Tracker inchangé : 110 tickets, 109 résolus, 1 ouvert ;
n° **111** libre.

**Prochaine passe** : après le cinquième ticket livré à partir d'ici. Aucun n'est
nommé aujourd'hui.
