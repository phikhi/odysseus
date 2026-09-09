# shellcheck shell=bash
# The record a human is sent to read about a ticket, and what says when it moved.
#
# Everything else this pack judges is a path in the tree an iteration works in.
# These are not. They are what the loop leaves behind for somebody to read the
# next morning, they live where no tree of an iteration reaches, and until [70]
# a **green** iteration could create, move or destroy any of them without one
# word being said anywhere:
#
#   refs/heads/failed/<id>        the tree of a judged attempt, written by
#                                 `failures_preserve_attempt` ([07]). A ref is a
#                                 path in no working tree at all, and a worktree
#                                 shares the common git directory — so a session
#                                 in an iteration's worktree writes the same refs
#                                 the main tree does, and no scope-guard, no
#                                 rollback, no seal and no receipt names one.
#   receipts/<feature>/<id>.md    the audit receipt ([10]), written in the **main**
#                                 working tree, which `git worktree list` names to
#                                 anyone who asks and which is not the tree the
#                                 scope-guard compares.
#   docs/playthroughs/<feature>.md  what the feature does once it runs ([11]).
#                                 Same zone, same reach, and on this list because
#                                 the criterion says so and not because a probe
#                                 measured it ([31], [45]): a correction that
#                                 covered the two objects the drain's dossier
#                                 shows and left the third would be narrower than
#                                 the sentence justifying it.
#
# The criterion, so that a fourth object is added by reading it rather than by
# waiting for a defect: **what this pack writes durably, outside every tree it
# judges, for a human to read after the run is over.** Two members of that family
# are already witnessed elsewhere and are deliberately not here — `LEARNINGS.md`,
# which [14] copies before the first session because the *loop* reads it back, and
# `run.log`, whose own lines each entry point counts (`loop_journal_verify`) and
# which the human sink presents with its reserve since [67].
#
# ## What this is and what it is not
#
# A **witness**, exactly like [14]'s and [15]'s and never a control. It does not
# prevent: nothing here reaches into the git directory to put a ref back. It does
# not refuse: no run and no drain is stopped over one of these, and that is the
# posture [66], [67], [68] and [69] all took for the same reason — a guard that
# could stop a drain on a ref would hand a session a `git update-ref` to send home
# the human who came to empty the sink. It does not put anything back: this pack
# is not the author of a forged ref, the commit a ref named may already be
# unreachable, and a restore that invents is a second author for a state nobody
# measured ([66], word for word).
#
# What it buys is that the run in which it happened says so, on the two documents
# a morning reader has — and that is all it buys. A forgery laid down by a run
# nobody has started since is still in this run's baseline, which is why [70] also
# put the reserve on the dossier itself: form (1) without form (3) would trade one
# silence for a narrower one.
#
# ## Why a register, and what it excuses
#
# The pack writes these objects itself, so a witness alone would report the loop's
# own work as drift. What separates them is a register of what the pack is **about
# to** write, appended before the write and never after: a sibling iteration
# comparing in between then finds the key already registered, where a register fed
# after the fact would have a window in which one iteration accuses another of the
# receipt it just emitted.
#
# It is written by `loop.sh` and not by the modules that do the writing, which
# keeps `failures.sh` and `receipt.sh` from having to know this file exists — and
# it is entered on the two calls that write, not on every iteration: an iteration
# that ends green registers no `failed/<id>`, so a green session forging the ref
# of its own ticket is named like any other.
#
# What that excuses, written down rather than discovered later: a session that
# forges the object of a ticket the pack overwrites in the same iteration. The
# pack's own write lands on top, and what a human reads afterwards is the pack's.
#
# ## The fourth zone, which is not one of these
#
# [77] added one, and it is here rather than in the manifest below because it is
# not the same kind of object. On a backend whose tickets and receipts are not
# files of this repository, what *is* a file of this repository is the record of
# **where they are** and **who holds them** — the claim's liveness, the number of
# the open request, and the URL the human sink shows as the receipt. The adapter
# owns that file, so the adapter witnesses it (`tracker_sidecar_witness`) and the
# adapter says what moved under it (`tracker_sidecar_drift`); this module takes
# the baseline at the same instant as its own, and passes the lines on through the
# same two channels, so that a run has one place where it says what moved.
#
# Why the adapter and not a fourth arm of `forensic__manifest`: that file is read
# for an **answer** and not only shown to a human, so the ticket's repair is a run
# that reads its own copy of it. A witness here would have named the forgery and
# obeyed it.
#
# Public API
#   forensic_failed_refs         every `refs/heads/failed/*`, `<oid><TAB><ref>`;
#                                non-zero when git would not answer
#   forensic_witness DIR         the run's baseline, before any session exists
#   forensic_uncovered           one sentence per zone this witness cannot cover
#   forensic_expect DIR KIND ID  what the pack is about to write, before it writes
#   forensic_drift DIR           what moved that the pack did not write, as
#                                `subject<TAB>outcome<TAB>message`

# Every `refs/heads/failed/*` this repository holds, `<objectname><TAB><refname>`,
# one per line and in refname order — `for-each-ref` sorts by refname, which is
# what makes two readings say things in the same order.
#
# The whole refname and not the id: `%(refname:lstrip=3)` renders a bare
# `refs/heads/failed` as an empty id, and what a human is told to read is a ref
# name anyway. The name goes **last** for [37]'s reason — everything before the
# tab is read by position — and here that costs nothing, because git refuses
# control characters in a refname and the tab cannot be inside one.
#
# **Non-zero when git would not answer, and a caller must tell that from an empty
# namespace** ([59]). Read as an empty list, a refusal turns every ref a witness
# holds into a ref a session deleted, and the sentence for that accuses somebody
# of destroying evidence. `router_pin` reads it as empty on purpose and
# `router_branch_note` refuses on it, and the asymmetry is which mistake each one
# would make: the pin degrades to the reading `router.sh` had before [66], the
# note would make an accusation out of a machine that answered nothing. This
# file's own two readers take the second posture — no witness and no comparison
# rather than a manifest that lies about a namespace.
#
# Here rather than in `router.sh`, where [66] wrote it: it now has two callers in
# two layers — the drain, and the witness a run takes before its first session —
# and a second copy of the same `for-each-ref` would be a second place for the
# refusal clause above to be forgotten in.
forensic_failed_refs() {
  git for-each-ref --format='%(objectname)%09%(refname)' \
    refs/heads/failed/ 2>/dev/null
}

# Where this backend keeps audit receipts, or non-zero when it does not keep them
# in a directory at all. The adapter answers, for `tracker_receipt_path`'s reason:
# a caller that built the path itself would be a second author for that layout.
forensic__receipt_dir() {
  local dir
  dir="$(tracker_receipt_dir 2>/dev/null)" || return 1
  [ -n "$dir" ] || return 1
  printf '%s\n' "$dir"
  return 0
}

# The same question one zone over, and it is not a zone this file witnesses: the
# tickets. Asked here because `forensic_uncovered` is the one place a run says out
# loud what nothing in it covers, and because the answer decides a sentence a human
# reads rather than anything this module compares.
forensic__tickets_dir() {
  local dir
  dir="$(tracker_tickets_dir 2>/dev/null)" || return 1
  [ -n "$dir" ] || return 1
  printf '%s\n' "$dir"
  return 0
}

# Where the adapter keeps the local facts it has about tickets, or non-zero when
# it keeps none. Asked of the adapter for `forensic__receipt_dir`'s reason, and
# never composed here.
forensic__sidecar() {
  local file
  file="$(tracker_sidecar_path 2>/dev/null)" || return 1
  [ -n "$file" ] || return 1
  printf '%s\n' "$file"
  return 0
}

# The feature's playthrough, or nothing when this shell has no feature to name
# one for. Asked of `playthrough.sh` rather than composed here, for the reason
# above.
forensic__playthrough() {
  [ -n "${FEATURE:-}" ] || return 1
  playthrough_path 2>/dev/null || return 1
  return 0
}

# One number for one file, in **three** states and not two. A path that is not
# there digests to `-`, which is an answer and not a failure: a receipt that did
# not exist when this run started and exists now is exactly the event this is for.
#
# The third state is [59]'s rule applied to a digest rather than to a list. A file
# that is there and cannot be read — chmod'ed, replaced by a directory — would
# digest to `-` under the obvious spelling, and `-` is the answer for "not there":
# the comparison would then say the evidence is *gone* and accuse somebody of
# destroying it, over a document still sitting where it was. `?` says what
# happened instead, and still differs from every real digest, so the event is
# reported and only the sentence changes.
#
# `[ -f ]` first and never `cksum <"$1"` alone, for the reason [52] paid for: `-`
# is also a file name, and a working directory holding one would digest it.
forensic__digest() {
  local sum=''
  if [ -f "$1" ]; then
    sum="$(cksum <"$1" 2>/dev/null | awk '{ print $1 "." $2 }')" || sum=''
    [ -n "$sum" ] || sum='?'
  elif [ -e "$1" ]; then
    sum='?'
  fi
  [ -n "$sum" ] || sum='-'
  printf '%s\n' "$sum"
  return 0
}

# The live state of all three zones, `kind<TAB>key<TAB>digest`.
#
# Non-zero when git would not list the refs, and that propagates all the way up:
# a manifest missing its whole first zone would read as a namespace a session
# emptied.
#
# The playthrough is emitted whether or not it exists, because its key is fixed
# and its appearance is an event; a receipt and a ref have no fixed key, so their
# absence is an absent line and their appearance is a line the witness has not
# got. A receipt file whose name carries a newline arrives here as two keys
# neither of which resolves, so it is reported as two things that appeared with
# nothing to read — louder than silence, which is the direction to err in when a
# name cannot travel in a witness ([39], [52]).
forensic__manifest() {
  local refs dir line file listing tab
  tab="$(printf '\t')"

  refs="$(forensic_failed_refs)" || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf 'ref\t%s\t%s\n' "${line#*"$tab"}" "${line%%"$tab"*}"
  done <<REFS
$refs
REFS

  # Every entry under the directory and not only its regular files, which is the
  # criterion read literally: what this is about is a name the human sink points
  # at, and a receipt replaced by a directory of the same name is not a receipt
  # that was *deleted* — under `-type f` it would leave the listing altogether and
  # be reported as evidence somebody destroyed. `-mindepth 1` and not a bare walk
  # so the directory itself is not one of its own contents.
  #
  # `[ -d ]` before the walk and the walk's own status after it, both for [59]'s
  # reason at one turn lower: a directory that is not there yet has no receipts in
  # it, which is an answer, and a `find` that **refused** one that is there is not
  # the same fact at all — read as an empty listing it turns every receipt this run
  # started with into a receipt somebody deleted.
  if dir="$(forensic__receipt_dir)" && [ -d "$dir" ]; then
    listing="$(find "$dir" -mindepth 1 2>/dev/null)" || return 1
    while IFS= read -r file; do
      [ -n "$file" ] || continue
      printf 'receipt\t%s\t%s\n' "$file" "$(forensic__digest "$file")"
    done <<RECEIPTS
$(printf '%s\n' "$listing" | LC_ALL=C sort)
RECEIPTS
  fi

  if file="$(forensic__playthrough)"; then
    printf 'playthrough\t%s\t%s\n' "$file" "$(forensic__digest "$file")"
  fi
  return 0
}

# The run's baseline, into the run's own witness directory — the one
# `gate_frontier_common` makes, in `$TMPDIR` under a `mktemp` name the pilot never
# exports ([30], [40]). One per **run** and taken before the first session of the
# night exists, which is the whole of what makes a difference afterwards
# attributable to this run at all.
#
# Refuses rather than writes half a witness: a baseline missing a zone is one
# whose comparison accuses a session of emptying it.
forensic_witness() {
  local dir="${1:-}" manifest
  [ -n "$dir" ] && [ -d "$dir" ] || return 1
  manifest="$(forensic__manifest)" || return 1
  printf '%s\n' "$manifest" >"$dir/forensic.witness" 2>/dev/null || return 1
  : >"$dir/forensic.written" 2>/dev/null || return 1
  # And the adapter's own zone, at the same instant and for the same reason
  # ([77]). Asked only of a backend that says it keeps one: a refusal from
  # `sidecar_path` is "there is no such file", which is the local backend's
  # answer and not a failure, while a backend that has one and cannot be copied
  # is a run whose tracker's liveness it holds no copy of — the same refusal the
  # manifest gives, for the same reason.
  if tracker_sidecar_path >/dev/null 2>&1; then
    tracker_sidecar_witness "$dir" || return 1
  fi
  return 0
}

# The zone this witness does not cover on this backend, as the sentence a run says
# out loud once. A control that excludes a zone has to name who guards it, and on
# a backend whose receipts are not files nothing here does: the dossier of the
# human sink still points a human at one.
#
# Non-zero when there is nothing to say, so a caller reads it like every other
# event channel in this pack ([45]).
forensic_uncovered() {
  local said=1
  if ! forensic__receipt_dir >/dev/null 2>&1; then
    printf 'this backend does not keep audit receipts in a directory, so nothing in this run witnesses them: a receipt the human sink points at is attested by nothing here, and a receipt that is a pull request is an object a session reaches over the network, which no scope-guard, no rollback and no witness of this pack sees ([18])\n'
    said=0
    # And what *is* in this tree on such a backend, said in the same breath so
    # that the sentence above is not read as "nothing local is held" ([77]).
    # Where that receipt is, and who holds the ticket, are records of a file of
    # this repository that a session appends to: this run reads its own copy of
    # them and names what it did not write, and the file itself is still whatever
    # the last line says to anybody reading it outside a run — the human sink
    # included, which is why its dossier names the file.
    if forensic__sidecar >/dev/null 2>&1; then
      printf 'where that receipt is, and who holds a ticket, are records this backend keeps in %s — a file of this tree that no scope-guard judges and no rollback undoes: this run reads the copy it took before its first session and names any record it did not write, which puts nothing back and stops nothing ([77])\n' \
        "$(forensic__sidecar)"
    fi
  fi
  # The tickets, and it is a different guarantee under the same sentence ([18]).
  # `failures_protect_tracker` restores what a session wrote in the tracker by
  # comparing two git trees of the directory the tickets live in, and that is what
  # makes the write-surface the scope-guard judges against the contract as it stood
  # at spawn time. A backend that keeps its tickets elsewhere has no such directory:
  # the guard takes its "nothing here to compare" branch, nothing is restored, and
  # this line is the whole of what the run says about it. Said here rather than by
  # the guard because the guard runs once per iteration and this is a property of
  # the night — [64]'s lesson about eight identical lines on a console.
  if ! forensic__tickets_dir >/dev/null 2>&1; then
    printf 'this backend does not keep its tickets in a directory of this repository, so nothing here restores what a session writes in the tracker: the write-surface the scope-guard judges against is read from a ticket the session it judges can reach, and the two tree snapshots taken around every session compare nothing ([18] on [21])\n'
    said=0
  fi
  [ "$said" = 0 ] || return 1
  return 0
}

# The key one of the pack's own writes lands on. Composed here and by nothing
# else, so that the register and the manifest cannot name the same object two
# ways — a register entry that missed by one character would excuse nothing and
# say nothing about it.
forensic__key() {
  local kind="${1:-}" id="${2:-}" dir
  case "$kind" in
    ref)
      [ -n "$id" ] || return 1
      printf 'refs/heads/failed/%s\n' "$id"
      ;;
    receipt)
      [ -n "$id" ] || return 1
      dir="$(forensic__receipt_dir)" || return 1
      printf '%s/%s.md\n' "$dir" "${id%.md}"
      ;;
    playthrough)
      forensic__playthrough || return 1
      ;;
    *) return 1 ;;
  esac
  return 0
}

# What the pack is about to write. Appended **before** the write and never after:
# see the header on why the order is the guarantee.
#
# Silent and zero on everything it cannot do — no witness directory, a backend
# with no receipt directory, a kind it does not know. A register that refused
# would turn a witness into a control, which is exactly what this is not.
forensic_expect() {
  local dir="${1:-}" key
  [ -n "$dir" ] && [ -f "$dir/forensic.written" ] || return 0
  shift
  key="$(forensic__key "$@")" || return 0
  printf '%s\n' "$key" >>"$dir/forensic.written" 2>/dev/null || true
  return 0
}

# What moved under the witness that this run did not write, `kind<TAB>key<TAB>was
# <TAB>now`. Non-zero when nothing did, which is every ordinary night.
#
# Nothing here updates the witness, so an object that moved is reported by this
# iteration and by every iteration after it — the same shape as `capability_drift`
# and `gate__path_moved`, and for the same reason: there is no restore, so the
# difference is still true the next time somebody asks.
#
# One `awk` and no temporary file, which is a constraint and not a flourish: every
# name this pack composes in `$TMPDIR` is on `gate_tmp_names` and swept by the
# installer, and a witness that had to add one would have made that list wider for
# a file that lives for two milliseconds.
forensic__moved() {
  local dir="${1:-}" live moved
  [ -n "$dir" ] && [ -s "$dir/forensic.witness" ] || return 1
  live="$(forensic__manifest)" || return 1
  moved="$(awk -F'\t' -v OFS='\t' \
    -v reg="$dir/forensic.written" -v wit="$dir/forensic.witness" '
    BEGIN {
      while ((getline line < reg) > 0) { if (line != "") skip[line] = 1 }
      while ((getline line < wit) > 0) {
        if (split(line, f, "\t") < 3) continue
        kind[f[2]] = f[1]; was[f[2]] = f[3]
      }
    }
    NF >= 3 { kind[$2] = $1; now[$2] = $3 }
    END {
      for (k in kind) {
        if (k in skip) continue
        w = (k in was) ? was[k] : "-"
        n = (k in now) ? now[k] : "-"
        if (w == n) continue
        print kind[k], k, w, n
      }
    }' <<MANIFEST | LC_ALL=C sort
$live
MANIFEST
  )" || return 1
  [ -n "$moved" ] || return 1
  printf '%s\n' "$moved"
  return 0
}

# One clause naming what moved and what it costs, so that the iteration's sentence
# and the receipt's describe the same event in the same words. Three kinds times
# three directions, because "moved" is a different fact each time and a reader
# acts on them differently: something appeared that no run wrote, something a run
# wrote is gone, or the name still resolves and no longer names what it did.
forensic__clause() {
  local kind="${1:-}" key="${2:-}" was="${3:--}" now="${4:--}"
  case "$kind:$was:$now" in
    # First, and the quotes are the control: `?` is a glob metacharacter in a
    # `case` pattern, and unquoted this arm would match every three-field key
    # whose last field is one character long. It is first because it is the one
    # state where the sentences below would all be wrong — the object is still
    # sitting where the human sink points, and nothing here can say what is in it.
    *:*:'?')
      printf '`%s` is a name this run cannot read: it is not a file any more, or its mode changed under this run. The human sink still sends somebody to that name, and nothing here can say what it now holds\n' \
        "$key"
      ;;
    ref:-:*)
      printf '`%s` was written while this run was in flight, and no iteration of this run wrote it. A `failed/<id>` ref is written by a run that judged an attempt and by nothing else: it is what sends a `decision` ticket to the `arbitrate` desk of the human sink, and what the dossier tells a human to go and read. Nothing here removes it, and no gate judged the tree it names\n' \
        "$key"
      ;;
    ref:*:-)
      printf '`%s` is gone, and it pointed at `%s` when this run started. That ref is the tree of an attempt a run judged and rolled back, and it is the one piece of evidence about a ticket that outlives a `gc` — a receipt names git objects a `gc` may collect, a ref does not. The evidence is lost and not moved: a drain reading that ticket now finds no branch at all, and on a `decision` that is the sentence saying nothing ever ran on it\n' \
        "$key" "$was"
      ;;
    ref:*)
      printf '`%s` points at `%s` and pointed at `%s` when this run started. The ref is still there, so the human sink still sends somebody to read it — at a tree no run judged\n' \
        "$key" "$now" "$was"
      ;;
    receipt:-:*)
      printf '`%s` appeared while this run was in flight, and this run did not emit it. The human sink shows a receipt as the verdicts, the findings and the zones nothing judged of a ticket it finished with; this one is a document whose author nothing here can name\n' \
        "$key"
      ;;
    receipt:*:-)
      printf '`%s` is gone, and this run did not remove it. It was the asynchronous review surface of a ticket a run finished with, and the human sink now says no receipt was kept for that ticket\n' \
        "$key"
      ;;
    receipt:*)
      printf '`%s` is not the document this run started with, and this run did not rewrite it. The human sink shows it as an audit receipt — verdicts, findings, and the zones nothing judged — and what a human reads there now is not what the run that wrote it said\n' \
        "$key"
      ;;
    playthrough:-:*)
      printf '`%s` appeared while this run was in flight, and no value gate of this run wrote it. That document is what a human reads in the morning as the proof the feature does something ([11])\n' \
        "$key"
      ;;
    playthrough:*:-)
      printf '`%s` is gone, and no value gate of this run removed it. The proof that this feature does anything is no longer anywhere\n' \
        "$key"
      ;;
    *)
      printf '`%s` is not the document this run started with, and no value gate of this run rewrote it. What a human reads as the proof this feature does something is not what the run that measured it wrote\n' \
        "$key"
      ;;
  esac
  return 0
}

# The iteration's channel: `subject<TAB>outcome<TAB>message`, the shape
# `capability_drift` and `gate_path_drift` already use, and a `receipt_gap` on the
# way past.
#
# Two documents and not one, for [46]'s reason: the receipt is emitted on four
# routes only, so an iteration ending on a fresh retry produces none — and a run
# that *stops* there has no later iteration coming to produce one either. The line
# goes back to the caller because `run.log` belongs to the pilot and this runs in
# an iteration's shell.
#
# A gap and not a note: this is an event channel, silent when no such event was
# recorded, which is all it ever claims ([45]).
#
# The subject carries the key — a ref name or an absolute path — and never the
# word `receipt`, which is [15]'s lesson taken rather than repeated: `run.log` is
# the only durable document on the iteration a run stops on, and a line reading
# `receipt forensic-drift` sends a human looking without saying where.
forensic_drift() {
  local dir="${1:-}" kind key was now clause subject outcome message
  while IFS="$(printf '\t')" read -r kind key was now; do
    [ -n "$key" ] || continue
    clause="$(forensic__clause "$kind" "$key" "$was" "$now")"
    receipt_gap "the record the human sink sends somebody to read moved while this run was in flight: $clause — nothing here judged it, no rollback undoes it, and nothing puts it back"
    printf '%s\t%s\t%s\n' "$key" forensic-drift "$clause"
  done <<MOVED
$(forensic__moved "$dir" || true)
MOVED
  # And the adapter's zone, passed on unchanged ([77]). The sentence is the
  # adapter's because only it knows what one of its records decides; both
  # channels are this module's, so an iteration has one reading and a run one
  # place that says what moved under it.
  while IFS="$(printf '\t')" read -r subject outcome message; do
    [ -n "$subject" ] || continue
    receipt_gap "$message"
    printf '%s\t%s\t%s\n' "$subject" "${outcome:-sidecar-drift}" "$message"
  done <<SIDECAR
$(tracker_sidecar_drift "$dir" 2>/dev/null || true)
SIDECAR
  return 0
}
