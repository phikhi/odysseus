# Programmer une exécution UNIQUE (one-shot) à une heure absolue future, depuis un daemon bash headless, de façon portable Unix

> Recherche menée le 2026-07-24. Sources primaires = pages man officielles (POSIX, macOS/Apple, systemd/freedesktop) + doc officielle Claude Code. Tout le reste (défauts par distro, patterns crontab auto-effaçants) est explicitement marqué **communautaire**.

## Résumé exécutif (actionnable)

- **Aucun mécanisme n'est universellement présent ET activé par défaut.** Un daemon portable DOIT sonder ce qui est disponible et retomber en cascade. Ordre recommandé :
  - **Linux systemd** (majorité 2026) : `systemd-run` transient timer → `at` → crontab auto-effaçant → reprise humaine.
  - **Linux non-systemd** (Alpine/OpenRC, conteneurs, Devuan) : `at`/`atd` (souvent busybox) → crontab auto-effaçant → daemon `sleep` détaché → reprise humaine.
  - **macOS** : `at` **seulement si `atrun` a été activé une fois** (désactivé par défaut) → LaunchAgent auto-désinstallant → daemon `sleep` détaché → reprise humaine.
- **Piège n°1 : le reboot pendant l'attente.** Seuls les mécanismes dont la file est **sur disque** survivent : `at` (spool `/var/spool/`), un `.timer` systemd installé avec `Persistent=true`, une entrée crontab. Un **timer transient systemd-run** (dans `/run`, tmpfs) et un **daemon `sleep`** meurent au reboot. → Si l'attente peut traverser un redémarrage, privilégier `at` ou un timer installé, pas le transient.
- **Piège n°2 : `--user` systemd s'arrête au logout.** Sans `loginctl enable-linger $USER`, les unités utilisateur sont tuées à la déconnexion. Pour un daemon headless, activer le linger OU utiliser `--system` (nécessite root).
- **Piège n°3 : `atd`/`atrun` n'est pas activé par défaut** — surtout macOS (`Disabled=true` d'usine, activation root ponctuelle requise). Le binaire `at` peut exister mais rester inerte tant que le démon ne tourne pas.
- **Piège n°4 : PATH/env minimal** en `at`/cron. Toujours chemins absolus, `PATH=` explicite, et rediriger stdout/stderr vers un fichier (sinon `at` envoie par mail, et sans MTA la sortie est **silencieusement perdue**).
- **Le skill `schedule` de Claude Code n'est PAS une primitive d'ordonnancement local headless fiable.** `/schedule` crée une *routine cloud* (exécutée sur l'infra Anthropic), exige un **login claude.ai (abonnement)** — pas une clé API — et est **masqué/refusé si `ANTHROPIC_API_KEY`/`ANTHROPIC_AUTH_TOKEN` est défini** ou si des variables anti-télémétrie sont posées. En cron/headless avec auth par clé API, il est indisponible. De plus les serveurs MCP locaux (`claude mcp add`) **ne sont pas** exposés aux routines cloud. Utile comme *rappel/relance cloud*, pas comme minuterie locale.

---

## 1. `at` / `atd` (atrun)

### Officiel — spécification POSIX de `at(1)`
- **Syntaxe one-shot à heure absolue.** L'option `-t` prend un temps « au format de `touch -t` », décrit comme « an internationalized way of specifying a time for execution of the submitted job ». Le format `touch -t` est `[[CC]YY]MMDDhhmm[.SS]` → **`at -t YYYYMMDDhhmm`** est correct (ex. `at -t 202607251430`). Syntaxe libre acceptée aussi : `at 0815am Jan 24`, `at now "+ 1day"`, `echo cmd | at now + 5 hours`. [POSIX at(1p)](https://man7.org/linux/man-pages/man1/at.1p.html) · [macOS touch(1)](https://ss64.com/mac/touch.html)
- **Où va stdout/stderr.** « If -m is not used, the job's standard output and standard error shall be provided to the user by means of mail, unless they are redirected elsewhere. » → En headless **il FAUT rediriger** (`>>/chemin/log 2>&1`) car sans MTA local la sortie est perdue. [POSIX at(1p)](https://man7.org/linux/man-pages/man1/at.1p.html)
- **Code de retour.** `0` = soumission/suppression/listing réussi ; `>0` = erreur. ⚠️ C'est le code de **soumission**, pas celui du job exécuté plus tard — le job ne remonte son statut que par mail. [POSIX at(1p)](https://man7.org/linux/man-pages/man1/at.1p.html)
- **macOS : `atrun(8)`.** « The atrun utility runs commands queued by at(1). It is invoked periodically by launchd(8) as specified in the com.apple.atrun.plist property list. » — et surtout : **« By default the property list contains the Disabled key set to true, so atrun is never invoked. »** Activation (root, une fois) : `sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.atrun.plist`. Sur macOS, `at` **délègue donc à launchd** via `atrun`. [atrun(8) macOS](https://www.unix.com/man_page/osx/8/atrun/)

### Communautaire — disponibilité par défaut
- Le paquet `at` est **souvent présent mais pas garanti** ; à installer selon la distro (`apt install at`, `dnf install at`). Le service **`atd` n'est pas systématiquement activé** : `systemctl enable --now atd` peut être requis. Sur les images minimales/serveur, `at` est fréquemment absent. Fiabilité headless : bonne **une fois `atd` en marche** (file sur disque, survit au reboot), mais le prérequis « démon actif » n'est pas acquis. [linuxconfig](https://linuxconfig.org/how-to-schedule-tasks-using-at-command-on-linux) · [tecmint](https://www.tecmint.com/at-command-linux/) · [RHEL6 deployment guide](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/deployment_guide/sect-atd-running)
- Alpine/busybox fournit un `at` allégé (démon `atd` busybox) — options réduites, vérifier `-t`. (Observation communautaire.)

### Exemple headless robuste
```bash
echo '/usr/bin/env PATH=/usr/bin:/bin /chemin/reprise.sh >>/var/log/odysseus-oneshot.log 2>&1' \
  | at -t 202607251430
# vérifier: atd tourne ? sinon fallback
```

---

## 2. `systemd-run --on-calendar=` (timer transient) — Linux systemd

### Officiel — `systemd-run(1)`
- **One-shot à heure absolue.** `--on-calendar=` « Defines a calendar timer for starting the specified command. See *OnCalendar=* in systemd.timer(5). This option is a shortcut for **--timer-property=OnCalendar=**. » Un `OnCalendar` avec **date complète** (`2026-07-25 14:30:00`) ne matche **qu'une fois** → c'est le vrai one-shot. Il existe aussi `--on-active=` (délai monotone relatif, ex. `--on-active=5h`). [systemd-run(1)](https://man7.org/linux/man-pages/man1/systemd-run.1.html)
- **Ce que ça crée.** « a transient path, socket, or timer unit is created alongside the service unit for the specified command. Only the transient path, socket, or timer unit is started immediately, the transient service unit will be triggered by [it]. » [systemd-run(1)](https://man7.org/linux/man-pages/man1/systemd-run.1.html)
- **`--user` vs système.** `--user` = « the service manager of the calling user » ; **`--system` est le défaut** (nécessite privilèges). [systemd-run(1)](https://man7.org/linux/man-pages/man1/systemd-run.1.html)
- **Nettoyage auto.** `RemainAfterElapse=` (défaut **`true`**) : quand mis à **`false`**, « an elapsed timer unit that cannot elapse anymore is unloaded once its associated unit deactivated again. **Turning this off is particularly useful for transient timer units.** » → pour un vrai one-shot auto-nettoyé : `--timer-property=RemainAfterElapse=no`. [systemd.timer(5)](https://man7.org/linux/man-pages/man5/systemd.timer.5.html)
- **Rattrapage après reboot.** `Persistent=` (n'a d'effet qu'avec `OnCalendar=`) : « the time when the service unit was last triggered is stored on disk … the service unit is triggered immediately if it would have been triggered at least once during the time when the timer was inactive. » ⚠️ **Mais les unités transient vivent dans `/run` (tmpfs) et ne survivent PAS au reboot** — `Persistent` ne les sauve pas. Le rattrapage n'existe que pour un `.timer` **installé sur disque**. [systemd.timer(5)](https://man7.org/linux/man-pages/man5/systemd.timer.5.html) · [DoHost](https://dohost.us/index.php/2025/10/27/running-one-shot-commands-with-systemd-run/)
- **Survie au logout.** Unités `--user` = tuées à la déconnexion sauf `loginctl enable-linger $USER`. (Comportement systemd/loginctl standard.)
- **Sortie.** stdout/stderr du service transient sont capturés par le journal → `journalctl --user -u <unit>` / `systemctl status <unit>`. (Comportement standard des unités de service.)

### « Run once » natif ?
**N'existe pas** en tant que flag dédié. L'issue systemd **#34222** *demande* `--timer-run-once` / `RunOnce=true` ; réponse : mettre la **date complète** dans `OnCalendar` (le mainteneur note que sinon « from now on this command will be running daily »). État = **feature request ouverte, non livrée**. Le workaround = date absolue + `RemainAfterElapse=no`. [issue #34222](https://github.com/systemd/systemd/issues/34222)

### Exemple recommandé (one-shot auto-nettoyé)
```bash
# Court terme (pas de reboot attendu) :
systemd-run --user \
  --on-calendar="2026-07-25 14:30:00" \
  --timer-property=RemainAfterElapse=no \
  /chemin/reprise.sh
# Prérequis daemon headless : loginctl enable-linger "$USER"
# Sinon --system (root).
```

---

## 3. `launchd` (macOS)

### Officiel — `launchd.plist(5)`
- **`StartCalendarInterval`** : « causes the job to be started every calendar interval as specified » via `Minute`(0-59), `Hour`(0-23), `Day`(1-31), `Weekday`(0/7=dimanche), `Month`(1-12). **C'est récurrent : il n'y a pas de clé one-shot native pour le calendrier.** [launchd.plist(5)](https://keith.github.io/xcode-man-pages/launchd.plist.5.html)
- **Machine endormie/éteinte.** « Unlike cron which skips job invocations when the computer is asleep, launchd will start the job the next time the computer wakes up. If multiple intervals transpire before the computer is woken, those events will be coalesced into one event upon wake from sleep. » → rattrapage au réveil, mais **coalescé** (un seul déclenchement). [launchd.plist(5)](https://keith.github.io/xcode-man-pages/launchd.plist.5.html)
- **`RunAtLoad`** (défaut `false`) : lance le job au chargement. Doc déconseille l'abus (« speculative job launches have an adverse effect on system-boot »). [launchd.plist(5)](https://keith.github.io/xcode-man-pages/launchd.plist.5.html)
- **Agent vs Daemon.** LaunchAgents = par utilisateur (`~/Library/LaunchAgents`, `/Library/LaunchAgents`), tournent dans la session GUI de l'utilisateur ; LaunchDaemons = système (`/Library/LaunchDaemons`), tournent sans session. [launchd.plist(5)](https://keith.github.io/xcode-man-pages/launchd.plist.5.html)

### One-shot via launchd
Pas de clé native → deux voies :
1. **Passer par `at`** (qui délègue à `atrun`/launchd) une fois `atrun` activé — le plus simple si root dispo une fois (voir §1).
2. **LaunchAgent auto-désinstallant** : `StartCalendarInterval` réglé sur la date cible, dont le script termine par `launchctl bootout gui/$UID/<label>` + suppression du `.plist`. (Pattern communautaire, analogue au crontab auto-effaçant.)

### Piège macOS
`atrun` **et** launchd ne déclenchent pas pendant le sommeil ; launchd rattrape au réveil (coalescé), pas `atrun`. Pour une garantie horaire, il faut empêcher le sommeil (`caffeinate`) ou accepter le glissement. Activation de `atrun` = **root, une seule fois**. [atrun(8)](https://www.unix.com/man_page/osx/8/atrun/) · [Apple Community](https://discussions.apple.com/thread/253382003)

---

## 4. `cron` avec entrée auto-effaçante

### Pattern (communautaire)
Ajouter une ligne crontab pour l'heure cible, dont l'action se retire elle-même après exécution :
```cron
30 14 25 7 * /chemin/reprise.sh; /usr/bin/crontab -l | grep -v '/chemin/reprise.sh' | /usr/bin/crontab -
```
[dcblog](https://dcblog.dev/crontab-command-to-delete-itself)

### Pièges (communautaire)
- **Robustesse à l'échec.** Si le script `set -e` échoue avant la ligne d'auto-suppression, l'entrée **reste** et se rejouera (au prochain match, potentiellement dans un an vu les champs mois/jour). Structure plus sûre : `run-task || true; self-delete`. [dcblog / dev.to](https://dev.to/dcblog/crontab-command-to-delete-itself-1bph)
- **Race d'édition de crontab.** `crontab -l | ... | crontab -` n'est pas atomique : deux éditions concurrentes (le daemon + un autre process) peuvent se perdre. Sérialiser via un lock (`flock`).
- **PATH/env minimal.** cron tourne avec un PATH réduit (souvent `/usr/bin:/bin`) et sans le profil shell. → chemins absolus partout, `PATH=` en tête de crontab, et le PATH d'`/etc/environment` **n'est pas** hérité. [linuxblog.io](https://linuxblog.io/cron-crontab-task-scheduling-linux/) · [dev.to](https://dev.to/stackallflow/why-crontab-scripts-are-not-working-in-ubuntu-1f11)
- **Sommeil.** cron (contrairement à launchd) **saute** les exécutions manquées pendant l'arrêt/sommeil.

Robustesse : entrée sur disque (survit au reboot), mais fragile (race + auto-nettoyage conditionnel). À réserver au fallback.

---

## 5. Skill `schedule` de Claude Code

### Officiel — doc « Routines » et « Desktop scheduled tasks »
- **Nature.** `/schedule` (alias `/routines`) crée une **routine cloud** : « Routines execute on Anthropic-managed cloud infrastructure. » Ce n'est **pas** une minuterie locale. [routines](https://code.claude.com/docs/en/routines)
- **One-shot supporté.** « run … once at a specific future time ». Un one-off « fires the routine a single time at a specific timestamp. After the routine fires, it **auto-disables** and the web UI marks it as **Ran**. » CLI : `/schedule tomorrow at 9am, …`. ⚠️ « One-off scheduling from the CLI is rolling out gradually and may not be available on your account yet » → sinon via [claude.ai/code/routines](https://claude.ai/code/routines). [routines](https://code.claude.com/docs/en/routines)
- **Gating par plan.** « Routines are available on Pro, Max, Team, and Enterprise plans with **Claude Code on the web enabled**. » Un Owner Team/Enterprise peut tout désactiver (« Routines are disabled by your organization's policy »). [routines](https://code.claude.com/docs/en/routines)
- **Disponibilité HORS session interactive / headless — POINT CRITIQUE.** `/schedule` est **masqué ou refusé** (`Unknown command: /schedule`) quand :
  - « You are authenticated with a Console API key or a cloud provider (Bedrock, Vertex, Foundry). **`/schedule` requires a claude.ai subscription login.** If `ANTHROPIC_API_KEY` or `ANTHROPIC_AUTH_TOKEN` is set … remove it first » ;
  - « `DISABLE_TELEMETRY`, `DO_NOT_TRACK`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, or `DISABLE_GROWTHBOOK` is set … These disable feature-flag fetching, which `/schedule` depends on » ;
  - « You are inside a Claude Code on the web session ».
  → En **cron/headless typique (auth par clé API, télémétrie coupée)**, le skill est **indisponible**. Il exige un login claude.ai stocké + accès aux feature flags. [routines](https://code.claude.com/docs/en/routines)
- **MCP en headless/cloud (confirme l'indice).** « MCP servers you added locally in the CLI with `claude mcp add` are stored on your machine … so they **do not appear in the connectors list** » des routines. Les connecteurs d'une routine = intégrations claude.ai (authentifiées côté compte). → Un MCP branché interactivement en local est **absent** de la routine cloud. [routines](https://code.claude.com/docs/en/routines)
- **Alternatives locales officielles.**
  - **Desktop scheduled tasks** : tournent **sur la machine**, one-shot supporté (« remind me at 3pm tomorrow … creates a one-time task that **disables itself after it fires** »), MAIS « only fires **while the app is open and your computer is awake** ». Pas adapté à un daemon bash headless. [desktop-scheduled-tasks](https://code.claude.com/docs/en/desktop-scheduled-tasks)
  - **`/loop`** : ordonnancement **intra-session** uniquement (nécessite une session ouverte). [desktop-scheduled-tasks (tableau comparatif)](https://code.claude.com/docs/en/desktop-scheduled-tasks)

### Verdict pour Odysseus
Le skill `schedule` n'est **pas** une brique d'exécution one-shot locale pour un daemon bash headless. Sa valeur : programmer une **relance cloud** (routine one-off) qui reprendra le travail côté Anthropic — utile comme *reprise de secours* si le login claude.ai est présent, mais soumis à l'auth (absente en cron par clé API) et sans accès au FS/MCP local.

---

## 6. Synthèse actionnable — chaîne de fallback par plateforme

Le framework détecte la plateforme, tente chaque mécanisme dans l'ordre, et retombe sur la reprise humaine si aucun ne prend.

### Linux systemd (cas majoritaire 2026)
1. **`systemd-run --user --on-calendar="<date absolue>" --timer-property=RemainAfterElapse=no <cmd>`** — propre, journalisé, auto-nettoyé. Prérequis : `loginctl enable-linger $USER` (survie au logout). *Ne survit pas au reboot.*
2. **Si l'attente peut traverser un reboot** → préférer **`at -t YYYYMMDDhhmm`** (spool disque) OU un `.timer` **installé** avec `Persistent=true` (rattrapage au boot).
3. **`at`** si `atd` actif (`systemctl is-active atd`), sinon tenter `systemctl enable --now atd`.
4. **crontab auto-effaçant** (avec `flock` + `|| true; self-delete`).
5. **Reprise humaine.**

### Linux non-systemd (Alpine/OpenRC, conteneurs, Devuan)
1. **`at`/`atd`** (souvent busybox — vérifier le support de `-t`, sinon `at now + N minutes`).
2. **crontab auto-effaçant** (busybox `crond`).
3. **Daemon `sleep` détaché** : `nohup sh -c 'sleep <sec>; <cmd>' &` (survit au logout via nohup, **meurt au reboot**, tient un process).
4. **Reprise humaine.**

### macOS
1. **`at -t YYYYMMDDhhmm`** — **uniquement si `atrun` a été activé** (`launchctl print system/com.apple.atrun` ; sinon `sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.atrun.plist`, root, une fois).
2. **LaunchAgent auto-désinstallant** (`StartCalendarInterval` sur la date, script terminant par `launchctl bootout` + suppression du plist).
3. **Daemon `sleep` détaché** (+ `caffeinate` si l'attente doit ignorer le sommeil).
4. **Reprise humaine.**

### Pièges majeurs (transverses)
| Piège | Impact | Parade |
|-------|--------|--------|
| **Reboot pendant l'attente** | transient systemd + daemon `sleep` meurent | `at` / `.timer` `Persistent=true` / crontab (sur disque) |
| **Logout** (`--user`) | unités user tuées | `loginctl enable-linger $USER` ou `--system` |
| **`atd`/`atrun` non activé** (macOS surtout) | job jamais lancé | vérifier + activer (root une fois) |
| **PATH/env minimal** (at/cron) | commande introuvable | chemins absolus, `PATH=` explicite |
| **stdout/stderr** (at) | perdu sans MTA | rediriger `>>fichier 2>&1` |
| **Sommeil macOS/cron** | run sauté (cron) ou coalescé (launchd) | `caffeinate` / accepter le glissement |
| **Skill `schedule` = cloud + login claude.ai** | indispo en cron/API-key ; MCP local absent | ne pas en dépendre pour l'exécution locale ; réserver à la relance cloud |

---

## Non documenté / incertain (à surveiller)

| Point | Statut |
|-------|--------|
| `at` préinstallé + `atd` activé par défaut selon distro | **Communautaire, variable.** Ne pas supposer — sonder `command -v at` + `systemctl is-active atd`. |
| Support de `at -t` en busybox (Alpine) | **À vérifier à l'exécution** ; options busybox réduites. |
| Nettoyage exact des unités transient au reboot | Man page confirme `RemainAfterElapse=no` pour le GC après élapse ; la non-survie au reboot (tmpfs `/run`) est **standard mais explicité surtout par sources communautaires** (DoHost). |
| `RunOnce`/`--timer-run-once` systemd natif | **Demandé (#34222), non livré.** Workaround = date absolue + `RemainAfterElapse=no`. |
| One-off `/schedule` depuis la CLI | **Déploiement progressif** — peut être absent d'un compte (fallback web). |
| Invocation de `/schedule` en pur `claude -p` headless | **Non documenté comme flux supporté** ; gating claude.ai login + feature flags → à considérer indisponible en cron par clé API. |
| LaunchAgent one-shot auto-désinstallant | **Pattern communautaire**, pas une clé officielle launchd. |

---

### Sources
Officielles / primaires : [POSIX at(1p)](https://man7.org/linux/man-pages/man1/at.1p.html) · [atrun(8) macOS](https://www.unix.com/man_page/osx/8/atrun/) · [macOS touch(1) (-t)](https://ss64.com/mac/touch.html) · [systemd-run(1)](https://man7.org/linux/man-pages/man1/systemd-run.1.html) · [systemd.timer(5)](https://man7.org/linux/man-pages/man5/systemd.timer.5.html) · [launchd.plist(5)](https://keith.github.io/xcode-man-pages/launchd.plist.5.html) · [Claude Code — Routines](https://code.claude.com/docs/en/routines) · [Claude Code — Desktop scheduled tasks](https://code.claude.com/docs/en/desktop-scheduled-tasks) · [systemd issue #34222](https://github.com/systemd/systemd/issues/34222) · [RHEL — Running the At Service](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/6/html/deployment_guide/sect-atd-running)
Communautaires : [linuxconfig at](https://linuxconfig.org/how-to-schedule-tasks-using-at-command-on-linux) · [tecmint at](https://www.tecmint.com/at-command-linux/) · [DoHost systemd-run one-shot](https://dohost.us/index.php/2025/10/27/running-one-shot-commands-with-systemd-run/) · [Arch Wiki systemd/Timers](https://wiki.archlinux.org/title/Systemd/Timers) · [dcblog crontab auto-suppression](https://dcblog.dev/crontab-command-to-delete-itself) · [dev.to crontab self-delete](https://dev.to/dcblog/crontab-command-to-delete-itself-1bph) · [linuxblog.io cron/crontab](https://linuxblog.io/cron-crontab-task-scheduling-linux/) · [dev.to cron PATH](https://dev.to/stackallflow/why-crontab-scripts-are-not-working-in-ubuntu-1f11) · [Apple Community — enable at](https://discussions.apple.com/thread/253382003)
