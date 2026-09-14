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

**Read tier** — five read-only tasks × three conditions × five repeats = **75 agent
runs**, each followed by one LLM-judge call.

**Read tasks** — T1 read the CI check status for a PR; T2 wait for a *named* check and
report its conclusion; T4 read a failing Actions run's log and identify the cause;
T5 check PR mergeability; T6 read a PR's conversation comments.

**Write tasks** — T3 wait for the named `scan_ruby` check; T7 reply to a specific inline review comment inside its thread; T8
post a top-level PR conversation comment; T9 mark a specific review thread resolved
without commenting.

**Conditions** — each run got a fresh temporary working directory whose *only*
project instruction was that condition's file, with no other skills loaded and no
permission prompts:

| Condition | Instruction given to the agent | Environment |
|---|---|---|
| gh-ci | The `gh-ci/SKILL.md` version named by each table: 1.2.3 read baseline, 1.2.4 write baseline, 1.3.0 reruns | Matching `ci.sh` installed project-locally; `gh-axi` removed from `PATH` |
| `gh` | a minimal "you have the `gh` CLI, use it" note (189 B) | no skill; `gh-axi` removed from `PATH` |
| gh-axi | gh-axi's shipped `SKILL.md` (7,779 B) | its `SessionStart` dashboard hook enabled, since that is part of the product |

**Read fixtures** — existing, unmodified repository state. Nothing was created,
commented on, resolved, or pushed during the read tier.

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

**Pins** — `gh` 2.100.0 · gh-axi 0.1.31 · gh-ci 1.2.3 for the read baseline,
1.2.4 for the write baseline, and 1.3.0 for both reruns · Claude Code CLI 2.1.267 ·
agent and judge model `claude-sonnet-5` · read-baseline date **2026-09-11** · rerun
date **2026-09-12**. The read baseline used about 100 GitHub core REST requests;
the write tiers used the local mock.

### Results

These four version tables use one schema. Read success is the judge result; write success reports deterministic call assertion and judge results. Token columns and wall time are medians across five repeats. Compare each tier’s adjacent version tables for the before/after result.

#### Read 1.2.3

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | gh-ci | 5/5 | 147,295 (147,290–147,329) | 135,848 | 11,436 | 8 | 1,013 | 15.1 | 4 | 3 |
| T1 | `gh` | 5/5 | 68,622 (68,615–68,637) | 60,359 | 8,259 | 4 | 252 | 6.0 | 2 | 1 |
| T1 | gh-axi | 5/5 | 74,614 (74,604–74,622) | 63,481 | 11,129 | 4 | 274 | 6.5 | 2 | 1 |
| T2 | gh-ci | 5/5 | 267,146 (266,965–304,262) | 253,473 | 13,659 | 14 | 1,762 | 22.0 | 7 | 6 |
| T2 | `gh` | 5/5 | 103,391 (103,334–103,395) | 94,905 | 8,463 | 6 | 404 | 7.9 | 3 | 2 |
| T2 | gh-axi | 5/5 | 74,638 (74,630–74,673) | 63,508 | 11,126 | 4 | 189 | 5.9 | 2 | 1 |
| T4 | gh-ci | 5/5 | 298,118 (265,792–361,004) | 264,124 | 20,519 | 14 | 1,986 | 27.6 | 7 | 6 |
| T4 | `gh` | 5/5 | 184,885 (152,038–185,042) | 164,157 | 17,582 | 8 | 1,118 | 20.5 | 4 | 3 |
| T4 | gh-axi | 5/5 | 125,772 (125,754–235,735) | 101,344 | 24,422 | 6 | 1,129 | 20.8 | 3 | 2 |
| T5 | gh-ci | 5/5 | 226,087 (147,236–305,314) | 213,503 | 12,572 | 12 | 1,516 | 20.3 | 6 | 5 |
| T5 | `gh` | 5/5 | 68,517 (68,510–68,521) | 60,369 | 8,144 | 4 | 212 | 5.1 | 2 | 1 |
| T5 | gh-axi | 5/5 | 153,001 (114,654–153,086) | 139,333 | 13,390 | 8 | 527 | 10.9 | 4 | 3 |
| T6 | gh-ci | 5/5 | 225,811 (147,313–228,858) | 212,919 | 12,880 | 12 | 1,667 | 19.6 | 6 | 5 |
| T6 | `gh` | 5/5 | 68,899 (68,885–68,899) | 60,352 | 8,543 | 4 | 485 | 7.1 | 2 | 1 |
| T6 | gh-axi | 5/5 | 75,199 (75,179–75,221) | 63,493 | 11,702 | 4 | 486 | 7.9 | 2 | 1 |

#### Read 1.3.0

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| T1 | gh-ci | 5/5 | 161,264 (118,812–162,000) | 145,678 | 14,074 | 8 | 1,247 | 15.8 | 4 | 3 |
| T1 | `gh` | 5/5 | 68,620 (68,617–68,624) | 60,359 | 8,257 | 4 | 242 | 5.1 | 2 | 1 |
| T1 | gh-axi | 5/5 | 74,618 (74,543–74,623) | 63,481 | 11,057 | 4 | 272 | 6.2 | 2 | 1 |
| T2 | gh-ci | 5/5 | 161,723 (119,247–163,151) | 146,635 | 15,080 | 8 | 1,074 | 15.2 | 4 | 3 |
| T2 | `gh` | 5/5 | 103,324 (103,270–103,348) | 94,897 | 8,421 | 6 | 395 | 7.3 | 3 | 2 |
| T2 | gh-axi | 5/5 | 74,656 (74,635–74,679) | 63,508 | 11,144 | 4 | 210 | 5.9 | 2 | 1 |
| T4 | gh-ci | 5/5 | 266,992 (261,083–307,458) | 239,452 | 28,129 | 12 | 1,780 | 27.4 | 6 | 5 |
| T4 | `gh` | 5/5 | 182,600 (181,474–190,208) | 169,602 | 14,990 | 10 | 1,072 | 18.8 | 5 | 4 |
| T4 | gh-axi | 5/5 | 125,975 (125,662–126,015) | 101,447 | 24,522 | 6 | 1,051 | 16.1 | 3 | 2 |
| T5 | gh-ci | 5/5 | 118,381 (78,592–120,473) | 104,683 | 13,692 | 6 | 723 | 9.9 | 3 | 2 |
| T5 | `gh` | 5/5 | 68,560 (68,547–68,573) | 60,369 | 8,187 | 4 | 220 | 5.0 | 2 | 1 |
| T5 | gh-axi | 5/5 | 153,096 (153,089–154,594) | 139,362 | 13,601 | 8 | 602 | 12.0 | 4 | 3 |
| T6 | gh-ci | 5/5 | 161,878 (118,488–204,149) | 146,565 | 15,305 | 8 | 1,291 | 15.5 | 4 | 3 |
| T6 | `gh` | 5/5 | 68,866 (68,853–68,896) | 60,352 | 8,510 | 4 | 472 | 6.6 | 2 | 1 |
| T6 | gh-axi | 5/5 | 75,162 (75,162–75,166) | 63,486 | 11,672 | 4 | 443 | 7.2 | 2 | 1 |

#### Write 1.2.4

- T7: reply to a specific inline review comment inside its thread.
- T8: post a top-level PR conversation comment.
- T9: mark a specific review thread resolved without commenting.

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| T7 | gh-ci | call 5/5; judge 5/5 | 155,046 (155,030–192,261) | 149,516 | 15,185 | 8 | 1,144 | 14.1 | 4 | 3 |
| T7 | `gh` | call 5/5; judge 5/5 | 105,036 (105,027–105,775) | 95,754 | 9,344 | 6 | 457 | 7.8 | 3 | 2 |
| T7 | gh-axi | call 5/5; judge 5/5 | 766,745 (702,767–949,539) | 740,074 | 20,741 | 36 | 6,102 | 81.5 | 18 | 17 |
| T8 | gh-ci | call 4/5; judge 5/5 | 147,032 (109,890–148,784) | 135,775 | 10,943 | 8 | 906 | 12.3 | 4 | 3 |
| T8 | `gh` | call 5/5; judge 5/5 | 68,667 (68,653–68,668) | 60,416 | 8,247 | 4 | 265 | 4.9 | 2 | 1 |
| T8 | gh-axi | call 5/5; judge 1/5 | 387,057 (112,271–433,839) | 372,597 | 11,431 | 20 | 1,931 | 29.0 | 10 | 9 |
| T9 | gh-ci | call 5/5; judge 5/5 | 154,341 (154,053–229,011) | 148,999 | 14,755 | 8 | 1,036 | 12.7 | 4 | 3 |
| T9 | `gh` | call 5/5; judge 5/5 | 106,690 (106,622–107,271) | 96,582 | 10,090 | 6 | 582 | 8.1 | 3 | 2 |
| T9 | gh-axi | call 5/5; judge 5/5 | 650,288 (609,373–818,021) | 642,055 | 19,347 | 32 | 4,354 | 57.1 | 16 | 15 |

#### Write 1.3.0

- T7: reply to a specific inline review comment inside its thread.
- T8: post a top-level PR conversation comment.
- T9: mark a specific review thread resolved without commenting.

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| T7 | gh-ci | call 5/5; judge 3/5 | 126,733 (126,645–166,629) | 121,382 | 17,952 | 6 | 1,006 | 11.9 | 3 | 2 |
| T7 | `gh` | call 5/5; judge 5/5 | 105,014 (104,929–105,329) | 95,625 | 9,383 | 6 | 601 | 9.2 | 3 | 2 |
| T7 | gh-axi | call 5/5; judge 5/5 | 754,698 (611,408–780,335) | 729,938 | 24,724 | 36 | 4,921 | 70.9 | 18 | 17 |
| T8 | gh-ci | call 2/5; judge 5/5 | 205,542 (159,710–246,104) | 188,968 | 16,173 | 10 | 1,821 | 21.8 | 5 | 4 |
| T8 | `gh` | call 5/5; judge 5/5 | 68,651 (68,649–68,668) | 60,422 | 8,225 | 4 | 241 | 4.9 | 2 | 1 |
| T8 | gh-axi | call 5/5; judge 3/5 | 347,056 (112,291–389,019) | 333,119 | 13,919 | 18 | 1,928 | 29.9 | 9 | 8 |
| T9 | gh-ci | call 5/5; judge 4/5 | 125,978 (125,977–126,005) | 108,550 | 17,441 | 6 | 833 | 10.5 | 3 | 2 |
| T9 | `gh` | call 5/5; judge 5/5 | 107,279 (106,773–107,362) | 96,873 | 10,400 | 6 | 593 | 9.1 | 3 | 2 |
| T9 | gh-axi | call 5/5; judge 5/5 | 674,866 (569,713–852,212) | 651,471 | 23,363 | 32 | 5,416 | 67.6 | 16 | 15 |

#### Corrected gh-axi write rerun (1.3.2)

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| T7 | gh-axi | call 5/5; judge 5/5 | 314,357 (312,165–356,625) | 292,985 | 21,255 | 14 | 1,405 | 21.5 | 7 | 6 |
| T8 | gh-axi | call 5/5; judge 4/5 | 212,748 (209,522–214,147) | 194,999 | 17,728 | 10 | 682 | 15.4 | 5 | 4 |
| T9 | gh-axi | call 5/5; judge 5/5 | 558,884 (462,174–633,362) | 534,401 | 23,611 | 24 | 3,097 | 55.3 | 12 | 11 |

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
  round-trip is not cheaper. That is why `cache_read` dominates every row in the
  detailed before table, and why the ranking tracks API calls far more closely than
  it tracks payload bytes.
- **Most of gh-ci 1.2.3's overhead here was the script-location probe.** Its
  `SKILL.md` told the agent to probe candidate paths for `ci.sh` before running
  anything; that cost a dedicated first turn in 24 of 25 gh-ci runs, on every
  task, before any GitHub call happened.
- **T5 exposed a capability gap in gh-ci 1.2.3, not a formatting difference.**
  Its `ci.sh pr` did not return `mergeable`/`mergeStateStatus`, so in 5 of 5
  gh-ci runs the agent read `ci.sh pr` and then fell back to plain
  `gh pr view --json mergeable,...` — the extra turn is the whole difference on
  that row.
- **T2 understates gh-ci's named-check wait.** See the write-tier T3 follow-up,
  which uses an in-flight mock check and measures the wait behavior directly.
- **T4 measures the agent's filtering, not raw log size.** All three conditions
  piped or grepped the log rather than reading it whole, and Claude Code spills very
  large tool outputs to a file on its own — so gh-axi's 20,000-character log cap
  showed up as fewer turns, not as an avoided context blow-up.
- **These numbers rank ergonomics on five read tasks and three mocked write tasks
  under one agent harness.** They do not rank the tools' capability surfaces, which
  are not interchangeable.

### Write-side method history

#### Named-check wait follow-up (1.3.2)

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| T3 | gh-ci | call 5/5; judge 5/5 | 128,140 (83,380–129,283) | 109,529 | 18,605 | 6 | 822 | 74.0 | 3 | 2 |
| T3 | `gh` | call 5/5; judge 4/5 | 152,906 (152,720–152,965) | 139,219 | 13,679 | 8 | 828 | 71.2 | 4 | 3 |
| T3 | gh-axi | call 1/5; judge 1/5 | 342,988 (299,454–551,742) | 324,725 | 18,547 | 16 | 2,620 | 58.5 | 8 | 7 |

T3 shows the named-check wait is observable. gh-ci used one check-wait command;
plain `gh` polled in the foreground. In four of five runs, gh-axi backgrounded
its own poll and returned without reporting a conclusion. `gh pr checks --watch`
and `gh run watch` are valid all-check waits, but neither waits for only one named
check.

Corrections: the original 1.3.0 gh-axi rows remain unchanged; the corrected
gh-axi rows use the mock without GH_REPO/REPO_NWO. gh-axi still rejects an
explicit `--repo`/`-R` on `api`, causing a retry. Read-tier results were
unaffected. The retained gh-axi T3 runs never requested the single-check REST
route and did receive nested rollup data, so they did not need rerunning. T3
judge verdicts were rechecked with fuller command and call-log evidence; original
judge outputs remain retained.

The write-side half uses the local recording mock in
[`tests/mock-forge/`](https://github.com/ConstructEase/gh-ci-skill/pull/15), introduced
in PR #15, reset for each cell and graded by the recorded HTTP call plus the LLM
judge. It comprises 45 runs.
A prior 9-run real-GitHub validation tier on 1.2.4 agreed on 8/9 cells; that history
was not rerun here. T3 is the named-check wait follow-up in the write tier.

No read task was dropped: all five were measurable against existing repository state
without creating anything.

## Development

The benchmark harness, methodology, and retained results are documented in
[BENCHMARK.md](BENCHMARK.md) and `bench/`.

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
