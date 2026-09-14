#!/usr/bin/env bats

setup() {
  # Shadow real gh and git with stubs for all tests
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  # Provide repo context so _resolve_repo never calls gh
  export REPO_NWO="owner/repo"
  CI_SH="$BATS_TEST_DIRNAME/../gh-ci/resources/ci.sh"
}

# ---------------------------------------------------------------------------
# help / dispatch
# ---------------------------------------------------------------------------

@test "help exits 0 and shows usage" {
  run bash "$CI_SH" help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ci.sh"* ]]
}

@test "unknown command exits 1" {
  run bash -c "bash \"$CI_SH\" bogus-command 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unknown command: bogus-command"* ]]
}

# ---------------------------------------------------------------------------
# required-argument validation (all exit 1 before touching gh or git)
# ---------------------------------------------------------------------------

@test "failed-job-logs with no args exits 1" {
  run bash "$CI_SH" failed-job-logs
  [ "$status" -eq 1 ]
}

@test "check-wait with no args exits 1" {
  run bash "$CI_SH" check-wait
  [ "$status" -eq 1 ]
}

@test "reply with one arg exits 1" {
  run bash "$CI_SH" reply 123
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# flag parsing
# ---------------------------------------------------------------------------

@test "runs rejects unknown flag" {
  run bash -c "bash \"$CI_SH\" runs --bogus 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown flag: --bogus"* ]]
}

@test "wait rejects unknown flag" {
  run bash -c "bash \"$CI_SH\" wait 42 --bogus 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unknown flag: --bogus"* ]]
}

# ---------------------------------------------------------------------------
# timeout / --max 0
# ---------------------------------------------------------------------------

@test "wait exits 124 when --max 0" {
  run bash "$CI_SH" wait 42 --max 0
  [ "$status" -eq 124 ]
}

@test "check-wait exits 124 when --max 0" {
  run bash "$CI_SH" check-wait "Deploy" abc123 --max 0
  [ "$status" -eq 124 ]
}

# ---------------------------------------------------------------------------
# output filtering
# ---------------------------------------------------------------------------

@test "runs --sha filters to matching commit only" {
  run bash "$CI_SH" runs --sha abc123
  [ "$status" -eq 0 ]
  [[ "$output" == *"abc123"* ]]
  [[ "$output" != *"def456"* ]]
}

@test "runs without --sha returns all commits" {
  run bash "$CI_SH" runs
  [ "$status" -eq 0 ]
  [[ "$output" == *"abc123"* ]]
  [[ "$output" == *"def456"* ]]
}

# ---------------------------------------------------------------------------
# get-comment
# ---------------------------------------------------------------------------

@test "get-comment with no args exits 1" {
  run bash "$CI_SH" get-comment
  [ "$status" -eq 1 ]
  [[ "$output" == *"Usage: ci.sh get-comment"* ]]
}

@test "get-comment with unrecognised fragment exits 1" {
  run bash -c "bash \"$CI_SH\" get-comment 'https://github.com/owner/repo/pull/1#unknown-99' 2>&1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Unrecognised comment URL"* ]]
}

@test "get-comment discussion_r URL returns jq-filtered review comment" {
  run bash "$CI_SH" get-comment \
    "https://github.com/owner/repo/pull/1#discussion_r3356824857"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Looks good"* ]]
  # jq filter extracts .user.login — raw {"login":"alice"} must not appear
  [[ "$output" != *'"login"'* ]]
}

@test "get-comment issuecomment URL returns jq-filtered issue comment" {
  run bash "$CI_SH" get-comment \
    "https://github.com/owner/repo/pull/1#issuecomment-2345678"
  [ "$status" -eq 0 ]
  [[ "$output" == *"LGTM"* ]]
  [[ "$output" != *'"login"'* ]]
}

@test "get-comment changes-tab r<id> URL returns review comment body" {
  run bash "$CI_SH" get-comment \
    "https://github.com/owner/repo/pull/1/changes#r3356824857"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Looks good"* ]]
  [[ "$output" != *'"login"'* ]]
}

# ---------------------------------------------------------------------------
# regression: check-wait pagination and stdout validity
# ---------------------------------------------------------------------------

@test "check-wait requests per_page on its check-runs call" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  GH_STUB_LOG="$log" run bash "$CI_SH" check-wait "Deploy" abc123 --max 1 --interval 0
  [ "$status" -eq 124 ]
  run grep -c 'repos/owner/repo/commits/abc123/check-runs?per_page=100' "$log"
  [ "$status" -eq 0 ]
}

@test "check-wait --max 0 exits 124 and prints an empty JSON array" {
  # stderr discarded so $output is stdout alone
  run bash -c "bash \"$CI_SH\" check-wait Deploy abc123 --max 0 2>/dev/null"
  [ "$status" -eq 124 ]
  # stdout must be parseable JSON, not the bare newline of an uninitialised var
  echo "$output" | jq -e . >/dev/null
  [ "$(echo "$output" | jq -c .)" = "[]" ]
}

# ---------------------------------------------------------------------------
# regression: multi-word comment bodies
# ---------------------------------------------------------------------------

@test "comment passes an unquoted multi-word body through in full" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  GH_STUB_LOG="$log" run bash "$CI_SH" comment 123 hello world from firstmate
  [ "$status" -eq 0 ]
  run grep -Fx 'body=hello world from firstmate' "$log"
  [ "$status" -eq 0 ]
}

@test "reply passes an unquoted multi-word body through in full" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  GH_STUB_LOG="$log" run bash "$CI_SH" reply 123 456 hello world from firstmate
  [ "$status" -eq 0 ]
  run grep -Fx 'body=hello world from firstmate' "$log"
  [ "$status" -eq 0 ]
}

@test "comment with a single quoted body is unchanged" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  GH_STUB_LOG="$log" run bash "$CI_SH" comment 123 "one body"
  [ "$status" -eq 0 ]
  run grep -Fx 'body=one body' "$log"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# check-runs / check-wait: PR-number ref resolution
# ---------------------------------------------------------------------------

@test "check-runs prefers an existing digit-only literal ref over a PR" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  GH_STUB_LOG="$log" run bash "$CI_SH" check-runs 123
  [ "$status" -eq 0 ]
  run grep -c 'repos/owner/repo/commits/123/check-runs' "$log"
  [ "$status" -eq 0 ]
  run grep -c 'repos/owner/repo/commits/deadbeef123456/check-runs' "$log"
  [ "$status" -eq 1 ]
}

@test "check-runs resolves a PR number after the literal ref is not found" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  REPO_NWO="org/target" GH_STUB_LOG="$log" run bash "$CI_SH" check-runs 124
  [ "$status" -eq 0 ]
  run grep -c 'repos/org/target/commits/124/check-runs' "$log"
  [ "$status" -eq 0 ]
  run grep -c 'repos/org/target/commits/deadbeef124456/check-runs' "$log"
  [ "$status" -eq 0 ]
  run grep -Fx -- '--repo' "$log"
  [ "$status" -eq 0 ]
  run grep -Fx 'org/target' "$log"
  [ "$status" -eq 0 ]
}

@test "check-runs also resolves a PR number after a 404 literal response" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  GH_STUB_LOG="$log" run bash "$CI_SH" check-runs 125
  [ "$status" -eq 0 ]
  run grep -c 'repos/owner/repo/commits/125/check-runs' "$log"
  [ "$status" -eq 0 ]
  run grep -c 'repos/owner/repo/commits/deadbeef125456/check-runs' "$log"
  [ "$status" -eq 0 ]
}

@test "check-runs preserves unrelated 422 failures" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  GH_STUB_LOG="$log" run bash "$CI_SH" check-runs 126
  [ "$status" -eq 1 ]
  [[ "$output" == *"Validation Failed (HTTP 422)"* ]]
  run grep -c 'repos/owner/repo/commits/deadbeef126456/check-runs' "$log"
  [ "$status" -eq 1 ]
}

@test "check-runs with a SHA ref is used unchanged" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  GH_STUB_LOG="$log" run bash "$CI_SH" check-runs abc123
  [ "$status" -eq 0 ]
  run grep -c 'repos/owner/repo/commits/abc123/check-runs' "$log"
  [ "$status" -eq 0 ]
}

@test "check-runs keeps successful API diagnostics out of JSON" {
  debug_log="$BATS_TEST_TMPDIR/gh-debug"
  GH_STUB_API_DEBUG=1 run bash -c 'bash "$1" check-runs abc123 2>"$2"' _ "$CI_SH" "$debug_log"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | jq -e 'type == "array"' >/dev/null
  run grep -Fx 'debug: api request completed' "$debug_log"
  [ "$status" -eq 0 ]
}

@test "check-wait resolves a PR-number ref to its head SHA" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  GH_STUB_LOG="$log" run bash "$CI_SH" check-wait "Deploy" 124 --max 1 --interval 0
  [ "$status" -eq 124 ]
  run grep -c 'repos/owner/repo/commits/124/check-runs' "$log"
  [ "$status" -eq 0 ]
  run grep -c 'repos/owner/repo/commits/deadbeef124456/check-runs' "$log"
  [ "$status" -eq 0 ]
}

@test "check-wait with a SHA ref is used unchanged" {
  log="$BATS_TEST_TMPDIR/gh-calls"
  GH_STUB_LOG="$log" run bash "$CI_SH" check-wait "Deploy" abc123 --max 1 --interval 0
  [ "$status" -eq 124 ]
  run grep -c 'repos/owner/repo/commits/abc123/check-runs' "$log"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# pr: mergeable / mergeStateStatus
# ---------------------------------------------------------------------------

@test "pr includes mergeable and mergeStateStatus fields" {
  run bash "$CI_SH" pr 123
  [ "$status" -eq 0 ]
  [[ "$output" == *'"mergeable"'* ]]
  [[ "$output" == *'"mergeStateStatus"'* ]]
  [[ "$output" == *'"headRefOid"'* ]]
}

# ---------------------------------------------------------------------------
# failed-logs: output cap
# ---------------------------------------------------------------------------

@test "failed-logs under the cap is unchanged" {
  run bash "$CI_SH" failed-logs 42
  [ "$status" -eq 0 ]
  [ "$output" = "short log output" ]
}

@test "failed-logs over the cap truncates and spills to a temp file" {
  GH_STUB_BIG_LOG=1 run bash "$CI_SH" failed-logs 42
  [ "$status" -eq 0 ]
  [[ "$output" == *"output truncated"* ]]
  [[ "$output" == *"Full log:"* ]]
  tmpfile="$(echo "$output" | grep -oE '/[^[:space:]]*gh-ci-log[^[:space:]]*' | head -1)"
  [ -n "$tmpfile" ]
  [ -f "$tmpfile" ]
  rm -f "$tmpfile"
}

# ---------------------------------------------------------------------------
# write verbs at the HTTP layer, through tests/mock-forge
#
# The `gh` stub above can only see the arguments ci.sh passes to `gh`. These
# tests go one layer lower: real `gh` talks to a local recording mock behind
# GH_HOST, so the assertion is on the HTTP request GitHub would have received
# -- the method, the path and the JSON body. That is the only level at which
# "replied to the thread" can be told apart from "posted a top-level comment".
# ---------------------------------------------------------------------------

forge_start() {
  local forge_env
  for tool in gh python3 openssl curl jq; do
    command -v "$tool" >/dev/null 2>&1 || skip "$tool is not installed"
  done
  FORGE_HOME="$BATS_TEST_DIRNAME/mock-forge"
  # Drop the stub directory: these tests need the real gh binary.
  export PATH="${PATH#"$BATS_TEST_DIRNAME/stubs:"}"
  command -v gh >/dev/null 2>&1 || skip "gh is not installed"
  export GH_TOKEN=ghp_invalidinvalidinvalidinvalidinvalid
  export GITHUB_TOKEN=ghp_invalidinvalidinvalidinvalidinvalid
  unset REPO_NWO GH_REPO
  forge_env="$(bash "$FORGE_HOME/forge.sh" start "$BATS_TEST_TMPDIR/forge")" || {
    local start_status=$?
    echo "mock forge did not start" >&2
    return "$start_status"
  }
  eval "$forge_env"
}

forge_stop() {
  [ -n "${FORGE_HOME:-}" ] || return 0
  bash "$FORGE_HOME/forge.sh" stop "$BATS_TEST_TMPDIR/forge" || true
}

teardown() {
  forge_stop
}

# The recorded calls, newest last, as a JSON array.
forge_calls() {
  jq -s '.' "$FORGE_CALLS"
}

# The node id of the first seeded review thread.
first_thread_id() {
  bash "$CI_SH" threads 1 | jq -r '.threads[0].id'
}

@test "forge: threads reads review threads over HTTP with databaseIds and node ids" {
  forge_start
  run bash "$CI_SH" threads 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.threads | length')" -eq 15 ]
  [ "$(echo "$output" | jq -r '.threads[0].comments.nodes[0].databaseId')" = "3408268489" ]
  echo "$output" | jq -e '.threads[0].id | startswith("PRRT_")'
}

@test "forge: reply POSTs to the review-comments endpoint with a numeric in_reply_to" {
  forge_start
  run bash "$CI_SH" reply 1 3408268489 Fixed in commit abc123
  [ "$status" -eq 0 ]
  run forge_calls
  # exactly one write, to the pull-request review comments path
  [ "$(echo "$output" | jq '[.[] | select(.method=="POST" and (.rest_path|test("/pulls/1/comments$")))] | length')" -eq 1 ]
  call=$(echo "$output" | jq '[.[] | select(.method=="POST" and (.rest_path|test("/pulls/1/comments$")))][0]')
  [ "$(echo "$call" | jq -r '.body.body')" = "Fixed in commit abc123" ]
  # in_reply_to must be a JSON number; real GitHub 422s on a string
  [ "$(echo "$call" | jq -r '.body.in_reply_to | type')" = "number" ]
  [ "$(echo "$call" | jq -r '.body.in_reply_to')" = "3408268489" ]
}

@test "forge: reply appends to the thread it was addressed to" {
  forge_start
  bash "$CI_SH" reply 1 3408268489 "Fixed in commit abc123"
  run bash "$CI_SH" threads 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.threads[0].comments.nodes | length')" -eq 2 ]
  [ "$(echo "$output" | jq -r '.threads[0].comments.nodes[1].body')" = "Fixed in commit abc123" ]
  # and no other thread grew
  [ "$(echo "$output" | jq -r '.threads[1].comments.nodes | length')" -eq 1 ]
}

@test "forge: string in_reply_to is rejected without changing a thread" {
  forge_start
  run gh api "repos/$GH_REPO/pulls/1/comments" \
        -f body="wrong JSON type" -f in_reply_to=3408268489
  [ "$status" -ne 0 ]
  [[ "$output" == *"in_reply_to must be an integer"* ]]
  run bash "$CI_SH" threads 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.threads[0].comments.nodes | length')" -eq 1 ]
}

@test "forge: reply to an unknown comment id surfaces GitHub's validation error" {
  forge_start
  run bash "$CI_SH" reply 1 999999999 "into the void"
  [ "$status" -ne 0 ]
  [[ "$output" == *"in_reply_to"* ]]
}

@test "forge: reply rejects an unknown PR without changing a thread" {
  forge_start
  run gh api "repos/$GH_REPO/pulls/999/comments" \
        -f body="wrong pull" -F in_reply_to=3408268489
  [ "$status" -ne 0 ]
  [[ "$output" == *"Not Found"* ]]
  run bash "$CI_SH" threads 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.threads[0].comments.nodes | length')" -eq 1 ]
}

@test "forge: dedicated reply rejects an unknown PR without changing a thread" {
  forge_start
  run gh api "repos/$GH_REPO/pulls/999/comments/3408268489/replies" \
        -f body="wrong pull"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Not Found"* ]]
  run bash "$CI_SH" threads 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.threads[0].comments.nodes | length')" -eq 1 ]
}

@test "forge: comment POSTs to the issue-comments endpoint, not the review one" {
  forge_start
  run bash "$CI_SH" comment 1 CI is green on this branch
  [ "$status" -eq 0 ]
  run forge_calls
  [ "$(echo "$output" | jq '[.[] | select(.method=="POST" and (.rest_path|test("/issues/1/comments$")))] | length')" -eq 1 ]
  # the discrimination an LLM judge reading prose cannot make
  [ "$(echo "$output" | jq '[.[] | select(.method=="POST" and (.rest_path|test("/pulls/1/comments$")))] | length')" -eq 0 ]
  [ "$(echo "$output" | jq -r '[.[] | select(.method=="POST" and (.rest_path|test("/issues/1/comments$")))][0].body.body')" = "CI is green on this branch" ]
}

@test "forge: comment rejects an unknown PR without writing" {
  forge_start
  run gh api "repos/$GH_REPO/issues/999/comments" -f body="wrong pull"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Not Found"* ]]
  run bash "$CI_SH" comments 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r 'length')" -eq 0 ]
}

@test "forge: resolve sends the resolveReviewThread mutation and the thread flips" {
  forge_start
  tid="$(first_thread_id)"
  run bash "$CI_SH" resolve "$tid"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.data.resolveReviewThread.thread.isResolved')" = "true" ]
  run forge_calls
  [ "$(echo "$output" | jq '[.[] | select(.graphql_op=="resolveReviewThread")] | length')" -eq 1 ]
  [ "$(echo "$output" | jq -r '[.[] | select(.graphql_op=="resolveReviewThread")][0].body.variables.threadId')" = "$tid" ]
  # the default (unresolved-only) listing no longer shows it
  run bash "$CI_SH" threads 1
  [ "$(echo "$output" | jq -r '.threads | length')" -eq 14 ]
  run bash "$CI_SH" threads 1 --all
  [ "$(echo "$output" | jq -r '.threads | length')" -eq 15 ]
}

@test "forge: unresolve is recorded as its own mutation and reverses resolve" {
  forge_start
  tid="$(first_thread_id)"
  bash "$CI_SH" resolve "$tid"
  run bash "$CI_SH" unresolve "$tid"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.data.unresolveReviewThread.thread.isResolved')" = "false" ]
  run forge_calls
  # the two mutations must be distinguishable in the log, even though
  # "resolveReviewThread" is a substring of "unresolveReviewThread"
  [ "$(echo "$output" | jq '[.[] | select(.graphql_op=="unresolveReviewThread")] | length')" -eq 1 ]
  [ "$(echo "$output" | jq '[.[] | select(.graphql_op=="resolveReviewThread")] | length')" -eq 1 ]
  run bash "$CI_SH" threads 1
  [ "$(echo "$output" | jq -r '.threads | length')" -eq 15 ]
}

@test "forge: a mutation field on Query is rejected without changing state" {
  forge_start
  tid="$(first_thread_id)"
  run gh api graphql -f query="{ resolveReviewThread(input: {threadId: \"$tid\"}) { thread { isResolved } } }"
  [ "$status" -ne 0 ]
  [[ "$output" == *"doesn't exist on type 'Query'"* ]]
  run bash "$CI_SH" threads 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.threads | length')" -eq 15 ]
}

@test "forge: an anonymous mutation executes on the Mutation root" {
  forge_start
  tid="$(first_thread_id)"
  run gh api graphql -f query="mutation { resolveReviewThread(input: {threadId: \"$tid\"}) { thread { isResolved } } }"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.data.resolveReviewThread.thread.isResolved')" = "true" ]
}

@test "forge: operationName selects the matching operation without side effects" {
  forge_start
  tid="$(first_thread_id)"
  query="mutation ResolveFirst { resolveReviewThread(input: {threadId: \"$tid\"}) { thread { isResolved } } } query ReadViewer { viewer { login } }"
  run gh api graphql -f operationName=ReadViewer -f query="$query"
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.data.viewer.login')" = "calebl" ]
  run bash "$CI_SH" threads 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.threads | length')" -eq 15 ]
}

@test "forge: multiple operations without operationName are rejected" {
  forge_start
  tid="$(first_thread_id)"
  query="mutation ResolveFirst { resolveReviewThread(input: {threadId: \"$tid\"}) { thread { isResolved } } } query ReadViewer { viewer { login } }"
  run gh api graphql -f query="$query"
  [ "$status" -ne 0 ]
  [[ "$output" == *"provide operation name"* ]]
  run bash "$CI_SH" threads 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.threads | length')" -eq 15 ]
}

@test "forge: addComment rejects missing and unknown subjects without writing" {
  forge_start
  run gh api graphql -f query='mutation { addComment(input: {body: "missing subject"}) { commentEdge { node { url } } } }'
  [ "$status" -ne 0 ]
  [[ "$output" == *"subjectId"* ]]
  run gh api graphql -f query='mutation { addComment(input: {subjectId: "PR_kwUNKNOWN", body: "unknown subject"}) { commentEdge { node { url } } } }'
  [ "$status" -ne 0 ]
  [[ "$output" == *"PR_kwUNKNOWN"* ]]
  run bash "$CI_SH" comments 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r 'length')" -eq 0 ]
}

@test "forge: review-comment mutation rejects a missing body without replying" {
  forge_start
  cid="$(bash "$CI_SH" threads 1 | jq -r '.threads[0].comments.nodes[0].id')"
  run gh api graphql -f query="mutation { addPullRequestReviewComment(input: {inReplyTo: \"$cid\"}) { comment { body } } }"
  [ "$status" -ne 0 ]
  [[ "$output" == *"body"* ]]
  run bash "$CI_SH" threads 1
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.threads[0].comments.nodes | length')" -eq 1 ]
}

@test "forge: resolving an unknown thread id returns a GraphQL error" {
  forge_start
  run bash "$CI_SH" resolve PRRT_kwNOTATHREAD
  [[ "$output" == *"Could not resolve to a node"* ]]
}

@test "forge: reset restores the seeded state and truncates the call log" {
  forge_start
  bash "$CI_SH" resolve "$(first_thread_id)"
  bash "$CI_SH" comment 1 "before reset"
  bash "$FORGE_HOME/forge.sh" reset "$BATS_TEST_TMPDIR/forge"
  [ ! -s "$FORGE_CALLS" ]
  run bash "$CI_SH" threads 1
  [ "$(echo "$output" | jq -r '.threads | length')" -eq 15 ]
  run bash "$CI_SH" comments 1
  [ "$(echo "$output" | jq -r 'length')" -eq 0 ]
}

@test "forge: the environment it hands out points gh away from github.com" {
  forge_start
  # Containment: GH_HOST is a loopback address, and the github.com token is a
  # dummy, so a call that escaped the mock would fail auth rather than write.
  [[ "$GH_HOST" == 127.0.0.1:* ]]
  [[ "$GH_TOKEN" == ghp_invalid* ]]
  # `gh api user` is answered by the mock, which proves the routing holds.
  run gh api user --jq .login
  [ "$status" -eq 0 ]
  [ "$output" = "calebl" ]
  run forge_calls
  [ "$(echo "$output" | jq '[.[] | select(.rest_path=="/user")] | length')" -eq 1 ]
}

@test "forge: the dedicated review-comment replies endpoint works and is logged" {
  forge_start
  run gh api "repos/$GH_REPO/pulls/1/comments/3408268489/replies" \
        -f body="via the replies endpoint"
  [ "$status" -eq 0 ]
  run forge_calls
  call=$(echo "$output" | jq '[.[] | select(.method=="POST" and (.rest_path|test("/comments/3408268489/replies$")))][0]')
  [ "$(echo "$call" | jq -r '.status')" = "201" ]
  # and it landed in that thread, not a new one
  run bash "$CI_SH" threads 1
  [ "$(echo "$output" | jq -r '.threads | length')" -eq 15 ]
  [ "$(echo "$output" | jq -r '.threads[0].comments.nodes[-1].body')" = "via the replies endpoint" ]
}

@test "forge: the call log records the response status of every request" {
  forge_start
  bash "$CI_SH" comment 1 "ok write" || true
  bash "$CI_SH" reply 1 999999999 "rejected write" || true
  run forge_calls
  # the accepted write and the rejected one are distinguishable in the log,
  # which is what lets a grader count only the calls GitHub actually took
  [ "$(echo "$output" | jq -r '[.[] | select(.rest_path|test("/issues/1/comments$"))][0].status')" = "201" ]
  [ "$(echo "$output" | jq -r '[.[] | select(.rest_path|test("/pulls/1/comments$"))][0].status')" = "422" ]
}

@test "forge: a GraphQL error is flagged in the call log despite the 200" {
  forge_start
  bash "$CI_SH" resolve PRRT_kwNOTATHREAD || true
  run forge_calls
  [ "$(echo "$output" | jq -r '[.[] | select(.graphql_op=="resolveReviewThread")][0].status')" = "200" ]
  [ "$(echo "$output" | jq -r '[.[] | select(.graphql_op=="resolveReviewThread")][0].graphql_errors')" = "true" ]
}

@test "forge: the call log records the GraphQL mutation field, not just the operation name" {
  forge_start
  tid="$(first_thread_id)"
  bash "$CI_SH" resolve "$tid"
  run forge_calls
  # A client names its operation whatever it likes -- gh sends
  # `mutation CommentCreate { addComment(...) }` -- so only the selected field
  # identifies what was actually done.
  call=$(echo "$output" | jq '[.[] | select(.graphql_fields != null and (.graphql_fields|index("resolveReviewThread")))][0]')
  [ "$(echo "$call" | jq -r '.status')" = "200" ]
  run gh api graphql -f query='mutation NamedWhateverILike { addComment(input: {subjectId: "PR_kwDOMOCKF1", body: "hi"}) { commentEdge { node { url } } } }'
  [ "$status" -eq 0 ]
  run forge_calls
  [ "$(echo "$output" | jq '[.[] | select(.graphql_fields != null and (.graphql_fields|index("addComment")))] | length')" -eq 1 ]
}

@test "forge: allocated comment ids look like real GitHub ids" {
  forge_start
  a=$(bash "$CI_SH" comment 1 "first"  | jq -r .id)
  b=$(bash "$CI_SH" comment 1 "second" | jq -r .id)
  # 10 digits, like every real GitHub comment id
  [[ "$a" =~ ^[0-9]{10}$ ]]
  [[ "$b" =~ ^[0-9]{10}$ ]]
  # and not consecutive: an id ending in a round run of digits reads as
  # fabricated to anything grading the agent's reported URL
  [ "$b" -gt "$((a + 1))" ]
}

@test "forge: a posted comment can be edited and deleted again" {
  forge_start
  id=$(bash "$CI_SH" comment 1 "first wording" | jq -r .id)
  run gh api "repos/$GH_REPO/issues/comments/$id" -X PATCH -f body="second wording"
  [ "$status" -eq 0 ]
  [ "$(bash "$CI_SH" comments 1 | jq -r '.[0].body')" = "second wording" ]
  run gh api "repos/$GH_REPO/issues/comments/$id" -X DELETE
  [ "$status" -eq 0 ]
  [ "$(bash "$CI_SH" comments 1 | jq -r 'length')" -eq 0 ]
  # the delete is in the log as a 204, so a grader can tell the write did not survive
  run forge_calls
  [ "$(echo "$output" | jq -r '[.[] | select(.method=="DELETE")][0].status')" = "204" ]
}

@test "forge: deleting a thread's root review comment removes the thread" {
  forge_start
  run gh api "repos/$GH_REPO/pulls/comments/3408268489" -X DELETE
  [ "$status" -eq 0 ]
  [ "$(bash "$CI_SH" threads 1 | jq -r '.threads | length')" -eq 14 ]
}
