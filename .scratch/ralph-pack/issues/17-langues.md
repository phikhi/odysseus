# 17 — Langues (consigne + gate de langue + interact)

**What to build:** Le découplage `LANG_INTERACT` (parole à l'humain, HITL) / `LANG_ARTIFACT` (prose durable rédigée) : injection de la consigne dans les sessions fraîches, langue d'interaction côté HITL, et **gate de langue objectif** ajouté comme lentille (la consigne molle est doublée d'un check).

**Blocked by:** 05, 03

**Write-surface:** `.claude/lib/lang.sh`, `test/lang.bats`

**Status:** ready-for-agent

- [ ] La consigne `LANG_ARTIFACT` est injectée dans le prompt de chaque session fraîche ; le code/identifiants (Standards) et les fichiers du pack en sont exclus.
- [ ] Un gate de langue objectif (détection post-hoc, par-fichier, tolérant — langue dominante, termes étrangers cités OK) vérifie la prose rédigée ; échec → retry (patron scope-guard).
- [ ] Une édition de fichier existant matche la **langue du fichier** plutôt que `LANG_ARTIFACT`.
- [ ] `LANG_INTERACT` n'est utilisé que sur les surfaces HITL ; une session AFK ne l'emploie pas.

- **Contrainte posée par [06], livré le 30/07/2026 : la lentille Standards n'est pas le gate de langue, et il ne faut pas se laisser croire l'inverse.** Le registre de lentilles ajoute un regard *jugement* qui relit le diff et peut parfaitement remarquer qu'un commentaire est dans la mauvaise langue. Ça ne coche pas une seule ligne de ce ticket : une lentille est un modèle dont le verdict n'est vérifié par rien, un gate de langue est un check déterministe. La ligne « Prose durable en `LANG_ARTIFACT` » du tableau de frontière dit maintenant explicitement que ce ticket reste le propriétaire, précisément pour empêcher cette confusion — c'est la même erreur, un cran plus bas, que celle de lire une consigne du prompt comme une contrainte.

- **Ce que [06] offre en revanche, gratuitement : le patron.** Le gate de langue est un check objectif, donc une branche de la **phase objective** et pas une lentille — même patron que le scope-guard, code de retour dans un fichier. Si un jour il fallait qu'il soit configurable par lentille, `lenses_want_<nom>` / `lenses_rubric_<nom>` est le point d'extension et `gate_run` n'a pas à changer.
