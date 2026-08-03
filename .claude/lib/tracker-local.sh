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

# Accepts `01`, `01-alpha` or `01-alpha.md`.
#
# A bare number that matches more than one ticket is refused rather than
# resolved to whichever file sorts first: dependencies are written as bare
# numbers (`Blocked by: 01`), so a silent pick would block — or unblock — the
# wrong ticket, and nothing downstream would ever notice.
tracker_local__path() {
  local id="${1%.md}" dir file hit='' matches=0
  dir="$(tracker_local__issues_dir)"
  if [ -f "$dir/$id.md" ]; then
    printf '%s\n' "$dir/$id.md"
    return 0
  fi
  for file in "$dir/$id"-*.md; do
    [ -e "$file" ] || continue
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
    [ "$(tracker_local__field_of_file "$file" Status)" = "ready-for-agent" ] || continue
    tracker_local__is_unblocked "$file" || continue
    id="$(basename "$file")"
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

tracker_local_open_ticket() {
  local slug="$1" title="$2" dir nn id file body
  dir="$(tracker_local__issues_dir)"
  mkdir -p "$dir"
  nn="$(tracker_local__next_nn)"
  id="$nn-$slug"
  file="$dir/$id.md"
  body="$(cat)"
  {
    printf '# %s — %s\n\n' "$nn" "$title"
    if [ -n "$body" ]; then printf '%s\n' "$body"; fi
  } | state_atomic_write "$file"
  tracker_local__has_field "$file" "Blocked by" ||
    tracker_local__set_fields "$id" "Blocked by" None
  tracker_local__has_field "$file" Status ||
    tracker_local__set_fields "$id" Status ready-for-agent
  printf '%s\n' "$id"
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
tracker_local__number_taken() {
  local dir="$1" nn="$2" hit
  [ ! -f "$dir/$nn.md" ] || return 0
  for hit in "$dir/$nn"-*.md; do
    [ -e "$hit" ] || continue
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
tracker_local_renumber() {
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
