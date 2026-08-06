# shellcheck shell=bash
# The tracker adapter interface.
#
# The loop never talks to a backend. It calls these operations, and the
# dispatcher routes each one to `tracker_<backend>_<op>` for the configured
# TRACKER_BACKEND. A new backend is a new lib/tracker-<name>.sh implementing
# the same operations under its own prefix — nothing here and nothing in the
# loop changes. Prefixing is also what lets every adapter be sourced at once
# without the last one silently winning.
#
#   tracker_frontier                  eligible ticket ids, min-NN first, one per line
#   tracker_ids                       every ticket id, whatever its state, min-NN first
#   tracker_read_ticket ID            the ticket on stdout
#   tracker_claim ID [OWNER]          take the ticket; non-zero if it was lost
#   tracker_unclaim ID                give it back to the frontier
#   tracker_mark_resolved ID          the gate came back green; clears the claim
#                                     and the retry counter
#   tracker_mark_escalated ID REASON  hand it to the human sink, with a reason
#   tracker_mark_ready ID             re-inject (re-slice, human fix, wiring)
#   tracker_block_on ID DEPS          hold it until those tickets are resolved
#   tracker_bump_failures ID          count one failure; new count on stdout
#   tracker_open_ticket SLUG TITLE    create a ticket from stdin; id on stdout
#   tracker_renumber ID               give it an id no other ticket shares; the
#                                     id it now carries on stdout
#   tracker_append_note ID            append a comment from stdin
#   tracker_emit_receipt ID           write the audit receipt from stdin
#
# Marking is the loop's job, after the gate — never the session's.

tracker__dispatch() {
  local op="$1"
  shift
  local backend="${TRACKER_BACKEND:-local}"
  local fn="tracker_${backend}_${op}"
  local out rc=0
  if ! declare -f "$fn" >/dev/null 2>&1; then
    printf 'tracker: backend "%s" does not implement %s\n' "$backend" "$op" >&2
    return 3
  fi
  case "$op" in
    frontier | ids | read_ticket | field)
      "$fn" "$@"
      ;;
    open_ticket | renumber)
      # The two operations whose *answer* is an id, and the register wants the id
      # a guard will meet in `issues/` rather than the argument. `open_ticket`
      # takes a slug, so noting the argument wrote a line naming no ticket at all
      # — a nuisance while only the restore read the register ([13]), and wrong
      # the moment the quarantine reads it ([42]): the one thing it asks is
      # whether an id that appeared is the loop's own creation. `renumber` needs
      # both, because it moves a file: the number that stopped existing and the
      # one that now does.
      [ "$op" = open_ticket ] || tracker__note_write "${1:-}"
      out="$("$fn" "$@")" || rc=$?
      [ -z "$out" ] || printf '%s\n' "$out"
      tracker__note_write "$out"
      return "$rc"
      ;;
    *)
      tracker__note_write "${1:-}"
      "$fn" "$@"
      ;;
  esac
}

# ── what the loop itself wrote, and when ─────────────────────────────────────
#
# The register [13] needed, and it is here rather than in the loop because this is
# the one place every tracker write goes through — a second list kept beside the
# call sites would be the [25] defect again, wrong the first time somebody adds an
# operation.
#
# What it is for. `failures_protect_tracker` ([21]) compares two tree objects of
# the whole tickets directory around one session and restores whatever moved. With
# one iteration in flight that is exactly "what the session wrote"; with two, the
# loop *legitimately* writes in `issues/` inside another iteration's window — a
# sibling's claim, its retry counter, its marking — and the first iteration to come
# back would restore them. Probed while delivering [13], and it is not theoretical:
# two disjoint tickets ground in parallel came out with one resolved and the other
# stuck `claimed`, its own marking undone by its neighbour's guard.
#
# So the guard is told which paths are **not the session's doing**, by id. It is
# the same pattern as `gate_is_bookkeeping` — one definition of "this is the loop's
# own work", read by the control that would otherwise judge it — applied to time
# rather than to path.
#
# **Every guard over `issues/` reads this, and that took a second ticket** ([42]).
# [13] wired the producer to one consumer: `failures_protect_tracker` as the loop
# calls it, and neither `failures_quarantine_strays` nor the same guard as
# `failures_reslice` calls it. Above `MAX_PARALLEL=1` the two undo each other — a
# re-slice restores a sibling's marking, a sibling quarantines the tickets a
# re-slice just created. The question a shared definition answers is never "where
# is the source" but "who reads it, and who should have": the guards ask
# `failures__register_since`, which asks here, and a third guard inherits the answer
# instead of keeping a list beside it.
#
# A file and not a variable, because the writers are different shells: the pilot
# claims, an iteration marks, and a value written in one is not visible in the
# other. It lives in `$TMPDIR` for the reason the ignore pin does ([30]): out of
# the tree, so no write-surface reaches it and no `git clean` takes it. One
# `printf` of one short line under `>>` is a single append and needs no lock.
#
# The *name* of that file travels by plain shell inheritance and is never
# exported, which is the correction [40] made to the sentence above. Both halves
# are needed and they are not the same half: a file, because these shells cannot
# see each other's variables; unexported, because every one of them is a
# descendant of the pilot and none of them needs an environment entry to get the
# path. The only process that an `export` ever reached was `claude` — and a
# session that is told this path appends its own id and walks straight past
# `failures_protect_tracker`. What keeps a secret is not where it lives but who
# is told its name.
#
# Everything but the four read operations counts as a write, derived from the list
# rather than from the operations that happen to write today: an adapter that grows
# an operation must not be able to slip past this by being forgotten ([31] — read
# the list against its criterion, not against the cases that prompted it).
tracker__note_write() {
  local id="$1"
  [ -n "$id" ] || return 0
  [ -n "${RALPH_TRACKER_LOG:-}" ] || return 0
  printf '%s\n' "$id" >>"$RALPH_TRACKER_LOG" 2>/dev/null || true
  return 0
}

# Where the register stands now. An iteration takes this *before* it snapshots the
# tickets, so anything appended between the two is excluded rather than missed:
# over-excluding is a ticket the guard leaves alone, under-excluding is a
# sibling's claim destroyed.
tracker_write_mark() {
  [ -n "${RALPH_TRACKER_LOG:-}" ] && [ -f "$RALPH_TRACKER_LOG" ] || {
    printf '0\n'
    return 0
  }
  awk 'END { print NR + 0 }' "$RALPH_TRACKER_LOG"
}

# The ids the loop wrote since that mark, space-fenced so a `case` can ask whether
# one is in it.
tracker_writes_since() {
  local mark="${1:-0}"
  [ -n "${RALPH_TRACKER_LOG:-}" ] && [ -f "$RALPH_TRACKER_LOG" ] || {
    printf ' \n'
    return 0
  }
  printf ' %s\n' "$(awk -v m="$mark" 'NR > m { printf "%s ", $0 }' "$RALPH_TRACKER_LOG")"
}

tracker_frontier() { tracker__dispatch frontier "$@"; }
tracker_ids() { tracker__dispatch ids "$@"; }
tracker_read_ticket() { tracker__dispatch read_ticket "$@"; }
tracker_claim() { tracker__dispatch claim "$@"; }
tracker_unclaim() { tracker__dispatch unclaim "$@"; }
tracker_mark_resolved() { tracker__dispatch mark_resolved "$@"; }
tracker_mark_escalated() { tracker__dispatch mark_escalated "$@"; }
tracker_mark_ready() { tracker__dispatch mark_ready "$@"; }
tracker_block_on() { tracker__dispatch block_on "$@"; }
tracker_bump_failures() { tracker__dispatch bump_failures "$@"; }
tracker_open_ticket() { tracker__dispatch open_ticket "$@"; }
# Only the quarantine calls this, and only on what a session added. A backend
# whose ids cannot collide — one numbered server-side — returns the id unchanged
# and is done; it still owes its own ticket an answer to the question underneath
# ([27]): what does `tracker_ids` do when two tickets claim one identifier.
tracker_renumber() { tracker__dispatch renumber "$@"; }
tracker_append_note() { tracker__dispatch append_note "$@"; }
tracker_emit_receipt() { tracker__dispatch emit_receipt "$@"; }

# Read one field of a ticket. Not part of the seven operations, but every
# backend needs it and the loop reads Failures:/Escalation:/Write-surface:.
#
# Two fields carry an obligation the dispatcher cannot enforce, so they are written
# down here rather than left to whichever backend was read last.
#
# `Failures:` is a budget, not a history: `mark_resolved` clears it. A backend that
# keeps it re-creates [26]'s defect — a counter cumulative over the ticket's whole
# life, escalating `failed-impl` a ticket that was delivered green twice. Where it
# is *not* cleared is a decision each re-injection path owes its own ticket:
# `mark_ready` keeps it today, so a re-injected ticket is escalated on its first
# attempt (owned by [16] for the human sink, [11] for the wiring loop).
#
# One field's *shape* is part of this interface rather than a detail of the
# backend that writes it: `Claimed` reads `owner=<who> at=<iso8601>`, because the
# liveness policy (lib/claim.sh) is backend-agnostic and single-machine — it has
# to know who to ping and when the claim was taken. A remote backend stores the
# claim as an assignee and keeps liveness in a local sidecar (spec §152); it
# still has to render those two facts here. An owner not shaped `pid:<n>` is
# judged by CLAIM_TTL alone, so a backend that renders one is saying "do not ping
# this, wait it out" — and, since [26], "and do not charge the ticket a retry for
# having waited". The two go together: an owner the pack never pinged is not
# evidence that an attempt failed.
tracker_field() { tracker__dispatch field "$@"; }

# ── what is wrong with this tracker before the run starts ────────────────────
#
# One scan, at the preflight, of the state no per-ticket read would ever surface:
# two tickets carrying one number. Dependencies are written as bare numbers
# (`Blocked by: 01`), so a duplicate does not break the ticket that carries it —
# it breaks every ticket that *points* at it, silently and permanently, by
# keeping them out of a frontier that is a memoryless scan ([27]).
#
# A session can no longer create one (the quarantine renumbers what it adds), so
# what is left is a human editing the directory by hand, and finding that ticket
# by ticket in the middle of a night is exactly what this avoids.
#
# Not dispatched: the question is about the *shape* of ids, which the interface
# owns, not about how a backend stores them. A backend numbering server-side
# finds nothing here, which is the right answer rather than an unimplemented one.
#
# Findings are `subject <TAB> outcome <TAB> sentence`, one per line, and non-zero
# means there was at least one. Reporting, not refusing: a duplicate costs the
# tickets that name it and nothing else, and a run that refuses to start over it
# trades a night of work for a warning a human can read in the morning either way.
tracker_preflight() {
  local ids nn dep found=0 carriers raw id
  ids="$(tracker_ids)" || return 0
  [ -n "$ids" ] || return 0

  for nn in $(tracker__ambiguous_numbers "$ids"); do
    carriers="$(tracker__carriers "$ids" "$nn")"
    printf '%s\tambiguous-id\ttwo or more tickets carry the number %s (%s): a bare "%s" is never safe to resolve, so anything blocked on it can never enter the frontier\n' \
      "$nn" "$nn" "$(tracker__commas "$carriers")" "$nn"
    found=1
  done
  [ "$found" = 1 ] || return 0

  for id in $ids; do
    raw="$(tracker_field "$id" 'Blocked by')" || continue
    for dep in $(printf '%s' "$raw" | tr ',' ' '); do
      case "$dep" in
        [0-9]*) ;;
        *) continue ;;
      esac
      tracker__is_ambiguous "$ids" "$dep" || continue
      printf '%s\tblocked-on-ambiguous-id\t%s is blocked on %s, which %s tickets carry (%s): it stays out of the frontier until a human renames one of them\n' \
        "$id" "$id" "$dep" \
        "$(tracker__carriers "$ids" "$dep" | wc -w | tr -d ' ')" \
        "$(tracker__commas "$(tracker__carriers "$ids" "$dep")")"
    done
  done
  return 1
}

# Every id shaped `NN-slug` for this NN. An id that is *exactly* the number is
# not one of them and settles the question on its own: a backend resolving a bare
# number matches the exact id before anything else, so `01.md` beside `01-alpha.md`
# is unambiguous — and renumbering over it would move a ticket nobody could
# have mis-resolved.
tracker__carriers() {
  local ids="$1" nn="$2" id out=''
  for id in $ids; do
    [ "$id" != "$nn" ] || return 0
  done
  for id in $ids; do
    case "$id" in
      "$nn"-*) out="$out $id" ;;
    esac
  done
  printf '%s\n' "${out# }"
}

tracker__is_ambiguous() {
  local n
  n="$(tracker__carriers "$1" "$2" | wc -w)"
  [ "$n" -gt 1 ]
}

tracker__ambiguous_numbers() {
  local ids="$1" id nn seen=' ' out=''
  for id in $ids; do
    case "$id" in
      [0-9]*-*) nn="${id%%-*}" ;;
      *) continue ;;
    esac
    case "$nn" in *[!0-9]*) continue ;; esac
    case "$seen" in *" $nn "*) continue ;; esac
    seen="$seen$nn "
    tracker__is_ambiguous "$ids" "$nn" || continue
    out="$out $nn"
  done
  printf '%s\n' "${out# }"
}

tracker__commas() {
  printf '%s' "$1" | tr -s ' ' '\n' | sed '/^$/d' | tr '\n' ' ' | sed 's/ *$//; s/ /, /g'
}
