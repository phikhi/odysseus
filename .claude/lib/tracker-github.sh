# shellcheck shell=bash
# The `github` tracker backend: issues of a repository, and the pull request an
# iteration leaves behind ([18], spec §52).
#
# Everything a remote backend does is in `lib/forge.sh`; what is here is the two
# things only this forge knows — the shape of its API, and the fact that this file
# exists at all, because `tracker__dispatch` routes `TRACKER_BACKEND=github` to
# `tracker_github_<op>` and to nothing else.
#
# What this backend answers, in the vocabulary of `lib/tracker.sh`:
#
#   a ticket        an issue. The pack's fields live in its **body**, the same
#                   `**Name:** v` a markdown ticket carries, so the state model is
#                   the local one and not a translation of it.
#   an id           `<number>-<slug>`, or the bare `<number>` for an issue a human
#                   opened. Server-numbered, so `renumber` returns what it was
#                   given ([27]); slug-carrying, because two readers of [65] read
#                   the slug out of the id text.
#   a claim         the assignee, published for a human — and decided locally, by
#                   the sidecar `lib/forge.sh` keeps, because `claim.sh` pings a
#                   pid and a pid means nothing on another host (spec §152, §213).
#   a receipt       the pull request, into which the branch of the iteration is
#                   pushed so that the git references the receipt carries resolve
#                   for whoever reads it ([10]).
#   `wait_ci`       the pull request's combined status, waited on before the issue
#                   is closed, when `WAIT_CI` is not `off`.
#
# Every operation refuses by a return code and never by ending its caller ([71]).

# The one thing that differs between two forges, as a table. Read by
# `lib/forge.sh` through `forge__spec`, which calls it by name — that indirection
# is what keeps a third forge a new file rather than an edit to the shared core.
#
# Non-zero on a key this backend does not answer, which is how `forge__user_id`
# discovers that this forge assigns by login and never needs a lookup.
tracker_github_forge_spec() {
  case "$1" in
    api) printf 'https://api.github.com\n' ;;
    auth-header) printf 'Authorization: Bearer %%s\n' ;;
    accept) printf 'Accept: application/vnd.github+json\n' ;;
    id-key) printf 'number\n' ;;
    body-key) printf 'body\n' ;;
    user-key) printf 'login\n' ;;
    update-method) printf 'PATCH\n' ;;
    close) printf '{"state":"closed"}\n' ;;
    reopen) printf '{"state":"open"}\n' ;;
    unassign) printf '{"assignees":[]}\n' ;;
    assign-by) printf 'login\n' ;;
    # `state=all`, because a resolved ticket owns its write-surface just as much as
    # an open one — the scope-guard asks `tracker_ids` for **every** ticket
    # whatever its state, and a listing of open issues would tell it that nobody
    # declared a path a closed ticket declares.
    path-list) printf '/repos/{repo}/issues?state=all&per_page={size}&page={arg}\n' ;;
    path-issue) printf '/repos/{repo}/issues/{arg}\n' ;;
    path-create) printf '/repos/{repo}/issues\n' ;;
    path-note) printf '/repos/{repo}/issues/{arg}/comments\n' ;;
    path-request) printf '/repos/{repo}/pulls\n' ;;
    path-request-one) printf '/repos/{repo}/pulls/{arg}\n' ;;
    # The combined status of a ref, which is one request for what a human reads as
    # the tick beside the branch. A branch name with no slash in it is what makes
    # this a path segment rather than something that has to be escaped, which is
    # why `branch-prefix` ends in a dash.
    path-ci) printf '/repos/{repo}/commits/{arg}/status\n' ;;
    ci-key) printf 'state\n' ;;
    branch-prefix) printf 'ralph-\n' ;;
    head-key) printf 'head\n' ;;
    base-key) printf 'base\n' ;;
    request-body-key) printf 'body\n' ;;
    request-url-key) printf 'html_url\n' ;;
    *) return 1 ;;
  esac
  return 0
}

# ── the interface ────────────────────────────────────────────────────────────

tracker_github_frontier() { forge_frontier github; }
tracker_github_ids() { forge_ids github; }
tracker_github_read_ticket() { forge_read_ticket github "$@"; }
tracker_github_field() { forge_field github "$@"; }
tracker_github_claim() { forge_claim github "$@"; }
tracker_github_unclaim() { forge_unclaim github "$@"; }
tracker_github_mark_resolved() { forge_mark_resolved github "$@"; }
tracker_github_mark_escalated() { forge_mark_escalated github "$@"; }
tracker_github_mark_ready() { forge_mark_ready github "$@"; }
tracker_github_mark_wontfix() { forge_mark_wontfix github "$@"; }
tracker_github_block_on() { forge_block_on github "$@"; }
tracker_github_bump_failures() { forge_bump_failures github "$@"; }
tracker_github_clear_failures() { forge_clear_failures github "$@"; }
tracker_github_open_ticket() { forge_open_ticket github "$@"; }
tracker_github_open_unique() { forge_open_unique github "$@"; }
tracker_github_renumber() { forge_renumber github "$@"; }
tracker_github_append_note() { forge_append_note github "$@"; }
tracker_github_emit_receipt() { forge_emit_receipt github "$@"; }
tracker_github_receipt_path() { forge_receipt_path github "$@"; }

# **A refusal, and a foreseen one** ([70]). The receipt of this backend is a pull
# request, which is not a path anybody can walk, so there is no directory here for
# the forensic witness of a run to take. What that costs is said once at the start
# of every run (`forensic_uncovered`) and carried by the human sink's dossier,
# which prints the reserve written for a receipt that is not in this tree.
tracker_github_receipt_dir() { return 1; }

# **The same shape one zone over, and it costs more** ([18] on [21]). The tickets
# of this backend are issues, not files, so `failures_protect_tracker` has no tree
# to snapshot around a session and nothing here restores what a session writes in
# the tracker. The scope-guard therefore judges a session against a write-surface
# that session could have edited — over the network, which no scope-guard, no
# rollback and no witness of this pack sees. Said once per run through
# `forensic_uncovered`, with its row in `docs/frontiere-de-confiance.md`.
tracker_github_tickets_dir() { return 1; }

# **And the zone that is not a refusal** ([77]). This backend does keep local
# facts about a ticket in this tree — the claim's liveness, the number of the
# open request, and where the receipt of a ticket is — because a pid means
# nothing on another host (spec §152). They are in a file of `.scratch/<feature>/`
# that a session appends to, so a run reads its own copy of them and names what
# it did not write.
tracker_github_sidecar_path() { forge_sidecar_path; }
tracker_github_sidecar_witness() { forge_sidecar_witness "$@"; }
tracker_github_sidecar_drift() { forge_sidecar_drift "$@"; }
