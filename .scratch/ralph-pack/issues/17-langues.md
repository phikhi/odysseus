# 17 — Langues (consigne + gate de langue + interact)

**What to build:** Le découplage `LANG_INTERACT` (parole à l'humain, HITL) / `LANG_ARTIFACT` (prose durable rédigée) : injection de la consigne dans les sessions fraîches, langue d'interaction côté HITL, et **gate de langue objectif** ajouté comme lentille (la consigne molle est doublée d'un check).

**Blocked by:** 05, 03

**Write-surface:** `.claude/lib/lang.sh`, `test/lang.bats`

**Status:** ready-for-agent

- [ ] La consigne `LANG_ARTIFACT` est injectée dans le prompt de chaque session fraîche ; le code/identifiants (Standards) et les fichiers du pack en sont exclus.
- [ ] Un gate de langue objectif (détection post-hoc, par-fichier, tolérant — langue dominante, termes étrangers cités OK) vérifie la prose rédigée ; échec → retry (patron scope-guard).
- [ ] Une édition de fichier existant matche la **langue du fichier** plutôt que `LANG_ARTIFACT`.
- [ ] `LANG_INTERACT` n'est utilisé que sur les surfaces HITL ; une session AFK ne l'emploie pas.
