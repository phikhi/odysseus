# 96 — Le reçu d'audit est assemblé dans la zone dont il se protège

**What to build:** Que le reçu d'audit — le seul document durable que la nuit produit sur elle-même — soit assemblé hors de portée de ce dont il rend compte, ou qu'il cesse d'affirmer dans son propre texte une garantie qu'il ne tient pas.

**Blocked by:** 94

**Write-surface:** `.claude/lib/receipt.sh`, `.claude/lib/gate.sh`, `test/receipt.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

- [ ] Le **workspace** du reçu n'est plus tenu par un nom. C'est un `mktemp -d "$TMPDIR/ralph-receipt.XXXXXX"` et « un nom n'est pas une garde » est la racine de la passe du 10/09, payée par [80] et [81]. Ses pièces sont quatre fichiers texte — `facts`, `notes`, `gaps`, `branch.<nom>` — et `receipt__fact` lit la **dernière** occurrence, donc un `>>` suffit.
- [ ] La **source** que le reçu cite (`$dir/<branche>.out`, via `receipt_keep_branch`) est celle que [94] aura traitée : ce ticket hérite de cette décision au lieu d'en prendre une seconde.
- [ ] La **phrase que le document imprime sur lui-même** dit la vérité après réparation. Aujourd'hui il se termine par *« Assembled by the process that measured this iteration … It does **not** read `run.log` … so the session this receipt is about can rewrite it »* — une phrase qui oppose une garantie au journal tout en rangeant ses propres pièces dans la zone voisine. Même chose pour les trois paragraphes de tête de `lib/receipt.sh` : *« None of those is reachable from a session's write-surface »* est faux aux deux moitiés.
- [ ] La ligne « Un reçu d'audit dit ce qui s'est vraiment passé » du tableau est réécrite avec ce qui la tient réellement.
- [ ] Les tests mettent en scène un **survivant réel** et assertent le contenu du reçu **déposé** (`receipts/<feature>/<id>.md`), pas l'état d'un workspace. Témoin appairé obligatoire.
- [ ] Une entrée de mutation par garantie livrée, avec son témoin appairé.

## Comments

- **Ouvert par la passe transversale du 23/09/2026** (`../passe-transversale-23-09.md`, §3). Sonde : `../sondes/passe-23-09/q4-le-recu-daudit.bats`.

- **Ordre PROPOSÉ, à valider par Philippe** : **[95] → [94] → [96]**. Ce ticket en dernier parce qu'il cite `$dir/<branche>.out` comme source : ce qui lui reste en propre — son workspace et la phrase qu'il imprime sur lui-même — n'appartient qu'à lui.

- **Mesuré**, suite rouge, le reçu déposé dans `receipts/<feature>/01-alpha.md`. Témoin appairé, sans survivant : `tests=red`, findings `FAIL: 3 of 12 tests failed in src/alpha`, outcome `gate-red`. Avec un `nohup` laissé par la session qui écrit dans `$TMPDIR/ralph-receipt.*` : **`tests=green typecheck=green scope=green lang=green`**, findings *« the suite passed cleanly on the first attempt »*, outcome **`resolved`** — et le document forgé porte toujours sa propre phrase de garantie.

- **Le seul résidu qui trahit**, et il ne vaut pas une défense : `what the loop then did: escalated:failed-impl`, un fait écrit après la dernière forge du survivant. Un survivant qui couvrirait aussi ce fait ne laisserait rien. Ne pas construire la réparation sur « il reste une incohérence » : c'est un accident de séquence.

- **Ce qui distingue ce ticket de [94]** : ici rien n'est décidé. C'est ce qu'un humain lit **à la place** de ce qui s'est passé, et c'est le seul document qui survit à la nuit dans le dépôt. Une réparation qui se contenterait de le fiabiliser à moitié doit dire laquelle des deux moitiés elle tient.

- **La posture par défaut du pack, si le workspace ne peut pas sortir de `$TMPDIR`** : [39] — nommer ce qu'on ne sait pas adresser, et le nommer **à chaque tour** ([24]), pas une fois dans un document. Un reçu qui dirait dans son texte quelles de ses pièces sont à portée de l'itération dont il rend compte serait déjà plus honnête que celui d'aujourd'hui.

- **Ne pas chercher `RECEIPT_MAX_LINES`** : `receipt_preflight` refuse déjà au démarrage une valeur qui lit comme « off », et c'est la forme que [17] et [31] ont posée. Rien à rouvrir là.
