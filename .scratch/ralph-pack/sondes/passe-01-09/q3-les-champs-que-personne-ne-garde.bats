#!/usr/bin/env bats
#
# Passe transversale du 01/09 — Q3, Q4 et Q5, côté drain.
#
# [58] a livré `router_protect_tracker` et a nommé lui-même ce qui reste :
#   « `Failures:`, `Blocked by:` et le corps de n'importe quel ticket : PERSONNE. »
#   « Un ticket tiré d'un état non restaurable *vers* le puits (`resolved` →
#     `ready-for-human` + `Escalation: sign-off`) est nommé au moment où ça
#     arrive, mais un drain SUIVANT épinglera cette raison depuis le fichier et
#     un `s` la prendra pour vraie. »
#   « Un ticket `claimed` par un run mort qu'une session résout n'est pas remis. »
#
# Et [55] avait écrit, pour justifier d'épingler `Escalation:` :
#   « Le menu est ré-offert après une session, donc un `Escalation:` relu sur le
#     fichier laisserait la session choisir le guichet — donc la question, le
#     traitement et TOUT LE PROMPT — de la session SUIVANTE sur le même ticket.
#     `Failures:` et la ref `failed/<id>` restent non épinglés : ils déplacent la
#     question posée à un humain et ne peuvent déplacer aucune transition. »
#
# Ces cas sont écrits ; cette sonde les mesure en run réel.
#
# Instrument, pas test : chaque cas finit par un `false` volontaire.

load ../../../../test/helpers/harness
load ../../../../test/helpers/assert

setup() {
  harness_setup
}

teardown() {
  harness_teardown
}

drain() {
  run bash "$PACK_DIR/human-loop.sh"
}

mk_ticket() {
  local id="$1" file
  shift
  file="$TRACKER_DIR/$id.md"
  {
    printf '# %s — written by a sonde\n\n' "$id"
    printf '**What to build:** A fixture for the human sink.\n\n'
    while [ "$#" -ge 2 ]; do
      printf '**%s:** %s\n\n' "$1" "$2"
      shift 2
    done
    printf -- '- [ ] Something a human decides about.\n'
  } >"$file"
  harness__commit "sonde: $id"
}

# ── Q3a — `Failures:` écrit sur un ticket VOISIN de la frontière ──────────────
#
# Le voisin n'est pas dans le puits : il est `ready-for-agent`, donc il attend un
# run AFK. `router_protect_tracker` ne compare que `Status:` et `Escalation:`,
# donc rien ne bouge et rien n'est dit. Ce que `Failures:` décide est le budget
# de retries : `failures__policy` escalade dès que le compteur dépasse RETRY_N.

@test "Q3a une session routée écrit Failures: sur un ticket de la frontière" {
  mk_ticket 20-first Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/one.txt`' 'Blocked by' None
  mk_ticket 22-agent Status ready-for-agent \
    'Write-surface' '`src/two.txt`' 'Blocked by' None

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
perl -pi -e 's/^\*\*Status:\*\* ready-for-agent$/**Status:** ready-for-agent\n\n**Failures:** 9/' \
  "$tracker/22-agent.md"
exit 0
SCRIPT

  drain <<'ANSWERS'
o
n
ANSWERS
  printf '=== rc du drain               : %s\n' "$status"
  printf '=== Failures 22-agent         : %s\n' "$(ticket_field 22-agent Failures)"
  printf '=== Status 22-agent           : %s\n' "$(ticket_status 22-agent)"
  printf '=== 22-agent nommé au drain ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c '22-agent')"

  # Et ce que le run AFK en fait. Le gate est rouge, donc le seul enjeu est le
  # nombre de sessions que le ticket obtient.
  set_config TEST_CMD 'false'
  # Le faux qui LIVRE, celui du harnais : une session qui n'écrit rien serait
  # `delivery=red` ([35]) et ne mesurerait pas le budget de retries.
  rm -f "$SHIM_STATE/claude.script"
  run_loop
  printf '=== rc du run AFK             : %s\n' "$status"
  printf '=== itérations                : %s\n' \
    "$(printf '%s\n' "$output" | grep -c '^ralph: iteration ')"
  printf '=== Status 22-agent après run : %s\n' "$(ticket_status 22-agent)"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}

@test "Q3b témoin appairé : la même paire, sans l'édition de la session" {
  mk_ticket 20-first Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/one.txt`' 'Blocked by' None
  mk_ticket 22-agent Status ready-for-agent \
    'Write-surface' '`src/two.txt`' 'Blocked by' None

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT

  drain <<'ANSWERS'
o
n
ANSWERS
  printf '=== Failures 22-agent         : %s\n' "$(ticket_field 22-agent Failures)"

  set_config TEST_CMD 'false'
  # Le faux qui LIVRE, celui du harnais : une session qui n'écrit rien serait
  # `delivery=red` ([35]) et ne mesurerait pas le budget de retries.
  rm -f "$SHIM_STATE/claude.script"
  run_loop
  printf '=== rc du run AFK             : %s\n' "$status"
  printf '=== itérations                : %s\n' \
    "$(printf '%s\n' "$output" | grep -c '^ralph: iteration ')"
  printf '=== Status 22-agent après run : %s\n' "$(ticket_status 22-agent)"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}

# ── Q3c — `Failures:` sur SON PROPRE ticket déplace le guichet suivant ────────
#
# L'argument exact de [55] pour épingler `Escalation:`, appliqué à l'entrée qu'il
# n'a pas épinglée : `router_desk` lit `Failures:` sur le fichier pour trancher
# entre `admit` et `triage-host` quand la raison est `decision`.

@test "Q3c une session routée choisit le guichet de la session suivante" {
  mk_ticket 20-first Status ready-for-human Escalation decision \
    'Write-surface' '`src/one.txt`' 'Blocked by' None

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
grep -q '^\*\*Failures:\*\*' "$tracker/20-first.md" || \
  perl -pi -e 's/^\*\*Escalation:\*\* decision$/**Escalation:** decision\n\n**Failures:** 1/' \
    "$tracker/20-first.md"
exit 0
SCRIPT

  drain <<'ANSWERS'
o
o
n
ANSWERS
  printf '=== rc du drain               : %s\n' "$status"
  printf '=== lignes « opening a … »    :\n%s\n' \
    "$(printf '%s\n' "$output" | grep 'opening a')"
  printf '=== sessions routées ouvertes : %s\n' "$(claude_call_count)"
  printf '=== guichet dans le prompt 1  : %s\n' \
    "$(claude_call_argv 1 | tr '\037' '\n' | grep -c 'No run ever judged this ticket')"
  printf '=== guichet dans le prompt 2  : %s\n' \
    "$(claude_call_argv 2 | tr '\037' '\n' | grep -c 'Nothing ever judged a session on this ticket')"
  printf '=== une ligne dit que Failures a bougé ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -ci 'failures')"
  printf '=== sortie du drain --------------------------------\n%s\n' "$output"

  set -e
  false
}

# ── Q3d — le CORPS d'un ticket voisin arrive dans le prompt suivant ───────────

@test "Q3d une session routée écrit dans le corps du ticket suivant du puits" {
  mk_ticket 20-first Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/one.txt`' 'Blocked by' None
  mk_ticket 21-second Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/two.txt`' 'Blocked by' None

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
grep -q 'SONDE-INJECTED-BODY' "$tracker/21-second.md" || \
  printf 'SONDE-INJECTED-BODY: written into a neighbour by the session routed on 20-first.\n' \
    >>"$tracker/21-second.md"
exit 0
SCRIPT

  drain <<'ANSWERS'
o
n
o
n
ANSWERS
  printf '=== rc du drain                        : %s\n' "$status"
  printf '=== sessions ouvertes                  : %s\n' "$(claude_call_count)"
  printf '=== la ligne injectée dans le prompt 2 : %s\n' \
    "$(claude_call_argv 2 | grep -c 'SONDE-INJECTED-BODY')"
  printf '=== une ligne du drain la nomme ?      : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'SONDE-INJECTED-BODY')"
  printf '=== le drain dit-il que 21-second a bougé ? : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'tracker-drift\|was moved to\|reads .Status')"
  printf '=== sortie du drain --------------------------------\n%s\n' "$output"

  set -e
  false
}

# ── Q4 — le sign-off fabriqué qu'un drain SUIVANT épingle depuis le fichier ───
#
# L'état d'origine choisi est `needs-triage` — la boîte de réception d'un humain,
# et un des états que `router__put_back` ne sait pas écrire. [58] a mesuré le cas
# `resolved`, dont il écrit lui-même que le dégât net est borné. Celui-ci ne l'est
# pas : le ticket n'a jamais été jugé par rien ni trié par personne.

@test "Q4 un needs-triage tiré vers le puits avec Escalation: sign-off" {
  mk_ticket 20-first Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/one.txt`' 'Blocked by' None
  mk_ticket 24-inbox Status needs-triage \
    'Write-surface' '`src/four.txt`' 'Blocked by' None

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
perl -pi -e 's/^\*\*Status:\*\* needs-triage$/**Status:** ready-for-human\n\n**Escalation:** sign-off/' \
  "$tracker/24-inbox.md"
exit 0
SCRIPT

  drain <<'ANSWERS'
o
n
ANSWERS
  printf '=== DRAIN 1 rc                : %s\n' "$status"
  printf '=== Status 24-inbox           : %s\n' "$(ticket_status 24-inbox)"
  printf '=== Escalation 24-inbox       : %s\n' "$(ticket_field 24-inbox Escalation)"
  printf '=== 24-inbox nommé ?          : %s\n' \
    "$(printf '%s\n' "$output" | grep -c '24-inbox')"
  printf '=== sortie du drain 1 ------------------------------\n%s\n' "$output"

  # Le drain SUIVANT. Aucune session n'est ouverte : l'humain lit le dossier et
  # signe. Rien à l'écran ne distingue cette raison d'une raison que le pack a
  # écrite.
  script_claude <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  drain <<'ANSWERS'
n
s
ANSWERS
  printf '=== DRAIN 2 rc                : %s\n' "$status"
  printf '=== Status 24-inbox           : %s\n' "$(ticket_status 24-inbox)"
  printf '=== guichet offert            : %s\n' \
    "$(printf '%s\n' "$output" | grep -c 'desk: approve')"
  printf '=== sortie du drain 2 ------------------------------\n%s\n' "$output"

  set -e
  false
}

# ── Q5 — un claimed d'un run mort qu'une session résout ───────────────────────

@test "Q5 un ticket claimed par un run mort, résolu par une session routée" {
  mk_ticket 20-first Status ready-for-human Escalation failed-impl \
    'Write-surface' '`src/one.txt`' 'Blocked by' None
  mk_ticket 25-inflight Status ready-for-agent \
    'Write-surface' '`src/five.txt`' 'Blocked by' None
  stamp_claim 25-inflight 'pid:999999' '2026-07-25T08:00:00Z'

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
tracker="$(cat "$RALPH_SHIM_STATE/tracker-dir")"
perl -pi -e 's/^\*\*Status:\*\* claimed$/**Status:** resolved/' "$tracker/25-inflight.md"
exit 0
SCRIPT

  drain <<'ANSWERS'
o
n
ANSWERS
  printf '=== rc du drain                : %s\n' "$status"
  printf '=== Status 25-inflight         : %s\n' "$(ticket_status 25-inflight)"
  printf '=== 25-inflight nommé ?        : %s\n' \
    "$(printf '%s\n' "$output" | grep -c '25-inflight')"
  printf '=== sortie du drain --------------------------------\n%s\n' "$output"

  script_claude <<'SCRIPT'
#!/usr/bin/env bash
exit 0
SCRIPT
  run_loop
  printf '=== rc du run AFK              : %s\n' "$status"
  printf '=== Status 25-inflight après   : %s\n' "$(ticket_status 25-inflight)"
  printf '=== le balayage le nomme ?     : %s\n' \
    "$(printf '%s\n' "$output" | grep -c '25-inflight')"
  printf '=== sortie du run ----------------------------------\n%s\n' "$output"

  set -e
  false
}
