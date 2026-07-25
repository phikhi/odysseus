# PROTOTYPE — Form factor du framework (ticket 09) · JETABLE

> Artefact jetable pour **réagir à la forme**, pas du code de prod. Répond à :
> « comment le framework se dépose dans n'importe quel futur projet ? »

## Forme recommandée (celle esquissée ici) : **pack + `init.sh`**

- Le framework EST un **pack** : `.claude/loop.sh` + `.claude/lib/*` + les **skills du substrat** (copiés/vendorés) + conventions de tracker + `CLAUDE.md` de base + `settings.json`.
- Il est **déposé par `init.sh`** : une commande unique qui marche dans **n'importe quel repo** (vierge OU existant) → passe le dépôt de « rien » à « prêt à discovery ».
- *Pas* un template repo (utile seulement en greenfield ; cloner n'aide pas un projet existant).

## Arborescence déposée dans un projet cible

```
<projet-cible>/
├── init.sh                     ← bootstrap (une commande) — s'auto-supprime après
├── CLAUDE.md                   ← base (règles + pointe skills/tracker) ; MERGÉ si déjà présent
├── .claude/
│   ├── settings.json           ← posture headless (permission-mode, hooks)
│   ├── ralph.config.sh         ← ⚙️ CONFIG PAR PROJET (le seul fichier qu'on édite)
│   ├── loop.sh                 ← la ralph loop (control-flow [06])
│   ├── lib/
│   │   ├── select.sh           ← [04] scan frontière min-NN
│   │   ├── budget.sh           ← [07] /api/oauth/usage, seuils, pause/reprise
│   │   ├── gate.sh             ← [08] tests+typecheck+review EN PARALLÈLE
│   │   └── state.sh            ← [04] marquage temp+mv, run.log, verrou de run
│   └── skills/                 ← substrat COPIÉ (self-contained pour la sandbox)
│       ├── grilling/  domain-modeling/  to-spec/  to-tickets/
│       ├── implement/  tdd/  code-review/  triage/  research/  wayfinder/
│       └── … (pinné à une version)
├── docs/agents/
│   ├── issue-tracker.md        ← conventions .scratch/<feature>/issues/NN-*.md
│   └── triage-labels.md        ← libellés canoniques
└── .scratch/                   ← racine du tracker (créée vide)
    └── .gitkeep
```

## Décisions ouvertes à trancher (le prototype prend une position par défaut, à valider)

1. **Forme** : pack + `init.sh` ✅ (vs template repo, vs init.sh seul).
2. **Skills : copie vs symlink vs vendor** → le proto **copie** (self-contained ; la sandbox de delivery [06/D1] n'a pas forcément d'install central). Pinné à une version.
3. **Config par projet** → un **seul** `.claude/ralph.config.sh` sourcé par `loop.sh` (modèle, commandes test/typecheck, seuils budget, dossier feature, sandbox). Voir le fichier.
4. **Bootstrap une commande** → `./init.sh` : dépose le pack, `git init` si besoin, crée `.scratch/`, écrit un `ralph.config.sh` de départ, MERGE le `CLAUDE.md`. ✅
```
