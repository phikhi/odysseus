# shellcheck shell=bash
# The `gitlab` tracker backend: issues of a project, and the merge request an
# iteration leaves behind ([18], spec §52).
#
# The twin of `tracker-github.sh`, and reading the two tables side by side is the
# point of the split: everything a remote backend *does* is in `lib/forge.sh`, and
# what is here is what this forge calls things.
#
# Four differences that are not naming, because they are the ones a reader has to
# know about:
#
#   the body        `description`, not `body`, and the same field on a merge
#                   request. The pack's own fields live in it exactly as they do
#                   in a markdown ticket.
#   the number      `iid`, the number that is unique **inside the project**, which
#                   is the one a human types and the one `#12` resolves to. Never
#                   `id`, which is unique across the whole instance and appears
#                   nowhere a human looks.
#   the transition  `state_event`, an imperative, where the other forge sets a
#                   state. Closing twice is not an error on either.
#   the assignee    a numeric id, so `lib/forge.sh` looks the login up once per
#                   shell rather than once per claim.
#
# Every operation refuses by a return code and never by ending its caller ([71]).

tracker_gitlab_forge_spec() {
  case "$1" in
    api) printf 'https://gitlab.com/api/v4\n' ;;
    # A personal access token goes in its own header here, and a bearer token is
    # the OAuth form; the header is per backend for that reason and not for
    # tidiness.
    auth-header) printf 'PRIVATE-TOKEN: %%s\n' ;;
    accept) printf 'Accept: application/json\n' ;;
    id-key) printf 'iid\n' ;;
    body-key) printf 'description\n' ;;
    user-key) printf 'username\n' ;;
    update-method) printf 'PUT\n' ;;
    close) printf '{"state_event":"close"}\n' ;;
    reopen) printf '{"state_event":"reopen"}\n' ;;
    unassign) printf '{"assignee_ids":[]}\n' ;;
    assign-by) printf 'id\n' ;;
    # No `state=` here: this endpoint answers with every issue of the project
    # whatever its state, which is what the scope-guard needs — a closed ticket
    # owns its write-surface just as much as an open one.
    path-list) printf '/projects/{repo}/issues?per_page={size}&page={arg}\n' ;;
    path-issue) printf '/projects/{repo}/issues/{arg}\n' ;;
    path-create) printf '/projects/{repo}/issues\n' ;;
    path-note) printf '/projects/{repo}/issues/{arg}/notes\n' ;;
    path-request) printf '/projects/{repo}/merge_requests\n' ;;
    path-request-one) printf '/projects/{repo}/merge_requests/{arg}\n' ;;
    # The pipelines of a ref, newest first, so the first record is the one that
    # answers for the branch as it stands.
    path-ci) printf '/projects/{repo}/pipelines?ref={arg}\n' ;;
    ci-key) printf '0.status\n' ;;
    path-user) printf '/users?username={arg}\n' ;;
    branch-prefix) printf 'ralph-\n' ;;
    head-key) printf 'source_branch\n' ;;
    base-key) printf 'target_branch\n' ;;
    request-body-key) printf 'description\n' ;;
    request-url-key) printf 'web_url\n' ;;
    *) return 1 ;;
  esac
  return 0
}

# ── the interface ────────────────────────────────────────────────────────────

tracker_gitlab_frontier() { forge_frontier gitlab; }
tracker_gitlab_ids() { forge_ids gitlab; }
tracker_gitlab_read_ticket() { forge_read_ticket gitlab "$@"; }
tracker_gitlab_field() { forge_field gitlab "$@"; }
tracker_gitlab_claim() { forge_claim gitlab "$@"; }
tracker_gitlab_unclaim() { forge_unclaim gitlab "$@"; }
tracker_gitlab_mark_resolved() { forge_mark_resolved gitlab "$@"; }
tracker_gitlab_mark_escalated() { forge_mark_escalated gitlab "$@"; }
tracker_gitlab_mark_ready() { forge_mark_ready gitlab "$@"; }
tracker_gitlab_mark_wontfix() { forge_mark_wontfix gitlab "$@"; }
tracker_gitlab_block_on() { forge_block_on gitlab "$@"; }
tracker_gitlab_bump_failures() { forge_bump_failures gitlab "$@"; }
tracker_gitlab_clear_failures() { forge_clear_failures gitlab "$@"; }
tracker_gitlab_open_ticket() { forge_open_ticket gitlab "$@"; }
tracker_gitlab_open_unique() { forge_open_unique gitlab "$@"; }
tracker_gitlab_renumber() { forge_renumber gitlab "$@"; }
tracker_gitlab_append_note() { forge_append_note gitlab "$@"; }
tracker_gitlab_emit_receipt() { forge_emit_receipt gitlab "$@"; }
tracker_gitlab_receipt_path() { forge_receipt_path gitlab "$@"; }

# The same two foreseen refusals as the other forge, for the same two reasons —
# a merge request is not a directory anybody can walk, and an issue is not a file
# in this tree. See `tracker-github.sh`, `forensic_uncovered` and the two rows of
# `docs/frontiere-de-confiance.md`.
tracker_gitlab_receipt_dir() { return 1; }
tracker_gitlab_tickets_dir() { return 1; }

# And the same third zone, which is not a refusal on either forge — see
# `tracker-github.sh` and [77].
tracker_gitlab_sidecar_path() { forge_sidecar_path; }
tracker_gitlab_sidecar_witness() { forge_sidecar_witness "$@"; }
tracker_gitlab_sidecar_drift() { forge_sidecar_drift "$@"; }

# And the same reading shared between the processes of one run — see
# `tracker-github.sh` and [75].
tracker_gitlab_cache_open() { forge_cache_open "$@"; }
tracker_gitlab_cache_prime() { forge_cache_prime gitlab; }
