# shellcheck shell=bash
# The usage budget: what is left of the subscription, and what the loop does
# when it runs out.
#
# ## Two sources, and only one of them may decide
#
#   the endpoint    `GET /api/oauth/usage`. **Proactive**: it answers before a
#                   session exists, which is the only way to *not* spawn one. And
#                   it is out of reach of the thing being judged — nothing a
#                   session writes changes what it says.
#   the in-band     every session's stream carries a `rate_limit_event` early on,
#   signal          with the same three facts (window, status, reset). **Free**,
#                   and under contract against the real binary ([20]). But it
#                   arrives in `.scratch/<feature>/.session.$$.jsonl`, and that is
#                   a file the judged session can write — the same boundary that
#                   made [23] pay for a second deadline.
#
# So the endpoint decides whenever it answers, and the in-band signal is a
# corrective that may only ever make this run **more** cautious, never less. What
# a forged one can buy is bounded twice over, by things no session writes:
# `BUDGET_MAX_PAUSE` bounds one pause, and the loop's own `STERILE_K` bounds how
# many unproductive iterations a run will sit through. A pause never touches
# `Failures:` — that field is the ticket's retry budget, and a subscription
# running out is not an attempt at the ticket ([26] on what a named field owes).
#
# ## What this module does not gate, and why
#
# **The re-slice session** ([07]) and **the review lenses** ([06]) are sessions
# too, and neither is gated here. Both run *inside* an iteration the gate below
# already cleared, and gating them would mean sleeping for hours in the middle of
# a failure path with a ticket claimed and a tree waiting to be rolled back — or,
# for a lens, inside a gate branch under `GATE_TIMEOUT`. The proactive gate is
# asked once per iteration, before a ticket is claimed, and that is the only
# place in this pack where sleeping is safe.
#
# Not gated is not the same as not *read*, and [43] is the difference. A lens the
# API refused judged nothing, so the two readers below are pointed at its stream
# too — by `lenses_refused_posture`, in the gate, before the gate's temporary
# directory goes. What comes back is a correction the pilot applies at the top of
# the next iteration, exactly like the delivery session's, and a ticket the gate
# went red on for that reason alone is given back without a retry charged. It
# still is not a decision taken inside the iteration: nothing sleeps down there.
#
# **An iteration is `1 + n` sessions, not one** ([06]): two review lenses always,
# up to five. This module cannot price that in advance — it compares utilisation
# ratios, not tokens — so the honest thing is to say it where a project sets the
# threshold rather than pretend the margin was computed. See ralph.config.sh.example.
#
# ## What is verified and what is merely built
#
# The in-band half is checked against the real binary by `test/contract-claude.bats`.
# The endpoint half is not: the suite is hermetic, the endpoint is undocumented,
# and the credential is the user's. `RALPH_REAL_USAGE=1` runs the one test that
# points this module's own parser at the real thing — the same posture [20] takes
# for the session stream. Until a human runs it, "this pack can read that payload"
# is an assumption, and it is written down as one in
# docs/frontiere-de-confiance.md rather than implied by a green suite.

budget__log() {
  printf 'ralph: budget: %s\n' "$*"
}

# ── configuration ────────────────────────────────────────────────────────────

budget_enabled() {
  [ "${BUDGET_CHECK:-on}" = on ]
}

# A threshold as a whole percent, so every comparison below is integer
# arithmetic in a shell that has no floats. Refused rather than defaulted when it
# is not a fraction — see budget_preflight.
budget__pct() {
  LC_ALL=C awk -v t="${1:-0}" 'BEGIN { printf "%d\n", int(t * 100 + 0.5) }'
}

budget__is_fraction() {
  LC_ALL=C awk -v t="${1:-}" \
    'BEGIN { exit (t ~ /^(0(\.[0-9]+)?|1(\.0+)?|\.[0-9]+)$/ && t + 0 > 0) ? 0 : 1 }'
}

# Refuse to start rather than grind a night behind a budget watch that cannot
# measure anything. Called from `loop_preflight` and not from `gate_preflight`:
# this is not a branch of the gate, it decides whether a session is spawned at
# all.
#
# Every refusal here is the same shape as the language gate's five ([17], [31]) —
# a value that switches the control off, or on for ever, without saying so:
#
#   BUDGET_CHECK       anything but on/off would be read as off.
#   THRESH_*           not a fraction reads as zero, and a threshold of zero
#                      blocks every spawn: the run would pause for ever. Above 1
#                      is the mirror — nothing ever crosses it.
#   USAGE_UA           the endpoint answers persistent 429s without a plausible
#                      one, so an empty value is a watch that never measures
#                      while looking exactly like one that does.
#   USAGE_URL          nothing to ask.
#   BUDGET_MAX_PAUSE   zero, or non-numeric read as zero, turns every session
#                      window into a stopped run.
#   USAGE_CACHE_TTL    non-numeric read as zero asks the endpoint on every
#                      iteration, which is how the 429s start.
budget_preflight() {
  local rc=0

  case "${BUDGET_CHECK:-on}" in
    on | off) ;;
    *)
      printf 'ralph: BUDGET_CHECK is "%s" — it has to be on or off, and anything else would switch the usage budget off by typo\n' \
        "${BUDGET_CHECK:-}" >&2
      rc=1
      ;;
  esac

  budget_enabled || return "$rc"

  if ! budget__is_fraction "${THRESH_5H:-}"; then
    printf 'ralph: THRESH_5H is "%s" — it has to be a fraction above 0 and at most 1; read as zero it would pause this run for ever, and above 1 nothing would ever cross it\n' \
      "${THRESH_5H:-}" >&2
    rc=1
  fi

  if ! budget__is_fraction "${THRESH_WEEK:-}"; then
    printf 'ralph: THRESH_WEEK is "%s" — it has to be a fraction above 0 and at most 1; read as zero it would stop this run before its first session\n' \
      "${THRESH_WEEK:-}" >&2
    rc=1
  fi

  if [ -z "${USAGE_UA:-}" ]; then
    printf 'ralph: USAGE_UA is empty — the usage endpoint answers persistent 429s without one, so the budget would never be measured while looking like it was. Set BUDGET_CHECK=off to run without a usage budget\n' >&2
    rc=1
  fi

  if [ -z "${USAGE_URL:-}" ]; then
    printf 'ralph: USAGE_URL is empty — there is nothing to ask. Set BUDGET_CHECK=off to run without a usage budget\n' >&2
    rc=1
  fi

  case "${BUDGET_MAX_PAUSE:-}" in
    '' | *[!0-9]* | 0)
      printf 'ralph: BUDGET_MAX_PAUSE is "%s" — it has to be a whole number of seconds above 0, or every blocked window would stop the run instead of waiting it out\n' \
        "${BUDGET_MAX_PAUSE:-}" >&2
      rc=1
      ;;
  esac

  case "${USAGE_CACHE_TTL:-}" in
    '' | *[!0-9]*)
      printf 'ralph: USAGE_CACHE_TTL is "%s" — it has to be a whole number of seconds (0 asks on every iteration, which is what the endpoint answers 429 to)\n' \
        "${USAGE_CACHE_TTL:-}" >&2
      rc=1
      ;;
  esac

  return "$rc"
}

# ── the endpoint ─────────────────────────────────────────────────────────────
#
# The cache lives in **this process's memory** and nowhere else, and that is the
# one decision in this file that closes a boundary rather than documenting it. A
# cache on disk would be a file the judged session can write — under `.scratch/`
# it is writable outright, and in `$TMPDIR` it is as reachable as the ignore
# witness [30] has to refuse when a session destroys it — and a control that reads
# what the controlled writes is not a control. A run is one process, the loop
# calls this from its own shell, and 180 s of freshness inside one run is exactly
# what the cache was for.
#
# The consequence is worth stating: nothing is shared between two runs, so two
# runs on two repositories ask twice. That is the correct trade against a shared
# file two runs would both write.

BUDGET__CACHE_BODY=''
BUDGET__CACHE_AT=0
BUDGET__SAID=''

# Said once per run, not once per iteration. A blind spot has to be named ([24]),
# and a line repeated fifty times is one a human learns to skip, which is the
# same as not saying it.
budget__say_once() {
  local key="$1"
  shift
  case " $BUDGET__SAID " in
    *" $key "*) return 0 ;;
  esac
  BUDGET__SAID="$BUDGET__SAID $key"
  budget__log "$*"
}

budget__now() {
  date +%s
}

# One request, or nothing. `--max-time` is not optional: a curl that hangs would
# hang the run in the one place where the loop is not watching a child, and this
# module exists to keep an AFK night bounded.
#
# The token comes from a command the project names, never from a file this pack
# goes looking for: a credential store is the user's business and its shape
# differs per platform. `USAGE_TOKEN_CMD` is read out of the sealed config ([24]),
# so it is exactly as trusted as `TEST_CMD` — which is the only reason evaluating
# it here is acceptable.
budget__request() {
  local token=''
  command -v curl >/dev/null 2>&1 || return 1
  if [ -n "${USAGE_TOKEN_CMD:-}" ]; then
    token="$(eval "${USAGE_TOKEN_CMD}" 2>/dev/null)" || token=''
  fi
  if [ -n "$token" ]; then
    curl -sS --max-time 10 \
      -H "User-Agent: ${USAGE_UA:-}" \
      -H "Authorization: Bearer $token" \
      "${USAGE_URL:-}" 2>/dev/null
  else
    curl -sS --max-time 10 \
      -H "User-Agent: ${USAGE_UA:-}" \
      "${USAGE_URL:-}" 2>/dev/null
  fi
}

# Refresh BUDGET__CACHE_BODY if it is older than the TTL. Non-zero when there is
# nothing to read: a body this run could not fetch, and an empty one, are the
# same answer — "I could not measure" — and neither of them is "nothing is used".
budget__fetch() {
  local force="${1:-0}" now age body
  now="$(budget__now)"
  age=$((now - BUDGET__CACHE_AT))
  if [ "$force" = 0 ] && [ -n "$BUDGET__CACHE_BODY" ] &&
    [ "$age" -ge 0 ] && [ "$age" -lt "${USAGE_CACHE_TTL:-180}" ]; then
    return 0
  fi
  body="$(budget__request)" || body=''
  [ -n "$body" ] || return 1
  BUDGET__CACHE_BODY="$body"
  BUDGET__CACHE_AT="$now"
  return 0
}

# One window of the payload as `<used-percent> <reset-epoch>`, or nothing.
#
# Deliberately not jq — the pack promises to run with nothing installed — and
# deliberately tolerant about two things the schema of an undocumented endpoint
# is entitled to differ on:
#
#   the reset key      `resets_at` (the spec) or `resetsAt` (the shape the
#                      in-band event uses), as an epoch or as an ISO instant.
#   the utilisation    a ratio in [0, 1], or a percent in (1, 100]. Both are
#                      converted to percent. `1` is read as the ratio, which is
#                      the cautious side of the one ambiguous value.
#
# What it is **not** tolerant about: a window it cannot read prints nothing.
# Reading a missing figure as zero is the false green this whole pack is built to
# refuse — a budget watch that passes everything in silence.
budget__window() {
  local body="$1" name="$2" object util reset epoch pct

  object="$(printf '%s' "$body" | tr -d ' \t\n' |
    sed -n "s/.*\"$name\":{\([^}]*\)}.*/\1/p")"
  [ -n "$object" ] || return 1

  util="$(printf '%s' "$object" | sed -n 's/.*"utilization":\([0-9][0-9.]*\).*/\1/p')"
  [ -n "$util" ] || return 1
  pct="$(LC_ALL=C awk -v u="$util" 'BEGIN {
    if (u < 0 || u > 100) exit 1
    printf "%d\n", (u <= 1 ? int(u * 100 + 0.5) : int(u + 0.5))
  }')" || return 1
  [ -n "$pct" ] || return 1

  reset="$(printf '%s' "$object" |
    sed -n 's/.*"resets\{0,1\}_\{0,1\}[aA]t":"\{0,1\}\([^,"}]*\)"\{0,1\}.*/\1/p')"
  epoch="$(budget__epoch "$reset")" || epoch=''

  printf '%s %s\n' "$pct" "$epoch"
}

# An instant as an epoch. A plain integer already is one; an ISO instant is
# handed to `date`, BSD spelling first because that is the shell this pack
# promises to run on, GNU second. Fractional seconds are dropped: no consumer
# here is measuring anything finer than a second.
#
# Non-zero rather than a guess when neither form parses. A run that slept a
# made-up span would be worse than one that stopped and said why.
budget__epoch() {
  local value="${1:-}" stamp
  [ -n "$value" ] || return 1
  case "$value" in
    *[!0-9]*) ;;
    *)
      printf '%s\n' "$value"
      return 0
      ;;
  esac
  stamp="$(printf '%s' "$value" | sed 's/\.[0-9]*Z$/Z/')"
  date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$stamp" +%s 2>/dev/null && return 0
  date -u -d "$stamp" +%s 2>/dev/null && return 0
  return 1
}

# ── the in-band signal ───────────────────────────────────────────────────────

# One flat scalar out of one stream line. Same shape as `session_result_field`
# and for the same reason: these are flat values and the pack has no jq.
budget__field() {
  printf '%s' "$1" | sed -n "s/.*\"$2\":\"\{0,1\}\([^,\"}]*\)\"\{0,1\}.*/\1/p"
}

# What the last `rate_limit_event` of a session's stream says, as
# `<status> <window> <reset-epoch>`, or nothing at all.
#
# The *last*, not the first: a session that ran long enough to be told twice is
# told the newer thing second. The event arrives third in the real capture — after
# `init` and a first thinking estimate — and nothing here depends on that position
# ([20] found it moves).
#
# Read before the stream is deleted, and passed around as a string afterwards: it
# is three words, and keeping the file alive to re-read them would keep a session's
# own file alive to be re-read. Two callers since [43], one per half of an
# iteration — the loop, on the delivery session's stream, and the gate, on a review
# lens's — and both of them read it while the file is still theirs to read.
budget_stream_posture() {
  local file="${1:-}" line
  [ -n "$file" ] && [ -f "$file" ] || return 0
  line="$(grep '"type":"rate_limit_event"' "$file" 2>/dev/null | tail -1)" || line=''
  [ -n "$line" ] || return 0
  printf '%s %s %s\n' \
    "$(budget__field "$line" status)" \
    "$(budget__field "$line" rateLimitType)" \
    "$(budget__field "$line" resetsAt)"
}

# Whether that posture says the session was not allowed to run.
#
# Anything that is not `allowed` counts as refused, including a status this pack
# has never seen. That is the cautious direction and it is the only direction a
# session-writable field is allowed to move a decision in: the cost of being
# wrong here is one iteration given back with no retry consumed, against a
# ticket billed for the subscription running out.
budget_refused() {
  local status
  status="$(printf '%s' "${1:-}" | awk '{ print $1 }')"
  [ -n "$status" ] || return 1
  [ "$status" != allowed ]
}

# ── the decision ─────────────────────────────────────────────────────────────

# May the loop spawn? Sets four variables in the caller's shell and returns
# non-zero when it may not:
#
#   RALPH_BUDGET_STATE    off | ok | blocked | unknown
#   RALPH_BUDGET_WINDOW   the window that blocks, when one does
#   RALPH_BUDGET_RESET    its reset instant as an epoch, when it is readable
#   RALPH_BUDGET_SOURCE   endpoint | stream | none
#   RALPH_BUDGET_HEADROOM how much of the tightest measured window is left before
#                         its threshold, as a percentage of that threshold — and
#                         **empty when nothing was measured**, which is not zero
#                         ([08]: a figure this pack cannot read is never read as
#                         nothing left). Nothing in this module acts on it; it is
#                         what lets [13] spend a nearly full window more slowly
#                         instead of running MAX_PARALLEL iterations at it
#
# Variables rather than stdout, and that is load-bearing: `$(budget_check)` would
# fork a subshell and the 180 s cache would die with it, so this run would ask the
# endpoint once per iteration and collect the 429s the cache exists to avoid.
#
# The order the windows are asked in is the order of what they *cost*. A weekly
# limit and a session window can both be over at once, and only one of the two
# answers "what should this run do now": sleeping to the session window's reset
# would wake up into the same wall.
budget_check() {
  local posture="${1:-}" force=0 name pct reset thresh seen=0 missing='' left

  RALPH_BUDGET_STATE=off
  RALPH_BUDGET_WINDOW=''
  RALPH_BUDGET_RESET=''
  RALPH_BUDGET_SOURCE=none
  RALPH_BUDGET_HEADROOM=''

  # Off is a declaration, and a run with no budget watch has to be
  # distinguishable from a run that measured one and found room ([24]: a zone
  # nobody guards gets said out loud).
  if ! budget_enabled; then
    budget__say_once off \
      "the usage budget is not watched (BUDGET_CHECK=off): nothing here will stop this run before it spends the subscription"
    return 0
  fi

  # A session that was told it is blocked is a reason to ask again rather than an
  # answer in itself: the cache would otherwise hold a "plenty left" for up to
  # three minutes across the very event that contradicts it.
  if budget_refused "$posture"; then force=1; fi

  if budget__fetch "$force"; then
    RALPH_BUDGET_SOURCE=endpoint
    for name in seven_day seven_day_opus five_hour; do
      # The opus limit is only this run's business when this run is spending it.
      # Gating a haiku night on a limit it does not touch would be a refusal
      # nobody could act on.
      if [ "$name" = seven_day_opus ] && ! budget__spends_opus; then
        continue
      fi
      read -r pct reset <<WINDOW
$(budget__window "$BUDGET__CACHE_BODY" "$name")
WINDOW
      if [ -z "${pct:-}" ]; then
        missing="$missing $name"
        continue
      fi
      seen=$((seen + 1))
      case "$name" in
        five_hour) thresh="$(budget__pct "${THRESH_5H:-0.95}")" ;;
        *) thresh="$(budget__pct "${THRESH_WEEK:-0.80}")" ;;
      esac
      # How much of this window is left before this project stops, as a share of
      # the threshold rather than of the window: the run stops at THRESH, so what
      # is spendable is the distance to it and not the distance to 100%. The
      # tightest window wins — a weekly cap at 5% left is not made roomier by a
      # session window that just reset. A threshold of zero would be a project
      # that stops immediately, and it is left at no headroom rather than divided
      # by.
      #
      # An `if` and not an `&&` chain: this file is sourced into a `set -e`
      # script, so a chain whose last test is false takes the whole function down
      # — and it would do it on the ordinary case, a window under its threshold.
      left=0
      if [ "$thresh" -gt 0 ] && [ "$pct" -lt "$thresh" ]; then
        left=$(((thresh - pct) * 100 / thresh))
      fi
      if [ -z "$RALPH_BUDGET_HEADROOM" ] || [ "$left" -lt "$RALPH_BUDGET_HEADROOM" ]; then
        RALPH_BUDGET_HEADROOM="$left"
      fi
      [ "$pct" -ge "$thresh" ] || continue
      RALPH_BUDGET_STATE=blocked
      RALPH_BUDGET_WINDOW="$name"
      RALPH_BUDGET_RESET="${reset:-}"
      budget__log "$name is at ${pct}% of the subscription and this project stops at ${thresh}%"
      return 1
    done

    if [ "$seen" -gt 0 ]; then
      [ -z "$missing" ] || budget__say_once missing \
        "the usage endpoint answered without$missing: those windows are not watched by this run"
      RALPH_BUDGET_STATE=ok
      return 0
    fi
    # A body that parsed as no window at all is a body this pack cannot read,
    # whatever HTTP thought of it.
    RALPH_BUDGET_SOURCE=none
  fi

  # Nothing from the endpoint. The in-band signal is all that is left, and it is
  # allowed to stop this run but never to let it carry on believing it measured
  # something.
  if budget_refused "$posture"; then
    RALPH_BUDGET_STATE=blocked
    RALPH_BUDGET_SOURCE=stream
    RALPH_BUDGET_WINDOW="$(printf '%s' "$posture" | awk '{ print $2 }')"
    [ -n "$RALPH_BUDGET_WINDOW" ] || RALPH_BUDGET_WINDOW=five_hour
    RALPH_BUDGET_RESET="$(budget__epoch "$(printf '%s' "$posture" | awk '{ print $3 }')")" ||
      RALPH_BUDGET_RESET=''
    budget__log "the usage endpoint said nothing this run could read, and the last session was told it is blocked ($RALPH_BUDGET_WINDOW)"
    return 1
  fi

  RALPH_BUDGET_STATE=unknown
  budget__say_once endpoint \
    "the usage endpoint could not be read ($USAGE_URL) — this run is flying on the in-band signal alone, which only ever arrives after a session has already started"
  return 0
}

# Whether this run is spending the opus limit at all. A name and not a probe:
# `MODEL` is what the spawn passes, and the alias a project writes (`opus`,
# `claude-opus-5`) is the only thing this pack sees before a session exists.
budget__spends_opus() {
  case "$(printf '%s' "${MODEL:-}" | tr 'A-Z' 'a-z')" in
    *opus*) return 0 ;;
  esac
  return 1
}

# ── waiting it out ───────────────────────────────────────────────────────────

# How long to sleep to reach an instant, or non-zero when this run must not.
#
# Refused rather than clamped when the instant is further out than
# `BUDGET_MAX_PAUSE`, and the difference matters in both directions. A session
# window resets within five hours, so a span beyond the cap is a clock that is
# wrong, an endpoint that is wrong, or a stream a session wrote — and a run that
# clamped would sleep the cap and then find the same wall. Stopping is visible in
# the morning; sleeping six hours to fail anyway is a night nobody hears about.
budget_span() {
  local reset="${1:-}" now span
  [ -n "$reset" ] || return 1
  case "$reset" in
    *[!0-9]*) return 1 ;;
  esac
  now="$(budget__now)"
  span=$((reset - now))
  [ "$span" -gt 0 ] || span=0
  [ "$span" -le "${BUDGET_MAX_PAUSE:-21600}" ] || return 1
  printf '%s\n' "$span"
}

# Sleep, in one-second steps, and give the loop its stop back.
#
# Not `sleep "$span"`, and this is the [25] lesson rather than a style: bash defers
# a trapped signal until the running external command returns, so a single five-hour
# sleep would hold a stop request for five hours. `RALPH_STOP` is the loop's, read
# here the way `gate.sh` reads the loop's `RALPH_IGNORE_PIN` — a run-level variable,
# not a call back up into the loop.
#
# Non-zero means it was cut short, and the loop stops rather than spawning into a
# window it never waited out.
#
# Waiting out a window is also what makes the cached answer worthless: it was
# measured before the reset this run has just slept through. Dropped here rather
# than left to the TTL, because the TTL is three minutes and the whole point of
# the pause is that the other side of it is a different world — a run that read
# the old body back would find the same wall and stop, having waited for nothing.
budget_pause() {
  local span="${1:-0}" started elapsed
  started=$SECONDS
  while :; do
    elapsed=$((SECONDS - started))
    if [ "$elapsed" -ge "$span" ]; then
      BUDGET__CACHE_BODY=''
      BUDGET__CACHE_AT=0
      return 0
    fi
    [ "${RALPH_STOP:-0}" = 0 ] || return 1
    sleep 1 || true
  done
}
