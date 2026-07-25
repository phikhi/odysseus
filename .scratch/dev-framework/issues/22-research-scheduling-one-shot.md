# Mécanisme de programmation one-shot portable (recherche)

Type: research
Status: resolved
Blocked by: —

> Durcissement v2. **Gradué depuis [17]** (auto-chaînage du successeur). **Informe** l'ordre de préférence du `SCHEDULER` d'[17] — ne **bloque pas** [17] (dont le design est verrouillé). Subagent `/research` lancé ; findings → `research/one-shot-scheduling-portable.md`.

## Question

Quel mécanisme permet de **programmer une exécution unique (one-shot) à une heure absolue future** depuis un **daemon bash headless** (la ralph loop), de façon **portable** Unix, et lequel privilégier dans quel environnement ?

À établir (sources primaires, marquer l'observation communautaire) :
- **`at` / `atd`** : disponibilité par défaut (Linux/macOS), démon activé ou non, syntaxe one-shot (`at -t`, `echo | at`), fiabilité headless, code retour.
- **`systemd-run --on-calendar` / transient timer** (Linux systemd) : one-shot, user vs system, survie au logout (`loginctl enable-linger`).
- **`launchd`** (macOS) : one-shot `StartCalendarInterval`, `launchctl`, agent utilisateur.
- **`cron` auto-effaçant** : ligne crontab qui s'exécute une fois puis se retire ; robustesse, race d'édition, PATH/env en cron.
- **skill `schedule` de Claude Code** : disponibilité **hors session interactive** (headless/cron/programmé), gating plan, API réelle.
- **Synthèse** : ordre de préférence recommandé pour la chaîne de fallback d'[17], **par plateforme**, avec les pièges (reboot, linger, tokens, PATH en cron).

## Answer

Recherche résolue par subagent `/research`. Findings complets et sourcés : [`research/one-shot-scheduling-portable.md`](../research/one-shot-scheduling-portable.md).

**Gist — aucun one-shot scheduler universel ; chaîne par plateforme, ordonnée par survie au reboot :**
- **Linux systemd** : `systemd-run --user --on-calendar="<date absolue>" --timer-property=RemainAfterElapse=no` (propre, journalisé, auto-nettoyé ; **ne survit PAS au reboot** — transient dans `/run` tmpfs ; requiert `loginctl enable-linger`) → `at` → crontab auto-effaçant → humain.
- **Linux non-systemd** : `at`/`atd` (souvent busybox) → crontab auto-effaçant → daemon `sleep` détaché (`nohup`) → humain.
- **macOS** : `at -t` **seulement si `atrun` activé** (désactivé par défaut, `Disabled=true`, activation root ponctuelle) → LaunchAgent auto-désinstallant → daemon `sleep` (+`caffeinate`) → humain.
- **Nuance décisive pour [17]** : le mur **hebdo** peut être à **des jours** → l'attente **peut traverser un reboot** → **privilégier les files sur disque** (`at` spool, `.timer` installé `Persistent=true`, crontab) **plutôt que** le transient `systemd-run` / le daemon `sleep` (qui meurent au reboot).
- **Skill `schedule`** : **inadapté** au local headless — routine **cloud** exigeant un login claude.ai (pas de clé API), **masquée si `ANTHROPIC_API_KEY`/télémétrie-off**, sans accès FS/MCP local. **Sorti de la chaîne locale** ; au mieux relance cloud de secours.
- **Pièges** : reboot (transient meurt), linger (`--user` au logout), `atd`/`atrun` non activés par défaut, PATH/env minimal, stdout `at` perdu sans redirection.

→ **Affine [17]** (voir sa note d'affinement).
