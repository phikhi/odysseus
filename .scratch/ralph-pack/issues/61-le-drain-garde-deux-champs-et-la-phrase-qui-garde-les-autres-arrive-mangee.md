# 61 — Le drain garde deux champs, et la phrase censée garder les trois autres arrive mangée

**What to build:** Deux choses que la passe du 01/09 a trouvées ensemble parce
qu'elles sont la même ligne du tableau, prise par ses deux bouts.

**1. Le prompt de la session routée perd les deux noms de champ qu'il existe pour
dire.** `router_prompt` construit son texte avec un heredoc **non cité**
(`cat <<PROMPT`, l. 1015 de `.claude/lib/router.sh`), et le paragraphe que [58] y
a ajouté le 01/09 écrit les deux noms **entre backticks** (l. 1046) :

    the drain took every ticket's
    `Status:` and `Escalation:` before this session started, …

Dans un heredoc non cité, une backtick est une substitution de commande. Ce que
la session reçoit réellement, mesuré sur le prompt réellement passé :

    its shape is worth knowing rather than guessing: the drain took every ticket's
     and  before this session started, puts any ticket it
    finds moved out of the human sink back where it was, …

et ce que l'humain voit, à **chaque** session routée :

    …/router.sh: line 1015: Status:: command not found
    …/router.sh: line 1015: Escalation:: command not found

**2. `Failures:`, `Blocked by:` et le corps décident, et personne ne les garde.**
[58] l'a écrit comme une limite (« PERSONNE ») ; la passe l'a mesuré comme un
mécanisme. Ce ne sont pas des champs inertes : ils déplacent ce que le pack
**exécute ensuite**.

**Blocked by:** None

**Write-surface:** `.claude/lib/router.sh`, `.claude/human-loop.sh`,
`test/human-loop.bats`, `test/mutate.sh`, `docs/frontiere-de-confiance.md`

**Status:** ready-for-agent

**Tags:** securite, frontiere-de-confiance

- [ ] **Le prompt arrive entier, et un test le tient.** Aujourd'hui **aucun test
      de `test/` ne cite ce paragraphe** (vérifié par `grep`), ce qui est
      exactement pourquoi il a pu être livré cassé. Corriger le heredoc — et
      décider s'il faut le citer entièrement (`<<'PROMPT'`) en sortant les
      substitutions, ou échapper : citer est la seule forme qui ne peut plus
      jamais exécuter du texte de prose, et c'est la question à trancher plutôt
      qu'à patcher.
- [ ] **Chercher les autres heredocs non cités du pack qui portent de la prose.**
      La panne n'est pas dans le paragraphe, elle est dans la forme : toute
      backtick, tout `$(` et tout `$mot` d'un texte destiné à un humain ou à un
      modèle est exécuté ou vidé. Un balayage, et ce qu'il trouve écrit ici.
- [ ] **`Failures:` cesse de décider en silence, ou le tableau dit qui décide.**
      Deux mécanismes mesurés, pas un :
      *(a)* écrit sur un ticket **voisin** de la frontière, il retire à ce ticket
      son budget de retries entier — `router_protect_tracker` ne compare que
      `Status:` et `Escalation:`, `tracker_mark_ready` et
      `tracker_mark_escalated` ne touchent pas le compteur, donc **rien ne bouge
      et rien n'est dit** ;
      *(b)* écrit sur **son propre** ticket, il déplace le guichet de la session
      **suivante** sur le même ticket (`decision` → `admit` ou `triage-host`),
      donc la question, le traitement et tout le prompt. C'est **mot pour mot
      l'argument par lequel [55] a épinglé `Escalation:`** — « le menu est
      ré-offert après une session, donc un `Escalation:` relu sur le fichier
      laisserait la session choisir le guichet … de la session suivante » — et
      [55] a écarté `Failures:` en écrivant qu'il « déplace la question posée à un
      humain et ne peut déplacer aucune transition ». La seconde moitié est vraie,
      la première est précisément ce que le pin existe pour empêcher.
- [ ] **Le corps aussi, et il est le plus direct.** Le corps d'un ticket **est**
      le prompt d'une session routée future : `router_prompt` le cite comme
      donnée, ce qui est la décision de [21]/[27] et reste correcte. Mesuré : une
      session routée sur `20-first` écrit une ligne dans le corps de `21-second`,
      et cette ligne arrive **verbatim dans le prompt de la session ouverte sur
      `21-second` par le même drain**, sans qu'une ligne la nomme. Dire ce qui
      tient ça — un troisième objet au même appel `router_pin`, ou l'aveu que
      rien ne le tient et que la phrase du prompt est tout ce qu'il y a.
- [ ] **La ligne du tableau est réécrite avec ce qui est mesuré**, pas avec
      « personne » : trois champs, trois mécanismes distincts, deux directions
      (le ticket tenu et ses voisins).
- [ ] **Une mutation par garantie livrée**, témoin appairé vérifié à la main.

## Comments

- **Origine : passe transversale du 01/09/2026.** Sondes conservées :
  `.scratch/ralph-pack/sondes/passe-01-09/q3-les-champs-que-personne-ne-garde.bats`
  (Q3a à Q3d, Q4, Q5) et
  `.scratch/ralph-pack/sondes/passe-01-09/q7-le-prompt-de-la-session-routee-est-un-heredoc-non-cite.bats`
  (Q7a, Q7b).

- **Le heredoc est de [58]** (`git blame` : `4c00163`, 01/09/2026, l. 1044-1050).
  La ligne `- Do not change this ticket's status…` qui le précède est de [55]
  (`2adbc9a`) et ne portait pas de backtick — c'est le paragraphe ajouté qui
  introduit la forme.

- **L'angle disculpé, et il valait la peine d'être posé.** Le heredoc étant non
  cité, la question suivante était : le **corps du ticket**, que ce prompt déclare
  lui-même être de la donnée écrite par une session, passe-t-il par cette
  expansion ? **Non** — mesuré (Q7b) avec un corps portant `` `id -u` ``,
  `$(id -u)` et `$HOME` : les trois arrivent **verbatim**. Le corps entre par une
  substitution de commande, et le résultat d'une substitution n'est pas
  re-analysé. Il n'y a donc pas d'injection de commande depuis un ticket, et
  c'est la seule raison pour laquelle ce ticket est une réparation de prose et
  pas une faille.

- **Ce que Q3a a rendu, avec son témoin.**

      avec l'édition   Failures 22-agent = 9, Status inchangé,
                       occurrences de « 22-agent » dans tout le drain : 0
                       → run AFK : 1 itération, escalade immédiate (failed-impl)
      sans l'édition   → run AFK : 3 itérations, budget complet

- **Ce que Q3c a rendu.**

      ralph: 20-first: opening a grilling session (admit)
      ralph: 20-first: opening a grilling session (triage-host)

  deux sessions sur le **même** ticket, deux guichets, la seconde choisie par la
  première. Occurrences de « failures » dans la sortie du drain : 0.

- **Ce qui est confirmé sans être neuf, et qui appartient à [58] qui l'a écrit.**
  Deux des trois résidus que [58] a nommés ont été rejoués et tiennent tels
  qu'écrits — ils ne rouvrent pas ce ticket, ils le bordent :
  - un ticket **`needs-triage`** tiré vers le puits avec `Escalation: sign-off`
    est nommé au premier drain, puis le **drain suivant** épingle la raison depuis
    le fichier, offre `desk: approve` (« This ticket is asking to be signed off »)
    et un `s` le résout. Le dossier ajoute alors *« Nothing in this pack writes
    `sign-off` today. This ticket was put here by hand »* — ce qui se lit comme
    « un humain l'a mis là ». **Ce que la passe ajoute à ce que [58] avait écrit :
    la seule trace de la fabrication est la ligne `tracker-drift` de `run.log`,
    c'est-à-dire le fichier que le dossier lui-même déclare non fiable (« the
    session these lines are about could have written them. Read them, do not rely
    on them »).** [58] avait choisi `resolved` comme état d'origine et noté que le
    dégât net était borné ; `needs-triage` n'est pas borné — le ticket n'a jamais
    été jugé par rien ni trié par personne ;
  - un ticket **`claimed` par un run mort** qu'une session résout n'est pas remis :
    nommé une fois au drain, puis le run AFK dit `exit 5`, « rien à moudre », et
    le balayage de [12] ne relit pas un résolu.
