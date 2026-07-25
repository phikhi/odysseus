# Auto-chaînage d'un successeur one-shot (mur hebdo)

Type: grilling
Status: resolved
Blocked by: —

> Durcissement v2 (emprunt Multiplyz : successeur programmé). **Révise [07]** : hebdo → `exit pause-hebdo` (relance humaine/cron). Voir `ANALYSE-multiplyz-vs-odysseus.md` §6.3.

## Question

Faut-il remplacer/augmenter le « **exit `pause-hebdo`** » [07] par un **successeur one-shot auto-programmé** au reset — en évitant l'écueil Multiplyz du **double-run** et de la **chaîne qui casse en silence** ?

Contexte : [07] gère la fenêtre 5h par `sleep` in-process, mais le mur **hebdo** sort en `pause-hebdo` → **relance humaine** (ou cron optionnel). Multiplyz **auto-chaîne** un successeur one-shot (skill `schedule`) au reset de la **fenêtre bloquante** ; c'est aussi leur **anti-collision** (un seul successeur à la fois). Risque documenté : un `release`/re-schedule manqué = « **projet gelé en silence** ».

À trancher :
- **Mécanisme de programmation portable** : le pack est **pur bash** (fallback sans node) — `at` ? `cron`/`crontab` ? `systemd-timer` ? `launchd` (macOS) ? le skill `schedule` (cloud, dispo seulement si gating plan) ? Quel défaut + quels fallbacks.
- **Fenêtre bloquante** : programmer au reset de la fenêtre **qui a bloqué** (5h vs hebdo), lu depuis `resets_at` [07] — **jamais `+7j`** (cadence hebdo incertaine, cf. recherche [02]).
- **Anti-double-run** : garantir **un seul successeur** programmé (sinon collision, cf. Multiplyz) ; rapport avec le **verrou de run [04]**.
- **Fallback si programmation indispo** : conserver le comportement actuel (`exit pause-hebdo` + reprise humaine).
- **Fin de scope** : ne **pas** re-programmer (rapport de complétion) — comme Multiplyz.

Peut faire graduer un ticket **research** (programmation one-shot portable depuis un daemon bash headless + dispo du skill `schedule` hors interactif) si la décision attend un fait.

## Answer

Décision verrouillée (grilling HITL). **Révise [07]** : le mur hebdo passe d'un exit-pause-humain à un **successeur one-shot auto-programmé** (AFK préservé), avec repli sur [07] si pas de scheduler.

**D1 — Adopter le successeur programmé (hebdo seulement), repli [07] sinon.** Sans auto-chaînage, un mur hebdo casse l'AFK jusqu'à une relance humaine (potentiellement une semaine). Le **5h reste le `sleep` in-process d'[07]** (court, robuste) ; **[17] ne change que le hebdo** (des jours → dormir un process bash est fragile : reboot = chaîne morte). Aucun scheduler (D2) → **repli [07]** (exit `pause-hebdo` + reprise humaine + rapport). Jamais de faux-AFK silencieux.

**D2 — Mécanisme portable : chaîne de fallback auto-détectée ([22] affine).** Aucun one-shot scheduler universel Unix → **chaîne ordonnée, auto-détectée au bootstrap [09]**, figée dans `SCHEDULER` (`ralph.config.sh`) : (1) `at`/`atd` → (2) `systemd-run --on-calendar` (Linux) / `launchd` (macOS) → (3) `cron` auto-effaçant → (4) skill `schedule` (cloud, si dispo hors interactif) → (5) **rien → repli [07] humain**. Le **design est verrouillé** ; l'**ordre de préférence exact par plateforme est un fait** → **ticket research [22]** (lancé en subagent, findings → `research/one-shot-scheduling-portable.md`) qui **affinera** `SCHEDULER` sans bloquer [17].

**D3 — Viser le `resets_at` de la fenêtre bloquante, jamais +7j.** Au message de limite : parser **quelle** limite (5h vs weekly) + lire `resets_at` via `/api/oauth/usage` [07]. Programmer au reset de la **fenêtre qui a bloqué** (+ marge), **jamais un `+7j` calculé** (cadence hebdo incertaine ~72h, cf. [02]). Reset hebdo inconnu → **ne pas** reprogrammer dans le même mur → repli [07] humain + rapport.

**D4 — Anti-double-run + quand ne pas programmer.**
- **Singleton** : remove-then-add — la boucle retire tout successeur en attente pour la feature puis en pose exactement un.
- **Filet dur = verrou de run [04]** : le successeur acquiert le verrou au démarrage ; si un run manuel le détient → il **cède** (yield). Le verrou [04] est l'anti-collision ultime ; le singleton gère la cadence.
- **NE PAS programmer** : **fin de scope** (rapport de complétion) ; **drift / `ready-for-human` bloquant** (attendre l'humain). On ne programme **que** sur un exit mur-budget **avec scope restant**.

### Contraintes créées ailleurs
- **[07] révisé** : le mur **hebdo** déclenche désormais un **successeur one-shot programmé** (l'exit-pause-humain devient le **repli**) ; le mur **5h** inchangé (`sleep` in-process). Toujours lire `resets_at`, jamais +7j.
- **[06] control-flow** : sur exit mur-hebdo avec scope restant → (a) singleton remove-then-add du successeur, (b) programmer via `SCHEDULER` au `resets_at` hebdo ; le successeur acquiert le verrou de run [04] au démarrage (yield si tenu).
- **[04]** : le verrou de run est le filet anti-double-run du successeur (réutilisation, aucun changement).
- **[09] form-factor** : auto-détection de la chaîne `SCHEDULER` au bootstrap + `SCHEDULER` dans `ralph.config.sh` ; documenter le repli humain.
- **[22] research** (gradué, en cours) : affine l'ordre de préférence `SCHEDULER` par plateforme ; informe [17], ne le bloque pas.

### Affinement (research [22], livré)

La chaîne `SCHEDULER` (D2) est **ordonnée par plateforme ET par survie au reboot** — car le mur hebdo (des jours) peut traverser un reboot → **file sur disque d'abord** :
- **Linux systemd** : pour le hebdo, **`at`** (spool disque, survit au reboot) **avant** `systemd-run` transient (`/run` tmpfs, meurt au reboot) ; le transient (`--on-calendar=<date absolue> --timer-property=RemainAfterElapse=no` + `loginctl enable-linger`) convient aux attentes courtes ; puis crontab auto-effaçant ; puis humain.
- **Linux non-systemd** : `at` → crontab auto-effaçant → daemon `sleep` (`nohup`, meurt au reboot) → humain.
- **macOS** : `at -t` **si `atrun` activé** (root une fois — `Disabled=true` par défaut) → LaunchAgent auto-désinstallant → daemon `sleep` (+`caffeinate`) → humain.
- **Skill `schedule` SORTI de la chaîne locale** : routine cloud (login claude.ai requis, indispo en clé-API / télémétrie-off, sans FS/MCP local) → au mieux relance cloud de secours, jamais la primitive locale.
- **À coder** : rediriger stdout d'`at` (`>>log 2>&1`, sinon perdu sans MTA), `PATH=` explicite, sonder `atd`/`atrun` actif **avant** de choisir, `enable-linger` pour `--user`.

Détails sourcés : [`research/one-shot-scheduling-portable.md`](../research/one-shot-scheduling-portable.md).
