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
#   Failures:       how many fresh retries it has burned
#   Write-surface:  what it is allowed to touch

tracker_local__issues_dir() {
  printf '%s/issues\n' "$(ralph_feature_dir)"
}

# Accepts `01`, `01-alpha` or `01-alpha.md`.
tracker_local__path() {
  local id="${1%.md}" dir file
  dir="$(tracker_local__issues_dir)"
  if [ -f "$dir/$id.md" ]; then
    printf '%s\n' "$dir/$id.md"
    return 0
  fi
  for file in "$dir/$id"-*.md; do
    [ -e "$file" ] || continue
    printf '%s\n' "$file"
    return 0
  done
  return 1
}

tracker_local__field_of_file() {
  sed -n "s/^\*\*$2:\*\*[[:space:]]*//p; s/^$2:[[:space:]]*//p" "$1" |
    awk 'NR == 1 { print }'
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
  [ -d "$dir" ] || return 0
  # The glob is lexical, and ids start with NN, so this is min-NN order.
  for file in "$dir"/*.md; do
    [ -e "$file" ] || continue
    [ "$(tracker_local__field_of_file "$file" Status)" = "ready-for-agent" ] || continue
    tracker_local__is_unblocked "$file" || continue
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

tracker_local_mark_resolved() {
  tracker_local__set_fields "$1" Status resolved Claimed --drop
}

tracker_local_mark_escalated() {
  local id="$1" reason="${2:?tracker: an escalation needs a reason}"
  tracker_local__set_fields "$id" Status ready-for-human Escalation "$reason" Claimed --drop
}

tracker_local_mark_ready() {
  tracker_local__set_fields "$1" Status ready-for-agent Claimed --drop Escalation --drop
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

tracker_local__next_nn() {
  local dir max
  dir="$(tracker_local__issues_dir)"
  max=$(ls "$dir" 2>/dev/null |
    sed -n 's/^\([0-9][0-9]*\)-.*\.md$/\1/p' |
    awk 'BEGIN { m = 0 } { n = $1 + 0; if (n > m) m = n } END { print m }')
  printf '%02d\n' "$((max + 1))"
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
