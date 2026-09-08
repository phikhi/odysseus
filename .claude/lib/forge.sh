# shellcheck shell=bash
# The shared core of the two remote tracker backends ([18]).
#
# `tracker-github.sh` and `tracker-gitlab.sh` implement the adapter interface of
# `lib/tracker.sh`; everything they have in common is here, and what differs
# between two forges is a table each of them publishes as
# `tracker_<backend>_forge_spec KEY`. That split is the point: a reader comparing
# the two backends reads two short tables, and a reader asking what a remote
# backend *does* reads one file.
#
# Not called `tracker-remote.sh`, and the name is load-bearing: `tracker__dispatch`
# routes `TRACKER_BACKEND=<name>` to `tracker_<name>_<op>`, so a shared core whose
# functions were named `tracker_remote_*` would make `TRACKER_BACKEND=remote` a
# half-working backend that answers some operations and silently mis-answers the
# rest. `forge_` cannot be reached that way: `TRACKER_BACKEND=forge` finds no
# `tracker_forge_frontier` and the dispatcher refuses out loud.
#
# ## The state model, and why it is the same one
#
# A ticket is an issue. **The pack's fields live in the issue body**, exactly as
# they live in a markdown file on the local backend, read with the same tolerant
# form (`**Name:** v` or `Name: v`) and written back in the bold form. That is not
# laziness about labels: it is what makes "the same e2e scenario produces the same
# observable state transitions" true rather than approximately true, and it is what
# lets one listing answer every read this pack makes of the tracker.
#
# What the forge's own vocabulary carries on top, for the human looking at the
# issue rather than for this pack:
#
#   assignee     the claim ([18]'s AC, spec §152). Set when the pack claims,
#                cleared when it gives the ticket back.
#   closed       `resolved` and `wontfix`. Reopened by every transition that puts
#                the ticket back in front of somebody.
#
# **Reads never consult those two**, and that is deliberate: a field and a forge
# state that disagree would give this pack two authorities for one fact, and the
# body is the one both backends share. The one exception is the claim's *owner*,
# below, which is a local question by design.
#
# ## Ids
#
# `<number>` or `<number>-<slug>`, where the number is the issue's own and the
# slug is the `Slug:` field the pack writes when it opens a ticket. Server-numbered
# ids cannot collide, so `renumber` returns what it was given ([27]) — but the slug
# is not optional decoration: `playthrough__opened_slug` and
# `playthrough__strangers` both read the slug out of the id text ([65]), and an id
# that dropped it would report every duplicate wiring ticket as one this run never
# opened and would name none of the strangers. An issue a human opened carries no
# `Slug:` and its id is the bare number, which is an id this pack already
# understands (`tracker__carriers` matches it exactly, `Blocked by: 12` resolves to
# it).
#
# **An id this backend hands out is one line, by construction, and there is
# nothing here to refuse** ([48], [64]). The number is an integer the forge
# allocated; the slug travels in the rendering the transport already uses, so a
# `Slug:` field a human filled in with a tab arrives as `\t` and never as a tab.
# `lib/tracker.sh` already provides for this answer — a backend numbering
# server-side calls `tracker_refuse_name` never and finds nothing at the preflight
# — and it is the right answer rather than a missing one. See `forge__record_id`
# for what that costs.
#
# ## What refuses, and how
#
# Every operation refuses by a **return code** and never by ending its caller
# ([71]): no `${N:?word}`, no `exit`, no errexit let travel. `3` belongs to the
# dispatcher, so refusals here start at `1`. An empty value is a value —
# `mark_escalated ID ""` writes the sink's ordinary shape, with no `Escalation:`.
#
# ## What this costs, measured rather than claimed
#
# One listing answers `frontier`, `ids`, `read_ticket` and every `field` of every
# ticket. It is memoised in a **variable of the calling shell**, and what that buys
# is exactly one thing: the reads inside **one call** collapse into one request. A
# frontier scan of forty tickets each naming a blocker is one request and not
# forty-one, and a `set_fields` reads what it is about to rewrite for free.
#
# **What it does not buy, said here because the obvious sentence about it is
# wrong.** A shell variable dies at the first command substitution, and a command
# substitution is how every consumer in this pack reads the tracker — `$(tracker_ids)`,
# `$(tracker_field ...)`, a heredoc fed by one. So a caller that asks for six things
# about forty tickets pays forty listings and not one, whatever this memo does:
# `router__tracker_state` does that once per drained ticket ([58]/[61]), and
# `gate__surface_owner` walks the ids asking each one for its write-surface. Order
# of magnitude on a tracker of forty: **one** request for a frontier scan, forty-one
# for a scope overflow into an undeclared path, two hundred and forty for one ticket
# drained.
#
# The parade is a cache with a longer lifetime, and the two lifetimes available are
# both refused here rather than picked badly. A file in `.scratch/<feature>/` is a
# file a routed session writes, which is [40]'s rule and [21]'s corollary: a control
# reading what the thing it controls can write is not a control — and this cache
# decides what the tracker *says*, which is everything. A file in the run's own
# witness directory would be right, and `human-loop.sh` does not make one: giving
# the drain one is a change to the entry point and not to a backend. Owner: **[75]**.
#
# ## Public API
#
#   forge_ids F                    every id, min number first, one per line
#   forge_frontier F               the eligible ones
#   forge_read_ticket F ID         the issue body
#   forge_field F ID NAME          one field of it
#   forge_claim F ID [OWNER]       assign, stamp, and record it locally
#   forge_unclaim F ID             give it back
#   forge_mark_resolved F ID       wait for CI if asked, then close
#   forge_mark_escalated F ID WHY  hand it to the human sink
#   forge_mark_ready F ID          re-inject
#   forge_mark_wontfix F ID        closed by a human
#   forge_block_on F ID DEPS       hold it
#   forge_bump_failures F ID       count one; the new count on stdout
#   forge_clear_failures F ID      the retry budget back
#   forge_open_ticket F SLUG TITLE     create from stdin; id on stdout
#   forge_open_unique F SLUG TITLE     the same, unless the slug is taken
#   forge_renumber F ID            the id it carries, which is the one given
#   forge_append_note F ID         a comment from stdin
#   forge_emit_receipt F ID        the receipt from stdin, into the request
#   forge_receipt_path F ID        where that request is, if this machine knows
#   forge_json                     a JSON document on stdin, one leaf per line
#   forge_json_string              a value on stdin, as a JSON string

# The listing this shell has already paid for, and the key it was taken under. A
# variable and never a file: see the header.
FORGE__CACHE=''
FORGE__CACHE_KEY=''
# The user id a forge that assigns by id needs, looked up once per shell.
FORGE__USER_ID=''
FORGE__USER_ID_KEY=''

# ── the flavour table ────────────────────────────────────────────────────────

# One value out of the backend's own table. Called by name rather than by a `case`
# here so that adding a third forge is adding a file, which is the promise
# `lib/tracker.sh` makes about backends and has to keep about their shared core.
#
# Non-zero when the backend does not answer the key, which is a bug in the
# backend and not a state: a caller that read an empty base URL would build
# `/repos/...` and ask the local filesystem for it.
forge__spec() {
  local flavour="$1" key="$2" fn out
  fn="tracker_${flavour}_forge_spec"
  declare -f "$fn" >/dev/null 2>&1 || return 1
  out="$("$fn" "$key")" || return 1
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
  return 0
}

# The repository (or project) this backend was pointed at, and the one place that
# refusal is worded. Every operation goes through a read or a write, and both start
# here, so an unconfigured backend refuses on its first call rather than composing
# a URL out of an empty string.
forge__repo() {
  [ -n "${TRACKER_REPO:-}" ] || {
    printf 'forge: TRACKER_REPO is not set — a remote tracker backend has no repository to talk to\n' >&2
    return 1
  }
  printf '%s\n' "$TRACKER_REPO"
  return 0
}

# Percent-encoding for the one place a path segment can hold a slash: a GitLab
# project is `group/name` and travels inside the URL path. Only the characters a
# path segment may not carry, which keeps the URL a human can read in `run.log`.
forge__urlenc() {
  LC_ALL=C awk 'BEGIN {
    # From one and not from zero: NUL is not a character an awk string can hold,
    # and it is not a byte a URL can carry either.
    for (i = 1; i < 256; i++) ord[sprintf("%c", i)] = i
  }
  {
    line = $0
    out = ""
    for (i = 1; i <= length(line); i++) {
      c = substr(line, i, 1)
      if (c ~ /[A-Za-z0-9._~-]/) { out = out c }
      else { out = out sprintf("%%%02X", ord[c]) }
    }
    print out
  }'
}

# ── the transport ────────────────────────────────────────────────────────────

# One request. `<body>` on stdout, the HTTP status as the **last** line, and
# non-zero when curl itself could not ask.
#
# `--max-time` is not optional, for `budget__request`'s reason one module over: a
# hung request would hang the run in a place where nothing is watching a child,
# and this pack exists to keep an AFK night bounded.
#
# The token comes from a command the project names ([24]'s criterion, and the same
# arrangement `USAGE_TOKEN_CMD` already has): a credential store is the user's
# business, and `TRACKER_TOKEN_CMD` is read out of the sealed config, so it is
# exactly as trusted as `TEST_CMD`.
forge__http() {
  local flavour="$1" method="$2" url="$3" data="${4:-}"
  local token='' header accept
  command -v curl >/dev/null 2>&1 || {
    printf 'forge: curl is not on PATH — a remote tracker backend cannot ask anything\n' >&2
    return 1
  }
  if [ -n "${TRACKER_TOKEN_CMD:-}" ]; then
    token="$(eval "${TRACKER_TOKEN_CMD}" 2>/dev/null)" || token=''
  fi
  header="$(forge__spec "$flavour" auth-header)" || return 1
  accept="$(forge__spec "$flavour" accept)" || accept='Accept: application/json'

  set -- curl -sS --max-time "${FORGE_TIMEOUT:-30}" -X "$method" \
    -H "$accept" -H 'Content-Type: application/json' \
    -w '
%{http_code}'
  if [ -n "$token" ]; then
    set -- "$@" -H "$(printf "$header" "$token")"
  fi
  if [ -n "$data" ]; then
    set -- "$@" --data-binary "$data"
  fi
  "$@" "$url" 2>/dev/null
}

# The same, with the status read off and judged. The body on stdout, non-zero on
# anything that is not a 2xx — and the status said on stderr, because a 404 on a
# repository and a 401 on a token are the two mistakes a project makes first and
# neither of them is visible in an empty body.
forge__api() {
  local flavour="$1" method="$2" path="$3" data="${4:-}"
  local base out status body tries left
  base="$(forge__api_base "$flavour")" || return 1

  # A **read** is asked again before it is given up on, and a write is not. The
  # asymmetry is the point: a `GET` is idempotent, so a second attempt costs a
  # request and buys a night — the pilot reads the frontier through a heredoc
  # command substitution, so a listing that refused once reaches it as an empty
  # frontier, which is what starts the terminal value gate. A `POST` or a `PATCH`
  # retried after a timeout is a ticket opened twice or a comment written twice,
  # and neither of those is something a caller can undo.
  tries=1
  [ "$method" != GET ] || tries="${FORGE_READ_TRIES:-3}"
  case "$tries" in
    '' | 0 | *[!0-9]*) tries=1 ;;
  esac
  left="$tries"

  while :; do
    left=$((left - 1))
    out="$(forge__http "$flavour" "$method" "$base$path" "$data")" || out=''
    if [ -n "$out" ]; then
      status="${out##*$'\n'}"
      body="${out%$'\n'*}"
      case "$status" in
        2*)
          [ -z "$body" ] || printf '%s\n' "$body"
          return 0
          ;;
        4*)
          # A refusal about the request itself — a repository that is not there, a
          # token that is not allowed — and asking again would only ask it again.
          printf 'forge: %s %s answered %s\n' "$method" "$path" "$status" >&2
          return 1
          ;;
      esac
    fi
    if [ "$left" -le 0 ]; then
      printf 'forge: %s %s did not answer (%s attempt(s))\n' "$method" "$path" "$tries" >&2
      return 1
    fi
    sleep "${FORGE_READ_BACKOFF:-2}"
  done
}

forge__api_base() {
  local flavour="$1" base
  if [ -n "${TRACKER_API:-}" ]; then
    printf '%s\n' "${TRACKER_API%/}"
    return 0
  fi
  base="$(forge__spec "$flavour" api)" || return 1
  printf '%s\n' "${base%/}"
  return 0
}

# ── JSON, in awk, because the pack promises to run with nothing installed ─────

# A JSON document on stdin, one **scalar leaf** per line: `<path><TAB><value>`.
# Paths are dotted, array elements are their index, so the first issue of a
# listing is `0.number`, `0.body`, `0.assignees.0.login`.
#
# Deliberately not jq, for `budget__window`'s reason. Deliberately **strict**,
# which is where it parts company with `budget__window`: that one reads a figure
# out of an undocumented endpoint and prints nothing when it cannot, and this one
# carries the text of a ticket — a value guessed at here is a ticket rewritten. So
# anything it cannot parse exactly refuses the whole document.
#
# Values are escaped on the way out, `\\` first: a body carries newlines and may
# carry tabs, and both are this transport's separators ([37] one layer down).
# `forge__unescape` is the only reader of that rendering.
#
# `\uXXXX` above 0x7F refuses rather than guesses. Both forges answer in raw UTF-8
# and escape only what JSON obliges them to, so this is a case that does not arise
# — and awk's `%c` is a byte on one implementation and a character on another, so
# the alternative is a ticket that is silently different on the next machine.
forge_json() {
  LC_ALL=C awk '
    { doc = doc $0 "\n" }
    function fail(why) { printf "forge: the forge answered something this pack cannot parse (%s)\n", why > "/dev/stderr"; bad = 1; exit 1 }
    function skipws() { while (i <= n && substr(doc, i, 1) ~ /[ \t\r\n]/) i++ }
    function esc(v) { gsub(/\\/, "\\\\", v); gsub(/\t/, "\\t", v); gsub(/\n/, "\\n", v); return v }
    function hex(c) { return index("0123456789abcdef", tolower(c)) - 1 }
    function pstring(  out, c, u, k, d) {
      if (substr(doc, i, 1) != "\"") { fail("a string was expected"); return "" }
      i++
      out = ""
      while (i <= n) {
        c = substr(doc, i, 1)
        if (c == "\"") { i++; return out }
        if (c == "\\") {
          i++
          c = substr(doc, i, 1)
          i++
          if (c == "n") { out = out "\n" }
          else if (c == "t") { out = out "\t" }
          else if (c == "r") { out = out "\r" }
          else if (c == "b") { out = out sprintf("%c", 8) }
          else if (c == "f") { out = out sprintf("%c", 12) }
          else if (c == "/") { out = out "/" }
          else if (c == "\\") { out = out "\\" }
          else if (c == "\"") { out = out "\"" }
          else if (c == "u") {
            u = 0
            for (k = 0; k < 4; k++) {
              d = hex(substr(doc, i + k, 1))
              if (d < 0) { fail("a broken \\u escape"); return "" }
              u = u * 16 + d
            }
            i += 4
            if (u > 127) { fail("a \\u escape above ASCII"); return "" }
            out = out sprintf("%c", u)
          }
          else { fail("an unknown escape"); return "" }
          continue
        }
        out = out c
        i++
      }
      fail("a string that never ends")
      return ""
    }
    function pvalue(path,   c, k, idx, sp) {
      skipws()
      if (i > n) { fail("the document ends where a value was expected"); return }
      c = substr(doc, i, 1)
      if (c == "{") {
        i++
        skipws()
        if (substr(doc, i, 1) == "}") { i++; return }
        while (i <= n) {
          skipws()
          k = pstring()
          if (bad) return
          skipws()
          if (substr(doc, i, 1) != ":") { fail("a key with no value"); return }
          i++
          sp = (path == "") ? k : path "." k
          pvalue(sp)
          if (bad) return
          skipws()
          c = substr(doc, i, 1)
          i++
          if (c == "}") return
          if (c != ",") { fail("an object that does not close"); return }
        }
        fail("an object that never ends")
        return
      }
      if (c == "[") {
        i++
        skipws()
        if (substr(doc, i, 1) == "]") { i++; return }
        idx = 0
        while (i <= n) {
          sp = (path == "") ? idx : path "." idx
          pvalue(sp)
          if (bad) return
          idx++
          skipws()
          c = substr(doc, i, 1)
          i++
          if (c == "]") return
          if (c != ",") { fail("an array that does not close"); return }
        }
        fail("an array that never ends")
        return
      }
      if (c == "\"") { k = pstring(); if (bad) return; print path "\t" esc(k); return }
      if (substr(doc, i, 4) == "true") { i += 4; print path "\ttrue"; return }
      if (substr(doc, i, 5) == "false") { i += 5; print path "\tfalse"; return }
      if (substr(doc, i, 4) == "null") { i += 4; print path "\t"; return }
      if (c ~ /[-0-9]/) {
        k = ""
        while (i <= n && substr(doc, i, 1) ~ /[-+0-9.eE]/) { k = k substr(doc, i, 1); i++ }
        print path "\t" k
        return
      }
      fail("a value that is none of the six JSON kinds")
    }
    END {
      n = length(doc)
      i = 1
      pvalue("")
      if (bad) exit 1
      skipws()
      if (i <= n) { fail("trailing text after the document"); exit 1 }
      exit 0
    }
  '
}

# The reverse of the escaping above, for one value.
forge__unescape() {
  printf '%s' "$1" | LC_ALL=C awk '
    { line = $0; out = ""
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "\\" && i < length(line)) {
          i++
          d = substr(line, i, 1)
          if (d == "n") out = out "\n"
          else if (d == "t") out = out "\t"
          else if (d == "\\") out = out "\\"
          else out = out d
        } else out = out c
      }
      printf "%s", out
    }'
}

# A value on stdin, as a JSON string with its quotes. Control characters that have
# no short escape go out as `\u00XX`, which is what keeps a ticket body carrying a
# form feed from producing a document the forge rejects with a 400 nobody can read.
forge_json_string() {
  LC_ALL=C awk '
    BEGIN { printf "\"" }
    { if (NR > 1) printf "\\n"; line = $0
      for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "\"") printf "\\\""
        else if (c == "\\") printf "\\\\"
        else if (c == "\t") printf "\\t"
        else if (c == "\r") printf "\\r"
        else if (c < " ") printf "\\u%04x", index(" ", c)
        else printf "%s", c
      }
    }
    END { printf "\"" }'
}

# ── the listing every read is served from ────────────────────────────────────

# Every issue of the repository, as the forge's own JSON, memoised for this shell.
#
# Paged until a page comes back short: a tracker of a hundred tickets is ordinary
# and a first page is not the tracker. Non-zero when any page refuses, and that is
# [59]'s rule in a place it costs the most — a listing read as empty turns every
# ticket into a ticket that is not there, which is a frontier of nothing and a
# `tracker_ids` that tells the scope-guard nobody owns anything.
forge__listing() {
  local flavour="$1" repo key page=1 path body all='' count
  repo="$(forge__repo)" || return 1
  key="$flavour/$repo"
  if [ "$FORGE__CACHE_KEY" = "$key" ]; then
    printf '%s\n' "$FORGE__CACHE"
    return 0
  fi
  while [ "$page" -le 20 ]; do
    path="$(forge__path "$flavour" list "$page")" || return 1
    body="$(forge__api "$flavour" GET "$path")" || return 1
    body="$(printf '%s\n' "$body" | forge_json)" || return 1
    all="$all$body
"
    count="$(printf '%s' "$body" | LC_ALL=C awk -F'\t' '
      { split($1, f, "."); if (f[1] != last) { n++; last = f[1] } }
      END { print n + 0 }')"
    [ "${count:-0}" -ge "${FORGE_PAGE:-100}" ] || break
    page=$((page + 1))
  done
  FORGE__CACHE="$all"
  FORGE__CACHE_KEY="$key"
  printf '%s\n' "$all"
  return 0
}

# Everything this shell believes about the tracker, thrown away. Called by every
# write, and by nothing else: a cache that outlived a write would answer the next
# read with the state before it, and the state before a claim is a frontier that
# still holds the ticket.
forge__forget() {
  FORGE__CACHE=''
  FORGE__CACHE_KEY=''
  return 0
}

# One record per issue: `<number><TAB><slug><TAB><assignee><TAB><state><TAB><body>`,
# the body still escaped, ordered by number ascending — which is the "min-NN
# first" every consumer of `frontier` and `ids` relies on.
#
# A page of a forge listing may hold objects that are not issues: GitHub answers
# `GET /issues` with pull requests too, and one of them carrying a `Status:` line
# in its body would enter the frontier as a ticket nobody can claim. They are
# dropped on the key that names them (`pull_request`), which is the forge's own
# marker and not a guess about titles.
forge__records() {
  local flavour="$1" listing idkey bodykey userkey
  listing="$(forge__listing "$flavour")" || return 1
  idkey="$(forge__spec "$flavour" id-key)" || return 1
  bodykey="$(forge__spec "$flavour" body-key)" || return 1
  userkey="$(forge__spec "$flavour" user-key)" || return 1
  printf '%s' "$listing" | LC_ALL=C awk -F'\t' \
    -v idkey="$idkey" -v bodykey="$bodykey" -v userkey="$userkey" '
    BEGIN { sep = sprintf("%c", 1) }
    {
      p = $1
      dot = index(p, ".")
      if (dot == 0) next
      rec = substr(p, 1, dot - 1)
      key = substr(p, dot + 1)
      if (rec !~ /^[0-9]+$/) next
      if (!(rec in seen)) { seen[rec] = 1; order[n++] = rec }
      if (key == idkey) num[rec] = $2
      else if (key == bodykey) body[rec] = $2
      else if (key == "assignees.0." userkey) who[rec] = $2
      else if (key == "state") st[rec] = $2
      else if (key ~ /^pull_request(\.|$)/) pr[rec] = 1
    }
    END {
      for (k = 0; k < n; k++) {
        rec = order[k]
        if (rec in pr) continue
        if (num[rec] == "") continue
        slug = ""
        b = body[rec]
        # The `Slug:` field, read off the escaped body: `\n` is the separator
        # there, so this is the same tolerant match the rest of the pack makes
        # against a line.
        # A leading separator is prepended rather than matched with `(^|...)`:
        # `^` inside an alternation is an anchor on one awk and a literal on
        # another, and the body arrives with its newlines already escaped, so the
        # two characters this prepends are exactly the separator.
        #
        # Escaped backslashes are folded to one byte first, and that is not
        # tidiness: in an escaped body a literal backslash is `\\`, so a field
        # value ending in one puts a `\` immediately before the `n` of the next
        # separator — and a scan looking for the two characters `\n` cuts the
        # value one character early, on a ticket that is perfectly well formed.
        m = "\\n" b
        gsub(/\\\\/, sep, m)
        if (match(m, /\\n\*\*Slug:\*\*[ \t]*/) || match(m, /\\nSlug:[ \t]*/)) {
          rest = substr(m, RSTART + RLENGTH)
          e = index(rest, "\\n")
          slug = (e > 0) ? substr(rest, 1, e - 1) : rest
          sub(/[ \t]+$/, "", slug)
          gsub(sep, "\\\\", slug)
        }
        printf "%s\t%s\t%s\t%s\t%s\n", num[rec], slug, who[rec], st[rec], b
      }
    }' | LC_ALL=C sort -t"$(printf '\t')" -k1,1n
  return 0
}

# The id a record carries — `<number>-<slug>`, or the bare number when the issue
# holds no slug (a human opened it).
#
# **This backend never hands out a name it cannot address, and it has nothing to
# refuse** ([48], [64]). The number is an integer the forge allocated, and the
# slug travels in the rendering the transport already uses — `\n` and `\t` for the
# two separators, `\\` for the backslash that renders them — so an id is one line
# by construction whatever a human types in the `Slug:` field of an issue. That is
# the answer `lib/tracker.sh` already provides for: a backend numbering
# server-side calls `tracker_refuse_name` never and finds nothing at the
# preflight, which is the right answer rather than a missing one, exactly as it is
# for `ambiguous-id`.
#
# What it costs, said rather than left to be discovered: an id for an issue whose
# slug carries a tab reads `12-a\tb` and not `12-a<TAB>b`. It is the name the pack
# uses in its lists and its journal; the name a human needs to find the issue is
# the number, and that half is exact.
forge__record_id() {
  local num="$1" slug="$2"
  [ -n "$slug" ] || {
    printf '%s\n' "$num"
    return 0
  }
  printf '%s\n' "$num-$slug"
  return 0
}

# The record of one id, by its number half. An id is `<number>` or
# `<number>-<slug>`, and the number is what the forge knows.
forge__record() {
  local flavour="$1" id="$2" num rec
  num="${id%%-*}"
  case "$num" in
    '' | *[!0-9]*) return 1 ;;
  esac
  rec="$(forge__records "$flavour")" || return 1
  printf '%s' "$rec" | LC_ALL=C awk -F'\t' -v n="$num" '$1 == n { print; found = 1; exit }
    END { if (!found) exit 1 }'
}

forge__number() {
  local id="$1" num="${1%%-*}"
  case "$num" in
    '' | *[!0-9]*) return 1 ;;
  esac
  printf '%s\n' "$num"
  return 0
}

# ── reading ──────────────────────────────────────────────────────────────────

# Every id, and **non-zero when the tracker could not be listed** ([59], and AC 5
# of [18]). An empty list is the answer "this tracker holds no tickets", which is
# what `gate__surface_owner` reads as "no other ticket declared this path" — so a
# refusal read as emptiness turns every drift against a contract into a stray
# write and retries it for ever. The records are taken into a variable first for
# exactly that: a heredoc command substitution swallows the status.
# One field of a tab-separated record, by position, and **never** `IFS=<tab> read`.
# A tab is an IFS whitespace character, so a run of them collapses and a leading
# one is dropped: a record whose assignee is empty — every unclaimed ticket —
# arrived one field short, and the frontier read the forge's `open` as the ticket's
# slug. Peeled with parameter expansion, which splits nothing and collapses
# nothing.
forge__field_at() {
  local line="$2" tab i=1
  tab="$(printf '\t')"
  while [ "$i" -lt "$1" ]; do
    case "$line" in
      *"$tab"*) line="${line#*"$tab"}" ;;
      *) return 1 ;;
    esac
    i=$((i + 1))
  done
  printf '%s\n' "${line%%"$tab"*}"
  return 0
}

# The last field, which is the body: everything after the fourth tab, tabs
# included — there are none, the escaping saw to that, but taking the tail rather
# than one field is what keeps that true if the record ever grows a column.
forge__body_at() {
  local line="$1" tab i=1
  tab="$(printf '\t')"
  while [ "$i" -le 4 ]; do
    case "$line" in
      *"$tab"*) line="${line#*"$tab"}" ;;
      *) return 1 ;;
    esac
    i=$((i + 1))
  done
  printf '%s\n' "$line"
  return 0
}

forge_ids() {
  local flavour="$1" line num slug id records
  records="$(forge__records "$flavour")" || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    num="$(forge__field_at 1 "$line")" || continue
    slug="$(forge__field_at 2 "$line")" || slug=''
    id="$(forge__record_id "$num" "$slug")" || continue
    printf '%s\n' "$id"
  done <<RECORDS
$records
RECORDS
  return 0
}

forge_read_ticket() {
  local flavour="$1" id="$2" rec body
  rec="$(forge__record "$flavour" "$id")" || return 1
  body="$(printf '%s' "$rec" | cut -f5-)"
  forge__unescape "$body"
  printf '\n'
  return 0
}

# One field out of a body, with the same tolerance the local backend reads a file
# with — `**Name:** v` or `Name: v`, trailing blanks trimmed, `[[:space:]]` so a
# CRLF checkout does not silently drop every ticket out of the frontier.
forge__field_of() {
  local body="$1" name="$2"
  printf '%s\n' "$body" |
    sed -n "s/^\*\*$name:\*\*[[:space:]]*//p; s/^$name:[[:space:]]*//p" |
    awk 'NR == 1 { sub(/[[:space:]]+$/, ""); print }'
}

# One field of one ticket.
#
# `Claimed` is the one field that is not read out of the body, and that is
# spec §152 rather than an optimisation: liveness is single-machine, so who holds
# a claim is a question this machine answers about itself. See `forge__claimed`.
forge_field() {
  local flavour="$1" id="$2" name="$3" rec body
  if [ "$name" = Claimed ]; then
    forge__claimed "$flavour" "$id"
    return $?
  fi
  rec="$(forge__record "$flavour" "$id")" || return 1
  body="$(forge__unescape "$(printf '%s' "$rec" | cut -f5-)")"
  forge__field_of "$body" "$name"
  return 0
}

# The frontier: `ready-for-agent`, unblocked, in number order.
forge_frontier() {
  local flavour="$1" line num slug body id records
  records="$(forge__records "$flavour")" || {
    # Says so rather than reporting an empty frontier: "no tickets" and "the forge
    # would not answer" look identical from the loop, and only one is good news.
    #
    # **What the non-zero buys, and what it does not**, because the second half is
    # the honest part. `select_next_ticket` reads it; `loop__next_ticket` — the one
    # the pilot actually uses — reads the frontier through a heredoc command
    # substitution, which swallows a status, so a refused listing still reaches the
    # pilot as an empty frontier and an empty frontier is what starts the terminal
    # value gate. Closing that is a change to the loop, which AC 1 of [18] forbids;
    # what is done here instead is on this side of the interface — `forge__api`
    # retries a read before giving up, so a blip is not a night — and the residue
    # has its row in `docs/frontiere-de-confiance.md`.
    printf 'forge: the tracker could not be listed — this is not an empty frontier\n' >&2
    return 1
  }
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    num="$(forge__field_at 1 "$line")" || continue
    slug="$(forge__field_at 2 "$line")" || slug=''
    id="$(forge__record_id "$num" "$slug")" || continue
    # Guarded, because both entry points run under `set -e`: a record with fewer
    # columns than this expects is a bug in `forge__records`, and the shape it
    # would take here is a run that ends in the middle of a frontier scan rather
    # than a ticket that is skipped.
    body="$(forge__body_at "$line")" || continue
    body="$(forge__unescape "$body")"
    [ "$(forge__field_of "$body" Status)" = "ready-for-agent" ] || continue
    forge__is_unblocked "$flavour" "$body" || continue
    printf '%s\n' "$id"
  done <<RECORDS
$records
RECORDS
  return 0
}

# Every blocker resolved. An id that points at nothing blocks: an unknown
# dependency is never safe to assume met — the same fail-safe the local backend
# applies, and the same bare-number vocabulary ([27]).
forge__is_unblocked() {
  local flavour="$1" body="$2" raw dep status
  raw="$(forge__field_of "$body" 'Blocked by')"
  [ -n "$raw" ] || return 0
  for dep in $(printf '%s' "$raw" | tr ',' ' '); do
    case "$dep" in
      [0-9]*) ;;
      *) continue ;;
    esac
    status="$(forge_field "$flavour" "${dep%%-*}" Status)" || return 1
    [ "$status" = resolved ] || return 1
  done
  return 0
}

# ── writing a field ──────────────────────────────────────────────────────────

# Set or drop any number of fields of one ticket, and publish the whole body in
# one request. Callers never see a half-updated ticket, for the reason
# `tracker_local__set_fields` publishes in one rename.
forge__set_fields() {
  local flavour="$1" id="$2"
  shift 2
  local rec body num name value payload bodykey
  rec="$(forge__record "$flavour" "$id")" || return 1
  num="$(printf '%s' "$rec" | cut -f1)"
  body="$(forge__unescape "$(printf '%s' "$rec" | cut -f5-)")"
  while [ "$#" -ge 2 ]; do
    name="$1"
    value="$2"
    shift 2
    if [ "$value" = "--drop" ]; then
      body="$(forge__drop_field "$body" "$name")"
    else
      body="$(forge__patch_field "$body" "$name" "$value")"
    fi
  done
  bodykey="$(forge__spec "$flavour" body-key)" || return 1
  payload="{\"$bodykey\":$(printf '%s' "$body" | forge_json_string)}"
  forge__update "$flavour" "$num" "$payload" || return 1
  return 0
}

# **Neither the name nor the value travels through `awk -v`**, and that is a
# fragility this pack measured before it had a backend that could be bitten by it
# (passe transversale du 29/07/2026): awk interprets escapes in a `-v` assignment,
# so a value carrying `\n` arrives as a real newline and cuts the ticket in two —
# the field after it falls into the body and stops being read. On the local backend
# no value was ever of hostile origin; here `Escalation:` can carry what a drain
# pinned off a ticket, and a slug can carry what a human typed. `ENVIRON` is passed
# as bytes and interprets nothing.
forge__patch_field() {
  local body="$1" name="$2" value="$3"
  printf '%s\n' "$body" |
    FORGE_FIELD_NAME="$name" FORGE_FIELD_VALUE="$value" LC_ALL=C awk '
    BEGIN { done = 0; has = 0; n = ENVIRON["FORGE_FIELD_NAME"]; v = ENVIRON["FORGE_FIELD_VALUE"] }
    { line[NR] = $0
      if (!has && (index($0, "**" n ":**") == 1 || index($0, n ":") == 1)) has = 1 }
    END {
      for (k = 1; k <= NR; k++) {
        l = line[k]
        if (has && !done && (index(l, "**" n ":**") == 1 || index(l, n ":") == 1)) {
          print "**" n ":** " v
          done = 1
          continue
        }
        print l
        if (!has && !done && (index(l, "**Status:**") == 1 || index(l, "Status:") == 1)) {
          print ""
          print "**" n ":** " v
          done = 1
        }
      }
      if (!done) { print ""; print "**" n ":** " v }
    }'
}

forge__drop_field() {
  local body="$1" name="$2"
  printf '%s\n' "$body" | FORGE_FIELD_NAME="$name" LC_ALL=C awk '
    BEGIN { n = ENVIRON["FORGE_FIELD_NAME"] }
    index($0, "**" n ":**") == 1 || index($0, n ":") == 1 { skip = 1; next }
    skip == 1 && $0 == "" { skip = 0; next }
    { skip = 0; print }'
}

# One issue updated, and the memo of this shell dropped with it.
forge__update() {
  local flavour="$1" num="$2" payload="$3" path method
  path="$(forge__path "$flavour" issue "$num")" || return 1
  method="$(forge__spec "$flavour" update-method)" || return 1
  forge__api "$flavour" "$method" "$path" "$payload" >/dev/null || return 1
  forge__forget
  return 0
}

# ── the claim, and the sidecar that decides its liveness ─────────────────────
#
# The claim is **published** as the issue's assignee, which is what [18]'s AC
# asks for and what a human looking at the forge sees. What decides whether it is
# still held is a **local** record, which is spec §152 and not an implementation
# detail: `claim.sh` pings a pid, and a pid means nothing on another host. So a
# claim this machine took reads `owner=pid:<n>`, and the ordinary liveness of
# `lib/claim.sh` applies to it unchanged — including reclaiming it at sight when
# the run that took it is gone, which is the wedge a remote backend would otherwise
# only ever leave to `CLAIM_TTL`.
#
# An assignee this machine did not stamp reads `owner=assignee:<login>`, which
# `claim_owner_kind` calls `foreign`: never pinged, never reclaimed on sight, judged
# by `CLAIM_TTL` alone, and — since [26] — never charged a retry for having been
# waited out. Stealing a ticket a human is assigned to would be worse than waiting.
#
# **What that leaves open, written here rather than discovered:** with `CLAIM_TTL`
# disabled *and* an assignee this machine never stamped, nothing ever reclaims the
# ticket. That is [12]'s deliberate answer and not an oversight — the alternative is
# a pack that takes work away from a person — and it is bounded on the side that
# matters, this pack's own runs, by the record below.
#
# The record's `at` for an assignee this machine did not stamp is the moment this
# machine **first saw** the assignment, not the moment it happened: the forges
# expose that only through a second request per ticket, and a claim with no
# timestamp at all is one `claim_age_seconds` refuses, which fails open and takes
# the ticket away from its assignee immediately. First sight is later than the
# truth, so it errs towards leaving the assignee alone.

forge__sidecar() {
  printf '%s/.forge-claims\n' "$(ralph_feature_dir)"
}

# The last record for an id, or nothing. Append-only with the last line winning:
# every writer here appends one short line, which a POSIX filesystem does not
# interleave, so two iterations recording two tickets never need a lock for this.
forge__local_record() {
  local id="$1" kind="$2" file value
  file="$(forge__sidecar)"
  [ -f "$file" ] || return 1
  # `ENVIRON` and not `-v`, for `forge__patch_field`'s reason: awk interprets the
  # escapes of a `-v` assignment, and an id may carry the `\\` this transport
  # renders a backslash with — which would look up a key one character shorter
  # than the one that was written.
  value="$(FORGE_ID="$id" FORGE_KIND="$kind" LC_ALL=C awk -F'\t' '
    BEGIN { id = ENVIRON["FORGE_ID"]; k = ENVIRON["FORGE_KIND"] }
    $1 == id && $2 == k { v = $3 }
    END { if (v == "" || v == "-") exit 1; print v }' "$file")" || return 1
  printf '%s\n' "$value"
  return 0
}

forge__record_local() {
  local id="$1" kind="$2" value="$3" file dir
  file="$(forge__sidecar)"
  dir="$(dirname "$file")"
  mkdir -p "$dir" 2>/dev/null || return 1
  printf '%s\t%s\t%s\n' "$id" "$kind" "$value" >>"$file" 2>/dev/null || return 1
  return 0
}

# The `Claimed:` record of a ticket, in the shape the interface fixes:
# `owner=<who> at=<iso8601>`. Empty when nothing holds it.
forge__claimed() {
  local flavour="$1" id="$2" rec who record now
  record="$(forge__local_record "$id" claim)" || record=''
  if [ -n "$record" ]; then
    printf '%s\n' "$record"
    return 0
  fi
  rec="$(forge__record "$flavour" "$id")" || return 1
  who="$(printf '%s' "$rec" | cut -f3)"
  [ -n "$who" ] || return 0
  now="$(ralph_now)"
  record="owner=assignee:$who at=$now"
  # First sight, stamped so that the backstop counts from something. Recorded and
  # not recomputed: a timestamp recomputed on every read is a claim that is never
  # older than a second, which is a backstop that never fires.
  forge__record_local "$id" claim "$record" || true
  printf '%s\n' "$record"
  return 0
}

# The guard that serialises what this machine does to the tracker: taking a claim,
# and opening a ticket under a slug nobody else has taken. Beside the run lock and
# not on a ticket, for [49]'s rule — a guard about the tracker as a whole belongs
# where the run lock is.
#
# **It serialises this machine and nothing more, and that is the honest limit of a
# remote backend here.** Neither forge offers a compare-and-swap on an issue, so
# two runs on two hosts can both read `ready-for-agent` and both stamp themselves.
# That is spec §213 — liveness is single-machine, there is no distributed
# orchestration — said in the one place where somebody would otherwise assume the
# forge provides it.
forge__guard() {
  printf '%s/.forge.guard\n' "$(ralph_feature_dir)"
}

forge__guard_take() {
  local tries=120
  while [ "$tries" -gt 0 ]; do
    state_guard_take "$(forge__guard)" "forge guard" "${FEATURE:-unknown}" && return 0
    tries=$((tries - 1))
    sleep 0.05
  done
  return 1
}

forge__guard_release() {
  state_guard_release "$(forge__guard)"
  return 0
}

forge_claim() {
  local flavour="$1" id="$2" owner="${3:-pid:$$}" rec num status rc=0
  num="$(forge__number "$id")" || return 1

  forge__guard_take || return 1
  forge__forget
  rec="$(forge__record "$flavour" "$id")" || {
    forge__guard_release
    return 1
  }
  status="$(forge__field_of "$(forge__unescape "$(printf '%s' "$rec" | cut -f5-)")" Status)"
  if [ "$status" = ready-for-agent ]; then
    if forge__set_fields "$flavour" "$id" Status claimed; then
      forge__record_local "$id" claim "owner=$owner at=$(ralph_now)" || rc=1
      forge__assign "$flavour" "$num" || true
    else
      rc=1
    fi
  else
    rc=1
  fi
  forge__guard_release
  return "$rc"
}

# The claim as the forge tells it. A failure here is **not** a failed claim: the
# ticket is already `claimed` in the body, which is what every read of this pack
# goes through, and refusing would leave a ticket marked and unowned. Said, and
# carried on.
forge__assign() {
  local flavour="$1" num="$2" payload
  [ -n "${TRACKER_USER:-}" ] || return 0
  payload="$(forge__assign_payload "$flavour")" || return 0
  forge__update "$flavour" "$num" "$payload" || {
    printf 'forge: %s could not be assigned to %s — the claim stands in the ticket, and the forge does not show it\n' \
      "$num" "$TRACKER_USER" >&2
    return 1
  }
  return 0
}

forge__unassign() {
  local flavour="$1" num="$2" payload
  payload="$(forge__spec "$flavour" unassign)" || return 0
  forge__update "$flavour" "$num" "$payload" || return 1
  return 0
}

# What to send to hand the issue to `TRACKER_USER`. One forge names the login,
# the other wants a numeric id — looked up once per shell, because a lookup per
# claim is a request per ticket for an answer that does not change.
forge__assign_payload() {
  local flavour="$1" how uid
  how="$(forge__spec "$flavour" assign-by)" || return 1
  case "$how" in
    login) printf '{"assignees":["%s"]}\n' "$TRACKER_USER" ;;
    id)
      uid="$(forge__user_id "$flavour")" || return 1
      printf '{"assignee_ids":[%s]}\n' "$uid"
      ;;
    *) return 1 ;;
  esac
  return 0
}

forge__user_id() {
  local flavour="$1" path body uid
  if [ "$FORGE__USER_ID_KEY" = "$flavour/$TRACKER_USER" ] && [ -n "$FORGE__USER_ID" ]; then
    printf '%s\n' "$FORGE__USER_ID"
    return 0
  fi
  path="$(forge__path "$flavour" user "$TRACKER_USER")" || return 1
  body="$(forge__api "$flavour" GET "$path")" || return 1
  uid="$(printf '%s\n' "$body" | forge_json | LC_ALL=C awk -F'\t' '$1 == "0.id" { print $2; exit }')" || return 1
  [ -n "$uid" ] || return 1
  FORGE__USER_ID="$uid"
  FORGE__USER_ID_KEY="$flavour/$TRACKER_USER"
  printf '%s\n' "$uid"
  return 0
}

# Every transition that stops this machine holding the ticket drops the local
# record with it. A record left behind is a claim this pack would go on believing
# it holds, on a ticket somebody else has since taken.
forge__drop_claim() {
  local flavour="$1" id="$2" num
  forge__record_local "$id" claim '-' || true
  num="$(forge__number "$id")" || return 0
  forge__unassign "$flavour" "$num" || true
  return 0
}

# ── the transitions ──────────────────────────────────────────────────────────

forge_unclaim() {
  local flavour="$1" id="$2"
  forge__set_fields "$flavour" "$id" Status ready-for-agent Claimed --drop || return 1
  forge__drop_claim "$flavour" "$id"
  return 0
}

# The gate came back green — and on this backend that is not the last word, when
# the project asked for one ([18]'s AC on `wait_ci`).
#
# The order is the guarantee: the request is opened and its CI is waited on
# **before** anything is closed, so a ticket whose pipeline goes red is never
# `resolved` for a moment. On red, on a timeout, or when the request could not be
# opened at all, this escalates instead and refuses.
#
# **What that refusal costs, said here because nothing else says it.** `loop.sh`
# does not read this operation's status — it journals `resolved` and moves on —
# so a red pipeline leaves `run.log` saying `resolved` while the tracker says
# `ready-for-human`. The tracker is right: it is the authority every later scan,
# the drain included, reads. The journal records this run's own verdict, which was
# the gate's, and the forge's verdict arrives after it. Making the loop read the
# status is a change to the loop's control flow, which [18] is explicitly not
# allowed to make; it is written down in `docs/frontiere-de-confiance.md` and owned
# by a ticket of its own.
forge_mark_resolved() {
  local flavour="$1" id="$2" verdict
  if forge__wait_ci_wanted; then
    verdict="$(forge__integrate "$flavour" "$id")" || {
      forge_mark_escalated "$flavour" "$id" "${verdict:-ci-unreachable}" || true
      return 1
    }
  fi
  forge__set_fields "$flavour" "$id" Status resolved Claimed --drop Failures --drop || return 1
  forge__drop_claim "$flavour" "$id"
  forge__close "$flavour" "$id" || true
  return 0
}

forge_mark_escalated() {
  local flavour="$1" id="$2"
  [ "$#" -ge 3 ] || return 2
  local reason="$3"
  if [ -n "$reason" ]; then
    forge__set_fields "$flavour" "$id" Status ready-for-human Escalation "$reason" Claimed --drop || return 1
  else
    forge__set_fields "$flavour" "$id" Status ready-for-human Escalation --drop Claimed --drop || return 1
  fi
  forge__drop_claim "$flavour" "$id"
  forge__reopen "$flavour" "$id" || true
  return 0
}

forge_mark_ready() {
  local flavour="$1" id="$2"
  forge__set_fields "$flavour" "$id" Status ready-for-agent Claimed --drop Escalation --drop || return 1
  forge__drop_claim "$flavour" "$id"
  forge__reopen "$flavour" "$id" || true
  return 0
}

forge_mark_wontfix() {
  local flavour="$1" id="$2"
  forge__set_fields "$flavour" "$id" Status wontfix Claimed --drop Escalation --drop \
    Failures --drop || return 1
  forge__drop_claim "$flavour" "$id"
  forge__close "$flavour" "$id" || true
  return 0
}

forge_clear_failures() {
  local flavour="$1" id="$2"
  forge__set_fields "$flavour" "$id" Failures --drop
}

forge_bump_failures() {
  local flavour="$1" id="$2" current next
  current="$(forge_field "$flavour" "$id" Failures)" || current=''
  case "$current" in
    '' | *[!0-9]*) current=0 ;;
  esac
  next=$((current + 1))
  forge__set_fields "$flavour" "$id" Failures "$next" || return 1
  printf '%s\n' "$next"
  return 0
}

# Hold a ticket until other tickets are resolved, keeping the blockers already
# there — the same merge the local backend makes, and for the same reason: they
# were resolved when it entered the frontier, so dropping them loses what a human
# wrote and changes nothing for the loop.
forge_block_on() {
  local flavour="$1" id="$2" deps="${3:-}" current dep merged=''
  current="$(forge_field "$flavour" "$id" 'Blocked by')" || current=''
  for dep in $(printf '%s %s' "$current" "$deps" | tr ',' ' '); do
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
  forge__set_fields "$flavour" "$id" "Blocked by" \
    "$(printf '%s' "$merged" | tr ' ' ',' | sed 's/,/, /g')"
}

forge__close() {
  local flavour="$1" id="$2" num payload
  num="$(forge__number "$id")" || return 1
  payload="$(forge__spec "$flavour" close)" || return 1
  forge__update "$flavour" "$num" "$payload"
}

forge__reopen() {
  local flavour="$1" id="$2" num payload
  num="$(forge__number "$id")" || return 1
  payload="$(forge__spec "$flavour" reopen)" || return 1
  forge__update "$flavour" "$num" "$payload"
}

# ── creating ─────────────────────────────────────────────────────────────────

# The slug as this backend will hand it out. Normalised **before** it becomes part
# of an id and never after it has been read back ([48]): a title is prose and a
# caller's slug is prose too, and an id is a line in every list this pack carries.
forge__slug() {
  local slug
  slug="$(printf '%s' "$1" | tr 'A-Z' 'a-z' |
    tr -c 'a-z0-9-' '-' | sed -e 's/-\{1,\}/-/g' -e 's/^-//' -e 's/-$//' |
    cut -c1-60 | sed 's/-$//')" || slug=''
  printf '%s\n' "$slug"
  return 0
}

forge_open_ticket() {
  forge__open "$1" "$2" "$3" ''
}

forge_open_unique() {
  forge__open "$1" "$2" "$3" unique
}

# The body is read before the guard is taken, for the reason the local backend
# reads it before allocating a number: under the guard, the whole creation path
# would wait on somebody else's stdin.
forge__open() {
  local flavour="$1" slug="$2" title="$3" unique="${4:-}" body payload num id rc=0
  body="$(cat)"
  slug="$(forge__slug "$slug")"
  [ -n "$slug" ] || slug=ticket

  forge__guard_take || {
    printf 'forge: refusing to open a ticket against a tracker nothing serialises\n' >&2
    return 1
  }
  forge__forget

  if [ -n "$unique" ] && forge__slug_taken "$flavour" "$slug"; then
    forge__guard_release
    return 0
  fi

  # The slug is a field of the body and not a decoration of the title, because it
  # has to come back in the **listing** — one request for the whole tracker — and
  # because a title is what a human renames.
  body="$(forge__patch_field "$body" Slug "$slug")"
  payload="$(forge__create_payload "$flavour" "$title" "$body")" || rc=1
  if [ "$rc" = 0 ]; then
    num="$(forge__create "$flavour" "$payload")" || rc=1
  fi
  forge__guard_release
  [ "$rc" = 0 ] || return 1
  id="$num-$slug"
  printf '%s\n' "$id"
  return 0
}

forge__create_payload() {
  local flavour="$1" title="$2" body="$3" bodykey
  bodykey="$(forge__spec "$flavour" body-key)" || return 1
  printf '{"title":%s,"%s":%s}\n' \
    "$(printf '%s' "$title" | forge_json_string)" "$bodykey" \
    "$(printf '%s' "$body" | forge_json_string)"
  return 0
}

forge__create() {
  local flavour="$1" payload="$2" path body idkey num
  path="$(forge__path "$flavour" create)" || return 1
  idkey="$(forge__spec "$flavour" id-key)" || return 1
  body="$(forge__api "$flavour" POST "$path" "$payload")" || return 1
  num="$(printf '%s\n' "$body" | forge_json |
    LC_ALL=C awk -F'\t' -v k="$idkey" '$1 == k { print $2; exit }')" || return 1
  [ -n "$num" ] || return 1
  forge__forget
  printf '%s\n' "$num"
  return 0
}

forge__slug_taken() {
  local flavour="$1" slug="$2" line s
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    s="$(forge__field_at 2 "$line")" || continue
    [ "$s" = "$slug" ] || continue
    return 0
  done <<RECORDS
$(forge__records "$flavour" || printf '')
RECORDS
  return 1
}

# An id no other ticket shares, which on a forge is the id it already has: numbers
# are allocated server-side, so the collision `tracker_renumber` exists to undo
# cannot happen here. Written down rather than deduced from the fact that it works
# ([27]) — and the question underneath still has an answer: `forge__record` matches
# on the number, and a number is unique in a repository, so two tickets never claim
# one identifier.
forge_renumber() {
  printf '%s\n' "$2"
  return 0
}

forge_append_note() {
  local flavour="$1" id="$2" num note path payload
  num="$(forge__number "$id")" || return 1
  note="$(cat)"
  path="$(forge__path "$flavour" note "$num")" || return 1
  payload="{\"body\":$(printf '%s' "$note" | forge_json_string)}"
  forge__api "$flavour" POST "$path" "$payload" >/dev/null || return 1
  return 0
}

# ── the receipt, which is the request ────────────────────────────────────────
#
# On this backend the audit receipt is the pull (or merge) request of the
# iteration ([10], spec §52). The document arrives on stdin and a location goes
# back on stdout, exactly as it does for a file.
#
# **What becomes of the git references the receipt carries**, which [10] left to
# this ticket. The receipt sends a reader to `git show <sha>` and
# `git log -p failed/<id>`, and those are objects of the repository the run was
# started in — a sentence that references nothing for somebody who does not have
# it. The answer is not to inline the diff, which [10] refused and for a reason
# that has not changed: a receipt is not a second copy of the repository. The
# answer is that **this backend pushes the branch it is talking about**. The
# request carries the tree, the reader is looking at the diff while reading the
# receipt, and the shas resolve for anybody who fetched. What is still local is
# `failed/<id>`, and the receipt already says so in its own words.
#
# **What attests it, and what does not** ([70]). Nothing here does. A file receipt
# lives in the main working tree, which is a zone this pack witnesses; a request
# lives on a service a session reaches over the network, and no scope-guard, no
# rollback and no witness of this pack sees a write made there. `tracker_receipt_dir`
# refuses on this backend, the run says so once at startup (`forensic_uncovered`),
# and `router_dossier` prints the reserve written for it rather than the one written
# for a file. What does attest it is the forge's own record of who wrote what,
# which this pack neither reads nor checks.
#
# **It writes no ticket**, and that is a decision rather than a limitation ([10]):
# an adapter that wrote a link, a label or a comment onto the issue while emitting
# a receipt would have to note the id in the register of [13] itself, and the
# register belongs to the dispatcher — which exempts `emit_receipt` precisely
# because it writes a document *about* a ticket. So the link between the two is
# made by the forge, out of the `#<number>` the request's body carries, and the
# only thing this machine writes down is where the request is.
forge_emit_receipt() {
  local flavour="$1" id="$2" doc url
  doc="$(cat)"
  url="$(forge__request "$flavour" "$id" "$doc")" || return 1
  printf '%s\n' "$url"
  return 0
}

# Where the request for this ticket is, as this machine recorded it. Non-zero and
# silent when there is none — which on this backend also covers "this machine has
# never emitted a receipt for it", and that is the contract ([16]): the answer is
# "there is nothing to read", never a URL that resolves to nothing.
forge_receipt_path() {
  forge__local_record "$2" receipt
}

# The request, opened **or updated**, with the receipt as its body. The URL on
# stdout.
#
# Opened once per ticket and rewritten afterwards, which is not an optimisation: a
# second `POST` for a head branch that already has a request is a 422 on one forge
# and a duplicate on the other, and this is called twice on an ordinary green
# iteration — once by `mark_resolved`, which needs the request to exist before it
# can wait for its pipeline, and once by `emit_receipt`, which has the document.
# Which of the two happened is remembered where every other local fact about a
# ticket is, in the sidecar.
forge__request() {
  local flavour="$1" id="$2" doc="$3"
  local num branch head base payload path method body url urlkey idkey reqid bodykey
  num="$(forge__number "$id")" || return 1
  reqid="$(forge__local_record "$id" request)" || reqid=''
  head="$(forge__spec "$flavour" branch-prefix)" || head='ralph-'
  head="$head$id"

  branch="$(forge__push "$id" "$head")" || return 1

  if [ -n "$reqid" ]; then
    path="$(forge__path "$flavour" request-one "$reqid")" || return 1
    method="$(forge__spec "$flavour" update-method)" || return 1
    bodykey="$(forge__spec "$flavour" request-body-key)" || return 1
    payload="{\"$bodykey\":$(forge__receipt_text "$num" "$doc" | forge_json_string)}"
  else
    base="$(forge__base_branch)" || return 1
    path="$(forge__path "$flavour" request)" || return 1
    method=POST
    payload="$(forge__request_payload "$flavour" "$id" "$num" "$head" "$base" "$doc")" || return 1
  fi

  body="$(forge__api "$flavour" "$method" "$path" "$payload")" || return 1
  urlkey="$(forge__spec "$flavour" request-url-key)" || return 1
  idkey="$(forge__spec "$flavour" id-key)" || return 1
  url="$(printf '%s\n' "$body" | forge_json |
    LC_ALL=C awk -F'\t' -v k="$urlkey" '$1 == k { print $2; exit }')" || url=''
  [ -n "$url" ] || return 1
  if [ -z "$reqid" ]; then
    reqid="$(printf '%s\n' "$body" | forge_json |
      LC_ALL=C awk -F'\t' -v k="$idkey" '$1 == k { print $2; exit }')" || reqid=''
    [ -z "$reqid" ] || forge__record_local "$id" request "$reqid" || true
  fi
  forge__record_local "$id" receipt "$url" || true
  forge__record_local "$id" branch "$branch" || true
  printf '%s\n' "$url"
  return 0
}

# The issue number in the body, and it is the only link this adapter makes: both
# forges cross-reference an issue a request mentions, so a human sees the two
# together without this pack writing a word on the ticket ([10]).
forge__receipt_text() {
  printf 'Audit receipt for #%s.\n\n%s\n' "$1" "$2"
}

forge__request_payload() {
  local flavour="$1" id="$2" num="$3" head="$4" base="$5" doc="$6" headkey basekey
  headkey="$(forge__spec "$flavour" head-key)" || return 1
  basekey="$(forge__spec "$flavour" base-key)" || return 1
  doc="$(forge__receipt_text "$num" "$doc")"
  printf '{"title":%s,"%s":%s,"%s":%s,"%s":%s}\n' \
    "$(printf 'ralph: %s' "$id" | forge_json_string)" \
    "$headkey" "$(printf '%s' "$head" | forge_json_string)" \
    "$basekey" "$(printf '%s' "$base" | forge_json_string)" \
    "$(forge__spec "$flavour" request-body-key)" \
    "$(printf '%s' "$doc" | forge_json_string)"
  return 0
}

# The tree this iteration left, pushed under a name the request can point at. The
# name of the ref that was pushed, on stdout.
#
# `failed/<id>` when the attempt was rolled back and that ref exists, and `HEAD`
# otherwise: those are the two trees a receipt is ever about, and reading the
# repository for it rather than an environment variable keeps this adapter out of
# the loop's own vocabulary.
forge__push() {
  local id="$1" head="$2" src='HEAD'
  if git rev-parse --verify --quiet "refs/heads/failed/$id" >/dev/null 2>&1; then
    src="refs/heads/failed/$id"
  fi
  git push --force "${RECEIPT_REMOTE:-origin}" "$src:refs/heads/$head" >/dev/null 2>&1 || {
    printf 'forge: could not push %s to %s — there is no request to write the receipt into\n' \
      "$src" "${RECEIPT_REMOTE:-origin}" >&2
    return 1
  }
  printf '%s\n' "$src"
  return 0
}

# What the request is opened against. Configured, or the remote's own default
# branch, and refused when neither answers — a request opened against a guess is a
# diff nobody asked for.
forge__base_branch() {
  local ref
  if [ -n "${RECEIPT_BASE:-}" ]; then
    printf '%s\n' "$RECEIPT_BASE"
    return 0
  fi
  ref="$(git symbolic-ref --quiet "refs/remotes/${RECEIPT_REMOTE:-origin}/HEAD" 2>/dev/null)" || ref=''
  if [ -n "$ref" ]; then
    printf '%s\n' "${ref##*/}"
    return 0
  fi
  printf 'forge: RECEIPT_BASE is not set and %s has no default branch — nothing says what this request is against\n' \
    "${RECEIPT_REMOTE:-origin}" >&2
  return 1
}

# ── waiting for the forge's own verdict ──────────────────────────────────────

# Whether this run waits for CI. `off` never, `on` always, `auto` when the forge
# reports a pipeline for the branch — which is the default, and the only reading
# of "on by default if CI is detected" that does not block a project that has none.
forge__wait_ci_wanted() {
  case "${WAIT_CI:-auto}" in
    off | 0 | no) return 1 ;;
    *) return 0 ;;
  esac
}

# Open the request for this iteration and wait for its pipeline. Empty on stdout
# and zero when the forge said green (or had nothing to say and `WAIT_CI=auto`);
# a reason on stdout and non-zero otherwise, which is what `mark_resolved`
# escalates with.
forge__integrate() {
  local flavour="$1" id="$2" branch status waited=0 step limit
  limit="${WAIT_CI_TIMEOUT:-${GATE_TIMEOUT:-1800}}"
  case "$limit" in
    '' | *[!0-9]*) limit=1800 ;;
  esac
  step="${FORGE_CI_POLL:-10}"
  case "$step" in
    '' | *[!0-9]*) step=10 ;;
  esac

  forge__request "$flavour" "$id" "$(forge__pending_note "$id")" >/dev/null || {
    printf 'ci-unreachable\n'
    return 1
  }
  branch="$(forge__spec "$flavour" branch-prefix)" || branch='ralph/'
  branch="$branch$id"

  while [ "$waited" -le "$limit" ]; do
    status="$(forge__ci_status "$flavour" "$branch")" || status='unknown'
    case "$status" in
      success)
        return 0
        ;;
      none)
        # No pipeline at all. `auto` reads that as "this project has no CI", which
        # is the whole of the opt-in; `on` is a project that said it has one, and
        # a missing pipeline is then a fact worth escalating rather than passing.
        case "${WAIT_CI:-auto}" in
          on | 1 | yes)
            printf 'ci-absent\n'
            return 1
            ;;
          *) return 0 ;;
        esac
        ;;
      failed)
        printf 'ci-red\n'
        return 1
        ;;
      unknown)
        printf 'ci-unreachable\n'
        return 1
        ;;
    esac
    sleep "$step"
    waited=$((waited + step))
  done
  printf 'ci-timeout\n'
  return 1
}

# What a request says while its receipt is not written yet. The receipt replaces
# it the moment the iteration has one, and a request whose body was empty until
# then would be a review surface that says nothing during the only window somebody
# might be watching it.
forge__pending_note() {
  printf 'Opened by ralph for %s. The audit receipt replaces this text when the iteration has one.\n' "$1"
}

# `success`, `failed`, `pending`, `none` or `unknown` for a branch. `unknown` is a
# forge that would not answer, and it is deliberately not `none`: read as "there is
# no CI" it would pass a green through a network that said nothing ([59]'s rule,
# one module over).
forge__ci_status() {
  local flavour="$1" branch="$2" path body raw cikey
  path="$(forge__path "$flavour" ci "$branch")" || return 1
  body="$(forge__api "$flavour" GET "$path")" || {
    printf 'unknown\n'
    return 0
  }
  cikey="$(forge__spec "$flavour" ci-key)" || cikey=''
  raw="$(printf '%s\n' "$body" | forge_json |
    LC_ALL=C awk -F'\t' -v k="$cikey" '$1 == k { print $2; exit }')" || raw=''
  forge__ci_normalise "$raw"
  return 0
}

# The two forges name the same three outcomes differently, and one of them uses a
# word the other uses for something else. Mapped in one place so that a reader
# comparing the backends reads a table rather than two dialects.
forge__ci_normalise() {
  case "${1:-}" in
    '') printf 'none\n' ;;
    success | passed | completed | neutral | skipped) printf 'success\n' ;;
    failure | failed | error | canceled | cancelled | timed_out | action_required) printf 'failed\n' ;;
    pending | running | queued | created | waiting_for_resource | preparing | scheduled | manual | in_progress) printf 'pending\n' ;;
    *) printf 'unknown\n' ;;
  esac
  return 0
}

# ── paths ────────────────────────────────────────────────────────────────────

# One endpoint of one forge, with the repository and the argument already in it.
#
# `{repo}` and `{arg}` and never a `printf` format, which is not a matter of
# taste: `printf` reuses its format while arguments remain, so a template naming
# the repository and not the argument would print the path **twice** — and a
# template built out of a value the project configured is a format string the
# project writes. Parameter expansion has neither behaviour.
forge__path() {
  local flavour="$1" which="$2" arg="${3:-}" tmpl repo enc path
  tmpl="$(forge__spec "$flavour" "path-$which")" || return 1
  repo="$(forge__repo)" || return 1
  enc="$(printf '%s' "$repo" | forge__urlenc)"
  path="${tmpl//\{repo\}/$enc}"
  path="${path//\{arg\}/$(printf '%s' "$arg" | forge__urlenc)}"
  printf '%s\n' "$path"
  return 0
}
