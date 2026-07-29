# shellcheck shell=bash
# Claim liveness: which claims are still held, and what becomes of a ticket
# whose owner is gone.
#
# Taking a claim is a test-and-set in the adapter (`tracker_claim`): one picker
# wins, the ticket leaves the frontier. Giving it back was the missing half. A
# run that dies without marking its ticket leaves it `claimed` for good, because
# the frontier is `ready-for-agent` and nothing ever asked whether the owner
# still existed. Probed on 28/07/2026: SIGKILL a run mid-session, and the next
# run grinds the rest of the frontier and reports `exit 0` — "this run ground
# everything it could" — with a ticket nobody will ever pick up again. Literally
# true, completely misleading, and invisible without reading the tracker by hand.
#
# The asymmetry was the finding: a stale *lock* is taken over (state_guard_take
# pings the owner's pid), a stale *claim* was not, through the same primitive.
#
# Liveness is single-machine on purpose (spec §213): a pid means nothing on
# another host and this pack has no heartbeat. Two questions, and either answer
# is enough to declare a claim dead:
#
#   pid   is the owning process still there (`kill -0`)
#   TTL   is the claim younger than CLAIM_TTL
#
# The TTL is not a slower copy of the pid check. Pids are recycled, and a
# recycled pid answers `kill -0` on behalf of a process that has nothing to do
# with this run — forever. It is what makes every wedge temporary.
#
# Fail-open, strictly: everything uncertain counts as dead. No record, no
# timestamp, a timestamp this pack cannot parse, a claim stamped in the future. A
# claim nobody can prove alive has to be reclaimable, or one crashed run costs a
# ticket permanently — which is the fault this module exists to close. Being
# wrong the other way is bounded: the claim is a test-and-set, so two runs cannot
# both end up holding the ticket, and the run and tree locks refuse a second run
# outright anyway.
#
# The record this reads is `owner=<who> at=<iso8601>`, off the `Claimed` field of
# whatever backend is configured. That shape is therefore part of the adapter
# interface and not a detail of the local backend: a remote backend stores the
# claim as an assignee, and it still has to render those two facts here — see
# tracker.sh. An owner this pack cannot ping (anything not shaped `pid:<n>`) is
# judged by the TTL alone rather than reclaimed on sight: stealing a ticket a
# human is assigned to would be worse than waiting out the backstop.

# One field out of a claim record, without word splitting or globbing a value
# the tracker holds. Non-zero when the record does not carry it at all, which the
# callers treat as "cannot prove it alive".
claim__field() {
  local padded=" $1 " key="$2" rest
  rest="${padded#* $key=}"
  [ "$rest" != "$padded" ] || return 1
  printf '%s\n' "${rest%% *}"
}

claim_owner() {
  claim__field "$1" owner
}

# ISO 8601 UTC to seconds since the epoch, in arithmetic only.
#
# No `date` conversion, because there is no portable one: `-d` is GNU, `-j -f` is
# BSD, and the pack has to run on a stock macOS shell. Probing which one this
# machine has would also put a fork on a path the monitor review of [04] spent a
# ticket getting forks out of.
#
# Days-from-civil, with the year shifted to start in March so that February's
# length and the leap rules stop being special cases. Refuses anything that is
# not exactly the shape `ralph_now` writes: a value this cannot parse is a claim
# whose age is unknown, and the caller fails open on it.
claim__epoch_of_iso() {
  local iso="$1" y m d hh mm ss era yoe doy doe days
  case "$iso" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z) ;;
    *) return 1 ;;
  esac

  # 10# on every field: a zero-padded hour is not an octal number here, and
  # `08` would otherwise be an arithmetic error rather than eight.
  y=$((10#${iso:0:4}))
  m=$((10#${iso:5:2}))
  d=$((10#${iso:8:2}))
  hh=$((10#${iso:11:2}))
  mm=$((10#${iso:14:2}))
  ss=$((10#${iso:17:2}))
  [ "$m" -ge 1 ] && [ "$m" -le 12 ] || return 1
  [ "$d" -ge 1 ] && [ "$d" -le 31 ] || return 1

  [ "$m" -le 2 ] && y=$((y - 1))
  era=$((y / 400))
  yoe=$((y - era * 400))
  doy=$(((153 * (m > 2 ? m - 3 : m + 9) + 2) / 5 + d - 1))
  doe=$((yoe * 365 + yoe / 4 - yoe / 100 + doy))
  days=$((era * 146097 + doe - 719468))
  printf '%s\n' "$((days * 86400 + hh * 3600 + mm * 60 + ss))"
}

# How long ago the claim was stamped, in seconds. Non-zero when that cannot be
# established at all — an absent, malformed or unparseable timestamp.
claim_age_seconds() {
  local at stamped now
  at="$(claim__field "$1" at)" || return 1
  stamped="$(claim__epoch_of_iso "$at")" || return 1
  now="$(claim__epoch_of_iso "$(ralph_now)")" || return 1
  printf '%s\n' "$((now - stamped))"
}

# Is this claim still held by something? Non-zero means reclaimable.
#
# CLAIM_TTL unset, zero or non-numeric means no backstop, the same reading
# GATE_TIMEOUT gives a missing deadline — the pid check then stands alone, and a
# recycled pid can wedge a ticket until a human looks. Documented in the config
# rather than silently clamped: a project that wants the pid check alone is
# allowed to say so.
claim_is_held() {
  local record="$1" owner age pingable=0

  [ -n "$record" ] || return 1

  age="$(claim_age_seconds "$record")" || return 1
  # A claim from the future is not a claim this pack wrote — a clock that jumped,
  # or a forged record. Uncertain, so reclaimable.
  [ "$age" -ge 0 ] || return 1

  case "${CLAIM_TTL:-0}" in
    '' | 0 | *[!0-9]*) ;;
    *) [ "$age" -le "$CLAIM_TTL" ] || return 1 ;;
  esac

  owner="$(claim_owner "$record")" || return 1
  [ -n "$owner" ] || return 1

  case "$owner" in
    pid:*[!0-9]* | pid:) return 1 ;;
    pid:*)
      kill -0 "${owner#pid:}" 2>/dev/null || return 1
      return 0
      ;;
    *) pingable=1 ;;
  esac

  # Not ours to ping, and the TTL above says it is still young enough.
  [ "$pingable" = 1 ]
}

# Every claimed ticket whose claim nobody can prove alive, back on the frontier.
#
# Called before the frontier is read, on every iteration: the frontier is a
# memoryless scan and this is part of deriving it. Prints one `<id>
# <disposition>` line per ticket it touched — the caller journals them, because
# writing the run journal is the loop's job and a lib that reached up into it
# would turn the stack into a mesh.
claim_reclaim_stale() {
  local id status record disposition

  for id in $(tracker_ids); do
    status="$(tracker_field "$id" Status)" || continue
    [ "$status" = claimed ] || continue
    record="$(tracker_field "$id" Claimed)" || record=""
    claim_is_held "$record" && continue

    disposition="$(failures_after_dead_owner "$id")" || disposition=unknown
    printf '%s %s\n' "$id" "$disposition"
  done
  return 0
}
