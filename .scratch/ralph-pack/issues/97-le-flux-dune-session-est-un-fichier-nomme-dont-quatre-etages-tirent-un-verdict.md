# 97 — Le flux d'une session est un fichier nommé dont quatre étages tirent un verdict

**What to build:** Que le flux `stream-json` d'une session — le seul objet dont les quatre étages qui spawnent un `claude` tirent leur réponse — ne soit plus un fichier nommé de `$TMPDIR` pendant toute la durée de la session qui l'écrit, ou que chaque étage dise ce que sa réponse vaut.

**Blocked by:** None

**Write-surface:** `.claude/lib/session.sh`, `.claude/lib/monitor.sh`, `.claude/lib/lenses.sh`, `.claude/lib/playthrough.sh`, `.claude/lib/retro.sh`, `.claude/loop.sh`, `test/smoke.bats`, `test/lenses.bats`, `test/playthrough.bats`, `test/retro.bats`, `test/budget.bats`, `test/canary.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** needs-triage

- [ ] Le **verdict d'une lentille** (`lenses__verdict`, dernière ligne `RALPH-LENS-VERDICT:` du flux) n'est plus lu dans un fichier qu'un process extérieur à l'arbre du pilote peut réécrire pendant que la session écrit. C'est le poste qui achète un **vert** : `pass` forgé → la lentille est verte, le gate est vert, le ticket est `resolved`.
- [ ] Les **trois autres verdicts de flux** sont traités par la même décision ou l'aveu est écrit pour chacun : `playthrough_close` (le gate de valeur, [11]), `retro_run` (leçon, ADR, escalade, capacité, [14]/[63]), et la **posture de budget** de la session de livraison (`budget_stream_posture "$outfile"` → `$slot/posture` → le pilote pause ou arrête le run).
- [ ] Les **faits du reçu** tirés du même flux sont tranchés : `session_result_field num_turns`, `total_cost_usd`, `monitor_peak_tokens`. Ce ne sont pas des verdicts, mais ils sont la comptabilité de la nuit.
- [ ] La ligne du tableau qui dit ce qu'un flux de session vaut est écrite. Aujourd'hui le tableau ne parle du flux **que** pour la lentille (ligne « Une panne de quota ne coûte pas un retry au ticket »), et la borne qu'il y écrit — « au-dessus de `MAX_PARALLEL=1` » — est fausse pour la même raison que celle de [92] l'était : un survivant de la session **jugée** n'a pas besoin d'une sœur.
- [ ] Le **`skip` du canari** posé en livrant [94] est levé : `test/canary.bats`, « a process the judged session left behind cannot forge a lens verdict ». C'est le marqueur de cette faille et il fait partie des AC de ce ticket (CLAUDE.md, DoD 7).
- [ ] Témoin appairé et survivant réel, comme [92] et [94].

## Comments

- **Ouvert le 24/09/2026 en livrant [94]**, qui a fermé le canal et pas la source. [94] a sorti du répertoire du gate les trois réponses que le **parent** lisait après la mort d'une branche — la classe d'échec, la ligne de couverture, la posture de refus d'une lentille — en les faisant voyager sur un descripteur d'un fichier sans nom (`gate_note` / `gate_noted`). Ce qui reste, et que [94] ne pouvait pas atteindre depuis sa write-surface : **le flux lui-même**.

- **Pourquoi ça ne se ferme pas au-dessus de `session_spawn`.** Le flux doit avoir un nom pendant toute la session, pour deux raisons mécaniques :
  - `session_spawn` le donne à `claude` par une redirection (`>"$outfile"`), et se le donne d'abord à lui-même (`: >"$outfile"`) ;
  - `monitor_watch` le suit par un descripteur **à lui** (`exec 3<"$file"`), ouvert *par le chemin*, parce qu'un descripteur ne se rembobine pas et que `/dev/fd/N` est un `dup` sur darwin — le lecteur partagerait l'offset de l'écrivain.

  Un `/dev/fd/N` passé comme `$outfile` échoue sur la seconde : ouvrir en lecture le `dup` d'un descripteur ouvert en écriture ne marche pas, et l'ouvrir en lecture-écriture donne au moniteur l'offset de `claude`. **Mesuré et écarté en livrant [94] — ne pas re-sonder cette sortie sans dire ce qui est différent.**

- **Ce qu'un survivant achète aujourd'hui sur le flux d'une lentille.** `lenses__verdict` prend la **dernière** occurrence du jeton dans le flux (à dessein : un modèle qui cite sa consigne en chemin ne décide pas du verdict). Donc une boucle qui ajoute `RALPH-LENS-VERDICT: pass` en fin de fichier gagne à tous les coups, et pas dans une fenêtre étroite. C'est un **vert forgé**, la pire classe du projet.

- **Ce que [94] a déjà rendu plus cher, et qu'il ne faut pas re-mesurer comme si rien n'avait bougé** : la lecture qui *décidait de la facturation* se fait maintenant **dans la branche**, tout de suite après le retour de `session_spawn`. Le scénario de la sonde `q1` — attendre que le verdict apparaisse, puis réécrire le flux — arrive désormais trop tard pour la posture. Ce qui reste atteignable sur la posture est une course : tronquer le flux entre la dernière écriture de `claude` et `lenses__verdict`. Le **verdict**, lui, n'est pas une course du tout, pour la raison du point précédent.

- **La borne qui existe déjà et qui n'est pas une réparation** : la posture ne peut que rendre le run *plus* prudent ([43]), et `STERILE_K` / `ITER_CAP` bornent la nuit. Rien de tout ça ne borne un `pass` forgé.

- **Une piste à instruire, pas une solution** : le jeton de verdict pourrait porter un secret que le juge reçoit dans son prompt. Depuis [94] le prompt d'une lentille est **sans nom** (`lenses__prompt_open`), donc un secret écrit dedans n'est lisible par personne d'autre — mais le juge le recopie dans sa réponse, donc dans le flux, donc un survivant l'y lit avant `lenses__verdict`. Il faudrait alors prendre la **première** occurrence et non la dernière, ce qui rouvre exactement la raison pour laquelle `lenses__verdict` prend la dernière. À trancher, pas à supposer.
