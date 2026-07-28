# 21 — Protéger le tracker des écritures de session

**What to build:** Le tracker est la seule autorité d'état du système, et une session peut aujourd'hui l'éditer sans que rien ne le voie. Rendre cette écriture **détectable et annulable**, et faire lire au scope-guard la write-surface telle qu'elle était au démarrage de la session — pas telle qu'elle est au moment du gate.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/gate.sh`, `test/canary.bats`, `test/failures.bats`

**Status:** ready-for-agent

- [ ] Toute écriture d'une session dans `.scratch/<feature>/issues/**` est détectée, **avant** que le gate ne lise quoi que ce soit du tracker.
- [ ] Une modification d'un ticket existant est annulée (restaurée depuis le snapshot pré-session), et une itération qui a réécrit le tracker ne peut pas être verte.
- [ ] Le scope-guard juge la session contre la write-surface qui était déclarée **au moment du spawn**.
- [ ] Un ticket créé par une session reste mis en quarantaine (livré par [07]) : la garantie est étendue des créations aux éditions.
- [ ] Le test `skip` du canari (« a session cannot widen its own write-surface ») est levé.

## Comments

- **Faille vivante, trouvée en livrant [07] et reproduite.** Le scope-guard lit la write-surface **sur le disque, au moment du gate** (`gate_write_surface` → `tracker_field`), c'est-à-dire *après* la session. Or trois mécanismes s'accordent pour rendre une écriture de session dans le tracker invisible :

  1. `gate__drop_bookkeeping` écarte `.scratch/<feature>/` du diff jugé par le scope-guard ([05], à raison : le claim, le journal et le flux de session vivent là) ;
  2. le rollback de [07] exclut le même préfixe (à raison aussi : sans quoi le compteur `Failures:` retomberait à zéro à chaque tentative et rien ne serait jamais escaladé) ;
  3. la quarantaine de [07] ne compare que des **ids** : elle voit un ticket créé, pas un ticket modifié.

  Conséquence : une session qui réécrit la ligne `**Write-surface:**` de son propre ticket en `*` obtient un scope-guard **vert** sur n'importe quelle écriture. C'est un faux vert avec un mécanisme, pas un hasard — exactement ce que ce pack existe pour refuser. Variante de la même faille : une session qui met `Status: resolved` sur un *autre* ticket le fait sortir de la frontière définitivement, et le run le rapporte comme une nuit normale.

  **Reproduit** (une session qui écrit `src/alpha.txt`, `src/rogue.txt`, modifie `CONTEXT.md`, et remplace sa write-surface par `*`) :

  ```
  exit=0
  ralph: gate: 01-alpha: tests=green typecheck=green scope=green
  statut: resolved
  rogue.txt encore là: OUI
  write-surface après le run: `*`
  ```

  Le test est dans `test/canary.bats`, marqué `skip` (« a session cannot widen its own write-surface ») et il porte les attentes d'après-correctif : scope rouge jugé contre la surface du spawn, édition annulée, rien de résolu. **Le lever est un critère d'acceptation de ce ticket.**

- **Ce qui protège aujourd'hui** : le prompt de session l'interdit explicitement, et [07] met en quarantaine les tickets *créés*. C'est tout. Une consigne de prompt non vérifiée n'est pas une garantie — c'est le constat qui a produit le scope-guard lui-même.

- **Piste de correctif** (à valider en l'implémentant) : un snapshot du seul répertoire `issues/` autour du spawn (`GIT_INDEX_FILE` jetable + `git add -A -- .scratch/<feature>/issues` + `write-tree`, bien moins cher qu'un parcours complet), comparé après la session. La fenêtre est propre : entre le snapshot pré-spawn et le retour de la session, la boucle n'écrit **rien** dans `issues/` — le claim est antérieur, le marquage, le `Failures:` et le journal sont postérieurs. Donc tout delta est l'œuvre de la session. Ajouts → quarantaine (déjà fait) ; modifications et suppressions → restauration depuis le snapshot, et l'itération ne peut pas être verte.

- **Ordre** : ce ticket n'est pas bloqué, et il porte un faux vert. Il passe donc devant [20] et [06] si le critère « aucun faux vert » reste prioritaire.
