# 14 — Auto-apprentissage + ADR en delivery

**What to build:** Le **subagent retro frais** post-gate (tier bon marché, auto-suppressif) qui capte la connaissance apprise : un record de leçon (+ index LEARNINGS injecté inline) et/ou un ADR interne, avec anti-bruit sur l'index et promotion jamais silencieuse.

**Blocked by:** 05, 10

**Write-surface:** `.claude/lib/retro.sh`, `test/retro.bats`

**Status:** ready-for-agent

- [ ] Après le gate, un subagent retro frais (auto-suppressif) n'écrit un record de leçon (`learning-records/NNNN`, format `teach`) **que** s'il y a une leçon ; sinon rien.
- [ ] L'index `LEARNINGS.md` reste un working set borné, injecté inline dans les sessions fraîches ; anti-bruit par dedup / supersession / drain-par-promotion.
- [ ] Une décision d'archi **interne** non-triviale est gravée en ADR (`docs/adr/`) ; une décision **contractuelle** escalade au lieu d'un ADR autonome.
- [ ] La promotion d'une leçon récurrente est soit **autonome** (guidance `CLAUDE.md`), soit **escaladée** (gate/lint/hook → `ready-for-human`) — jamais silencieuse.
- [ ] Écriture atomique (temp + `mv`) des records et de l'index.

## Comments

- **Contrainte posée par [31], livré le 30/07/2026 : `CLAUDE.md` est scellé, donc l'AC de promotion autonome ne peut pas s'écrire comme elle est rédigée.** Le scellement couvre désormais tout ce qu'un `claude` frais lit au démarrage, `CLAUDE.md` et `CLAUDE.local.md` compris, et **aucune write-surface ne peut couvrir un chemin scellé** : un ticket qui déclare `CLAUDE.md` est rouge à chaque tentative, définitivement. La décision a été prise en connaissance de ce coût — la boucle n'édite pas les règles qui la jugent — donc c'est ce ticket qui doit s'adapter, pas le scellement.

  Deux issues, à trancher ici et à écrire :

  1. **La promotion autonome va dans `LEARNINGS.md`**, qui est déjà le mécanisme de ce ticket (index borné, injecté inline dans les sessions fraîches). Une guidance promue y vit et atteint chaque session sans toucher un chemin scellé. C'est la voie qui préserve l'AC « jamais silencieuse » sans rien coûter.
  2. **Ou la promotion vers `CLAUDE.md` devient une escalade** — `ready-for-human`, un humain édite. Cohérent avec l'autre moitié de l'AC (« gate/lint/hook → escalade »), et cohérent avec [15], qui refuse déjà toute création de capacité en AFK.

  Le piège à ne pas rouvrir : contourner le scellement en écrivant la guidance dans un fichier *non* scellé que le prompt irait lire ensuite. Ce serait recréer exactement le canal que [31] vient de fermer, sous un autre nom — et cette fois sans qu'aucun contrôle le remarque.

- **Contrainte posée par [10], livré le 07/08/2026 : la moitié du trou de [06] est refermée, et l'autre moitié est ici.** Les findings d'une lentille rouge survivent maintenant à l'itération — `gate__aggregate` les copie hors du répertoire temporaire du gate avant que `gate_run` ne le détruise, et le reçu les porte en entier (`RECEIPT_MAX_LINES`, 200 lignes par défaut, ce qui est retiré est compté). Ce qui **n'existe toujours pas** est le canal de retour : rien ne remonte ces findings vers le prompt de la session suivante, donc une session retryée après une lentille rouge peut réécrire exactement le même code et se faire rougir à l'identique jusqu'à `RETRY_N`. C'est le record de leçon de ce ticket, et il a maintenant une source à lire qui n'est ni un stdout ni un fichier qu'une session peut écrire. Deux précautions à porter : la source est le **reçu**, pas `run.log` (une session peut réécrire le journal, cf. `docs/frontiere-de-confiance.md`) ; et un reçu n'existe que pour une itération *finale*, donc les findings d'un retry intermédiaire ne sont **nulle part** — si la leçon doit être injectée entre deux tentatives du même ticket, c'est un canal que ce ticket doit ouvrir, pas un reçu à aller lire.

- **Contrainte posée par [45], livré le 24/08/2026 : le canal du reçu a deux sections, et une seule est de la matière à leçon.** [45] a relu les producteurs du reçu contre le critère écrit dans `receipt.sh` et en a câblé quatre familles de plus. Trois choses pour ce ticket :

  1. **`receipt_note` et `receipt_gap` ne disent pas la même chose.** Les notes sont de la **couverture** — ce que rien n'a jugé, présent sur chaque itération, verte comprise. Les gaps sont ce que le pack allait faire et n'a pas fait : un arbre non remis, une branche `failed/<ticket>` que git a refusée, un split qui n'a pas eu lieu. Une leçon ne se tire pas d'un gap : « git a refusé d'écrire une ref » n'est pas une chose qu'une session suivante peut faire différemment, et l'injecter dans un prompt apprendrait à un modèle à compenser une panne d'infrastructure.
  2. **La liste des routes qui produisent un document s'est élargie** : livré, escaladé, `not-integrated`, et un rollback qui n'a pas pu agir. Les deux dernières ne sont **pas** des jugements sur le code — un gate vert dont le travail a disparu, une itération dont l'arbre n'est pas revenu — donc un lecteur qui promeut des leçons doit les sauter, ou il apprendra du bruit d'infrastructure. Le discriminant est dans le document et pas à deviner : l'outcome et la ligne de verdicts.
  3. **Une partie du texte d'une ligne de reçu vient de la session** (un nom de chemin, un slug de plan). Le rendu markdown est neutralisé par construction — chaque ligne est préfixée `- ` — mais un canal qui **réinjecte** du reçu vers un prompt de session redonne à une session le droit d'écrire dans le prompt de la suivante, ce qui est la frontière que ce dépôt documente. À traiter comme de la donnée citée, jamais comme de l'instruction.
