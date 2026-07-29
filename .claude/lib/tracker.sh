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
#   tracker_append_note ID            append a comment from stdin
#   tracker_emit_receipt ID           write the audit receipt from stdin
#
# Marking is the loop's job, after the gate — never the session's.

tracker__dispatch() {
  local op="$1"
  shift
  local backend="${TRACKER_BACKEND:-local}"
  local fn="tracker_${backend}_${op}"
  if ! declare -f "$fn" >/dev/null 2>&1; then
    printf 'tracker: backend "%s" does not implement %s\n' "$backend" "$op" >&2
    return 3
  fi
  "$fn" "$@"
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
