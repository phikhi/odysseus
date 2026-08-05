# shellcheck shell=bash
# The language gate: what language an iteration wrote its durable prose in.
#
# Two keys, deliberately decoupled ([17]). `LANG_INTERACT` is the language an
# agent speaks *to a human* — grilling, reports, the human loop — and nothing on
# the AFK path reads it: a session that nobody is talking to has no interaction
# language. `LANG_ARTIFACT` is the language of durable written prose, and that
# one is a property of the repository rather than of whoever is watching it.
#
# ## Why this is a gate and not a line in the prompt
#
# The prompt has carried "durable prose is written in $LANG_ARTIFACT" since [03],
# and docs/frontiere-de-confiance.md listed it as held by **nothing**. A rule a
# session is asked to follow is not a rule the loop keeps, and the review lenses
# of [06] do not close it either: a lens is a model whose verdict nothing checks,
# so "the Standards lens would notice" is exactly the confusion that document
# exists to prevent. What holds a rule is a check that answers the same way twice.
#
# ## What it judges, and what it deliberately does not
#
# **Prose files, read out of the tree the gate judges.** `LANG_PROSE_PATHS` is a
# list of globs and defaults to the markdown family: a `.md` a session wrote is
# prose, a `.py` is code with prose in it. Comments inside source files are the
# obvious next thing to want and are **not** covered — extracting them means a
# comment syntax per language, and a wrong answer there turns honest code red.
# The limit is written in the trust boundary rather than implied by silence.
#
# **Per file, tolerantly, on the dominant language.** A French document quoting
# `git rebase --onto` and three English terms is French. What decides is the
# share of the words this gate *recognises* that belong to the expected language,
# against `LANG_CHECK_THRESHOLD`. Below `LANG_CHECK_MIN_HITS` recognisable words
# a file is not judged at all and is counted out loud: a table of identifiers and
# a two-line note are not evidence of anything, and reddening them would teach a
# project to switch the gate off.
#
# **An edit matches the file, not the config.** For a file that already existed,
# the expected language is the dominant language of its version in the *base*
# tree — the state the session was handed. A project that has a French README and
# an English `LANG_ARTIFACT` can be worked on without the loop rewriting either.
# The baseline is pre-session on purpose: read from the working tree, a session
# could set the expected language of a file by writing it, which is the shape of
# defect this pack keeps finding (a control whose input the controlled writes).
#
# ## What a session can still do
#
# Fool it. The detector counts function words, so prose sprinkled with `the` and
# `and` passes; this is a check against **drift**, not against an adversary, and
# the difference is written down rather than hoped for. What it does catch is the
# case that actually happens: a fresh session with no conversation writes its
# documentation in the model's default language instead of the project's.
#
# ## Adding a language
#
# Add `lang_words_<code>` and put `<code>` in `lang_codes`. Words are ASCII and
# unaccented — the tokeniser works on bytes under `LC_ALL=C`, so `être` reaches
# it as `tre` — and a word claimed by two languages **votes for neither**. That
# rule is what lets the lists be written generously instead of hand-made
# disjoint: `de`, `la` and `in` say nothing about which language a text is in,
# and a list that pretends otherwise makes every score wrong in both directions.

# ── the shipped word lists ───────────────────────────────────────────────────
#
# Function words, which is the point: they are the words a text cannot avoid and
# the words a translation of a technical document changes. Content words would
# make the score a measure of the subject rather than of the language.

lang_codes() {
  printf 'en\nfr\nes\nde\nit\npt\n'
}

lang_words_en() {
  printf '%s\n' 'the and of to that for with as this be on not but they have
from or we you which their has can when there would about than its been into
only other these such more if does should must each one what will'
}

lang_words_fr() {
  printf '%s\n' 'le la les des une dans pour avec sur sont qui que pas plus mais
comme tout cette leur aussi sans donc alors ainsi chaque entre quand doit peut
nous vous elle ils ses ne aux du est et meme faire fait deux avoir etre celui
dont encore toujours autre tres afin selon depuis apres avant sous vers chez
lorsque ceci cela'
}

lang_words_es() {
  printf '%s\n' 'el los las una unos unas para con por como pero desde hasta
sobre entre cuando donde porque tambien mas muy este esta estos estas ese esa
aquel ser estar hacer tiene puede debe sus ya solo asi cada'
}

lang_words_de() {
  printf '%s\n' 'der die das und ist nicht mit von den dem ein eine einen einem
auch aber oder wenn dann noch nur schon sehr kann muss soll wird werden sind
haben hat sich durch nach bei zum zur diese dieser dieses'
}

lang_words_it() {
  printf '%s\n' 'il lo gli che una per con non sono questo come anche piu molto
quando dove essere fare dei delle nel nella alla allo sul sulla questa perche
quindi senza tra verso prima dopo sempre ancora ogni loro'
}

lang_words_pt() {
  printf '%s\n' 'os as uma umas para com por como mas nao muito quando onde
porque tambem mais este esta esses essas ser estar fazer tem pode deve seus ja
apenas assim cada pelo pela pelos das dos ao aos'
}

# Whether this pack can say anything about a language at all. The preflight is
# what turns a `no` into a refusal to start, so nothing downstream has to
# remember that an unknown language means "judged nothing" rather than "green".
lang_known() {
  local code
  [ -n "${1:-}" ] || return 1
  while IFS= read -r code; do
    [ "$code" = "$1" ] && return 0
  done <<CODES
$(lang_codes)
CODES
  return 1
}

# The lists as one row per language, `<code> <word> <word> …`, which is the only
# shape the scorer needs. Built here rather than inside the scorer so that a test
# can hand the scorer a table of its own and drive the ambiguity rule directly.
lang_table() {
  local code
  while IFS= read -r code; do
    [ -n "$code" ] || continue
    printf '%s %s\n' "$code" "$("lang_words_$code" | tr '\n' ' ')"
  done <<CODES
$(lang_codes)
CODES
}

# ── measuring one text ───────────────────────────────────────────────────────

# Read prose on stdin, print `<recognised> <hits for $1> <dominant> <its hits>`.
#
# One awk pass, under `LC_ALL=C` so that the tokeniser works on bytes and gives
# the same answer on a machine whose locale is not the pack's. Accented letters
# fall out with the punctuation, which is why the lists carry none.
#
# What is stripped before a word is counted, and each has a reason:
#   fenced blocks   code is not prose, and a code block full of English keywords
#                   in a French document would be counted as French prose failing
#   inline spans    same, one identifier at a time
#   link targets    a URL is a path, and `/en/docs/` is not a sentence
#
# Ties go to the alphabetically first code, so the answer never depends on the
# iteration order of an awk array.
#
# The table arrives semicolon-joined and not as it is printed: a `-v` value
# carrying a newline is a syntax error in the awk macOS ships, which is the shell
# this pack promises to run on. The rows keep their own shape in `lang_table` so
# that a test can read one.
lang_measure() {
  LC_ALL=C awk -v table="$(lang_table | tr '\n' ';')" -v want="${1:-}" '
    BEGIN {
      rows = split(table, row, ";")
      for (i = 1; i <= rows; i++) {
        if (row[i] == "") continue
        k = split(row[i], f, " ")
        for (j = 2; j <= k; j++) {
          # A word two languages claim is evidence for neither. Blanked rather
          # than deleted, so a third list claiming it cannot revive it.
          if (f[j] in claim) { if (claim[f[j]] != f[1]) claim[f[j]] = "" }
          else claim[f[j]] = f[1]
        }
      }
      fence = 0
      total = 0
    }
    {
      line = $0
      if (line ~ /^[ \t]*(```|~~~)/) { fence = 1 - fence; next }
      if (fence) next
      gsub(/`[^`]*`/, " ", line)
      gsub(/https?:\/\/[^ ]*/, " ", line)
      gsub(/\]\([^)]*\)/, " ", line)
      line = tolower(line)
      gsub(/[^a-z]/, " ", line)
      n = split(line, w, " ")
      for (i = 1; i <= n; i++) {
        if (w[i] in claim) {
          if (claim[w[i]] == "") continue
          hits[claim[w[i]]]++
          total++
        }
      }
    }
    END {
      best = ""
      bestn = 0
      for (c in hits) {
        if (hits[c] > bestn || (hits[c] == bestn && best != "" && c < best)) {
          best = c
          bestn = hits[c]
        }
      }
      printf "%d %d %s %d\n", total, (want == "" ? 0 : hits[want] + 0), \
        (best == "" ? "-" : best), bestn
    }'
}

# ── configuration ────────────────────────────────────────────────────────────

lang_enabled() {
  [ "${LANG_CHECK:-on}" = on ]
}

# The threshold as a whole percent, so the verdict is integer arithmetic and not
# a float comparison in a shell that has none. Refused rather than defaulted when
# it is not a number: see lang_preflight — a threshold read as zero is the gate
# switched off by typo.
lang_threshold_pct() {
  LC_ALL=C awk -v t="${LANG_CHECK_THRESHOLD:-0.80}" \
    'BEGIN { printf "%d\n", int(t * 100 + 0.5) }'
}

lang_min_hits() {
  printf '%s\n' "${LANG_CHECK_MIN_HITS:-12}"
}

lang_prose_paths() {
  gate_authored_list "${LANG_PROSE_PATHS:-}"
}

lang_exempt_paths() {
  gate_authored_list "${LANG_EXEMPT_PATHS:-}"
}

# Refuse to start rather than grind a night behind a language gate that cannot
# judge anything. Called from `gate_preflight`, with the rest of them.
#
# Five refusals, and every one of them is the same shape: a value that turns this
# check off without saying so. A `LANG_CHECK` that is neither `on` nor `off`
# would be read as off, which is why `LENSES` refuses a name it cannot run
# instead of skipping it. A threshold that is not a fraction reads as zero, and a
# threshold of zero passes everything. An empty `LANG_PROSE_PATHS` leaves nothing
# to judge. A `LANG_CHECK_MIN_HITS` of zero divides by zero on the first file
# with no recognisable word. And a `LANG_ARTIFACT` this pack has no word list for
# would judge nothing at all while reporting green: that last one is what a
# project has to *declare* rather than fall into, exactly the way
# `TYPECHECK_CMD=none` is a decision and an empty one is an oversight.
#
# The list is written against the criterion — "which value of which key makes
# this branch pass everything in silence" — and not against the cases that
# prompted it. That distinction is [31]'s, and it found the seal three files
# short of its own.
lang_preflight() {
  local rc=0

  case "${LANG_CHECK:-on}" in
    on | off) ;;
    *)
      printf 'ralph: LANG_CHECK is "%s" — it has to be on or off, and anything else would switch the language gate off by typo\n' \
        "${LANG_CHECK:-}" >&2
      rc=1
      ;;
  esac

  lang_enabled || return "$rc"

  if ! LC_ALL=C awk -v t="${LANG_CHECK_THRESHOLD:-}" \
    'BEGIN { exit (t ~ /^(0(\.[0-9]+)?|1(\.0+)?|\.[0-9]+)$/ && t + 0 > 0) ? 0 : 1 }'; then
    printf 'ralph: LANG_CHECK_THRESHOLD is "%s" — it has to be a fraction above 0 and at most 1, or the language gate passes everything\n' \
      "${LANG_CHECK_THRESHOLD:-}" >&2
    rc=1
  fi

  # Two more of the same family, and they are the ones a reading of the criterion
  # turns up rather than the cases that prompted it ([31]). An empty
  # `LANG_PROSE_PATHS` means nothing is prose, so the branch runs, judges nothing
  # and reports green — an off switch that says nothing, where `LANG_CHECK=off`
  # says it every iteration. And `LANG_CHECK_MIN_HITS` at zero means every file
  # is judged including the ones with no recognisable word at all, which is a
  # division by zero in the share: fail-closed, but as a branch dying without a
  # verdict, which is a diagnosis nobody can act on.
  if [ -z "$(lang_prose_paths)" ]; then
    printf 'ralph: LANG_PROSE_PATHS is empty — nothing would count as prose and the language gate would judge nothing while reporting green. Set LANG_CHECK=off to run without one\n' >&2
    rc=1
  fi

  case "${LANG_CHECK_MIN_HITS:-}" in
    '' | *[!0-9]* | 0)
      printf 'ralph: LANG_CHECK_MIN_HITS is "%s" — it has to be a whole number of words above 0\n' \
        "${LANG_CHECK_MIN_HITS:-}" >&2
      rc=1
      ;;
  esac

  if ! lang_known "${LANG_ARTIFACT:-}"; then
    printf 'ralph: no word list for LANG_ARTIFACT="%s" — this pack knows %s. Set LANG_CHECK=off to declare that this project runs without a language gate, rather than have one that judges nothing\n' \
      "${LANG_ARTIFACT:-}" "$(lang_codes | tr '\n' ' ' | sed 's/ *$//')" >&2
    rc=1
  fi

  return "$rc"
}

# ── the rule handed to a session ─────────────────────────────────────────────

# The prompt lines, next to the check that keeps them. A rule and its enforcement
# drifting apart is how "durable prose is in $LANG_ARTIFACT" spent thirty tickets
# looking like a guarantee, so they live in one file and the sentence changes
# with the key: it says "checked" only where it is.
#
# Nothing here mentions `LANG_INTERACT`, and that is the whole of its acceptance
# criterion — an AFK session is not talking to anybody.
lang_session_rules() {
  local artifact="${LANG_ARTIFACT:-en}"
  cat <<RULES
- Durable prose you write — documentation, comments, anything a human reads
  later — is in $artifact. Code is not prose: identifiers, keywords and APIs
  stay as they are, and so does a foreign term you are quoting. When you edit a
  file that already exists, match the language that file is written in rather
  than $artifact.
RULES
  lang_enabled || return 0
  cat <<RULES
  This one is checked and not only asked: every prose file this iteration wrote
  is read back afterwards, and one whose dominant language is not the expected
  one makes the iteration red.
RULES
}

# ── the gate branch ──────────────────────────────────────────────────────────

# Which language a file is expected to be in, printed as `<code> <why>`.
#
# `file` when the file already existed and its own prose decides, `artifact` when
# it is new — or when the version the session was handed carries too little prose
# to tell, which is the honest answer for a stub somebody is now filling in.
#
# Read out of the base *tree object*, never off disk: the base is the state the
# session was handed, and a session that could set a file's expected language by
# writing it would be the control-reads-what-it-controls defect one more time.
lang__expected() {
  local base="$1" file="$2" total hits dominant dhits

  if [ -n "$base" ] && git cat-file -e "$base:$file" 2>/dev/null; then
    read -r total hits dominant dhits <<MEASURE
$(git cat-file -p "$base:$file" 2>/dev/null | lang_measure '')
MEASURE
    if [ "${total:-0}" -ge "$(lang_min_hits)" ] && lang_known "${dominant:-}"; then
      printf '%s file\n' "$dominant"
      return 0
    fi
  fi
  printf '%s artifact\n' "${LANG_ARTIFACT:-en}"
}

# Runs as a gate branch: findings on stdout, the zone line in a sidecar file
# because a branch runs in its own process and cannot log from the loop's shell.
#
# Both trees are given and neither is read from disk, for the reason [29] wrote
# down at length: `TEST_CMD` is running while this branch runs, so a check that
# read the working tree would answer about a state no other branch is judging —
# a verdict that depends on who wrote first is a draw and not a verdict.
#
# An unreadable tree refuses to pass rather than falling through to "no prose
# file changed, nothing to say". Redundant with the scope-guard, which refuses on
# the same tree in the same iteration, and deliberately so: a guard whose
# fail-closed is somebody else's is a guard that goes green the day that somebody
# else moves ([34]).
lang_check() {
  local ticket="$1" base="$2" now="$3" zonefile="${4:-}"
  local changed file expected why prose exempt
  local total hits dominant dhits share
  local seen=0 undecided=0 skipped=0 unaddressable=0 rc=0 min pct

  if [ -z "$now" ] || ! changed="$(gate_changed_files "$base" "$now")"; then
    printf 'the language gate could not read the working tree — refusing to pass it\n'
    return 1
  fi

  prose="$(lang_prose_paths)"
  exempt="$(lang_exempt_paths)"
  min="$(lang_min_hits)"
  pct="$(lang_threshold_pct)"

  while IFS= read -r file; do
    [ -n "$file" ] || continue
    # A name git could not print as itself. Anything outside pure ASCII comes
    # back C-quoted — `"docs/sp\303\251cification.md"`, quotes included — and
    # that string is a path for nobody: `git cat-file` refuses it, and so does
    # every other consumer of this list ([39], opened by the probes of [17]).
    # Asked before the prose filter, because a quoted name does not match `*.md`
    # either, and being dropped by the glob is exactly how this would stay
    # invisible.
    #
    # Counted rather than judged. Reddening a French project because one of its
    # files is called `spécification.md` is the false red on honest work this
    # gate exists to avoid, and a name nobody can address has no honest verdict —
    # this branch cannot even tell whether it is prose. The count is what makes
    # the gap visible every iteration instead of once in a document, and it is
    # what [39] has to drive to zero.
    case "$file" in
      '"'*'"')
        unaddressable=$((unaddressable + 1))
        continue
        ;;
    esac
    gate_in_surface "$file" "$prose" || continue
    # Counted, not passed over in silence. `LANG_EXEMPT_PATHS` is the switch that
    # could turn this whole check off without saying so — the pack's own files
    # are in it by default, and `.` would be in it by accident — so the zone line
    # says how many files it took out ([24]: a key that drives a control is a
    # switch, and what it switches off has to be visible).
    if gate_under_path "$file" "$exempt"; then
      skipped=$((skipped + 1))
      continue
    fi
    # A deleted prose file has no content to judge and is not a finding.
    git cat-file -e "$now:$file" 2>/dev/null || continue

    read -r expected why <<EXPECTED
$(lang__expected "$base" "$file")
EXPECTED

    # Piped into the scorer rather than held in a variable, and that is about the
    # real run rather than about taste: a session is entitled to write a large
    # document, and a command substitution would put the whole of it in this
    # shell's memory to count function words in it. What comes back is four
    # numbers.
    read -r total hits dominant dhits <<MEASURE
$(git cat-file -p "$now:$file" 2>/dev/null | lang_measure "$expected")
MEASURE

    if [ "${total:-0}" -lt "$min" ]; then
      undecided=$((undecided + 1))
      continue
    fi

    seen=$((seen + 1))
    [ $((hits * 100)) -lt $((pct * total)) ] || continue

    rc=1
    share=$((hits * 100 / total))
    if [ "$why" = file ]; then
      printf 'wrote %s, whose prose now reads as %s — that file was already in %s before this session, and an edit matches the file rather than LANG_ARTIFACT (%s%% of it was %s, and this gate wants %s%%)\n' \
        "$file" "$dominant" "$expected" "$share" "$expected" "$pct"
    else
      printf 'wrote %s, whose prose reads as %s — this project writes durable prose in %s (%s%% of it was %s, and this gate wants %s%%)\n' \
        "$file" "$dominant" "$expected" "$share" "$expected" "$pct"
    fi
  done <<PROSE
$changed
PROSE

  if [ -n "$zonefile" ] &&
    [ $((seen + undecided + skipped + unaddressable)) -gt 0 ]; then
    printf 'the language gate checked %s prose file(s), could not tell the language of %s (too little prose to judge), could not address %s (a name git prints quoted), and did not look at %s (LANG_EXEMPT_PATHS)\n' \
      "$seen" "$undecided" "$unaddressable" "$skipped" >"$zonefile"
  fi

  return "$rc"
}
