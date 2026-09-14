# gh-ci

An [agent skill](https://github.com/vercel-labs/skills) that wraps the GitHub CLI and GraphQL API into short, composable commands for CI monitoring and PR review.

## Install

```bash
npx skills add ConstructEase/gh-ci-skill
```

## What it does

- **CI and check runs** — list, check status, wait for completion, fetch failed logs
- **PR review** — read threads/comments, reply, resolve/unresolve threads, post comments
- **Smart defaults** — run ID defaults to the latest on the current branch; PR number defaults to the current branch's PR

## Requirements

- [gh](https://cli.github.com/) (authenticated)
- [jq](https://jqlang.github.io/jq/)

## Commands

See the [skill reference](gh-ci/SKILL.md#available-commands) for command behavior and
examples. Run `ci.sh help` for the complete runtime command list.

## Benchmark results

Read-only half of a three-way comparison between **gh-ci** (this skill), the plain
**`gh`** CLI, and **gh-axi**, on real GitHub CI and PR-review work.

### Method

Five read-only tasks × three conditions × five repeats = **75 agent runs**, each
followed by one LLM-judge call.

**Tasks** — T1 read the CI check status for a PR; T2 wait for a *named* check and
report its conclusion; T4 read a failing Actions run's log and identify the cause;
T5 check PR mergeability; T6 read a PR's conversation comments.

**Conditions** — each run got a fresh temporary working directory whose *only*
project instruction was that condition's file, with no other skills loaded and no
permission prompts:

| Condition | Instruction given to the agent | Environment |
|---|---|---|
| gh-ci | gh-ci 1.2.3's `gh-ci/SKILL.md` (4,603 B) | `ci.sh` installed project-locally; `gh-axi` removed from `PATH` |
| `gh` | a minimal "you have the `gh` CLI, use it" note (189 B) | no skill; `gh-axi` removed from `PATH` |
| gh-axi | gh-axi's shipped `SKILL.md` (7,779 B) | its `SessionStart` dashboard hook enabled, since that is part of the product |

**Fixtures** — existing, unmodified repository state. Nothing was created, commented
on, resolved, or pushed for this benchmark.

| Task | Fixture |
|---|---|
| T1, T2, T5 | `ConstructEase/sentry-basecamp-bot` PR #40, head `1312fe2c17bfcf9998a0da81030e051c49ad0a29` (checks: `scan_ruby` failing, `lint` and `test` passing; `mergeable: CONFLICTING`) |
| T4 | `ConstructEase/sentry-basecamp-bot` Actions run `30991856371`, job `scan_ruby` |
| T6 | `ConstructEase/app` PR #1653 (closed, 3 conversation comments) |

**Scoring and measurement** — an LLM judge graded each run PASS/FAIL against a
written per-task reference answer, seeing the agent's final answer and the list of
commands it actually ran (so a right answer reached without running a command fails
as a hallucination). Usage came from `claude -p --output-format stream-json`: API
calls are distinct assistant message ids, token totals come from the terminal
`result` event. Condition order was shuffled per repeat block. **Medians and
inter-quartile ranges** are reported across the five repeats, never means.

**Pins** — `gh` 2.100.0 · gh-axi 0.1.31 · gh-ci 1.2.3 · Claude Code CLI 2.1.267 ·
agent and judge model `claude-sonnet-5` · run date **2026-09-11** · ~100 GitHub core
REST requests for the whole experiment.

### Results

Token columns are medians. "Total input" is `input + cache_read + cache_write` —
the real per-session cost driver.

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls |
|---|---|---|---|---|---|---|---|---|---|
| **T1** CI status for a PR | gh-ci | 100% (5/5) | 147,295 (147,290–147,329) | 135,848 | 11,436 | 8 | 1,013 | 15.1 | 4 |
| | `gh` | 100% (5/5) | 68,622 (68,615–68,637) | 60,359 | 8,259 | 4 | 252 | 6.0 | 2 |
| | gh-axi | 100% (5/5) | 74,614 (74,604–74,622) | 63,481 | 11,129 | 4 | 274 | 6.5 | 2 |
| **T2** Wait on a named check | gh-ci | 100% (5/5) | 267,146 (266,965–304,262) | 253,473 | 13,659 | 14 | 1,762 | 22.0 | 7 |
| | `gh` | 100% (5/5) | 103,391 (103,334–103,395) | 94,905 | 8,463 | 6 | 404 | 7.9 | 3 |
| | gh-axi | 100% (5/5) | 74,638 (74,630–74,673) | 63,508 | 11,126 | 4 | 189 | 5.9 | 2 |
| **T4** Read a failing run log | gh-ci | 100% (5/5) | 298,118 (265,792–361,004) | 264,124 | 20,519 | 14 | 1,986 | 27.6 | 7 |
| | `gh` | 100% (5/5) | 184,885 (152,038–185,042) | 164,157 | 17,582 | 8 | 1,118 | 20.5 | 4 |
| | gh-axi | 100% (5/5) | 125,772 (125,754–235,735) | 101,344 | 24,422 | 6 | 1,129 | 20.8 | 3 |
| **T5** Check mergeability | gh-ci | 100% (5/5) | 226,087 (147,236–305,314) | 213,503 | 12,572 | 12 | 1,516 | 20.3 | 6 |
| | `gh` | 100% (5/5) | 68,517 (68,510–68,521) | 60,369 | 8,144 | 4 | 212 | 5.1 | 2 |
| | gh-axi | 100% (5/5) | 153,001 (114,654–153,086) | 139,333 | 13,390 | 8 | 527 | 10.9 | 4 |
| **T6** Read PR comments | gh-ci | 100% (5/5) | 225,811 (147,313–228,858) | 212,919 | 12,880 | 12 | 1,667 | 19.6 | 6 |
| | `gh` | 100% (5/5) | 68,899 (68,885–68,899) | 60,352 | 8,543 | 4 | 485 | 7.1 | 2 |
| | gh-axi | 100% (5/5) | 75,199 (75,179–75,221) | 63,493 | 11,702 | 4 | 486 | 7.9 | 2 |

Every condition passed all 25 read runs. On every task, gh-ci used between about
1.5× and 3.6× the total input tokens and between 1.5× and 3.5× the API calls of
`gh` or gh-axi; cross-task medians are not reported because task workloads differ.

All 75 runs exited 0 and all 75 were judged PASS. On correctness the read-only half
is a wash; the spread is entirely in turns, tokens, and wall clock.

### How to read this

- **Payload size alone is misleading.** The number that matters is total input
  tokens across the whole session, because every extra turn re-reads the entire
  prior context from cache. A tool whose output is 6× smaller but costs one more
  round-trip is not cheaper. That is why `cache_read` dominates every row above,
  and why the ranking tracks API calls far more closely than it tracks payload
  bytes.
- **Most of gh-ci 1.2.3's overhead here was the script-location probe.** Its
  `SKILL.md` told the agent to probe candidate paths for `ci.sh` before running
  anything; that cost a dedicated first turn in 24 of 25 gh-ci runs, on every
  task, before any GitHub call happened.
- **T5 exposed a capability gap in gh-ci 1.2.3, not a formatting difference.**
  Its `ci.sh pr` did not return `mergeable`/`mergeStateStatus`, so in 5 of 5
  gh-ci runs the agent read `ci.sh pr` and then fell back to plain
  `gh pr view --json mergeable,...` — the extra turn is the whole difference on
  that row.
- **T2 understates gh-ci's named-check wait.** The fixture check had already
  completed, so `gh` and gh-axi could answer with a single one-shot probe. Neither
  can actually *wait* on a named check; measuring that would need a check still in
  flight, which this read-only fixture set could not provide.
- **T4 measures the agent's filtering, not raw log size.** All three conditions
  piped or grepped the log rather than reading it whole, and Claude Code spills very
  large tool outputs to a file on its own — so gh-axi's 20,000-character log cap
  showed up as fewer turns, not as an avoided context blow-up.
- **These numbers rank ergonomics on five read tasks under one agent harness.** They
  do not rank the tools' capability surfaces, which are not interchangeable.

### Not run: the write-side half

**T7 (reply to an inline review comment), T8 (post a top-level PR comment) and T9
(resolve a review thread) were not run.** Each mutates a real pull request, and no
fixture repository or PR was authorized for this experiment. That is the half where
the three tools differ most — gh-ci has dedicated verbs for T7 and T9 and the other
two have none — so nothing above speaks to the write-side review loop.

No read task was dropped: all five were measurable against existing repository state
without creating anything.

## Development

Tests use [bats-core](https://github.com/bats-core/bats-core):

```bash
brew install bats-core
bats tests/
```

Some tests drive `ci.sh` through [`tests/mock-forge/`](tests/mock-forge/), a
local recording GitHub-API mock that `gh` talks to over loopback HTTPS, so the
write verbs are asserted on the HTTP request rather than on the `gh` arguments.
It makes no outward calls; its own README lists the fixture's development
requirements.

Note: the skill lives in the `gh-ci/` subdirectory (`gh-ci/SKILL.md` + `gh-ci/resources/ci.sh`). The skills CLI treats a directory containing a SKILL.md as the skill and copies that directory on install. Keeping the skill out of the repo root matters: current `npx skills` versions install a root-level SKILL.md as a single file and drop everything else, which would break `ci.sh` on `npx skills update`. Repo-level files (`tests/`, `.github/`, `README.md`, `LICENSE`) stay outside the skill directory and are never installed.

## License

MIT
