# shellcheck shell=bash
# The audit receipt: one iteration, written down where a human reads it later.
#
# Four layers of observability, and this file owns two of them. They are never
# mixed, and the difference is what each one may be believed for:
#
#   the run journal    `run.log`, append-only, one line per event of the run,
#                      written by the pilot and never read back to decide
#                      anything. A dense trace for the morning: which tickets
#                      moved, what they cost, in what order.
#   the audit receipt  one markdown document per ticket the loop finished with —
#                      `resolved`, or escalated to the human sink — assembled by
#                      the process that measured the iteration. This is the
#                      asynchronous review surface: verdicts, findings, the zones
#                      nothing judged, and the work **by reference**.
#   the playthrough    what the feature does once it runs ([11]).
#   LEARNINGS          what a later session should know before it starts ([14]).
#
# **Why the receipt does not read the journal, which is the whole design** ([21]).
# `run.log` lives under `.scratch/<feature>/`, and nothing in this pack guards that
# directory: the tracker's own protection stops at `issues/` and cannot be widened,
# because the session stream is written *inside* the window being watched. So a
# session can rewrite the journal — and a receipt assembled from a source the judged
# session can edit is not a receipt, it is a session's account of itself.
#
# The receipt is therefore built from what the *loop* measured and from objects the
# loop wrote: the gate's own verdict variables, the branch output the gate collected
# before it removed its temporary directory, the durable commit, the tree objects
# the scope-guard was handed, the `failed/<ticket>` ref. None of those is reachable
# from a session's write-surface, and none of them is a file whose name a session is
# told — this workspace lives in `$TMPDIR` under a `mktemp` name that is never
# exported, the same secret discipline as the ignore pin ([30]) and the tracker
# register ([40]). The register itself is not a source either, and that is a
# decision rather than an omission: it is an unauthenticated trace between processes
# of one run, and its granularity is an id, so "the loop wrote X" says neither who
# nor what. A receipt that quoted it would assert more than its source.
#
# What that costs is written down rather than papered over: a ticket delivered on
# its third attempt has two earlier receipts and this one, and nothing here counts
# them for you — the count that used to answer that question is `Failures:`, which
# `mark_resolved` clears ([26]). What this receipt can vouch for is the value that
# field carried **when the session was spawned**, read after the tracker was
# restored from its pre-session snapshot, which is a number the loop controls.
#
# Public API
#   receipt_open                 start a receipt for this iteration
#   receipt_fact KEY VALUE...    record one fact (last write wins)
#   receipt_note SENTENCE...     record one line the run said out loud
#   receipt_gap SENTENCE...      record one thing that did not happen
#   receipt_keep_branch NAME FILE   keep a red branch's output while it exists
#   receipt_render TICKET        the document on stdout
#   receipt_emit TICKET          render it and hand it to the tracker adapter
#   receipt_close                throw the workspace away
#
# Everything is a no-op when no receipt is open, so a lib may call `receipt_note`
# unconditionally: the gate and the failure policy both run outside a receipt in
# their own tests, and a module that had to ask first would grow the check in five
# places and forget it in the sixth.

# Where this iteration's evidence accumulates, or empty. A shell variable of the
# iteration and never exported: `claude` is spawned from this very shell, and a
# path handed to a session in its environment is exactly as writable as a file in
# the tree — the lesson [40] paid for on the tracker register.
RALPH_RECEIPT="${RALPH_RECEIPT:-}"

# How much of a red branch's output is kept. The findings of a review lens are the
# only copy that survives the gate ([06]: the stream dies with the gate's temporary
# directory), so this has to be generous; a test suite that prints a megabyte is
# the reason it is not unbounded. What is dropped is always counted out loud.
RECEIPT_MAX_LINES="${RECEIPT_MAX_LINES:-200}"

# The one key this module gives a project, and the one way that key can switch the
# module off without saying so. `RECEIPT_MAX_LINES=0` — or a value that is not a
# number, which `tail` reads as an error and this file would swallow — keeps
# nothing: every receipt comes out with an empty findings section, and a night of
# red review lenses leaves no trace anywhere at all, the gate having removed the
# streams and twenty lines having scrolled past. That is the shape [17] refused
# five times over and [31] wrote the rule for: a value that reads as "off" has to
# be a decision a project takes out loud, never one it falls into.
#
# Refused at the door and not clamped to the default, for the same reason: a run
# that quietly ignored what the config asked for would be a second lie on top of
# the first.
receipt_preflight() {
  case "${RECEIPT_MAX_LINES:-}" in
    '' | 0 | *[!0-9]*)
      printf 'ralph: RECEIPT_MAX_LINES is "%s" — a receipt that keeps no lines of a red branch is an audit surface with no findings on it, and a review lens leaves no other copy\n' \
        "${RECEIPT_MAX_LINES:-}" >&2
      return 1
      ;;
  esac
  return 0
}

receipt_open() {
  local dir
  RALPH_RECEIPT=""
  dir="$(mktemp -d "${TMPDIR:-/tmp}/ralph-receipt.XXXXXX")" || return 1
  RALPH_RECEIPT="$dir"
  return 0
}

receipt_close() {
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  rm -rf "$RALPH_RECEIPT"
  RALPH_RECEIPT=""
  return 0
}

# One fact. Appended rather than replaced, and read back as the *last* occurrence:
# a fact recorded early and corrected later — an outcome that was `gate-red` until
# the budget classifier looked at it ([43]) — must not need its call site to know
# it was the first one.
receipt_fact() {
  local key="$1"
  shift
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  printf '%s\t%s\n' "$key" "$*" >>"$RALPH_RECEIPT/facts" 2>/dev/null || true
  return 0
}

receipt__fact() {
  [ -n "${RALPH_RECEIPT:-}" ] && [ -f "$RALPH_RECEIPT/facts" ] || return 0
  awk -F'\t' -v k="$1" '
    $1 == k { line = $0; sub(/^[^\t]*\t/, "", line); out = line }
    END { if (out != "") print out }
  ' "$RALPH_RECEIPT/facts" 2>/dev/null || true
}

# One line the run said out loud, kept in the order it was said.
#
# These are the sentences about what *nothing* judged — the ignored zone ([24]),
# the frontier a session moved ([30], [32]), what the gate itself wrote after the
# tree it judged ([29]), what the language gate did not look at ([17]), what the
# provisioning put in the worktree ([13]) — plus the admissions that are not zeroes
# ([34]). They scroll past on stdout during a night; this is where they last.
receipt_note() {
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  printf '%s\n' "$*" >>"$RALPH_RECEIPT/notes" 2>/dev/null || true
  return 0
}

# One thing this pack was going to do and did not, or could not measure at all.
#
# A second channel and not a second spelling of the one above ([45]). The notes
# are about **coverage** — the zones nothing walked — and they are on every
# iteration, green ones included; these are about the pack's own actions failing,
# they are rare, and what a human does about them is different: a tree that was
# not put back, a `failed/<ticket>` git refused to write, a tracker file that
# could not be restored. Buried in a list of ignored paths, the second kind reads
# as more coverage bookkeeping. They get their own section for that reason alone.
#
# Verbatim like the notes, and for the same reason: each of these sentences was
# written where the fact is known, and rephrasing one here would be a second
# author for a single claim.
#
# The asymmetry with the notes is deliberate and is written in the renderer: an
# empty note list has to confess, because nobody walking a zone is not the same as
# an empty zone. An empty gap list is a list of **events** that did not occur, so
# its absence says no such event was recorded — which is all it ever claimed.
receipt_gap() {
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  printf '%s\n' "$*" >>"$RALPH_RECEIPT/gaps" 2>/dev/null || true
  return 0
}

# What a red branch had to say, kept while the gate's directory still exists.
#
# Taken *during* the gate and not after it, which is [06]'s constraint and not a
# convenience: a lens's prompt and stream live under the gate's `$TMPDIR`
# directory, `gate_run` removes it, and after that the only trace of a model's
# findings is twenty lines that scrolled past on stdout. This receipt is the one
# place they can survive the night.
receipt_keep_branch() {
  local name="$1" file="$2" total
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  [ -n "$name" ] && [ -s "$file" ] || return 0
  total="$(awk 'END { print NR + 0 }' "$file")"
  {
    if [ "$total" -gt "$RECEIPT_MAX_LINES" ]; then
      printf '(the first %s line(s) of %s are not kept here: this branch is quoted from the end)\n\n' \
        "$((total - RECEIPT_MAX_LINES))" "$total"
    fi
    tail -"$RECEIPT_MAX_LINES" "$file"
  } >"$RALPH_RECEIPT/branch.$name" 2>/dev/null || true
  printf '%s\n' "$name" >>"$RALPH_RECEIPT/branches" 2>/dev/null || true
  return 0
}

# ── the document ─────────────────────────────────────────────────────────────

# What happened, in one paragraph, and it is the part of this file that has to be
# right. Every sentence below exists because reading the outcome alone, or the
# verdict alone, sends a human to the wrong place:
#
#   nothing-delivered  a session answered and wrote nothing. There is no verdict
#                   and, deliberately, no forensic branch ([35]).
#   session-*       a deadline this pack measured itself. The gate never ran, so
#                   there is nothing to recopy, and the stream is cut mid-event so
#                   turns and cost are missing rather than zero ([23]).
#   tracker-write   the three branches can all be green ([21]): a receipt that
#                   said "gate-red" would send a human to read passing tests.
#
# **`budget-pause` is not in the list, and that is the answer to [43] rather than
# an omission.** A ticket the subscription ran out under is given back to the
# frontier with no retry charged, so the loop has *not* finished with it and no
# receipt is written at all — the trap that ticket described, a document reading
# `standards=red` for a lens the API never let start, is out of reach on that
# route. It is reachable on exactly one other: a gate where a refused lens sits
# beside a lens that answered `fail`. There the gate is billable, the ticket can
# escalate, and the verdict line really does say red for a branch that judged
# nothing. What carries that difference into the document is the gate's own
# per-lens sentence, kept with the rest of what nothing here judged — not this
# summary, which would be inferring from the verdict the very thing [43] says
# cannot be inferred from it.
receipt__summary() {
  local ticket="$1" outcome="$2" failed="$3"
  case "$outcome" in
    resolved)
      printf 'The loop marked `%s` resolved. Every gate branch that ran came back green, the work was committed inside this iteration'"'"'s worktree and it reached the branch.\n' "$ticket"
      ;;
    nothing-delivered)
      printf 'A session answered on `%s` and changed no file this gate can see. Nothing was judged: there is no red check to read, no lens verdict, and no `failed/%s` branch — it would hold the tree the session was handed. The question this receipt puts to a human is why this ticket makes a session do nothing.\n' \
        "$ticket" "$ticket"
      ;;
    session-stalled)
      printf 'The session on `%s` wrote nothing for long enough that this run terminated it. The gate never ran, so there is no verdict below, and the stream this receipt would have quoted was cut mid-event: turns and cost are missing rather than zero.\n' "$ticket"
      ;;
    session-timeout)
      printf 'The session on `%s` ran past this run'"'"'s wall clock without finishing and was terminated. The gate never ran, so there is no verdict below, and the stream was cut mid-event: turns and cost are missing rather than zero.\n' "$ticket"
      ;;
    over-soft-limit)
      printf 'The session on `%s` crossed the context soft limit and was terminated. That is evidence about the size of the slice and about nothing else: the gate never ran, so nothing here judged the code.\n' "$ticket"
      ;;
    tracker-write)
      printf 'The session on `%s` edited the tracker, which takes the green away whatever the branches said. Read the verdicts below as a statement about the code and not as the reason this iteration failed: they may all be green.\n' "$ticket"
      ;;
    not-integrated)
      printf 'The gate on `%s` was green and the work never reached the branch. It stayed in a worktree this run then destroyed, so it did not happen: the ticket went back with no retry consumed and the run stopped.\n' "$ticket"
      ;;
    gate-red)
      printf 'The gate on `%s` was red: %s.\n' "$ticket" "${failed:-no branch named}"
      ;;
    *)
      printf 'The iteration on `%s` ended as `%s`. Nothing below should be read as a verdict unless the verdict line names it.\n' \
        "$ticket" "$outcome"
      ;;
  esac
}

receipt__verdicts() {
  local verdicts="$1"
  printf '## Verdicts\n\n'
  if [ -z "$verdicts" ]; then
    printf 'No gate ran on this iteration, so there is no verdict here. An empty verdict line is not a green one.\n'
    return 0
  fi
  printf '    %s\n\n' "$verdicts"
  printf 'Green is earned and never assumed. A branch that is **absent** above was not run, which is not the same as passing: `typecheck=` is missing when the project declared it has none, `lang=` when it switched the language gate off, and a review lens is missing when this ticket did not trigger it. Read the missing names, not only the red ones.\n'
  return 0
}

# The work, always as a reference and never as content. A receipt that carried the
# diff would be a second copy of the repository that nobody diffs and that drifts
# the moment a branch moves; what a reviewer needs is the object name and a command.
receipt__evidence() {
  local ticket="$1" commit base tree branch
  commit="$(receipt__fact commit)"
  base="$(receipt__fact base)"
  tree="$(receipt__fact tree)"
  branch="$(receipt__fact failed-branch)"

  # Two *different* trees, or no diff at all. Equal ones are the delivery refusal
  # of [35] — the gate compares them and stops there — and `git diff-tree -r X X`
  # is an empty diff dressed up as something to go and read.
  [ -n "$base" ] && [ -n "$tree" ] && [ "$base" != "$tree" ] || base=''

  printf '## What to read\n\n'
  if [ -n "$commit" ]; then
    printf -- '- the work as it landed: `git show %s`\n' "$commit"
  fi
  if [ -n "$base" ]; then
    printf -- '- the diff this gate judged: `git diff-tree -r %s %s`\n' "$base" "$tree"
  fi
  if [ -n "$branch" ]; then
    printf -- '- the attempt, kept before the rollback undid it: `git log -p %s`\n' "$branch"
  fi
  if [ -z "$commit" ] && [ -z "$branch" ] && [ -z "$base" ]; then
    printf -- '- nothing of the work itself: this iteration produced no commit, no diff and no forensic branch. What is left is the verdicts above, the zones below, and the ticket.\n'
  else
    printf -- '- those are git **objects**, not refs, apart from the branch. They are exact and they belong to this iteration — a branch tip read afterwards is whatever a sibling has since made it — and the price of that is written here rather than discovered: once the branch has moved past them, a `git gc` may collect them, and a receipt kept longer than that names work the repository no longer holds.\n'
  fi
  printf -- '- the session'"'"'s own stream: removed at the end of the iteration, and nothing kept it. It is the target project'"'"'s quota that pays for a stream, and a receipt is not a place to store megabytes of NDJSON.\n'
  printf '\nNone of that is inlined here on purpose.\n'
  return 0
}

receipt__findings() {
  local name printed=0
  [ -f "$RALPH_RECEIPT/branches" ] || return 0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    [ -f "$RALPH_RECEIPT/branch.$name" ] || continue
    if [ "$printed" = 0 ]; then
      printf '## Findings\n\n'
      printf 'What each red branch had to say. For a review lens this is the only copy: the prompt and the stream live in the gate'"'"'s temporary directory, and the gate removes it.\n\n'
      printed=1
    fi
    printf '### %s — red\n\n' "$name"
    sed 's/^/    /' "$RALPH_RECEIPT/branch.$name"
    printf '\n'
  done <"$RALPH_RECEIPT/branches"
  return 0
}

# What this iteration was going to do and did not ([45]). Absent when nothing was
# recorded, which is the one thing this section is entitled to mean: these are
# events, and no event of this kind was seen.
receipt__gaps() {
  [ -s "$RALPH_RECEIPT/gaps" ] || return 0
  printf '## What did not happen\n\n'
  printf 'Things this run set out to do and could not. None of them is a verdict on the code, and each of them means some other line of this document is narrower than it looks — a tree that is not back where the session found it, a reference that was promised and not written.\n\n'
  sed 's/^/- /' "$RALPH_RECEIPT/gaps"
  printf '\n'
  return 0
}

# The zones this pack names on every iteration rather than once in a document, and
# the admissions that are not zeroes ([34]). Reproduced verbatim: each of these
# sentences was written where the fact is known, and rephrasing them here would be
# a second author for one claim.
#
# Rendered even when there is nothing in it, which is [45] and the same refusal
# `receipt__verdicts` makes two functions up. These sentences are written where
# the fact is known — by the gate as it judges, by the rollback as it puts the tree
# back — so an iteration where neither ran produces none of them, and a section
# that simply vanished would read as "the zones were empty" on exactly the routes
# where nobody looked at them.
receipt__unjudged() {
  local provisioned
  provisioned="$(receipt__fact provisioned)"
  case "$provisioned" in '' | 0) provisioned='' ;; esac
  if [ ! -s "$RALPH_RECEIPT/notes" ] && [ -z "$provisioned" ]; then
    printf '## What nothing here judged\n\n'
    printf 'Nothing here named a zone, and that is a statement about this iteration and not about the repository. The sentences that go here are written as the fact becomes known — the gate names what it did not judge, the rollback names what it could not undo — so an iteration neither of them reached produces none of them: the ignored paths, the ignore frontier and whatever was written after the tree was taken were never walked. An empty list here is not an empty zone.\n\n'
    return 0
  fi
  printf '## What nothing here judged\n\n'
  # Rendered rather than quoted, because this one is the pilot's fact and not a
  # sentence anybody said inside the iteration ([13]): the provisioning happens
  # before the fork, in the shell that owns the worktree.
  [ -z "$provisioned" ] ||
    printf -- '- %s path(s) were copied into this iteration'"'"'s worktree by `WORKTREE_PROVISION`, which nothing here judges and no rollback undoes\n' \
      "$provisioned"
  [ ! -s "$RALPH_RECEIPT/notes" ] || sed 's/^/- /' "$RALPH_RECEIPT/notes"
  printf '\n'
  return 0
}

receipt__meta() {
  local attempt tokens stopped
  printf '## Meta\n\n'
  printf -- '- outcome: `%s`\n' "$(receipt__fact outcome)"
  printf -- '- what the loop then did: %s\n' "$(receipt__fact action)"
  # And whether anything will act on it, which the line above cannot say on its
  # own ([45]). `retry:1/3` is an honest account of what the failure policy
  # decided and a misleading one to read alone when the run stopped on this very
  # iteration: no later iteration is coming to spend that retry.
  stopped="$(receipt__fact run-stopped)"
  [ -z "$stopped" ] ||
    printf -- '- the run stops on this iteration: %s. Whatever the line above says would happen next, nothing in this run will do it.\n' \
      "$stopped"
  attempt="$(receipt__fact attempt)"
  if [ -n "$attempt" ]; then
    printf -- '- attempt: %s. `Failures:` is a retry budget and not a history — it is cleared on delivery ([26]) — so this is the value the ticket carried when this session was spawned, read after the tracker was restored from its pre-session snapshot, plus one.\n' \
      "$attempt"
  fi
  printf -- '- iteration %s of this run, in `%s`\n' \
    "$(receipt__fact iteration)" "$(receipt__fact worktree)"
  printf -- '- turns: %s, cost: %s\n' \
    "$(receipt__fact turns)" "$(receipt__fact cost)"
  tokens="$(receipt__fact tokens)"
  # Never the word "total", and that is [20] rather than a phrasing preference:
  # the number is the largest context window seen in the stream's `assistant`
  # events, and the `usage` block of a multi-turn `result` line repeats the last
  # iteration's counters rather than summing them. A receipt that presented this as
  # an audited total would lie about exactly the session that used the most.
  printf -- '- context: %s tokens, the peak observed in the session'"'"'s stream. Not a total, and not a bill.\n' \
    "${tokens:-0}"
  return 0
}

receipt_render() {
  local ticket="$1" outcome verdicts failed
  [ -n "${RALPH_RECEIPT:-}" ] || return 1
  outcome="$(receipt__fact outcome)"
  verdicts="$(receipt__fact verdicts)"
  failed="$(receipt__fact failed)"

  printf '# %s — %s\n\n' "$ticket" "${outcome:-unknown}"
  receipt__summary "$ticket" "$outcome" "$failed"
  printf '\n'
  receipt__verdicts "$verdicts"
  printf '\n'
  receipt__evidence "$ticket"
  printf '\n'
  receipt__findings
  # Before the zones and not after them ([45]): a promise this run could not keep
  # is rare and actionable, the zone list is long and on every iteration, and the
  # order of a document decides which of the two a human reads.
  receipt__gaps
  receipt__unjudged
  receipt__meta
  printf '\n## Where this receipt comes from\n\n'
  printf 'Assembled by the process that measured this iteration, from the gate'"'"'s own verdicts, the branch output it collected before removing its temporary directory, and the objects the loop wrote. It does **not** read `run.log`: that file lives under `.scratch/`, which no check in this pack guards, so the session this receipt is about can rewrite it.\n'
  return 0
}

# Rendered, then handed to whichever backend is configured. In the local backend
# that is a file under `receipts/`; on a remote one it is the pull request. The
# loop never knows which, which is the whole point of the adapter interface — and
# the reason this hands over a document rather than a path.
receipt_emit() {
  local ticket="$1" out
  [ -n "${RALPH_RECEIPT:-}" ] || return 1
  out="$(receipt_render "$ticket" | tracker_emit_receipt "$ticket")" || return 1
  [ -z "$out" ] || printf '%s\n' "$out"
  return 0
}
