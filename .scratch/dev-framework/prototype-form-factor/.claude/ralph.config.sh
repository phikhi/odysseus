#!/usr/bin/env bash
# PROTOTYPE — CONFIG PAR PROJET. Le SEUL fichier qu'un humain règle par projet.
# Sourcé par loop.sh. Tout ce qui varie d'un projet à l'autre vit ICI.

# — Cible du run —
FEATURE="${FEATURE:?ex: dev-framework}"     # dossier .scratch/<FEATURE>/issues/ à broyer
MODEL="opus"                                 # modèle des sessions delivery

# — Commandes objectives du gate [08] (spécifiques au projet) —
TEST_CMD="npm test"                          # doit sortir non-zéro si rouge
TYPECHECK_CMD="npx tsc --noEmit"             # idem
# code-review = /code-review (skill), pas une commande projet

# — Budget [07] : seuils asymétriques (%) —
THRESH_5H=90                                 # fenêtre 5h : agressif
THRESH_WEEK=85                               # hebdo (seven_day + seven_day_opus) : conservateur
USAGE_UA="claude-code/2.1.79"                # User-Agent OBLIGATOIRE pour /api/oauth/usage

# — Filet contexte [03] —
SOFT_LIMIT_TOKENS=150000                     # SIGTERM la session au franchissement
# dur 200K = frontière dumb-zone (auto-compact OFF forcé par loop.sh)

# — Gardes anti-emballement [06] —
ITER_CAP=200                                 # backstop boucle infinie
STERILE_K=5                                  # K itérations sans résolution -> stop+alerte
RETRY_N=2                                    # retries fresh par ticket avant escalade [08]
HUMAN_CHECKPOINT_EVERY=0                     # 0 = off (AFK) ; >0 = pause tous les N résolus

# — Reprise hebdo [07] —
WEEKLY_RESUME="human"                        # "human" (exit pause-hebdo) | "cron" (relance auto)
