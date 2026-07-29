# 27 — Un ticket renommé laisse deux fois le même NN, et la frontière ne s'en remet pas

**What to build:** Refermer la combinaison que la protection du tracker de [21] ne couvre pas. Un renommage de fichier de ticket est un `D` plus un `A` : la protection **restaure** le supprimé et **laisse** le créé, par deux décisions correctes prises séparément. Résultat, deux fichiers portent le même `NN`, `tracker_local__path` refuse à juste titre de résoudre un numéro nu ambigu, et tout ticket portant `Blocked by: NN` quitte la frontière — définitivement.

**Blocked by:** None

**Write-surface:** `.claude/lib/failures.sh`, `.claude/lib/tracker-local.sh`, `test/failures.bats`, `test/tracker-local.bats`, `test/mutate.sh`

**Status:** ready-for-agent

- [ ] Un `NN` en double ne peut pas naître d'une session : soit le renommage est restauré des deux côtés, soit le fichier créé est mis en quarantaine sous un identifiant qui ne collisionne pas.
- [ ] Un `NN` en double déjà présent — un humain peut en créer un à la main — est signalé au préflight du run, pas découvert ticket par ticket en cours de route.
- [ ] Un ticket dont le blocage pointe vers un `NN` ambigu ne disparaît pas en silence : la boucle dit lequel et pourquoi, dans `run.log` et non seulement sur stderr.
- [ ] Le test crée la collision par un renommage de session, pas en déposant deux fichiers à la main : c'est le chemin qui l'a produite.

## Comments

- **Origine : passe transversale 01→22, le 29/07/2026.** Sondé avec une session qui fait `mv .scratch/demo/issues/01-alpha.md .scratch/demo/issues/01-alpha-v2.md`, tracker seedé avec `01-alpha` et `03-blocked` (`Blocked by: 01`). Le pack se comporte comme prévu à chaque étape, et le résultat est cassé :

  ```
  ralph: 01-alpha: the session edited the tracker — restored 1 ticket file(s)
  ralph: 01-alpha: the session wrote the tracker itself — quarantined 01-alpha-v2
  ...
  tracker: "01" matches 2 tickets — an ambiguous id is never safe to resolve
  ```

  Tracker après le run : `01-alpha.md`, `01-alpha-v2.md`, `03-blocked.md`. `tracker_field 01` est illisible, `tracker_frontier` ne rend plus rien d'exploitable, et `03-blocked` est hors frontière pour toujours — son blocage ne pourra plus jamais être évalué comme satisfait. Le run a bouclé trois fois sur `01-alpha`, l'a escaladé en `failed-impl`, puis est sorti en « sterile run ». Dans un tracker plus grand il serait sorti en `exit 0` — « ce run a broyé tout ce qu'il pouvait » — avec un ticket silencieusement perdu.

- **Aucun des deux comportements n'est faux tout seul, et c'est ça la trouvaille.** [21] a raison de restaurer un ticket modifié ou supprimé : c'est ce qui empêche une session de réécrire la write-surface sur laquelle elle va être jugée. [21] a aussi raison de **ne pas** supprimer un ticket créé : « le rendre au snapshot aurait effacé la seule copie de ce qu'il demandait », donc quarantaine et un humain tranche. Le troisième corollaire de `docs/frontiere-de-confiance.md` — « un contrôle qui restaure doit dire ce qu'il ne restaure pas » — a été posé en livrant [21] et il pointait déjà ici : ce que la protection ne restaure pas, c'est un `A`, et un renommage est le cas où un `A` et un `D` décrivent le **même** ticket.

- **Ce qui aggrave : l'itération suivante hérite du désordre.** Aux itérations 2 et 3 la sonde lit « restored **2** ticket file(s) » : le snapshot pré-session contient désormais le fichier mis en quarantaine, la session le réécrase, et la protection restaure les deux. Le ticket accumule ses trois `Failures:` sur un défaut que la boucle a elle-même stabilisé dans le tracker.

- **Priorité honnête : c'est le moins probable des quatre trous trouvés par cette passe.** Une session à qui l'on dit « ne touche à aucun ticket » ne renomme pas un fichier de ticket par accident. Ce qui le rend digne d'un ticket plutôt que d'un commentaire, c'est qu'il est **permanent** quand il arrive — rien dans le pack ne sort le tracker de cet état — et qu'il casse la frontière entière, pas seulement le ticket touché. Le contrôle de préflight de l'AC 2 est peut-être la moitié qui vaut le plus cher pour le moins d'effort.

- **Contrainte pour [18] : ce trou est propre au backend local.** La collision naît de la convention « le nom de fichier porte le `NN` » et du glob `NN-*.md` de `tracker_local__path`. Un backend distant numérote côté serveur et n'a pas ce chemin — mais il devra dire, dans son propre ticket, comment il rend `tracker_ids` stable quand deux tickets prétendent au même identifiant.
