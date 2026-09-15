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
**gh-axi**, using `claude -p` agents over five repeats per task/condition cell,
reporting medians. The read and write tiers were last measured on **gh-ci 1.3.0**,
and the named-check wait on **gh-ci 1.3.2**. Full methodology, fixtures,
reproduction steps, earlier versions and corrections: see
[BENCHMARK.md](BENCHMARK.md).

**Read tasks** — T1 read the CI check status for a PR; T2 wait for a *named* check
and report its conclusion; T4 read a failing Actions run's log and identify the
cause; T5 check PR mergeability; T6 read a PR's conversation comments.

**Write tasks** — T3 wait for the named `scan_ruby` check; T7 reply to a specific
inline review comment inside its thread; T8 post a top-level PR conversation
comment; T9 mark a specific review thread resolved without commenting.

### Read (gh-ci 1.3.0)

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

### Write (gh-ci 1.3.0; gh-axi rows corrected 1.3.2)

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| T7 | gh-ci | call 5/5; judge 3/5 | 126,733 (126,645–166,629) | 121,382 | 17,952 | 6 | 1,006 | 11.9 | 3 | 2 |
| T7 | `gh` | call 5/5; judge 5/5 | 105,014 (104,929–105,329) | 95,625 | 9,383 | 6 | 601 | 9.2 | 3 | 2 |
| T7 | gh-axi\* | call 5/5; judge 5/5 | 314,357 (312,165–356,625) | 292,985 | 21,255 | 14 | 1,405 | 21.5 | 7 | 6 |
| T8 | gh-ci | call 2/5; judge 5/5 | 205,542 (159,710–246,104) | 188,968 | 16,173 | 10 | 1,821 | 21.8 | 5 | 4 |
| T8 | `gh` | call 5/5; judge 5/5 | 68,651 (68,649–68,668) | 60,422 | 8,225 | 4 | 241 | 4.9 | 2 | 1 |
| T8 | gh-axi\* | call 5/5; judge 4/5 | 212,748 (209,522–214,147) | 194,999 | 17,728 | 10 | 682 | 15.4 | 5 | 4 |
| T9 | gh-ci | call 5/5; judge 4/5 | 125,978 (125,977–126,005) | 108,550 | 17,441 | 6 | 833 | 10.5 | 3 | 2 |
| T9 | `gh` | call 5/5; judge 5/5 | 107,279 (106,773–107,362) | 96,873 | 10,400 | 6 | 593 | 9.1 | 3 | 2 |
| T9 | gh-axi\* | call 5/5; judge 5/5 | 558,884 (462,174–633,362) | 534,401 | 23,611 | 24 | 3,097 | 55.3 | 12 | 11 |

\* corrected rerun under the fixed mock, see BENCHMARK.md Corrections

### Named-check wait (gh-ci 1.3.2)

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| T3 | gh-ci | call 5/5; judge 5/5 | 128,140 (83,380–129,283) | 109,529 | 18,605 | 6 | 822 | 74.0 | 3 | 2 |
| T3 | `gh` | call 4/5; judge 4/5 | 152,906 (152,720–152,965) | 139,219 | 13,679 | 8 | 828 | 71.2 | 4 | 3 |
| T3 | gh-axi | call 1/5; judge 1/5 | 342,988 (299,454–551,742) | 324,725 | 18,547 | 16 | 2,620 | 58.5 | 8 | 7 |

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
