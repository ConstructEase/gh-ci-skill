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

Three-way comparison between **gh-ci** (this skill), the plain **`gh`** CLI, and
**gh-axi** in two tiers: five read tasks against real, unmodified GitHub state and
three write tasks against the local recording GitHub-API mock in
[`tests/mock-forge/`](https://github.com/ConstructEase/gh-ci-skill/pull/15), introduced
in PR #15. A nine-run tier on gh-ci 1.2.4 validated the mock once against real GitHub
and agreed on eight of nine cells. Nothing was created, commented on, resolved, or
pushed on any real repository during the read tier or the rerun.

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
on, resolved, or pushed during the read tier.

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

**Pins (before)** — `gh` 2.100.0 · gh-axi 0.1.31 · gh-ci 1.2.3 · Claude Code CLI 2.1.267 ·
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

**After rerun** — gh-ci 1.3.0 (this PR sets the skill version line to 1.3.2), same fixtures, prompts,
models, and five repeats; run date 2026-09-12. Read: 75 runs. Write Tier 1: 45 runs
against the recording mock in
[`tests/mock-forge/`](https://github.com/ConstructEase/gh-ci-skill/pull/15), with
call-log assertion plus judge.
Rerun spend was $15.02 ($8.01 read, $7.01 write); no Tier 2 or real-GitHub writes.

### Before / after summary

| Task / condition | Success before → after | Total input median (IQR) before → after | API calls before → after |
|---|---|---|---|
| T1 / C-ghci | 100% (5/5) → 100% (5/5) | 147,295 (147,290–147,329) → 161,264 (118,812–162,000) | 4 → 4 |
| T1 / C-gh | 100% (5/5) → 100% (5/5) | 68,622 (68,615–68,637) → 68,620 (68,617–68,624) | 2 → 2 |
| T1 / C-ghaxi | 100% (5/5) → 100% (5/5) | 74,614 (74,604–74,622) → 74,618 (74,543–74,623) | 2 → 2 |
| T2 / C-ghci | 100% (5/5) → 100% (5/5) | 267,146 (266,965–304,262) → 161,723 (119,247–163,151) | 7 → 4 |
| T2 / C-gh | 100% (5/5) → 100% (5/5) | 103,391 (103,334–103,395) → 103,324 (103,270–103,348) | 3 → 3 |
| T2 / C-ghaxi | 100% (5/5) → 100% (5/5) | 74,638 (74,630–74,673) → 74,656 (74,635–74,679) | 2 → 2 |
| T4 / C-ghci | 100% (5/5) → 100% (5/5) | 298,118 (265,792–361,004) → 266,992 (261,083–307,458) | 7 → 6 |
| T4 / C-gh | 100% (5/5) → 100% (5/5) | 184,885 (152,038–185,042) → 182,600 (181,474–190,208) | 4 → 5 |
| T4 / C-ghaxi | 100% (5/5) → 100% (5/5) | 125,772 (125,754–235,735) → 125,975 (125,662–126,015) | 3 → 3 |
| T5 / C-ghci | 100% (5/5) → 100% (5/5) | 226,087 (147,236–305,314) → 118,381 (78,592–120,473) | 6 → 3 |
| T5 / C-gh | 100% (5/5) → 100% (5/5) | 68,517 (68,510–68,521) → 68,560 (68,547–68,573) | 2 → 2 |
| T5 / C-ghaxi | 100% (5/5) → 100% (5/5) | 153,001 (114,654–153,086) → 153,096 (153,089–154,594) | 4 → 4 |
| T6 / C-ghci | 100% (5/5) → 100% (5/5) | 225,811 (147,313–228,858) → 161,878 (118,488–204,149) | 6 → 4 |
| T6 / C-gh | 100% (5/5) → 100% (5/5) | 68,899 (68,885–68,899) → 68,866 (68,853–68,896) | 2 → 2 |
| T6 / C-ghaxi | 100% (5/5) → 100% (5/5) | 75,199 (75,179–75,221) → 75,162 (75,162–75,166) | 2 → 2 |

Write-side results (before 1.2.4 → after 1.3.0; success is call assertion / judge;
total input is median; API calls are medians):

| Task / condition | Success (call/judge) before → after | Total input median (IQR) before → after | API calls before → after |
|---|---|---|---|
| T7 / C-ghci | 100%/100% → 100%/60% | 155,046 (155,030–192,261) → 126,733 (126,645–166,629) | 4 → 3 |
| T7 / C-gh | 100%/100% → 100%/100% | 105,036 (105,027–105,775) → 105,014 (104,929–105,329) | 3 → 3 |
| T7 / C-ghaxi | 100%/100% → 100%/100% | 766,745 (702,767–949,539) → 754,698 (611,408–780,335) | 18 → 18 |
| T8 / C-ghci | 80%/100% → 40%/100% | 147,032 (109,890–148,784) → 205,542 (159,710–246,104) | 4 → 5 |
| T8 / C-gh | 100%/100% → 100%/100% | 68,667 (68,653–68,668) → 68,651 (68,649–68,668) | 2 → 2 |
| T8 / C-ghaxi | 100%/20% → 100%/60% | 387,057 (112,271–433,839) → 347,056 (112,291–389,019) | 10 → 9 |
| T9 / C-ghci | 100%/100% → 100%/80% | 154,341 (154,053–229,011) → 125,978 (125,977–126,005) | 4 → 3 |
| T9 / C-gh | 100%/100% → 100%/100% | 106,690 (106,622–107,271) → 107,279 (106,773–107,362) | 3 → 3 |
| T9 / C-ghaxi | 100%/100% → 100%/100% | 650,288 (609,373–818,021) → 674,866 (569,713–852,212) | 16 → 16 |

The changes target turn cost: locate-and-run removes discovery, while PR-number check
references, mergeability fields, and bounded failed logs remove fallback turns/context.
gh-ci total input fell on T2, T4, T5, T6 and on T7 and T9, rose slightly on T1, and rose on T8 (147,032 → 205,542) where three of five runs hit the trailing-flag defect and re-posted; plain gh and gh-axi were unchanged within run-to-run noise.

The gh-ci T8 dip is a known unfixed trailing-flag defect: three runs folded the
trailing `--repo` flag into the comment body, then deleted and re-posted, so the call
assertion counted two comment calls. The T7/T9 judge dips are grading artifacts: the
judge receives commands truncated to 300 characters, and the 1.3.0 locate-and-run
one-liner puts the write subcommand beyond that cutoff; call-log assertions confirm
the writes occurred.

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

### Write-side method history

The write-side half uses the local recording mock in
[`tests/mock-forge/`](https://github.com/ConstructEase/gh-ci-skill/pull/15), introduced
in PR #15, reset for each cell and graded by the recorded HTTP call plus the LLM
judge. It comprises 45 runs.
A prior 9-run real-GitHub validation tier on 1.2.4 agreed on 8/9 cells; that history
was not rerun here.

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
