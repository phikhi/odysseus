# shellcheck shell=bash
# The `local` tracker backend: markdown files under .scratch/<feature>/issues/.
#
# State lives in the ticket and nowhere else. Reading the directory rebuilds
# everything a run needs — which is what makes a fresh session possible, and
# what makes a crashed run recoverable.
#
# Fields, read tolerantly (`**Name:** v` or `Name: v`) and always written back
# in the bold form:
#
#   Status:         ready-for-agent | claimed | resolved | ready-for-human
#                   | needs-triage | needs-info | wontfix
#   Blocked by:     None, or ticket numbers — unblocked means all resolved
#   Claimed:        owner=<who> at=<iso8601>
#   Escalation:     why it went to the human sink
#   Failures:       how many fresh retries it has burned, since it was last
#                   delivered — a resolution clears it
#   Write-surface:  what it is allowed to touch

tracker_local__issues_dir() {
  printf '%s/issues\n' "$(ralph_feature_dir)"
}

# ── the one name that is not an id ───────────────────────────────────────────
#
# Unix lets a file name carry a newline. An id may not carry one: since [37]
# every list of ids in this pack travels one id per line and is compared whole
# lines, which is what closed the space and the glob metacharacter and is also
# what leaves this open — the convention *is* the separator. Those two facts meet
# in this directory, whose file names are chosen by a session or by a human, and
# the meeting used to be silent. `99-a<LF>b.md` came out of the scans below as
# **two** ids the tracker does not hold; both entered the frontier where neither
# could be claimed, so the run ground nothing and stopped sterile; and
# `failures_quarantine_strays` announced `quarantined 99-a, b` having escalated
# nothing at all, the file itself staying `ready-for-agent` with whatever
# write-surface the session gave it. A control that reports an action it never
# took is exactly what `docs/frontiere-de-confiance.md` exists to catch.
#
# **The decision is to refuse, and it is written down rather than implied** ([48]).
# Carrying the name instead needs a NUL-delimited transport — `read -d ''`,
# `find -print0` — in every reader of every id list, and it was probed before
# being refused (30/08/2026). The *git* reader of this directory is already
# correct: git quotes such a name whatever `core.quotePath` says, so it arrives as
# **one** line, and `failures_protect_tracker` names it and refuses to vouch for
# the tracker over it ([39] via [21], [49]) — an iteration that meets one cannot
# be green. Carrying it would therefore buy only the ability to grind a ticket
# another guard of the same run already refuses, at the price of making every list
# in the pack NUL-separated for a name no project has.
#
# So a name that is not one line is not an id here, and no operation of this
# backend hands one out (`frontier`, `ids`), resolves one (`__path`), or lets one
# decide the answer about a name that *is* an id (`__number_taken`,
# `__slug_taken`, the carrier count of a renumber). What that leaves is a file the
# pack cannot reach, named out loud rather than skipped in silence, and the trust
# table carries the line.
#
# The one place a name like this still moves something is `tracker_local__next_nn`,
# and it is left alone knowingly: that function reads `ls` output through a sed
# that matches `NN-slug.md` on a whole line, so `12<LF>99-x.md` offers it `99-x.md`
# as if it were a ticket and the next number jumps past 99. It costs skipped
# numbers and nothing else — the number is still checked against the directory
# before it is used, and `__path` no longer resolves to the file that suggested it.
tracker_local__addressable() {
  # `$'\n'` and not `$(printf '\n')`: a command substitution strips trailing
  # newlines, so the second spelling would compare against the empty string and
  # every name would match.
  case "$1" in
    *$'\n'*) return 1 ;;
  esac
  return 0
}

# Said by the two scans that would otherwise hand the name out as an id, on every
# scan that meets one — and the repetition is the decision, not an oversight.
#
# A ticket nobody can reach is worse than a ticket nobody can grind if nothing
# says so, and the line has to survive being printed from a subshell: every
# consumer reads these lists as `$(tracker_ids)`, so a "say it once" flag kept in
# a variable would be forgotten between two callers and would quietly say it
# never. The name is rendered with its newline escaped, because a message that
# printed the raw name would arrive as two lines and reproduce the very defect it
# reports.
tracker_local__refuse_name() {
  printf 'tracker: "%s" carries a newline in its name — that is not an id this backend hands out and nothing in the pack can address it, so it is on no frontier and no scan of the tracker sees it. Rename it.\n' \
    "${1//$'\n'/\\n}" >&2
}

# Accepts `01`, `01-alpha` or `01-alpha.md`.
#
# A bare number that matches more than one ticket is refused rather than
# resolved to whichever file sorts first: dependencies are written as bare
# numbers (`Blocked by: 01`), so a silent pick would block — or unblock — the
# wrong ticket, and nothing downstream would ever notice.
tracker_local__path() {
  local id="${1%.md}" dir file hit='' matches=0
  # Both halves of [48], and the second is the one that matters to a ticket that
  # did nothing wrong: an id nothing can address resolves to nothing, and a file
  # nothing can address is not one of the carriers that make a bare number
  # ambiguous. Without that, one `99-a<LF>b.md` in the directory took `99` — and
  # every ticket holding `Blocked by: 99` — out of the frontier for good ([27]),
  # over a file no scan sees and no quarantine can renumber.
  tracker_local__addressable "$id" || return 1
  dir="$(tracker_local__issues_dir)"
  if [ -f "$dir/$id.md" ]; then
    printf '%s\n' "$dir/$id.md"
    return 0
  fi
  for file in "$dir/$id"-*.md; do
    [ -e "$file" ] || continue
    tracker_local__addressable "$file" || continue
    hit="$file"
    matches=$((matches + 1))
  done
  if [ "$matches" -gt 1 ]; then
    printf 'tracker: "%s" matches %s tickets — an ambiguous id is never safe to resolve\n' \
      "$id" "$matches" >&2
    return 1
  fi
  [ "$matches" = 1 ] || return 1
  printf '%s\n' "$hit"
}

# Trailing blanks are trimmed, and [[:space:]] covers the carriage return a
# CRLF file leaves behind. Without that trim, a tracker checked out on Windows —
# or a status line with one stray space after it — matches nothing, drops out of
# the frontier, and the run reports success having done nothing at all.
tracker_local__field_of_file() {
  sed -n "s/^\*\*$2:\*\*[[:space:]]*//p; s/^$2:[[:space:]]*//p" "$1" |
    awk 'NR == 1 { sub(/[[:space:]]+$/, ""); print }'
}

tracker_local__has_field() {
  grep -q -e "^\*\*$2:\*\*" -e "^$2:" "$1"
}

tracker_local_field() {
  local file
  file="$(tracker_local__path "$1")" || return 1
  tracker_local__field_of_file "$file" "$2"
}

tracker_local_read_ticket() {
  local file
  file="$(tracker_local__path "$1")" || return 1
  cat "$file"
}

# ── writing ──────────────────────────────────────────────────────────────────

# Set (or drop, with the value --drop) any number of fields, publishing the
# result in a single rename. Callers never see a half-updated ticket.
tracker_local__set_fields() {
  local id="$1"
  shift
  local file work
  file="$(tracker_local__path "$id")" || return 1
  work="$(mktemp "${file}.work.XXXXXX")" || return 1
  cp "$file" "$work"
  while [ "$#" -ge 2 ]; do
    if [ "$2" = "--drop" ]; then
      tracker_local__drop_field "$work" "$1"
    else
      tracker_local__patch_field "$work" "$1" "$2"
    fi || {
      rm -f "$work"
      return 1
    }
    shift 2
  done
  mv -f "$work" "$file"
}

tracker_local__patch_field() {
  local file="$1" name="$2" value="$3" tmp="$1.p"
  if tracker_local__has_field "$file" "$name"; then
    awk -v n="$name" -v v="$value" '
      !done && (index($0, "**" n ":**") == 1 || index($0, n ":") == 1) {
        print "**" n ":** " v
        done = 1
        next
      }
      { print }
    ' "$file" >"$tmp" || return 1
  else
    # A new field goes right below Status:, where a reader looks for it.
    awk -v n="$name" -v v="$value" '
      { print }
      !done && (index($0, "**Status:**") == 1 || index($0, "Status:") == 1) {
        print ""
        print "**" n ":** " v
        done = 1
      }
      END { if (!done) { print ""; print "**" n ":** " v } }
    ' "$file" >"$tmp" || return 1
  fi
  mv -f "$tmp" "$file"
}

tracker_local__drop_field() {
  local file="$1" name="$2" tmp="$1.p"
  awk -v n="$name" '
    index($0, "**" n ":**") == 1 || index($0, n ":") == 1 { skip = 1; next }
    skip == 1 && $0 == "" { skip = 0; next }
    { skip = 0; print }
  ' "$file" >"$tmp" || return 1
  mv -f "$tmp" "$file"
}

# ── the seven operations ─────────────────────────────────────────────────────

tracker_local_frontier() {
  local dir file id
  dir="$(tracker_local__issues_dir)"
  if [ ! -d "$dir" ]; then
    # Says so instead of reporting an empty frontier: "no tickets" and "no
    # tracker" look identical from the loop, and only one of them is good news.
    printf 'tracker: no issues directory at %s\n' "$dir" >&2
    return 0
  fi
  # The glob is lexical, and ids start with NN, so this is min-NN order.
  for file in "$dir"/*.md; do
    [ -e "$file" ] || continue
    id="$(basename "$file")"
    # Before the status is even read: a name this backend cannot hand out as an id
    # is not a ticket of this tracker whatever it says about itself ([48]).
    if ! tracker_local__addressable "$id"; then
      tracker_local__refuse_name "$id"
      continue
    fi
    [ "$(tracker_local__field_of_file "$file" Status)" = "ready-for-agent" ] || continue
    tracker_local__is_unblocked "$file" || continue
    printf '%s\n' "${id%.md}"
  done
}

# Every ticket, whatever its state. The scope-guard needs it: to tell a stray
# write from a scoping conflict it has to know who else declared the path, and
# a resolved or escalated ticket owns its write-surface just as much.
tracker_local_ids() {
  local dir file id
  dir="$(tracker_local__issues_dir)"
  [ -d "$dir" ] || return 0
  for file in "$dir"/*.md; do
    [ -e "$file" ] || continue
    id="$(basename "$file")"
    if ! tracker_local__addressable "$id"; then
      tracker_local__refuse_name "$id"
      continue
    fi
    printf '%s\n' "${id%.md}"
  done
}

# Unblocked means every ticket listed in `Blocked by:` is resolved. An id that
# points at nothing counts as blocking: an unknown dependency is never safe to
# assume met.
tracker_local__is_unblocked() {
  local file="$1" raw dep depfile
  raw="$(tracker_local__field_of_file "$file" 'Blocked by')"
  [ -n "$raw" ] || return 0
  for dep in $(printf '%s' "$raw" | tr ',' ' '); do
    case "$dep" in
      [0-9]*) ;;
      *) continue ;; # "None", prose, punctuation
    esac
    depfile="$(tracker_local__path "${dep%.md}")" || return 1
    [ "$(tracker_local__field_of_file "$depfile" Status)" = "resolved" ] || return 1
  done
  return 0
}

# Claiming is a test-and-set, and it has to be atomic: two pickers must not
# both read "ready-for-agent" and both stamp themselves owner. Re-reading our
# own stamp afterwards would not settle it — both writers can believe they won.
# So the read-modify-write happens under a guard, held only for its duration.
#
# This guard lives in `issues/`, beside the ticket it is about, and [47] left it
# there while putting its own next to the run lock. That asymmetry is deliberate
# and it is not the duration argument [47] gave for it ([49]): a guard on a ticket
# belongs with the ticket — a remote backend would take it wherever that ticket
# lives — and what made the placement dangerous was on the other side, in a guard
# comparing two trees of `issues/` as if the directory held nothing but tickets.
# That side is where it was fixed, once, for all three kinds of transient this
# pack leaves in there rather than only for this one.
tracker_local_claim() {
  local id="$1" owner="${2:-pid:$$}" file guard rc=0
  file="$(tracker_local__path "$id")" || return 1
  guard="$file.guard"

  state_guard_take "$guard" "claim guard" || return 1

  if [ "$(tracker_local__field_of_file "$file" Status)" = "ready-for-agent" ]; then
    tracker_local__set_fields "$id" Status claimed \
      Claimed "owner=$owner at=$(ralph_now)" || rc=1
  else
    rc=1
  fi

  state_guard_release "$guard"
  return "$rc"
}

tracker_local_unclaim() {
  tracker_local__set_fields "$1" Status ready-for-agent Claimed --drop
}

# The retry counter goes with the claim, and that is the whole of [26]'s AFK half:
# left in place it was cumulative over the ticket's entire life, across deliveries,
# so a ticket delivered green twice was escalated `failed-impl` on its third visit
# to the frontier. `resolved` is the only safe place to clear it — a green ticket is
# off the frontier, and if it comes back it comes back for a new reason. Clearing it
# on `unclaim`, between two retries, is what RETRY_N exists to prevent.
tracker_local_mark_resolved() {
  tracker_local__set_fields "$1" Status resolved Claimed --drop Failures --drop
}

tracker_local_mark_escalated() {
  local id="$1" reason="${2:?tracker: an escalation needs a reason}"
  tracker_local__set_fields "$id" Status ready-for-human Escalation "$reason" Claimed --drop
}

tracker_local_mark_ready() {
  tracker_local__set_fields "$1" Status ready-for-agent Claimed --drop Escalation --drop
}

# Closed, and the escalation reason dropped with it: a `wontfix` still carrying
# `Escalation: too-big` would read, next time somebody greps the tracker, as a
# ticket still waiting for a human. `Failures:` goes too — a closed ticket has no
# retry budget, and leaving the number behind is the cumulative counter [26]
# removed, in a state nobody looks at.
tracker_local_mark_wontfix() {
  tracker_local__set_fields "$1" Status wontfix Claimed --drop Escalation --drop \
    Failures --drop
}

# The retry budget back to full, without going through `resolved`.
#
# Dropped rather than set to `0`, which is what `mark_resolved` does and has to
# stay the same gesture: `tracker_local_bump_failures` reads a missing field and a
# `0` identically, so the two spellings mean the same thing to every reader — and
# a ticket carrying `Failures: 0` reads, to a human, as a ticket that has been
# tried and did not fail, which is not what a re-injection says about it.
tracker_local_clear_failures() {
  tracker_local__set_fields "$1" Failures --drop
}

# Hold a ticket until other tickets are resolved. Used by the re-slice: the
# ticket that was too big waits for the smaller ones it was cut into, and comes
# back to the frontier once they are all resolved — its own green gate is what
# closes it, never the split itself.
#
# Blockers already on the ticket are kept. They were resolved when it entered
# the frontier, so dropping them would change nothing for the loop and lose the
# reason a human wrote them down.
tracker_local_block_on() {
  local id="$1" deps="${2:-}" current dep merged=''
  current="$(tracker_local_field "$id" 'Blocked by')" || current=''
  for dep in $(printf '%s %s' "$current" "$deps" | tr ',' ' '); do
    # "None", prose and punctuation are not dependencies.
    case "$dep" in
      [0-9]*) ;;
      *) continue ;;
    esac
    case " $merged " in
      *" $dep "*) continue ;;
    esac
    merged="$merged $dep"
  done
  merged="${merged# }"
  [ -n "$merged" ] || merged=None
  tracker_local__set_fields "$id" "Blocked by" \
    "$(printf '%s' "$merged" | tr ' ' ',' | sed 's/,/, /g')"
}

tracker_local_bump_failures() {
  local id="$1" current next
  current="$(tracker_local_field "$id" Failures)"
  case "$current" in
    '' | *[!0-9]*) current=0 ;;
  esac
  next=$((current + 1))
  tracker_local__set_fields "$id" Failures "$next" || return 1
  printf '%s\n' "$next"
}

# ── serialising the number space ─────────────────────────────────────────────
#
# Allocating an `NN` is a read-modify-write on the *directory*: read what is
# there, take the next free number, write a file carrying it. That is exactly the
# shape `tracker_local_claim` already guards, for exactly the same reason — two
# openers must not both read the directory and both believe they won, and
# re-reading our own file afterwards would not settle it. There are three
# producers now (`failures_reslice`, the retro's escalation, `capability_propose`)
# and each runs inside its own iteration ([13]), so this is not hypothetical.
#
# What a collision costs is permanent, and it is not paid by the ticket carrying
# the number: dependencies are written as bare numbers, `tracker_local__path`
# rightly refuses to resolve one that two files carry, and every ticket holding
# `Blocked by: NN` leaves the frontier for good ([27]). Neither of the two repairs
# that exist can reach it either — `tracker_preflight` ran once at the start of
# the run, and the quarantine's renumber is disarmed by the register of the loop's
# own writes ([13]/[42]) precisely because it *is* the loop that wrote it. So the
# answer has to be here, before the collision exists.
#
# The guard sits in the feature directory and **not** in `issues/`, where the
# claim's guard sits, and the difference is not tidiness: `issues/` is what
# `failures_protect_tracker` snapshots as a git tree around every session, so a
# guard taken there while a sibling compares two snapshots arrives as a path that
# restore would try to check out. The number space belongs to the tracker as a
# whole rather than to any one ticket, so its guard belongs beside the run lock —
# and it inherits the run lock's exposure with it: a session can delete it ([12]),
# which is written down in `docs/frontiere-de-confiance.md` rather than left here.
tracker_local__open_guard() {
  printf '%s/.open.guard\n' "$(ralph_feature_dir)"
}

# Bounded, and what the bound reaches is a refusal rather than a free-for-all.
# `state_guard_take` already recovers a guard whose owner is gone; this waits for
# one that is merely busy. An allocation is one directory read and one write, so a
# caller still waiting out the bound is not queued behind work — and going ahead
# anyway would be the collision this exists to prevent, taken deliberately.
#
# The bound is a hundred and twenty tries and not a duration, so what it is worth
# is measured and not declared: eight seconds on this machine ([49]), the sleeps
# plus the cost of the loop, where [47] wrote six. Who pays it is the part worth
# knowing — `tracker_renumber` takes this guard once **per intruder**, so a
# session that drops ten files in the tracker costs a held guard eighty seconds of
# an iteration that is doing nothing else.
#
# Every stamp inside one run carries the *pilot's* pid, iterations being subshells
# of it ([13]), so the liveness `state_guard_take` reads is the run's own. That is
# the right anchor here and not a defect: a guard left by an iteration that died
# with the pilot still alive is one the pilot can still be inside.
tracker_local__open_guard_take() {
  local guard tries=120
  guard="$(tracker_local__open_guard)"
  while [ "$tries" -gt 0 ]; do
    state_guard_take "$guard" "ticket-open guard" "${FEATURE:-unknown}" && return 0
    tries=$((tries - 1))
    sleep 0.05
  done
  return 1
}

tracker_local__open_guard_release() {
  state_guard_release "$(tracker_local__open_guard)"
  return 0
}

# Why nothing was allocated, on the console **and** on the audit receipt ([49]).
#
# All three producers already say that no ticket was opened — the re-slice gaps
# twice, the two proposals say "either one was already waiting or the tracker
# refused the write" — and none of them can say *why*, because the reason belongs
# to this backend. Said here, once, on the document a human actually reads in the
# morning: `run.log` carries the ticket's own escalation (`too-big` for a
# re-slice), which is the wrong cause, and a line on the console is a line nobody
# reads ([45] is the general form of this).
#
# `receipt_gap` is a no-op when no receipt is open, so this is unconditional; each
# of the three producers runs inside an iteration that has one.
tracker_local__open_refused() {
  local what="$1" guard holder since
  guard="$(tracker_local__open_guard)"
  holder="$(state_guard_holder "$guard" 2>/dev/null)" || holder=''
  since="$(cat "$guard/since" 2>/dev/null)" || since=''
  printf 'tracker: could not take the ticket-open guard — %s\n' "$what" >&2
  receipt_gap "the ticket-open guard was held for the whole wait, by pid ${holder:-nobody the guard names} since ${since:-an unknown time}, so $what. A number handed out beside another allocation is permanent: a bare number stops resolving, and every ticket carrying it as a blocker leaves the frontier for good ([27])"
  return 0
}

tracker_local_open_ticket() {
  tracker_local__open "$1" "$2" ''
}

# The same creation, refused if a ticket already carries this slug. Nothing on
# stdout when one did, and that is a success: "already waiting for a human" is the
# answer the caller asked for.
#
# It is an operation rather than a check its caller makes first, and that is the
# whole of it. `capability_propose` read `tracker_ids`, found no proposal and
# opened one — two proposals in flight both read nothing and both opened, which is
# the race on the number entered by the other end. The only cure is for the
# question and the write to fall on the same side of the guard. Exposing the guard
# for a caller to take instead would not do it: `open_ticket` takes it too, so a
# caller holding it would wait for itself.
tracker_local_open_unique() {
  tracker_local__open "$1" "$2" unique
}

# The body is read **before** a number is allocated, and the guard is held across
# the allocation and the write that reserves it.
#
# That ordering is the width of the window rather than a matter of style. `nn` used
# to be computed first and `body="$(cat)"` came after, so a number was chosen and
# not yet written for as long as its caller took to produce the body — for a
# re-slice, the time of a plan. Under a guard the same ordering would be worse
# still: the whole number space would wait on somebody else's stdin.
tracker_local__open() {
  local slug="$1" title="$2" unique="${3:-}" dir body nn id file rc=0
  dir="$(tracker_local__issues_dir)"
  mkdir -p "$dir"
  body="$(cat)"

  tracker_local__open_guard_take || {
    tracker_local__open_refused 'refusing to allocate a number nothing serialises'
    return 1
  }

  if [ -n "$unique" ] && tracker_local__slug_taken "$dir" "$slug"; then
    tracker_local__open_guard_release
    return 0
  fi

  nn="$(tracker_local__next_nn)"
  id="$nn-$slug"
  file="$dir/$id.md"
  {
    printf '# %s — %s\n\n' "$nn" "$title"
    if [ -n "$body" ]; then printf '%s\n' "$body"; fi
  } | state_atomic_write "$file" || rc=1
  tracker_local__open_guard_release
  [ "$rc" = 0 ] || return 1

  tracker_local__has_field "$file" "Blocked by" ||
    tracker_local__set_fields "$id" "Blocked by" None
  tracker_local__has_field "$file" Status ||
    tracker_local__set_fields "$id" Status ready-for-agent
  printf '%s\n' "$id"
}

# Does any ticket already carry this slug — an id ending `-<slug>`, which is the
# comparison `capability_propose` made against `tracker_ids` and has to stay the
# same one, moved to the side of the guard where it settles something.
tracker_local__slug_taken() {
  local dir="$1" slug="$2" file base
  for file in "$dir"/*.md; do
    [ -e "$file" ] || continue
    # A name nothing can address does not hold a slug against an opening ([48]):
    # `99-x<LF>-cap.md` would otherwise answer "already waiting" for `cap` and
    # refuse a proposal for good, on behalf of a file no reader of this tracker
    # will ever show a human.
    tracker_local__addressable "$file" || continue
    base="$(basename "$file" .md)"
    case "$base" in
      *"-$slug") return 0 ;;
    esac
  done
  return 1
}

# The next free number, and free is checked rather than assumed.
#
# Both halves are there because a session names files in this directory too
# ([21] restores what it edits, [27] renumbers what it adds — neither stops it
# choosing a name). A ticket called `1000000000000000000000000000000-x.md` used
# to end the answer: awk renders that in scientific notation, `$(( ))` calls it a
# syntax error rather than a big number, and the caller got nothing. What that
# cost is not cosmetic — `tracker_open_ticket` builds an id out of it, and the
# renumber that keeps a bare number resolvable falls back to leaving the
# collision in place. So numbers too wide to be arithmetic are not candidates for
# "the highest one", and the result is walked forward until nothing carries it.
tracker_local__next_nn() {
  local dir max nn
  dir="$(tracker_local__issues_dir)"
  max=$(ls "$dir" 2>/dev/null |
    sed -n 's/^\([0-9][0-9]*\)-.*\.md$/\1/p' |
    awk 'BEGIN { m = 0 } length($1) <= 15 { n = $1 + 0; if (n > m) m = n } END { print m }')
  nn=$((max + 1))
  while tracker_local__number_taken "$dir" "$(printf '%02d' "$nn")"; do
    nn=$((nn + 1))
  done
  printf '%02d\n' "$nn"
}

# Does any ticket carry this number — as `NN.md` or as `NN-slug.md`.
#
# A file this backend cannot address carries nothing, here as everywhere ([48]),
# and the two halves have to agree: `__path` no longer counts such a file among
# the carriers of a number, so holding the number back for it would reserve it
# against nothing and hand the next opening a number further along for no reason.
tracker_local__number_taken() {
  local dir="$1" nn="$2" hit
  [ ! -f "$dir/$nn.md" ] || return 0
  for hit in "$dir/$nn"-*.md; do
    [ -e "$hit" ] || continue
    tracker_local__addressable "$hit" || continue
    return 0
  done
  return 1
}

# Give a ticket a number no other ticket carries, and say which id it now has.
#
# Called on what a session added to the tracker, and only there. The collision it
# undoes is born of two decisions that are each correct on their own ([21]): a
# renamed ticket file is a `D` plus an `A`, the deletion is restored and the
# addition is left for a human — so both files end up carrying the same `NN`,
# `tracker_local__path` rightly refuses to resolve a bare number, and every
# ticket holding `Blocked by: NN` leaves the frontier for good ([27]).
#
# Renaming the *addition* rather than restoring it away is what keeps [21]'s rule
# intact: nothing a session wrote is destroyed, it is handed to a human under a
# name that resolves. The body is left exactly as the session wrote it, heading
# included — the note the quarantine appends is where the old name is recorded,
# because rewriting the content would be the very deletion this avoids.
# Under the same guard as an opening, and for the same directory: this reads the
# number space and writes into it, so a renumber and an opening racing each other
# hand out the same number as surely as two openings do. The quarantine calls this
# from an iteration while a sibling iteration may be opening a re-slice child.
tracker_local_renumber() {
  local out rc=0
  tracker_local__open_guard_take || {
    tracker_local__open_refused 'refusing to renumber against a directory nothing serialises'
    return 1
  }
  out="$(tracker_local__renumber_held "$1")" || rc=$?
  tracker_local__open_guard_release
  [ -z "$out" ] || printf '%s\n' "$out"
  return "$rc"
}

tracker_local__renumber_held() {
  local id="$1" file dir base nn slug newnn newid carriers=0 hit
  file="$(tracker_local__path "$id")" || return 1
  dir="$(tracker_local__issues_dir)"
  base="$(basename "$file" .md)"

  # No `NN-` prefix, no bare number to be ambiguous about.
  case "$base" in
    [0-9]*-*) nn="${base%%-*}" ;;
    *)
      printf '%s\n' "$id"
      return 0
      ;;
  esac
  case "$nn" in
    *[!0-9]*)
      printf '%s\n' "$id"
      return 0
      ;;
  esac

  # Exactly the rule tracker_local__path applies, and it has to stay that way: a
  # file named `NN.md` is matched before the glob, so a bare `NN` resolves to it
  # whatever else shares the number. Calling that a collision would renumber a
  # ticket nothing was ever going to mis-resolve.
  if [ ! -f "$dir/$nn.md" ]; then
    for hit in "$dir/$nn"-*.md; do
      [ -e "$hit" ] || continue
      # The same rule `tracker_local__path` applies, for the same reason it has to
      # stay the same one ([48]): a file nothing can address is not a carrier, so
      # renumbering over it would move a ticket no bare number was ever going to
      # mis-resolve to.
      tracker_local__addressable "$hit" || continue
      carriers=$((carriers + 1))
    done
  fi
  if [ "$carriers" -le 1 ]; then
    printf '%s\n' "$id"
    return 0
  fi

  slug="${base#*-}"
  newnn="$(tracker_local__next_nn)"
  newid="$newnn-$slug"
  mv "$file" "$dir/$newid.md" || return 1
  printf '%s\n' "$newid"
}

tracker_local_append_note() {
  local id="$1" file note
  file="$(tracker_local__path "$id")" || return 1
  note="$(cat)"
  {
    cat "$file"
    grep -q '^## Comments' "$file" || printf '\n## Comments\n'
    printf '\n%s\n' "$note"
  } | state_atomic_write "$file"
}

# In the local backend the receipt is a file; on a remote backend it is the
# pull request. Either way the loop just hands it the content.
tracker_local_emit_receipt() {
  local id="$1" dir file
  dir="$(ralph_project_root)/receipts/${FEATURE}"
  mkdir -p "$dir"
  file="$dir/$id.md"
  state_atomic_write "$file" || return 1
  printf '%s\n' "$file"
}

# Where the last one can be read — the same name `emit_receipt` publishes, and
# derived from it rather than restated, so the two cannot drift.
#
# Non-zero and silent when there is none, and that includes a receipt
# `RECEIPTS_RETENTION_DAYS` has swept: a reader is entitled to "there is nothing
# to read" rather than to a path that does not resolve.
tracker_local_receipt_path() {
  local file
  file="$(ralph_project_root)/receipts/${FEATURE}/${1%.md}.md"
  [ -f "$file" ] || return 1
  printf '%s\n' "$file"
}
