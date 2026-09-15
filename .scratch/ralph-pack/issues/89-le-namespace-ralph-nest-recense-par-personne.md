# 89 — Le namespace `RALPH_*` n'est recensé par personne

**What to build:** Que l'hermétisme de la suite couvre ce que le pack se fabrique comme il couvre déjà ce que le projet configure : le namespace `RALPH_*` dérivé de la source, pas six noms écrits à la main.

**Blocked by:** None

**Write-surface:** `test/helpers/harness.bash`, `test/smoke.bats`, `test/mutate.sh`, `.claude/lib/retro.sh`, `.claude/lib/receipt.sh`, `.claude/lib/tracker.sh`, `.claude/lib/playthrough.sh`

**Status:** ready-for-agent

- [ ] `harness__clear_env` **dérive** de la source du pack les noms `RALPH_*` qu'il doit effacer, comme il dérive déjà les clés de configuration du `.example` trois lignes plus haut. Un nom ajouté au pack est effacé le jour où il arrive.
- [ ] Un test refuse le nom que la dérivation ne voit pas : une dérivation qui ne sait pas ce qu'elle ne voit pas ne prouve rien ([85]). Le critère du recensement est écrit dans le test, pas deviné.
- [ ] Le pendant de `test/smoke.bats` « *an exported config key does not leak in* » existe pour le namespace du pack : un run sous un `RALPH_*` exporté ne mesure pas l'environnement. Asserter sur ce qui a changé, jamais sur le succès du run.
- [ ] Les cinq noms qui **préservent** une valeur héritée au `source` sont tranchés un par un : soit la préservation est voulue et la ligne dit par qui elle est écrite, soit elle ne l'est pas et l'assignation devient inconditionnelle. Une réponse « ça ne se produit pas » n'en est pas une — c'est ce que [40] avait écrit pour un seul nom.
- [ ] Une entrée de mutation par garantie livrée, avec le témoin appairé.

## Comments

- **Ordre validé par Philippe le 14/09/2026** : **[87] → [86] → [88] → [89]**.
  Le critère est celui d'habitude — minimiser la reprise, jamais l'urgence. [87]
  devant parce qu'il ne touche que `test/` et qu'il pose le filet de source sous
  le heredoc de prose que [86] va réécrire ; [88] derrière [86] parce qu'il
  généralise une forme dont [86] livre le précédent ; [89] en dernier, sans arête.

- **Ouvert par la passe transversale du 14/09/2026** (`../passe-transversale-14-09.md`,
  §5). Sonde : `../sondes/passe-14-09/q4-le-namespace-ralph-nest-recense-nulle-part.bats`.

- **Le compte, mesuré.** Le pack nomme **42** variables `RALPH_*`.
  `harness__clear_env` en unset **6** : `RALPH_CONFIG`, `RALPH_DIR`,
  `RALPH_PROJECT_ROOT`, `RALPH_RUN_LOCK`, `RALPH_TREE_LOCK`,
  `RALPH_SOFT_LIMIT_HIT`. Les soixante-quatre clés de configuration, elles, sont
  dérivées du `.example` par un `sed`, dans la même fonction, juste au-dessus.

- **La règle que les six tiennent est celle de [40]**, recopiée dans le ticket
  [19] : *« `loop.sh` l'assigne aujourd'hui sans condition, ce qui est la seule
  raison pour laquelle une valeur héritée du shell d'un développeur est
  inoffensive — et c'est aussi pour ça que `harness__clear_env` peut se permettre
  de ne pas le connaître. »* Trente-six noms dépendent de cette règle et rien ne la
  vérifie.

- **Les cinq qui ne la respectent pas.** Leur lib les assigne **au `source`**, en
  `${X:-}`, donc en préservant une valeur héritée :

  | Nom | Lib | Ce qu'il porte |
  |---|---|---|
  | `RALPH_RETRO_STATE` | `retro.sh:102` | le répertoire d'état du rétro — celui que `retro_guards` compose, et où vivent `capability.seen` et `brief.<id>`, les deux objets que [83] a montrés |
  | `RALPH_RECEIPT` | `receipt.sh:66` | le répertoire du reçu d'audit |
  | `RALPH_TRACKER_SAID` | `tracker.sh:168` | ce qui **fait taire** le repli d'un constat de tracker ([64]) |
  | `RALPH_PLAYTHROUGH_SPEC` | `playthrough.sh:198` | le témoin de spec pris avant la première session |
  | `RALPH_PLAYTHROUGH_OPENED` | `playthrough.sh:513` | ce que le gate de valeur a ouvert |

  Mesuré : les valeurs traversent le `source` des vingt-quatre libs intactes, et
  `retro_guards` — le recensement de zones que [85] vient de dériver — rend un
  `index.guard` sous un répertoire choisi par l'environnement.

- **Ce que ce n'est pas, écrit pour que le ticket ne se trompe pas de menace.**
  Ce n'est **pas** un canal de session. Aucun de ces noms n'est exporté par le pack
  — seul `RALPH_DIR` l'est — donc ni un `claude` jugé, ni un successeur `at`, ni
  une lentille ne les place. Vérifié : `scheduler_command` n'en met que quatre sur
  la ligne mise en file (`PATH`, `RALPH_CONFIG`, `FEATURE`, `RALPH_PROJECT_ROOT`),
  et les autres ne sont pas dans l'environnement du pilote pour qu'`at` les
  capture. L'injecteur est le shell d'un humain, ou un wrapper.

- **Ce que c'est.** La moitié manquante de la garantie d'hermétisme de la suite.
  `test/smoke.bats` porte un test entier — *« the environment is hermetic: an
  exported config key does not leak in »* — parce qu'un `STERILE_K` dans le shell
  d'un développeur ferait mesurer son shell à la place du pack, et le commentaire
  de `harness__clear_env` le dit : *« This is not paranoia »*. Le namespace que le
  pack se fabrique lui-même n'a pas ce test, et il fait sept fois la taille de ce
  que le harnais en connaît.

- **Piège de dérivation, et c'est le seul vrai travail du ticket.** Un
  `grep -o 'RALPH_[A-Z0-9_]*'` sur `.claude/` attrape aussi les noms qui ne sont
  que dans des **commentaires** (`RALPH_REAL_USAGE`, qui est un interrupteur de
  test et pas une variable de run) — c'est le piège de harnais déjà payé plusieurs
  fois dans ce dépôt, un grep structurel qui attrape les commentaires. Et unset
  un nom que le harnais **pose lui-même** ensuite casserait la suite. La
  dérivation doit donc distinguer trois choses et le dire : ce que le pack lit,
  ce que le pack écrit, et ce que le harnais fournit.

- **Piège de mutation.** Une entrée qui retire un nom de la liste dérivée doit
  rougir un test qui **exporte** ce nom et mesure un effet, pas un test qui
  compare deux listes — sinon la mutation prouve la dérivation et pas ce qu'elle
  achète. Le témoin appairé : le même run sans la variable exportée.

- **Indépendant des trois autres tickets de la passe.** Il ne touche que `test/`
  si les cinq préservations sont jugées volontaires ; il touche `lib/` sinon, et
  dans ce cas il faut refaire les deux gates.

- **Ordre validé par Philippe le 15/09/2026** : **[90] → [86] → [88] → [89]**.
  [87] est livré (`726e62c`) et a ouvert [90] en route. La place retenue pour
  [90] est **devant [86]**, par le critère habituel — minimiser la reprise,
  jamais l'urgence — et c'est mot pour mot l'argument qui avait mis [87] devant
  [86] : l'AC 4 de [86] veut que le paragraphe du tracker soit **la même phrase**
  que celle que `init_preflight` imprime à la console, or cette phrase-là vit dans
  un `init__note "…"`, une chaîne entre guillemets doubles que [87] ne garde pas
  et que [90] garde. Livré devant, [90] est le filet sous cette moitié-là de la
  réécriture ; livré derrière, il constate après coup et peut coûter une seconde
  passe sur `init.sh`. [88] derrière [86] parce qu'il généralise une forme dont
  [86] livre le précédent ; [89] en dernier, sans arête.
