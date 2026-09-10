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
#   tracker_ids                       every ticket id, whatever its state, min-NN
#                                     first, one per line
#   tracker_read_ticket ID            the ticket on stdout
#   tracker_claim ID [OWNER]          take the ticket; non-zero if it was lost
#   tracker_unclaim ID                give it back to the frontier
#   tracker_mark_resolved ID          the gate came back green; clears the claim
#                                     and the retry counter
#   tracker_mark_escalated ID REASON  hand it to the human sink, with a reason —
#                                     or with none, when REASON is empty
#   tracker_mark_ready ID             re-inject (re-slice, human fix, wiring)
#   tracker_mark_wontfix ID           closed by a human, never to be ground
#   tracker_block_on ID DEPS          hold it until those tickets are resolved
#   tracker_bump_failures ID          count one failure; new count on stdout
#   tracker_clear_failures ID         give it its whole retry budget back
#   tracker_open_ticket SLUG TITLE    create a ticket from stdin; id on stdout
#   tracker_open_unique SLUG TITLE    the same, unless a ticket already carries
#                                     this slug; then nothing at all on stdout
#   tracker_renumber ID               give it an id no other ticket shares; the
#                                     id it now carries on stdout
#   tracker_append_note ID            append a comment from stdin
#   tracker_emit_receipt ID           write the audit receipt from stdin
#   tracker_receipt_path ID           where that receipt can be read, if it is
#                                     still there; non-zero when there is none
#   tracker_receipt_dir               the directory this backend keeps receipts
#                                     in; non-zero when it keeps them elsewhere
#   tracker_tickets_dir               the directory this backend keeps tickets
#                                     in; non-zero when it keeps them elsewhere
#
# Marking is the loop's job, after the gate — never the session's.
#
# **One id per line is part of this interface and not a habit of the local
# backend** ([37]). Every consumer in the pack reads these lists line by line and
# compares whole lines, because an id is the name of a file a session — or a
# human — puts in the tracker: a backend that answered with a line of words would
# reopen four faults at once, none of which is cosmetic (a quarantine that
# announces having escalated a ticket still on the frontier, a register that
# exempts every word of an id, a scope overflow classified retryable, and a claim
# on a dead owner that is never swept). The limit of that convention is written
# down where it belongs, in `docs/frontiere-de-confiance.md`: a file name may
# contain a newline, and this transport cannot carry one.
#
# **So a backend never hands out an id carrying a newline, and it refuses out
# loud.** That is the other half of the convention, and it is a clause of this
# interface rather than a habit of one adapter ([48]). Dropping the name is not
# optional — a list carrying it breaks every consumer at once, which is the whole
# of [37]. Saying so is not optional either: a ticket nobody can reach is worse
# than a ticket nobody can grind if nothing names the file a human has to rename.
#
# **And where the voice goes, because that is the half a new backend has to be
# told.** It calls `tracker_refuse_name` below and prints no sentence of its own.
# The interface collects those names and turns them into findings of
# `tracker_preflight` — said **once**, at the start of a run and at the start of a
# drain, in `run.log` and in the journal, which are the artefacts a human reads in
# the morning. Measured on 05/09/2026, before this existed: the local backend's
# own `printf ... >&2` said it eight times on the console of an AFK run and zero
# times in `run.log`, in the audit receipt and in the playthrough, and three of its
# consumers read these lists as `$(tracker_ids 2>/dev/null)` and threw the line
# away. A `>&2` in a producer is not a channel: every consumer decides whether it
# is heard.

# **How an operation refuses, because that is the other half a new backend has to
# be told** ([71]). An operation answers a caller; it never ends one.
#
#   a refusal is a return code    non-zero, and the caller decides what it means.
#                                 `3` is taken: the dispatcher above returns it
#                                 for an operation a backend does not implement,
#                                 so a backend's own refusal starts at `1` or `2`.
#   never a shell exit            not `${N:?word}`, not `exit`, not an errexit
#                                 left to travel. Every one of those ends the
#                                 *caller's* process, and this interface has two
#                                 callers: `loop.sh` and `human-loop.sh`.
#   an empty value is a value     `mark_escalated ID ""` is a ticket in the sink
#                                 with no `Escalation:`, which is what
#                                 `capability_propose` writes and what the drain
#                                 has to be able to put back. A missing argument
#                                 is the caller bug; an empty one is a state.
#
# This is written here rather than left to each adapter because the price is paid
# one entry point over. The drain is the caller that costs the most: it has no
# iteration subshell and no `proc_collect` between it and these operations —
# exactly because [67] removed the last one, for the sound reason that a report
# written in a command substitution dies with it. Measured on the code delivered
# by [67]: `tracker_local_mark_escalated` refusing an empty reason by `${2:?}`
# ended the drain in the middle of putting a neighbour back, and the drain exited
# `0`, which its header documents as an emptied sink.
#
# What holds it: nothing on this side, and that is stated rather than implied. A
# backend is a file a project installs, and no test of this pack can read one that
# does not exist yet. What exists is the other end — `human-loop.sh` refuses to
# exit `0` from anywhere but its own last line, so a backend that breaks this
# clause costs a human a wrong diagnosis and never a false "everything was
# drained". `docs/frontiere-de-confiance.md` carries the row.

# The names this process has already put in front of a human, one per line. See
# `tracker_finding_said`.
RALPH_TRACKER_SAID="${RALPH_TRACKER_SAID:-}"

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
    # The four reads, and the one write that is not a write *of a ticket* ([10]).
    # The criterion this list is read against is not "does it touch the disk" but
    # the question the register answers: did the loop itself write the ticket a
    # guard over `issues/` is about to compare ([31] — derive the list from its
    # criterion, not from the operations that happen to exist). `emit_receipt`
    # writes a document *about* a ticket, under `receipts/`, which no snapshot of
    # `issues/` will ever see; noting it would hand the restore and the quarantine
    # an id to skip for a file they do not look at, and the skip would land on
    # whichever sibling iteration was in flight at the time.
    frontier | ids | read_ticket | field | receipt_path | receipt_dir | tickets_dir | emit_receipt | sidecar_path | sidecar_witness | sidecar_drift)
      "$fn" "$@"
      ;;
    open_ticket | open_unique | renumber)
      # The operations whose *answer* is an id, and the register wants the id a
      # guard will meet in `issues/` rather than the argument. The two openings
      # take a slug, so noting the argument wrote a line naming no ticket at all
      # — a nuisance while only the restore read the register ([13]), and wrong
      # the moment the quarantine reads it ([42]): the one thing it asks is
      # whether an id that appeared is the loop's own creation. `renumber` needs
      # both, because it moves a file: the number that stopped existing and the
      # one that now does. An `open_unique` that opened nothing answers nothing,
      # and `tracker__note_write` writes no line for an empty id — which is right:
      # a creation that did not happen is not a write to exempt.
      case "$op" in
        open_ticket | open_unique) ;;
        *) tracker__note_write "${1:-}" ;;
      esac
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
# **And that sentence covers the telling, not the finding** ([80]). A session that
# globs `$TMPDIR` reads this file without being told anything, so the register is
# not a channel a session cannot write — it is one whose entries buy as little as
# they can be made to buy. Two clauses, both in `failures.sh` where the guards
# are: an entry naming the iteration's **own** ticket exempts nothing, and the
# register is not consulted at all by a run that can have no sibling in flight.
# Above `MAX_PARALLEL=1` a forged line still shields a *sibling's* ticket from the
# restore and a ticket a session created from the quarantine; that is written down
# in `docs/frontiere-de-confiance.md` and is not fixed here.
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

# The ids the loop wrote since that mark, one per line — the pack's list
# convention since [33], and here for the reason [37] gives one layer up: an id is
# a **file name a session chooses**, so a fence of words answers "is this id in the
# register" by comparing something that is not an id. The register is written one
# id per line by `tracker__note_write`; joining those lines back with spaces threw
# that away and the reader compared `*" $id "*` against it, so an id carrying a
# space exempted every one of its own words. Reachable, and it is a quarantine
# bypass rather than a cosmetic one: the loop claims `99-my ticket.md` — a name a
# human may perfectly well give a ticket — the register fence reads ` 99-my ticket `,
# and a session that then writes itself `99-my.md` with the write-surface it likes
# is exempted by `failures__in_list` and walks onto the frontier (probed, s2b).
tracker_writes_since() {
  local mark="${1:-0}"
  [ -n "${RALPH_TRACKER_LOG:-}" ] && [ -f "$RALPH_TRACKER_LOG" ] || return 0
  awk -v m="$mark" 'NR > m' "$RALPH_TRACKER_LOG"
}

tracker_frontier() { tracker__dispatch frontier "$@"; }
tracker_ids() { tracker__dispatch ids "$@"; }
tracker_read_ticket() { tracker__dispatch read_ticket "$@"; }
tracker_claim() { tracker__dispatch claim "$@"; }
tracker_unclaim() { tracker__dispatch unclaim "$@"; }
tracker_mark_resolved() { tracker__dispatch mark_resolved "$@"; }
tracker_mark_escalated() { tracker__dispatch mark_escalated "$@"; }
tracker_mark_ready() { tracker__dispatch mark_ready "$@"; }
# Closed by a human, and only ever by a human ([16]). It is a state the local
# backend already names and no producer ever wrote: a drain that could only
# re-inject is not a drain, and a request the loop opened for itself — a rule the
# retro asked for, a capability [15] refused to build — has to be refusable
# somewhere. Nothing on the AFK path calls it, which is the point.
tracker_mark_wontfix() { tracker__dispatch mark_wontfix "$@"; }
tracker_block_on() { tracker__dispatch block_on "$@"; }
tracker_bump_failures() { tracker__dispatch bump_failures "$@"; }
# The counter back to zero without going through `resolved`, and the operation
# exists because the *decision* to clear it is not the backend's ([26] left it to
# each re-injection path, and [16] is the first one to take it).
#
# An operation and not a caller writing the field, for the reason every write in
# this interface is one: it goes through the dispatcher, so it lands in the
# register the two guards over `issues/` read ([13], [42]), and a backend that
# stores the retry budget somewhere other than a ticket field owes it an answer
# instead of inheriting one that happens to work on markdown.
tracker_clear_failures() { tracker__dispatch clear_failures "$@"; }
tracker_open_ticket() { tracker__dispatch open_ticket "$@"; }
# "Open this, unless one carrying the slug is already there." An operation and not
# a caller reading `tracker_ids` first, because the read and the write have to be
# on the same side of whatever serialises creation — a caller that looks and then
# opens has the race of [47] by its other end, and two proposals in flight both
# find nothing and both open. A backend whose creation is not serialised owes this
# question its own answer rather than inheriting one: unimplemented is a loud
# refusal here (`does not implement open_unique`), which is the outcome to prefer
# over a duplicate nobody notices.
tracker_open_unique() { tracker__dispatch open_unique "$@"; }
# Only the quarantine calls this, and only on what a session added. A backend
# whose ids cannot collide — one numbered server-side — returns the id unchanged
# and is done; it still owes its own ticket an answer to the question underneath
# ([27]): what does `tracker_ids` do when two tickets claim one identifier.
tracker_renumber() { tracker__dispatch renumber "$@"; }
tracker_append_note() { tracker__dispatch append_note "$@"; }
tracker_emit_receipt() { tracker__dispatch emit_receipt "$@"; }
# Where the receipt for this ticket can be read, if it is still there — a read,
# and therefore not noted in the register.
#
# It exists because the human sink is the receipt's reader ([10]) and the reader
# must not know how a backend stores one: on the local backend it is a file under
# `receipts/<feature>/`, on a remote one it is the pull request the loop opened.
# A drain that built the path itself would be a second author for that layout,
# wrong the first time a backend keeps receipts anywhere else — and it would
# answer "no receipt" on every backend that does not use files, which reads as
# "nothing was written about this ticket".
tracker_receipt_path() { tracker__dispatch receipt_path "$@"; }
# Where a backend keeps receipts, as a directory, or a refusal when it does not
# keep them in one — the pull request of a remote backend is not a path anybody
# can walk. A read, and therefore not noted in the register either.
#
# The one caller is the witness [70] takes before a run's first session, and it
# needs what `receipt_path` cannot give: the receipt of an id that does not exist
# yet, and every file under the directory rather than the ones a ticket names. A
# forgery under a name no ticket carries is exactly the kind of thing this exists
# to see, so a per-id question would have been narrower than its own criterion
# ([31], [45]).
#
# **A backend that refuses here is a backend whose receipts nothing witnesses**,
# and the run says so once rather than going quiet: see `forensic_uncovered`, and
# [18], which owes the question what attests the provenance of a receipt that is
# a pull request.
tracker_receipt_dir() { tracker__dispatch receipt_dir "$@"; }
# Where a backend keeps its **tickets**, as a directory, or a refusal when it does
# not keep them in one — the issues of a remote backend live on a service and are
# a path in no tree at all. A read, and therefore not noted in the register.
#
# It is here for the reason `receipt_dir` is, one zone over ([18] on [21]).
# `failures_protect_tracker` snapshots a git tree of the tickets around every
# session and restores what moved: that is what makes the write-surface the
# scope-guard judges against the contract as it stood at spawn time. The path it
# snapshots was composed by `failures.sh` itself, which made it a second author for
# a layout only the adapter knows — and on a backend that keeps no tickets in this
# tree the pathspec matched nothing, both snapshots were the empty tree, and the
# guard **returned zero without a word** about a tracker nobody had looked at. A
# silent vouch is the shape of false green this pack exists to refuse.
#
# So the question is asked of the backend, and a refusal here is an answer: the
# guard takes its "there is nothing in this tree to compare" branch knowingly, and
# the run says once at startup that nothing witnesses the tracker of this backend
# (`forensic_uncovered`). What that leaves open — a session editing its own ticket
# over the network, which no snapshot, no rollback and no witness of this pack sees
# — is [18]'s answer, and it is in `docs/frontiere-de-confiance.md` rather than
# implied by a return code.
tracker_tickets_dir() { tracker__dispatch tickets_dir "$@"; }

# ── the local facts a backend keeps about tickets, in this tree ──────────────
#
# A third zone of the same family as the two above, and the one that had no
# question ([77]). A backend whose tickets live on a service still has to answer
# `Claimed:` in the shape `claim.sh` reads, and a pid means nothing on another
# host — so it keeps the liveness of a claim, and whatever else only this machine
# knows, in a file of this repository. That file is in `.scratch/<feature>/`,
# which `gate_is_bookkeeping` takes out of the scope-guard, which
# `failures_protect_tracker` does not restore, and which the witness of [70] does
# not know: what a session appends there decides who holds a ticket and which URL
# a human is sent to read.
#
# Three operations, all reads as far as the register of [13] is concerned — none
# of them writes a ticket:
#
#   sidecar_path       where those records are, so the human sink can name the
#                      file under the URL it shows. A refusal means this backend
#                      keeps no such file, and every caller reads it that way.
#   sidecar_witness D  the run's own copy of them, into the run's witness
#                      directory, before its first session exists. A backend that
#                      answers `sidecar_path` and refuses here is a run whose
#                      tracker's liveness nothing holds a copy of, and
#                      `forensic_witness` says so.
#   sidecar_drift D    what moved under that copy, `subject<TAB>outcome<TAB>message`
#                      — the shape `capability_drift`, `gate_path_drift` and
#                      `forensic_drift` already use. Silent when nothing did.
#
# **A backend that refuses `sidecar_path` is saying it keeps no local fact about a
# ticket outside the ticket**, which is what the local backend says: its claim is
# a field of the ticket file, restored around every session by [21]. The one
# thing it keeps beside a ticket is an exclusion guard, which is not a record —
# `gate__stale_guards` counts those, in both of the directories a backend of this
# pack puts one in.
tracker_sidecar_path() { tracker__dispatch sidecar_path "$@"; }
tracker_sidecar_witness() { tracker__dispatch sidecar_witness "$@"; }
tracker_sidecar_drift() { tracker__dispatch sidecar_drift "$@"; }

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

# ── the name a backend has to refuse, and where it says so ───────────────────
#
# Called by an adapter that has just met a name it can never hand out as an id,
# with the name exactly as the tracker holds it. Not dispatched, and not a
# per-backend sentence: the shape of an id belongs to this interface, so the
# rendering and the destination do too.
#
# Two destinations, one rendering. When `tracker_preflight` is listening — which
# is the start of a run and the start of a drain — the name is collected and comes
# back out as a finding, in `run.log` and in the journal. When nothing is
# listening, the sentence goes to stderr as it always did: a name that appears
# *after* a preflight, written into `issues/` by a session or by a human while the
# run is grinding, is seen by no preflight of this run, and going silent there
# would trade a real witness for a tidier console.
#
# **What the fallback still costs, measured rather than assumed** (06/09/2026): a
# session dropping such a file in the middle of a run gets the sentence repeated
# once per scan that meets it — thirteen times over three iterations — because a
# `>&2` in a producer has no memory a subshell can keep. Left as it is, and here
# is why that is not the defect [64] was opened on: that run is not silent about
# it anywhere else. `failures_protect_tracker` sees the file arrive under a name
# it cannot address, says so, and refuses to vouch for the tracker ([39], [49]), so
# the iteration is red and `run.log` carries its outcome. The case with no second
# witness at all is the file that was **already there** at the start, which is
# precisely the one the preflight now names once, in the file a human opens.
tracker_refuse_name() {
  local name="$1"
  # Both separators of a finding, escaped before the name goes anywhere. The
  # newline is [48]'s reason — a message printing the raw name arrives as two
  # lines and reproduces the very defect it reports — and the tab is this
  # ticket's: a finding is `subject <TAB> outcome <TAB> sentence`, read back by
  # `read -r subject outcome message`, so a name carrying a tab would shift every
  # field one place along and hand a human the sentence in pieces. A file name may
  # carry either.
  name="${name//$'\n'/\\n}"
  name="${name//$'\t'/\\t}"
  if [ -n "${RALPH_TRACKER_REFUSED:-}" ]; then
    printf '%s\n' "$name" >>"$RALPH_TRACKER_REFUSED" 2>/dev/null || true
    return 0
  fi
  case $'\n'"$RALPH_TRACKER_SAID" in
    *$'\n'"$name"$'\n'*) return 0 ;;
  esac
  tracker__refuse_sentence "$name" >&2
}

# ── what a reader has already been given ─────────────────────────────────────
#
# Called by an entry point for every finding it has just put in front of a human,
# and it is what turns "said out loud" into "said once". The measurement [64] was
# opened on is eight identical lines on the console of one AFK run: the preflight
# says the finding, and then every later scan that meets the same name says it
# again through the fallback above, at a reader who has already read it. Eight of
# anything identical teaches a reader to skip the ninth.
#
# Generic on purpose. The entry points hand over `subject` and `outcome` without
# knowing which findings have a producer that also speaks — `loop.sh` and
# `human-loop.sh` log whatever `tracker_preflight` returns and special-case
# nothing — and this function decides what is worth remembering. A finding with no
# second voice costs one comparison.
#
# A variable of the entry point's own shell, never a file and never exported. Both
# readers run their loop on a heredoc rather than a pipe, so what they record here
# is recorded in the process that goes on to grind the night, and every scan of
# every iteration runs in a subshell of it — which inherits it, the way
# `RALPH_TRACKER_LOG` is inherited and for the reason [40] paid for: what a session
# is never told the name of, a session cannot switch off. Delimited by newlines
# because a refused name is escaped before it gets here, so it holds none.
tracker_finding_said() {
  local subject="$1" outcome="$2"
  [ "$outcome" = unaddressable-name ] || return 0
  [ -n "$subject" ] || return 0
  case $'\n'"$RALPH_TRACKER_SAID" in
    *$'\n'"$subject"$'\n'*) return 0 ;;
  esac
  RALPH_TRACKER_SAID="$RALPH_TRACKER_SAID$subject
"
  return 0
}

# The one rendering of that finding, escaped name in, one line out. One place and
# not two: the drain says of a duplicate id exactly what the run says, and this
# has to hold for the second finding as much as for the first.
tracker__refuse_sentence() {
  printf 'tracker: "%s" carries a newline in its name — that is not an id this backend hands out and nothing in the pack can address it, so it is on no frontier and no scan of the tracker sees it. Rename it.\n' \
    "$1"
}

# ── what is wrong with this tracker before the run starts ────────────────────
#
# One scan, at the preflight, of the state no per-ticket read would ever surface.
# Two findings, and they are the same kind of thing: a tracker whose *ids* are
# wrong, which no ticket read tells anybody about because the ticket that pays is
# never the ticket that is wrong.
#
# **`unaddressable-name`**, since [64]. A name a backend cannot hand out as an id
# — in the local backend, a file name carrying a newline — is on no frontier, in
# no scan, moved by no guard and renumbered by no quarantine ([48]). The names
# come from the backends themselves through `tracker_refuse_name` above, collected
# while this function takes the id list and rendered here: the shape of an id is
# the interface's question, so a backend that numbers server-side finds nothing
# here, and that is the right answer rather than a missing one — exactly as it is
# for the duplicate below.
#
# **`ambiguous-id`**: two tickets carrying one number. Dependencies are written as
# bare numbers
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
# **Both entry points say both findings, and that is chosen rather than
# inherited.** `human_loop_preflight` does not call `loop_preflight` — a decision
# written down where it is taken, because a drain refused for an empty `TEST_CMD`
# would be a refusal protecting nothing — so nothing here reaches the drain by
# inheritance. It calls this function itself, and it should: a duplicate number is
# a thing only a human may fix, an unaddressable name is a file only a human can
# rename, and the drain is the one entry point with a human already reading. The
# alternative — leaving the drain to meet these on a console, scan by scan — is
# the shape [55]/[56]/[57] were opened for, one entry point holding a guarantee
# the other never inherited.
#
# **The collection is a file, and it exists only here.** A shell variable cannot
# carry it: every caller takes the id list out of a command substitution, so a
# name refused inside that subshell is gone the moment it returns — [48] said this
# about a "say it once" flag and it is just as true of a collector. So the
# temporary is made here, named to the backends through a variable that is
# **never exported** — the lesson [40] paid for, applied to a path a session must
# not be able to write ([21]'s corollary: a control reading a file the session can
# write is not a control) — and removed before this function returns, well before
# a session is spawned.
#
# Findings are `subject <TAB> outcome <TAB> sentence`, one per line, and non-zero
# means there was at least one. Reporting, not refusing: a duplicate costs the
# tickets that name it and nothing else, and a run that refuses to start over it
# trades a night of work for a warning a human can read in the morning either way.
# Ids are read one per line here and everywhere below ([37]). `for id in $ids` cut
# `99-my ticket` into two ids no ticket carries and replaced `99-a[0]` by whatever
# the current directory happened to hold — and the id namespace is file names a
# session chooses, so neither is hypothetical.
#
# `Blocked by:` is the one list on this page that stays a line of words, and that
# is a decision rather than an omission. It is **prose a human writes** in a
# ticket, like `Write-surface:`, and [33] left the written formats alone by
# converting them at the point of reading. What makes the answer the same here and
# not merely similar: a dependency is a bare *number* ([27]), the loop already
# drops every word that does not start with a digit, and a dependency resolving to
# nothing already blocks fail-safe — so `Blocked by: 99-my ticket` holds the ticket
# out of the frontier, which is the safe verdict and the one a human can read.
tracker_preflight() {
  local ids nn dep found=0 ambiguous=0 carriers raw id sink name
  sink="$(mktemp "${TMPDIR:-/tmp}/ralph-tracker.refused.XXXXXX")" || sink=''
  RALPH_TRACKER_REFUSED="$sink"
  # And not `|| return 0`: a backend that answered nothing may still have refused
  # a name on the way, and returning here would drop the finding that the tracker
  # holds *only* files nobody can address — the one case where the run has no work
  # and no idea why.
  ids="$(tracker_ids)" || ids=''
  RALPH_TRACKER_REFUSED=''

  if [ -n "$sink" ]; then
    while IFS= read -r name; do
      [ -n "$name" ] || continue
      printf '%s\tunaddressable-name\t%s\n' "$name" "$(tracker__refuse_sentence "$name")"
      found=1
    done <<REFUSED
$(LC_ALL=C sort -u "$sink")
REFUSED
    rm -f "$sink"
  fi

  [ -n "$ids" ] || return "$found"

  while IFS= read -r nn; do
    [ -n "$nn" ] || continue
    carriers="$(tracker__carriers "$ids" "$nn")"
    printf '%s\tambiguous-id\ttwo or more tickets carry the number %s (%s): a bare "%s" is never safe to resolve, so anything blocked on it can never enter the frontier\n' \
      "$nn" "$nn" "$(tracker__commas "$carriers")" "$nn"
    found=1
    ambiguous=1
  done <<AMBIGUOUS
$(tracker__ambiguous_numbers "$ids")
AMBIGUOUS
  [ "$ambiguous" = 1 ] || return "$found"

  while IFS= read -r id; do
    [ -n "$id" ] || continue
    raw="$(tracker_field "$id" 'Blocked by')" || continue
    for dep in $(printf '%s' "$raw" | tr ',' ' '); do
      case "$dep" in
        [0-9]*) ;;
        *) continue ;;
      esac
      tracker__is_ambiguous "$ids" "$dep" || continue
      printf '%s\tblocked-on-ambiguous-id\t%s is blocked on %s, which %s tickets carry (%s): it stays out of the frontier until a human renames one of them\n' \
        "$id" "$id" "$dep" \
        "$(tracker__count "$(tracker__carriers "$ids" "$dep")")" \
        "$(tracker__commas "$(tracker__carriers "$ids" "$dep")")"
    done
  done <<IDS
$ids
IDS
  return 1
}

# Every id shaped `NN-slug` for this NN, one per line. An id that is *exactly* the
# number is not one of them and settles the question on its own: a backend
# resolving a bare number matches the exact id before anything else, so `01.md`
# beside `01-alpha.md` is unambiguous — and renumbering over it would move a ticket
# nobody could have mis-resolved.
tracker__carriers() {
  local ids="$1" nn="$2" id
  if tracker__holds_exactly "$ids" "$nn"; then return 0; fi
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    case "$id" in
      "$nn"-*) printf '%s\n' "$id" ;;
    esac
  done <<IDS
$ids
IDS
  return 0
}

# Does any of these ids read exactly as this number.
tracker__holds_exactly() {
  local ids="$1" nn="$2" id
  while IFS= read -r id; do
    if [ "$id" = "$nn" ]; then return 0; fi
  done <<IDS
$ids
IDS
  return 1
}

# How many entries in a one-per-line list. `wc -w` counted *words*, which is the
# whole of [37]: one ticket named `99-my ticket.md` was two carriers of 99, so a
# number nothing was ambiguous about was reported as ambiguous — and the report is
# read by a human who then goes looking for a ticket called `99-my`.
tracker__count() {
  awk 'length { n++ } END { print n + 0 }' <<LIST
$1
LIST
}

tracker__is_ambiguous() {
  local n
  n="$(tracker__count "$(tracker__carriers "$1" "$2")")"
  [ "$n" -gt 1 ]
}

# The numbers carried by more than one ticket, one per line. `seen` stays a fence
# of words on purpose: what it holds are the `NN` halves, filtered to digits two
# lines above, and a digit string has no space to lose.
tracker__ambiguous_numbers() {
  local ids="$1" id nn seen=' '
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    case "$id" in
      [0-9]*-*) nn="${id%%-*}" ;;
      *) continue ;;
    esac
    case "$nn" in *[!0-9]*) continue ;; esac
    case "$seen" in *" $nn "*) continue ;; esac
    seen="$seen$nn "
    tracker__is_ambiguous "$ids" "$nn" || continue
    printf '%s\n' "$nn"
  done <<IDS
$ids
IDS
  return 0
}

# A one-per-line list rendered for a human. Joined line by line and never by
# `tr '\n' ' '` then `s/ /, /g`, which turned one id carrying a space into two
# names, in the very message a human reads to go find the file.
tracker__commas() {
  awk 'length { if (n++) printf ", "; printf "%s", $0 } END { if (n) print "" }' <<LIST
$1
LIST
}
