# 06 — Registre de lentilles de revue (Standards|Spec + gated)

**What to build:** Le registre extensible de lentilles ajouté au fan du gate : **Standards** et **Spec** toujours actives (via `/code-review`), **Fidélité**, **Sécurité**, **Accessibilité** déclenchées par prédicat au risque. Un projet ajoute une lentille sans refondre le gate.

**Blocked by:** 05

**Write-surface:** `.claude/lib/lenses.sh`, `test/lenses.bats`

**Status:** ready-for-agent

- [ ] Standards et Spec s'exécutent pour tout ticket.
- [ ] La lentille Fidélité/Accessibilité se déclenche ssi le ticket a une surface visible ; Sécurité ssi tag `security` **ou** write-surface ∩ `SECURITY_PATHS`.
- [ ] Un ticket sans surface ni chemin sensible ne déclenche que Standards|Spec.
- [ ] Le registre est extensible : ajouter une lentille avec son prédicat ne modifie pas le control-flow du gate.
- [ ] Une lentille rouge rend le gate rouge (intégrée au *resolved* d'[05]).

## Comments

- **Contrainte posée par [05] : les lentilles s'ajoutent *dans* `gate_run`, pas autour.** Le gate rend son verdict global par code de retour, mais le détail (`RALPH_GATE_VERDICTS`, `RALPH_GATE_FAILED`, `RALPH_GATE_SCOPE_CLASS`) passe par des variables de shell, écrites dans le shell de la boucle. Un registre qui appellerait `gate_run` depuis une substitution de commande ou un pipeline perdrait ce détail **en silence** : verdicts vides, classe de débordement introuvable, et [07] incapable de distinguer un drift d'un fichier neutre. Le registre doit fournir des branches supplémentaires à la même fonction — même patron que les trois branches objectives : un process par lentille, code de retour dans un fichier, agrégation à la fin.
- Une branche sans verdict compte **rouge** ([05]) : une lentille dont la session `claude -p` meurt ne doit pas devenir un vert par défaut. Le patron existant le garantit déjà, à condition de l'utiliser.
- Le diff à faire relire par une lentille est déjà calculable : `gate__changed_files "$base"` rend exactement ce que la session a touché, bookkeeping de la boucle exclu.
