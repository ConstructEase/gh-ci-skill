#!/usr/bin/env bats

setup() {
  # Shadow real gh and git with stubs for all tests
  export PATH="$BATS_TEST_DIRNAME/stubs:$PATH"
  # Provide repo context so _resolve_repo never calls gh
  export REPO_NWO="owner/repo"
  CI_SH="$BATS_TEST_DIRNAME/../resources/ci.sh"
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
