#!/bin/bash

# GitHub CI / PR review helper.
# Wraps the gh CLI + GraphQL with short, composable subcommands so the
# watch-ci skill (and developers) don't have to remember verbose invocations.
#
# Run ./resources/ci.sh help for all commands.
#
# Requires: gh (authenticated), jq.

set -euo pipefail

for cmd in gh jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "❌ Required command not found: $cmd" >&2; exit 1; }
done

OWNER=""
REPO=""
PR_NUMBER=""
RUN_ID=""

_resolve_repo() {
  if [ -z "${REPO_NWO:-}" ]; then
    REPO_NWO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
  fi
  OWNER="${REPO_NWO%%/*}"
  REPO="${REPO_NWO##*/}"
}

_resolve_pr() {
  local arg="${1:-}"
  if [ -n "$arg" ]; then
    # Accept a number or a URL; take the trailing path segment.
    PR_NUMBER="${arg##*/}"
  else
    PR_NUMBER="$(gh pr view --json number --jq .number 2>/dev/null || true)"
  fi
  if [ -z "$PR_NUMBER" ]; then
    echo "No PR number: pass one or open a PR for the current branch." >&2
    exit 1
  fi
}

# Resolve a run ID from $1, or fall back to the latest run on the current branch.
_resolve_run() {
  local arg="${1:-}"
  if [ -n "$arg" ]; then
    RUN_ID="$arg"
  else
    local branch
    branch="$(git branch --show-current)"
    RUN_ID="$(gh run list --branch "$branch" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  fi
  if [ -z "$RUN_ID" ]; then
    echo "No run found: pass a run ID or push a commit to trigger CI." >&2
    exit 1
  fi
}

# Read a comment body from either $1, --file <path>, or stdin.
# Usage: body=$(_read_body "$@")
_read_body() {
  if [ "${1:-}" = "--file" ]; then
    cat "$2"
  elif [ -n "${1:-}" ]; then
    printf '%s' "$1"
  else
    cat
  fi
}

cmd="${1:-help}"
shift 2>/dev/null || true

case "$cmd" in
  runs)
    # List recent CI runs for a branch. Optionally filter by --sha.
    # Usage: ci.sh runs [branch] [--sha <sha>] [--limit N]
    branch="$(git branch --show-current)"
    if [ $# -gt 0 ] && [ "${1:0:2}" != "--" ]; then
      branch="$1"; shift
    fi
    sha=""
    limit=20
    while [ $# -gt 0 ]; do
      case "$1" in
        --sha)   sha="$2"; shift 2 ;;
        --limit) limit="$2"; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
      esac
    done
    json=$(gh run list --branch "$branch" --limit "$limit" \
      --json databaseId,status,conclusion,name,workflowName,headSha,event,createdAt,url)
    if [ -n "$sha" ]; then
      echo "$json" | jq --arg sha "$sha" '[.[] | select(.headSha == $sha)]'
    else
      echo "$json"
    fi
    ;;

  status)
    # Current status/conclusion of a run (JSON).
    # Usage: ci.sh status [run-id]  (defaults to latest run on current branch)
    _resolve_run "${1:-}"
    gh run view "$RUN_ID" --json status,conclusion,name,displayTitle,jobs,url
    ;;

  wait)
    # Poll a run until status == completed. Prints the final JSON on stdout
    # and progress lines to stderr. Exits 124 on timeout.
    # Usage: ci.sh wait [run-id] [--interval 30] [--max 60]
    if [ $# -gt 0 ] && [ "${1:0:2}" != "--" ]; then
      _resolve_run "$1"; shift
    else
      _resolve_run ""
    fi
    run_id="$RUN_ID"
    interval=30
    max=60
    while [ $# -gt 0 ]; do
      case "$1" in
        --interval) interval="$2"; shift 2 ;;
        --max)      max="$2"; shift 2 ;;
        *) echo "unknown flag: $1" >&2; exit 1 ;;
      esac
    done
    status=""
    attempt=0
    while [ "$attempt" -lt "$max" ]; do
      result=$(gh run view "$run_id" --json status,conclusion,name,displayTitle,url)
      status=$(echo "$result" | jq -r .status)
      if [ "$status" = "completed" ]; then
        echo "$result"
        exit 0
      fi
      attempt=$((attempt + 1))
      echo "[$attempt/$max] run $run_id status=$status — waiting ${interval}s" >&2
      sleep "$interval"
    done
    echo "Timeout after $((interval * max))s — run $run_id status=$status" >&2
    gh run view "$run_id" --json status,conclusion,name,displayTitle,url
    exit 124
    ;;

  failed-logs)
    # Logs for failed steps in a run.
    # Usage: ci.sh failed-logs [run-id]  (defaults to latest run on current branch)
    _resolve_run "${1:-}"
    gh run view "$RUN_ID" --log-failed
    ;;

  failed-job-logs)
    # Logs for failed steps in a single job.
    # Usage: ci.sh failed-job-logs <job-id>
    if [ $# -eq 0 ]; then
      echo "Usage: ci.sh failed-job-logs <job-id>" >&2
      echo "Tip: run 'ci.sh status' to see job IDs." >&2
      exit 1
    fi
    gh run view --job "$1" --log-failed
    ;;

  threads)
    # Unresolved, non-outdated review threads as JSON.
    # Pass --all to include resolved/outdated threads too.
    # Usage: ci.sh threads [pr-number] [--all]
    _resolve_repo
    include_all=0
    pr_arg=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --all) include_all=1; shift ;;
        *) pr_arg="$1"; shift ;;
      esac
    done
    _resolve_pr "$pr_arg"
    json=$(gh api graphql \
      -F owner="$OWNER" -F repo="$REPO" -F number="$PR_NUMBER" \
      -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewDecision
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 20) {
            nodes {
              databaseId
              body
              path
              line
              originalLine
              diffHunk
              author { login }
              createdAt
            }
          }
        }
      }
    }
  }
}')
    if [ "$include_all" -eq 1 ]; then
      echo "$json" | jq '{
        reviewDecision: .data.repository.pullRequest.reviewDecision,
        threads: .data.repository.pullRequest.reviewThreads.nodes
      }'
    else
      echo "$json" | jq '{
        reviewDecision: .data.repository.pullRequest.reviewDecision,
        threads: [
          .data.repository.pullRequest.reviewThreads.nodes[]
          | select(.isResolved == false and .isOutdated == false)
        ]
      }'
    fi
    ;;

  comments)
    # Top-level PR conversation comments.
    # Usage: ci.sh comments [pr-number]
    _resolve_repo
    _resolve_pr "${1:-}"
    gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
      --jq '[.[] | {id, user: .user.login, body, created_at}]'
    ;;

  review-status)
    # Review decision + per-reviewer state.
    # Usage: ci.sh review-status [pr-number]
    _resolve_pr "${1:-}"
    gh pr view "$PR_NUMBER" --json reviewDecision,reviews
    ;;

  pr)
    # Show the PR for this branch (or a given PR).
    # Usage: ci.sh pr [pr-number]
    _resolve_pr "${1:-}"
    gh pr view "$PR_NUMBER" --json number,url,headRefName,headRefOid,state
    ;;

  reply)
    # Reply to an inline review comment (posts into the same thread).
    # The comment id here is the numeric databaseId (NOT the GraphQL node id).
    # Usage: ci.sh reply <pr> <comment-databaseId> <body>
    #    or: ci.sh reply <pr> <comment-databaseId> --file <path>
    #    or: ci.sh reply <pr> <comment-databaseId>          (body from stdin)
    if [ $# -lt 2 ]; then
      echo "Usage: ci.sh reply <pr> <comment-databaseId> [<body> | --file F | stdin]" >&2
      echo "Tip: run 'ci.sh threads' to see comment IDs." >&2
      exit 1
    fi
    _resolve_repo
    PR_NUMBER="$1"
    comment_id="$2"
    shift 2
    body="$(_read_body "$@")"
    gh api "repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments" \
      -X POST \
      -f body="$body" \
      -F in_reply_to="$comment_id"
    ;;

  comment)
    # Post a top-level PR conversation comment.
    # Usage: ci.sh comment [pr] <body>
    #    or: ci.sh comment [pr] --file <path>
    #    or: ci.sh comment [pr]              (body from stdin)
    #   PR defaults to current branch's PR if omitted.
    _resolve_repo
    # If first arg looks like a PR number, consume it; otherwise auto-detect.
    if [ $# -gt 0 ] && [[ "$1" =~ ^[0-9]+$ ]]; then
      _resolve_pr "$1"; shift
    else
      _resolve_pr ""
    fi
    body="$(_read_body "$@")"
    gh api "repos/$OWNER/$REPO/issues/$PR_NUMBER/comments" \
      -X POST \
      -f body="$body"
    ;;

  resolve)
    # Mark a review thread resolved. Takes the GraphQL node id (string like PRRT_kw...).
    # Usage: ci.sh resolve <thread-node-id>
    if [ $# -eq 0 ]; then
      echo "Usage: ci.sh resolve <thread-node-id>" >&2
      echo "Tip: run 'ci.sh threads' to see thread IDs." >&2
      exit 1
    fi
    gh api graphql -F threadId="$1" -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: { threadId: $threadId }) {
    thread { isResolved }
  }
}'
    ;;

  unresolve)
    # Mark a review thread unresolved.
    # Usage: ci.sh unresolve <thread-node-id>
    if [ $# -eq 0 ]; then
      echo "Usage: ci.sh unresolve <thread-node-id>" >&2
      echo "Tip: run 'ci.sh threads' to see thread IDs." >&2
      exit 1
    fi
    gh api graphql -F threadId="$1" -f query='
mutation($threadId: ID!) {
  unresolveReviewThread(input: { threadId: $threadId }) {
    thread { isResolved }
  }
}'
    ;;

  whoami)
    gh api user --jq .login
    ;;

  help|--help|-h|"")
    cat <<'EOF'
CI / PR helper — wraps gh + GitHub GraphQL.

Usage: ci.sh <command> [args]

CI run commands:
  runs [branch] [--sha <sha>] [--limit N]
      List recent CI runs on a branch. Filters by commit SHA if --sha given.
  status [run-id]
      Current status+conclusion of a run (JSON).
      Defaults to latest run on the current branch.
  wait [run-id] [--interval 30] [--max 60]
      Poll until status == completed. Exits 124 on timeout.
      Defaults to latest run on the current branch.
  failed-logs [run-id]
      Logs for failed steps in a run.
      Defaults to latest run on the current branch.
  failed-job-logs <job-id>
      Logs for failed steps in a single job.

PR read commands:
  threads [pr-number] [--all]   Review threads (unresolved+non-outdated by default).
  comments [pr-number]          Top-level PR conversation comments.
  review-status [pr-number]     Review decision + per-reviewer state.
  pr [pr-number]                PR summary (number, url, headRefName, headRefOid, state).

PR write commands:
  reply <pr> <comment-databaseId> [<body> | --file F | (stdin)]
      Reply to an inline review comment. The id is the numeric databaseId.
  comment [pr] [<body> | --file F | (stdin)]
      Post a top-level PR conversation comment.
      PR defaults to the current branch's PR.
  resolve <thread-node-id>
      Mark a review thread resolved (node id, e.g. PRRT_kw...).
  unresolve <thread-node-id>
      Mark a review thread unresolved.

Utility:
  whoami     Current gh login.

Notes:
- PR number defaults to the open PR for the current branch.
- Owner/repo are detected automatically from the git remote.
- Output is JSON where useful — pipe to jq for further processing.
- Requires gh (authenticated) and jq.
EOF
    ;;

  *)
    echo "Unknown command: $cmd" >&2
    echo "Run 'ci.sh help' for usage." >&2
    exit 1
    ;;
esac
