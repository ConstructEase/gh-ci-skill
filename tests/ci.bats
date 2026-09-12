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
  GH_STUB_LOG="$log" run bash "$CI_SH" check-runs 124
  [ "$status" -eq 0 ]
  run grep -c 'repos/owner/repo/commits/124/check-runs' "$log"
  [ "$status" -eq 0 ]
  run grep -c 'repos/owner/repo/commits/deadbeef124456/check-runs' "$log"
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
