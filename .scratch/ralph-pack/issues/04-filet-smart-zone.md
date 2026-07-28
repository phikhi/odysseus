# 04 — Filet smart-zone (auto-compact OFF + SIGTERM 150K)

**What to build:** Le filet runtime dur qui garantit qu'une session finit en smart zone, indépendamment du découpage : auto-compact désactivé, et SIGTERM de la session au franchissement du seuil mou 150K, détecté sur le flux stream-json. Le dur 200K reste la frontière dumb-zone documentée.

**Blocked by:** 03

**Write-surface:** `.claude/lib/monitor.sh`, `.claude/loop.sh`, `test/smart-zone.bats`, `test/helpers/harness.bash`, `test/helpers/shims/claude`, `test/smoke.bats`

**Status:** resolved

- [x] L'auto-compact est forcé OFF pour toute session spawnée par la boucle.
- [x] Un fake `claude` dont le flux franchit `SOFT_LIMIT_TOKENS` (150K) reçoit un SIGTERM ; l'itération est traitée comme non-succès (rollback + suite), pas comme `resolved`.
- [x] Sous le seuil, aucune interruption : le monitor n'affecte pas le happy-path d'[03].
- [x] Le seuil est piloté par `SOFT_LIMIT_TOKENS` (config) ; le dur 200K = frontière dumb-zone documentée.

## Comments

- **Trois tests écrits pour ce ticket étaient vacuous ; les trois mutations correspondantes passaient au vert.** C'est la partie du travail qui a demandé le plus de temps, et la plus utile.

  1. **L'environnement du harnais n'était pas hermétique.** Le test « auto-compact off » lisait `DISABLE_AUTO_COMPACT=1` dans l'environnement du spawn — mais cette variable venait du `settings.json` du dépôt odysseus lui-même, injectée dans toute commande lancée depuis ce projet. Le test mesurait le shell, pas la boucle. Pire, chaque clé de config étant écrite `KEY="${KEY:-défaut}"`, n'importe quel `MODEL` ou `TEST_CMD` exporté écrasait silencieusement la config d'un test. Le harnais efface maintenant, avant chaque test, toutes les clés dérivées de `ralph.config.sh.example` plus les `DISABLE_*`/`RALPH_*`. Un test dédié verrouille l'herméticité.

  2. **Le test de terminaison n'observait qu'un message de log.** Il passait donc alors même que le `kill` avait été retiré. La session runaway du fake se termine par un `result` à `num_turns=9` : si elle survit, le journal le porte. L'assertion est maintenant l'absence de cette trace, pas la présence d'une phrase que la boucle imprime de toute façon.

  3. **La garde `RALPH_SOFT_LIMIT_HIT` semblait redondante avec le code de retour** — un process tué sort en 143, donc l'itération échoue déjà. Sauf que Claude Code trappe SIGTERM et peut s'arrêter proprement avec exit 0 : la boucle déclarerait alors `resolved` une session qu'elle vient d'interrompre. Un test avec un fake qui trappe SIGTERM et sort 0 rend la garde nécessaire et vérifiée.

- **Le comptage inclut les tokens de cache.** `input_tokens + cache_creation_input_tokens + cache_read_input_tokens + output_tokens` : cachés ou non, ces tokens occupent la fenêtre. Sur la capture réelle, le prompt système place à lui seul le plancher autour de 20K — un seuil qui ignorerait le cache serait faux d'un ordre de grandeur.

- **Extraction anchorée sur `{` ou `,`.** Sans ça, `"input_tokens"` matcherait `"cache_read_input_tokens"` et le compte serait n'importe quoi. Le test unitaire du comptage utilise la structure `usage` réelle, imbrication `cache_creation` comprise.

- **Auto-compact coupé deux fois** : dans `settings.json` (couvre aussi les sessions interactives du projet cible) et dans l'environnement du spawn. La garantie ne doit pas dépendre d'un fichier que le projet hôte peut écraser.

- **La session tourne désormais en arrière-plan** pour que le monitor puisse la surveiller pendant qu'elle vit — `$!` sur un pipeline donne le pid du dernier maillon, donc celui de `claude`. Le monitor sonde le flux toutes les 100 ms et fait toujours une dernière passe après la mort du process, pour ne manquer aucune ligne.

- **Ce qui manque encore et arrive en [07]** : le rollback. L'AC parle de « rollback + suite » ; aujourd'hui l'itération rend simplement le ticket à la frontière, sans nettoyer ce que la session a écrit. Le re-slice autonome d'une slice trop grosse est également [07].

- **Le journal porte maintenant le pic de contexte** (`tokens=`), ce qui donne de quoi calibrer le découpage sur des runs réels.

- **Revue après [05] — le monitor coûtait plus cher que la session qu'il surveillait.** Deux coûts, mesurés sur un flux réaliste de 20 Mo (2076 lignes, 1038 événements `usage`) :

  1. **Chaque tick relisait tout le flux depuis le début.** La reprise se faisait par nombre de lignes consommées (`tail -n +N`), or `tail` doit rescanner le fichier pour retrouver la ligne N. Mesuré : **0,045 s par tick à 1 Mo, 0,112 s à 5 Mo, 0,358 s à 20 Mo** — alors que la boucle tique toutes les 0,1 s. Le coût total était donc quadratique en la taille du flux, payé des milliers de fois, en concurrence avec la session et avec la suite de tests du projet cible.
  2. **Quatre `sed` par événement.** L'extraction des quatre compteurs forkait un process chacun : une passe complète sur ces 20 Mo prenait **21 s de CPU**.

  Corrigé sans changer l'architecture (poll + SIGTERM) : le flux est tenu ouvert sur un descripteur et lu en avant — chaque tick ne coûte que ce que la session vient d'écrire — et l'extraction se fait en pure expansion de paramètres, sans aucun sous-process. Mesuré après : **1000 ticks sans nouvelle donnée = 29,6 ms au total** (0,03 ms le tick, contre 358 ms), et la passe complète sur 20 Mo tombe de 21 s à 3,9 s.

  Ce que le descripteur ouvert introduit en échange : un tick peut tomber **au milieu d'une ligne**. La ligne partielle est gardée pour le tick suivant et recollée ; sans ça, une moitié d'événement `usage` est analysée comme un événement entier et le seuil peut être manqué. Test de non-régression dédié (le fake écrit un événement en deux `printf` séparés par un `sleep`), mutation vérifiée : en jetant la partielle, la session runaway survit.

  Corollaire dans `loop.sh` : le fichier de flux est créé (`: >`) avant le spawn, parce qu'on ne peut pas ouvrir un descripteur sur un fichier qui n'existe pas encore.

- **Modifié par [07] : `over-soft-limit` est devenu un échec typé.** Une session coupée pour cause de contexte n'est plus rendue à la frontière : c'est le signal `too-big`, donc re-slice autonome puis, si aucun découpage ne préserve les AC, escalade `ready-for-human` avec `Escalation: too-big`. Les deux tests de ce ticket qui assertaient `ready-for-agent` après un SIGTERM disent maintenant `ready-for-human` (dans le scénario du test, la session de re-slice franchit la limite molle elle aussi, ce qui est exactement le cas « personne ne sait découper »). Le filet, lui, est inchangé.
- **Trou qui reste ici** : le filet borne le **contexte** d'une session, pas son **temps**. [07] a posé un chien de garde sur les branches du gate (`GATE_TIMEOUT`), mais une session `claude` qui pend sans émettre de token n'est bornée par rien — `monitor_watch` ne tique que sur ce que le flux écrit. Un timeout de session est le pendant manquant.
- **Le test « the threshold is the configured one, not a hard-coded 150K » était vacuous, trouvé le 28/07/2026.** Il posait `SOFT_LIMIT_TOKENS=20000` contre une session de 9015 tokens : 9015 est sous 20000 **et** sous 150000, donc remplacer la lecture de config par un `150000` en dur ne changeait rien et le test restait vert. Il testait « le seuil n'est pas 5000 », pas « le seuil vient de la config ». Refermé en plaçant le test du **côté de la ligne que les autres ne peuvent pas atteindre** : `SOFT_LIMIT_TOKENS=300000` contre une session de 200015 tokens, qui doit finir — un 150000 en dur la terminerait. Leçon transposable : un test de seuil doit choisir une valeur qui *inverse* le verdict par rapport à la constante suspecte, sinon il ne distingue rien.
