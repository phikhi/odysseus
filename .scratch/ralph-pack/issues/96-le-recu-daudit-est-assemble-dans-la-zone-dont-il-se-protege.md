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

- **Ordre VALIDÉ par Philippe le 23/09/2026** : **[95] → [94] → [96]**. Ce ticket en dernier parce qu'il cite `$dir/<branche>.out` comme source : ce qui lui reste en propre — son workspace et la phrase qu'il imprime sur lui-même — n'appartient qu'à lui.

- **Mesuré**, suite rouge, le reçu déposé dans `receipts/<feature>/01-alpha.md`. Témoin appairé, sans survivant : `tests=red`, findings `FAIL: 3 of 12 tests failed in src/alpha`, outcome `gate-red`. Avec un `nohup` laissé par la session qui écrit dans `$TMPDIR/ralph-receipt.*` : **`tests=green typecheck=green scope=green lang=green`**, findings *« the suite passed cleanly on the first attempt »*, outcome **`resolved`** — et le document forgé porte toujours sa propre phrase de garantie.

- **Le seul résidu qui trahit**, et il ne vaut pas une défense : `what the loop then did: escalated:failed-impl`, un fait écrit après la dernière forge du survivant. Un survivant qui couvrirait aussi ce fait ne laisserait rien. Ne pas construire la réparation sur « il reste une incohérence » : c'est un accident de séquence.

- **Ce qui distingue ce ticket de [94]** : ici rien n'est décidé. C'est ce qu'un humain lit **à la place** de ce qui s'est passé, et c'est le seul document qui survit à la nuit dans le dépôt. Une réparation qui se contenterait de le fiabiliser à moitié doit dire laquelle des deux moitiés elle tient.

- **La posture par défaut du pack, si le workspace ne peut pas sortir de `$TMPDIR`** : [39] — nommer ce qu'on ne sait pas adresser, et le nommer **à chaque tour** ([24]), pas une fois dans un document. Un reçu qui dirait dans son texte quelles de ses pièces sont à portée de l'itération dont il rend compte serait déjà plus honnête que celui d'aujourd'hui.

- **Ne pas chercher `RECEIPT_MAX_LINES`** : `receipt_preflight` refuse déjà au démarrage une valeur qui lit comme « off », et c'est la forme que [17] et [31] ont posée. Rien à rouvrir là.

- **Ce que [94] laisse, livré le 24/09/2026 — la décision dont ce ticket hérite est écrite.** `$dir/<branche>.out` **reste un fichier nommé** dans le répertoire du gate, et c'est une décision mesurée, pas un oubli. La borne évidente — la branche note la longueur de sa propre sortie, le parent refuse un fichier qui n'a plus cette longueur, la forme `grows` de [81] — a été **refusée sur mesure** : `proc_sweep` envoie un TERM à ce qu'une branche de commande a laissé tourner et dit lui-même qu'il ne le suit pas ([95]), donc un projet honnête dont le serveur de test log une ligne en s'arrêtant verrait ses constats refusés tous les matins. La raison est écrite au-dessus de `gate__report` et dans le tableau. Ce que ça borne : depuis [92] rien de ce fichier n'est un verdict, donc ce qu'un process qui y écrit achète est de la prose — dans le journal du matin et **dans ce reçu**. Donc : **ce ticket n'a pas à re-trancher le `.out`, il a à dire ce que son propre document vaut sachant que sa source de constats est celle-là.** Et `receipt_keep_branch` est l'autre lecteur : si ce ticket décide de nommer ce que le reçu ne tient pas, cette source est la première ligne à nommer.

- **Ce qui est neuf et réutilisable** : `gate_note` / `gate_noted` / `gate_notes_shut` (gate.sh) — un descripteur sur un fichier délié, hérité par une branche, fermé pour tout ce que le pack `exec` hors de lui-même. C'est le magasin à réutiliser quand un contrôle doit se méfier d'un fichier qu'une session peut écrire **et** que la réponse doit traverser un fork (le pendant de `RALPH_WITNESS_SEAL` de [81], qui ne traverse que dans le sens pilote → enfant). Le workspace du reçu, lui, est écrit par le **pilote** et lu par le **pilote** : le canal d'une branche ne s'y applique pas tel quel, mais la forme « ouvrir deux fois puis délier » si.
