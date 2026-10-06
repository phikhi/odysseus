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
# the scope-guard was handed, the `failed/<ticket>` ref. The register itself is not a
# source either, and that is a
# decision rather than an omission: it is an unauthenticated trace between processes
# of one run, and its granularity is an id, so "the loop wrote X" says neither who
# nor what. A receipt that quoted it would assert more than its source.
#
# **Where those pieces were assembled was the hole, and closing it is [96].** What
# stood here claimed that none of them was reachable from a session's write-surface
# and that this workspace lived under a `mktemp` name never exported, "the same
# secret discipline as the ignore pin ([30]) and the tracker register ([40])". Both
# halves were false, and the citation was the tell: `$TMPDIR` enumerates, which is
# what [80] paid for on that very register — a name is not a guard ([81]), and the
# permissions of one's own user are not one either. Measured by the 23/09 pass with
# a `nohup` a session left behind: `outcome resolved`, `verdicts tests=green
# typecheck=green scope=green lang=green` and a findings section reading "the suite
# passed cleanly on the first attempt" — on an iteration whose suite was red and
# whose ticket was escalated. The document a human reads *instead of* what happened,
# forged, and still carrying its own sentence of provenance.
#
# So an iteration's evidence is not in a place. It is in this shell, in a variable
# it never exports, which is the one thing a process outside this shell's own
# descendance cannot reach: a session inherits an environment, not a shell. That
# asymmetry is [81]'s witness seal one tier up, and the 23/09 pass measured it again
# from the other side — of the seventy variables `bash -c "$TEST_CMD"` receives,
# none is the seal.
#
# **What a variable cannot do is come back out of a subshell, and this pack writes
# eleven of its own sentences from one.** Measured rather than assumed, by
# instrumenting every write over the suite: 11 of 2445. `gate_tree_snapshot` and
# `gate_restore_tree` name what they could not read or could not put back, and every
# caller takes their tree through a command substitution — that is [59]'s shape and
# not an accident — and the three drift witnesses ([46], [52], [70]) are read by the
# loop through one as well. Dropping them was refused: the drift sentences are the
# only account an iteration gets of a capability surface, a program or a human's
# record moving under the run, and [70] promises them on the receipt of the
# iteration in flight.
#
# They travel the way a gate branch's second answer does ([94]): a file in `$TMPDIR`
# opened twice — once to write, once to read from offset zero — and unlinked before
# a byte is written, so the only handles on that inode are the two descriptors this
# shell holds. A subshell inherits them, and `receipt__take` reads the far end back
# into the variable on every call the opening shell makes itself, so a sentence
# written a level down is in the store before anything renders.
#
# The price of a descriptor is that it survives an `exec`. Measured: an inherited
# write end forges a record with one `printf`. So the programs this pack runs and
# did not write — every `claude` it spawns and every command line a project wrote
# ([95]'s census) — are exec'd holding nothing above stderr, by `proc_exec_bare` in
# the child of the fork. **This paragraph said the opposite from [96] on, and
# the suite agreed with it** ([101]): these descriptors were closed by `receipt_shut`,
# a redirection on a function call, and bash keeps a copy of whatever it closes that
# way — the session held the write end on fd 10, wrote one line there, and the line
# was in its own receipt, while the tests asked it about 5 and 4. The guarantee is
# asked of the run and of every descriptor now: a `TEST_CMD`, a session and a review
# lens each try to write a record on every number they could hold, and none of them
# may find one that takes it.
#
# The file has a name from its `mktemp` to its unlink — an external `rm`, a
# millisecond or two — and a process that polls `$TMPDIR` in a loop opens it in
# that instant at every opening and keeps the descriptor: measured on 29/09/2026,
# 270 forged lines in one receipt on the code [96] shipped. **This paragraph listed
# that as a hole until [103]**, and the channel is now served only once `lsof` has
# shown, after the unlink, that nothing but this shell holds the file and that
# nothing was written into it while it had a name; otherwise there is no receipt
# for that iteration, and the run's output says which process held its channel
# (`proc_channel_open`, where the reasons and the limits are written).
#
# A program git runs *for* this pack is exec'd by git, and git is started from this
# very shell: **this paragraph listed that as a hole until [104]**. Since [102] no
# git of the run reads the hook directory; but a hook a session *configures*
# (`hook.<name>.command`) is not a directory, and a sibling iteration past its own
# put-back ran it with these descriptors — fourteen forged lines in a sibling's
# receipt at MAX_PARALLEL=2 — as git ran, holding them, anything the operator's
# `~/.gitconfig` names, which no unset of this repository reaches: 204 lines from a
# `core.fsmonitor` at MAX_PARALLEL=1. Those programs still run; what changed is that
# every git this pack starts holds nothing above stderr (`proc_git`), so they have
# nothing of this shell to inherit.
#
# What this does **not** close, said where it is claimed. On a system that names
# another process's descriptors by path, Linux's `/proc/<pid>/fd`, an unlinked file
# can be reopened by any process of the same user — the session's survivors, or a
# program git ran — after the check of [103] as before it. Not measured away here.
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
#   receipt_branches             the red branches kept, one name per line
#   receipt_branch_text NAME     what that branch had to say
#   receipt_render TICKET        the document on stdout
#   receipt_emit TICKET          render it and hand it to the tracker adapter
#   receipt_close                close the channel and forget the evidence
#
# Everything is a no-op when no receipt is open, so a lib may call `receipt_note`
# unconditionally: the gate and the failure policy both run outside a receipt in
# their own tests, and a module that had to ask first would grow the check in five
# places and forget it in the sixth.

# Whether a receipt is open, and since [96] that is all it is: a word, because
# there is no path to hold. Every public function here is a no-op while it is
# empty, and forty call sites depend on that.
#
# Unconditional since [89]. Nothing exports it, so the `${…:-}` it replaces
# preserved a value from the shell that started the run and nothing else.
RALPH_RECEIPT=''

# The evidence of this iteration, one record per line, `kind<TAB>…`. A variable of
# the iteration's own shell and never exported — that is the whole of what keeps a
# session and its leftovers out of the document ([96], and see the head of this
# file for what it replaces).
RECEIPT_STORE=''

# The subshell level `receipt_open` was called at. Only that shell may take the
# channel's far end into the store: a subshell that read it would advance an offset
# nothing can rewind and then die with what it read, which is the one way this
# design loses a sentence rather than misplacing it.
RECEIPT_LEVEL=''

# The channel a subshell answers on, as literal digits because bash 3.2 has no
# `{var}>` and an `exec` wants a digit. Spent through `eval` in the four places
# that open, shut, close and hand them over, and nowhere else. The numbers left:
# `monitor_watch` has 3, the lens prompt of [94] has 7 and 6, and the gate's note
# channel has 9 and 8.
RECEIPT_CHANNEL_FD=5
RECEIPT_CHANNEL_BACK=4

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

# A `mktemp` name rather than a fixed one: `$TMPDIR` is enumerable, and a fixed name
# is one a watching process can create first. What an unpredictable name does not
# buy is the instant it exists — a process polling `$TMPDIR` without sleeping sees
# it every time — and that is the shared opener's to answer ([103]): this module
# makes the name, `proc_channel_open` opens, unlinks and asks who else holds it.
# Still a line in `gate_tmp_names`, which derives from this very call ([62]): the
# name is composed at the top level of `$TMPDIR`, and that list is about what a call
# can compose, not about how long it lasts.
#
# The guarantee a test can hold this to is the opener's: it never reports a
# receipt whose channel was not opened, unlinked and found alone. Why it was
# refused is in PROC_CHANNEL_REFUSAL, for the caller to say.
receipt_open() {
  local file
  RALPH_RECEIPT=''
  RECEIPT_STORE=''
  RECEIPT_LEVEL=''
  file="$(mktemp "${TMPDIR:-/tmp}/ralph-receipt.XXXXXX")" || file=''
  proc_channel_open "$RECEIPT_CHANNEL_FD" "$RECEIPT_CHANNEL_BACK" "$file" || return 1
  RECEIPT_LEVEL="${BASH_SUBSHELL:-0}"
  RALPH_RECEIPT='open'
  return 0
}

receipt_close() {
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  eval "exec $RECEIPT_CHANNEL_FD>&- $RECEIPT_CHANNEL_BACK<&-" 2>/dev/null || true
  RALPH_RECEIPT=''
  RECEIPT_STORE=''
  RECEIPT_LEVEL=''
  return 0
}

# One record, onto the channel and straight back off it when this is the shell that
# opened the receipt.
#
# Everything goes through the channel, including the writes this shell makes
# itself, and that is deliberate: a store with two ways in would have the rare one
# — the subshell's — exercised by almost nothing, and this pack has paid for
# branches that only a hostile day reaches. It costs no fork: `receipt__take` is
# builtin `read` on a regular file.
#
# Flattened onto one line, and that is not tidiness. Half of what these sentences
# quote comes from outside the pack — a path a session chose, what git printed —
# and a newline inside a value would let that content close the record and open a
# second one under a `kind` of its choosing. The pack's own multi-line notes were
# already two bullets in the document before this, so nothing reads differently.
receipt__put() {
  local line="$1"
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  line="${line//$'\n'/ }"
  line="${line//$'\r'/ }"
  printf '%s\n' "$line" >&"$RECEIPT_CHANNEL_FD" 2>/dev/null || return 0
  receipt__take
  return 0
}

# The channel's far end into the store, from where it was last read to wherever it
# now ends. Refused anywhere but the shell that opened the receipt, for the reason
# `RECEIPT_LEVEL` carries.
receipt__take() {
  local line chunk=''
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  [ "${BASH_SUBSHELL:-0}" = "${RECEIPT_LEVEL:-}" ] || return 0
  while IFS= read -r line; do
    chunk="$chunk$line
"
  done <&"$RECEIPT_CHANNEL_BACK"
  [ -n "$chunk" ] || return 0
  RECEIPT_STORE="$RECEIPT_STORE$chunk"
  return 0
}

# Every record of one kind, the kind stripped off. A reader and therefore a taker:
# a document rendered in a command substitution — which is how the retro reads one
# ([14]) — sees whatever the opening shell has already taken, and the opening shell
# takes on every write it makes.
receipt__records() {
  local kind="$1"
  receipt__take
  awk -F'\t' -v k="$kind" '
    $1 == k { line = $0; sub(/^[^\t]*\t/, "", line); print line }
  ' <<RECORDS
${RECEIPT_STORE:-}
RECORDS
  return 0
}

# One fact. Appended rather than replaced, and read back as the *last* occurrence:
# a fact recorded early and corrected later — an outcome that was `gate-red` until
# the budget classifier looked at it ([43]) — must not need its call site to know
# it was the first one.
receipt_fact() {
  local key="$1"
  shift
  receipt__put "fact"$'\t'"$key"$'\t'"$*"
  return 0
}

receipt__fact() {
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  receipt__take
  awk -F'\t' -v k="$1" '
    $1 == "fact" && $2 == k { line = $0; sub(/^[^\t]*\t[^\t]*\t/, "", line); out = line }
    END { if (out != "") print out }
  ' <<FACTS
${RECEIPT_STORE:-}
FACTS
  return 0
}

# One line the run said out loud, kept in the order it was said.
#
# These are the sentences about what *nothing* judged — the ignored zone ([24]),
# the frontier a session moved ([30], [32]), what the gate itself wrote after the
# tree it judged ([29]), what the language gate did not look at ([17]), what the
# provisioning put in the worktree ([13]) — plus the admissions that are not zeroes
# ([34]). They scroll past on stdout during a night; this is where they last.
receipt_note() {
  receipt__put "note"$'\t'"$*"
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
  receipt__put "gap"$'\t'"$*"
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
  local name="$1" file="$2" total line
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  [ -n "$name" ] && [ -s "$file" ] || return 0
  total="$(awk 'END { print NR + 0 }' "$file")"
  if [ "$total" -gt "$RECEIPT_MAX_LINES" ]; then
    receipt__put "branch"$'\t'"$name"$'\t'"(the first $((total - RECEIPT_MAX_LINES)) line(s) of $total are not kept here: this branch is quoted from the end)"
    receipt__put "branch"$'\t'"$name"$'\t'
  fi
  # One record per line of output, which is what makes a branch'"'"'s text fit a store
  # of lines at all — and it is also what keeps this the one source here that cannot
  # forge a record: a line of a file has no newline in it to close one with.
  while IFS= read -r line; do
    receipt__put "branch"$'\t'"$name"$'\t'"$line"
  done <<LINES
$(tail -"$RECEIPT_MAX_LINES" "$file")
LINES
  receipt__put "branches"$'\t'"$name"
  return 0
}

# What was kept, for a reader that is not the document.
#
# Public since [14], and the reason is the rule this pack keeps rather than a
# preference: the retry channel needs the same copy the document renders, and a
# second consumer of a `__` is an interface whose name lies. It is the same copy
# on purpose — the whole of [10]'s half of [06] is that a red lens's findings
# survive the gate *here* and nowhere else, so a channel that re-read them from
# somewhere would be re-reading a stream that no longer exists, or `run.log`,
# which the judged session can rewrite.
receipt_branches() {
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  receipt__records branches
}

receipt_branch_text() {
  [ -n "${RALPH_RECEIPT:-}" ] || return 0
  receipt__take
  awk -F'\t' -v n="$1" '
    $1 == "branch" && $2 == n { line = $0; sub(/^[^\t]*\t[^\t]*\t/, "", line); print line }
  ' <<BRANCH
${RECEIPT_STORE:-}
BRANCH
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
    not-marked)
      printf 'The gate on `%s` was green, the work reached the branch, and the tracker refused to mark the ticket resolved ([74]). Read the verdicts below as this run'"'"'s verdict on the code — they are the same ones a `resolved` iteration would carry — and read the ticket itself for where the refusal left it: on a backend that waits for a pipeline, a red one escalates it to a human and this is what that looks like from here.\n' "$ticket"
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
  # The third layer, by path and never by content ([10] on [11]). A receipt is
  # per ticket and the retention deletes it; a playthrough is per feature and
  # outlives every receipt, so quoting it here would make the proof that a feature
  # works a paragraph of a document that expires. Named only when it is there: a
  # line pointing at a file nobody wrote reads like a document somebody deleted.
  # The one from the *previous* round is the interesting case rather than an
  # accident of ordering — a wiring ticket exists because that playthrough was
  # red, and this is where its reader is told so.
  if [ -f "$(playthrough_path)" ]; then
    printf -- '- what this feature does once it runs, as of the last empty frontier: `%s`. Per feature, not per ticket, and it outlives this receipt.\n' \
      "$(playthrough_path)"
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
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    # A name whose kept output never made it to disk — `receipt_keep_branch`
    # tolerates a failed write — is not a heading with nothing under it.
    [ -n "$(receipt_branch_text "$name")" ] || continue
    if [ "$printed" = 0 ]; then
      printf '## Findings\n\n'
      printf 'What each red branch had to say. For a review lens this is the only copy: the prompt and the stream live in the gate'"'"'s temporary directory, and the gate removes it.\n\n'
      printed=1
    fi
    printf '### %s — red\n\n' "$name"
    receipt_branch_text "$name" | sed 's/^/    /'
    printf '\n'
  done <<BRANCHES
$(receipt_branches)
BRANCHES
  return 0
}

# What this iteration was going to do and did not ([45]). Absent when nothing was
# recorded, which is the one thing this section is entitled to mean: these are
# events, and no event of this kind was seen.
receipt__gaps() {
  local gaps
  gaps="$(receipt__records gap)"
  [ -n "$gaps" ] || return 0
  printf '## What did not happen\n\n'
  printf 'Things this run set out to do and could not. None of them is a verdict on the code, and each of them means some other line of this document is narrower than it looks — a tree that is not back where the session found it, a reference that was promised and not written.\n\n'
  printf '%s\n' "$gaps" | sed 's/^/- /'
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
  local provisioned notes
  provisioned="$(receipt__fact provisioned)"
  notes="$(receipt__records note)"
  case "$provisioned" in '' | 0) provisioned='' ;; esac
  if [ -z "$notes" ] && [ -z "$provisioned" ]; then
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
  [ -z "$notes" ] || printf '%s\n' "$notes" | sed 's/^/- /'
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
  printf 'Assembled by the process that measured this iteration, from the gate'"'"'s own verdicts, the branch output it collected before removing its temporary directory, and the objects the loop wrote. It does **not** read `run.log`: that file lives under `.scratch/`, which no check in this pack guards, so the session this receipt is about can rewrite it.\n\n'
  # And where it was *assembled*, which until [96] this paragraph did not say and
  # the head of `lib/receipt.sh` got wrong ([24]: named on every iteration, not
  # once in a document somebody has to go and find).
  printf 'Assembled nowhere a name reaches: the evidence above was held in a variable of the shell that measured this iteration and on a descriptor of a file unlinked before a byte was written to it — a file used only once `lsof` had shown, after the unlink, that nothing but that shell held it and that nothing had been written into it in the instant it had a name ([103]) — and every program this run launched without having written it — the session, the project'"'"'s commands, and git, with whatever its configuration makes it run: a configured hook, a `core.fsmonitor`, from this repository or from the operator'"'"'s `~/.gitconfig` ([104]) — was started holding nothing but its stdin, stdout and stderr, and the hook *directory* is read by no git of this run at all ([102]). So neither the session this receipt is about nor anything it left running could reach it, with the exceptions this run did not close: a descriptor in flight between two processes in a socket message at the instant of that check, which it cannot see and nobody measured; and, on a system that names another process'"'"'s descriptors by path such as Linux'"'"'s `/proc`, any process of the same user, after that check as before it.\n\n'
  # The half this does not hold, in the same breath as the half it does. A document
  # that claimed both would be back where [96] found it.
  printf 'One source above is not of that kind, and here is where that is said rather than left to be found: the quoted output of a red branch under **Findings** is read from a file in the gate'"'"'s temporary directory, which a process of this run can write to ([94] measured the bound that was refused, and why). Since [92] nothing in that file is a verdict — those come from the branches'"'"' own exit statuses — so what a process writing there buys is the wording of that section, and never a colour.\n'
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
