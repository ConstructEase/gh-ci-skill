# Benchmark harness

This directory retains the harness, frozen inputs, manifests, raw result rows, and
aggregates for the gh-ci benchmark. The read tier runs T1, T2, T4, T5, and T6
against existing, unmodified GitHub state. The historical write tier runs T7, T8,
and T9 only
against `tests/mock-forge/`, the local recording GitHub-API mock introduced in PR
#15. The 1.3.2 follow-up adds a separate T3 named-check task and corrected gh-axi
T7–T9 cells. The reruns performed no real-GitHub writes.

## Experimental design

Each task × condition cell has five repeats, with condition order deterministically
shuffled within each repeat. Read versions contain 75 agent runs; historical write
versions contain 45, and the T3 follow-up contains 15. Conditions are gh-ci, a
minimal plain-`gh` instruction, and gh-axi with
its product SessionStart hook. Every cell uses a fresh git workspace and only the
selected condition as project instructions.

The driver invokes Claude Code with `claude-sonnet-5`, a 240-second agent timeout,
and a 120-second `claude-sonnet-5` judge timeout. The judge sees the task, reference
answer, executed-command summary, and final answer. Write cells also grade the
recorded accepted HTTP mutations: each GraphQL mutation occurrence is graded by
its own outcome, the expected body must match completely, replies must target the
selected inline comment, and resolves must occur exactly once for the selected
thread without a comment.

API calls are distinct assistant message IDs. Input, cache-read, cache-write, and
output tokens come from the terminal stream result. `total input` is input +
cache-read + cache-write. Tables report the median and the total-input IQR across
five repeats; raw TSV rows and JSON aggregates remain under each version directory.

## Frozen versions and fixtures

The `--ghci` option accepts 1.2.3, 1.2.4, 1.3.0, or 1.3.2 and maps them to
repository commits recorded in the materializer. At startup the driver materializes that commit’s
`gh-ci/SKILL.md` and `gh-ci/resources/ci.sh` with `git show` into an ignored payload
directory. The materialized skill is the gh-ci condition; this prevents a checkout’s
current skill from silently changing a historical run. `bench/mkpathshim.sh` builds
the filtered executable directory, and each driver refuses to start unless `claude`
still resolves and `gh-axi` does not resolve for the gh-ci/plain-gh conditions.
The result tables select 1.2.3 for the read baseline, 1.2.4 for the write baseline,
and 1.3.0 for the historical read/write reruns. Those 1.3.0 reruns pin commit
`cf252806` and were run on 2026-09-12. The 1.3.2 named-check and corrected gh-axi
follow-up pins commit `9594571c` and was run on 2026-09-14.
Use a full clone when possible. In a shallow clone the materializer first tries the
matching version tag, then fetches the pinned commit from `origin` at depth 1 into
the ignored payload cache. To obtain the same history manually, run
`git fetch --unshallow origin '+refs/heads/*:refs/remotes/origin/*'`.

Read fixture identities and tool/model pins are recorded in the versioned manifests
and README. The write fixture is reset before every cell, uses `GH_HOST` plus dummy
tokens, and records all requests. Its containment depends on those environment
routes. The prior nine-cell real-GitHub validation on 1.2.4 agreed with the mock on
eight cells, but is historical context only and is not an executable harness mode.

## Answer keys

The reference answer keys are held privately by the maintainer because they contain
content from private ConstructEase repositories. They are intentionally excluded
from this repository, so outside readers cannot rerun the LLM judge without access
to those keys. Set `BENCH_ANSWER_KEYS` to an operator-supplied directory containing
`read/T<N>.txt` and `write/T<N>.txt` files for the tasks being run. Both drivers stop
before starting a benchmark if the variable is unset or a required key is missing.

## Reproduction

The 1.3.2 named-check follow-up contains 15 T3 cells and a corrected 15-cell
gh-axi T7–T9 rerun under `bench/write/results/1.3.2-ghaxi-rerun/`. T3 judge
grading was re-run with untruncated commands and compact call-log evidence;
per-run transcripts, call logs, and original and regraded judge outputs are
retained privately by the maintainer outside this repository because they embed
the private answer keys. For this follow-up, the repository retains only the result
TSVs, aggregates, and manifest. The corrected rerun isolates the `GH_REPO`
environment issue while supplying `REPO_NWO` to stand in for the
repository identity from a real clone; gh-axi may still retry when given an
explicit `--repo`/`-R` to `api`. The read tier was unaffected.

T3 uses a local in-flight check: `scan_ruby` starts `in_progress` and flips to
`completed`/`failure` after 60 seconds from its first observation after reset.
`gh pr checks --watch` and `gh run watch` wait on all checks rather than one
named check; runs using those commands are valid.

Prerequisites are Bash, git, `gh`, `jq`, Python 3, Claude Code, and the development
requirements listed by `tests/mock-forge/README.md`. From the repository root:

```bash
BENCH_ANSWER_KEYS=/path/to/private/keys \
  BENCH_RESULTS=bench/read/work/results.1.2.3.tsv BENCH_RUNROOT=bench/read/runs/1.2.3 \
  bench/read/driver/bench.sh --ghci 1.2.3 1 5
python3 bench/read/driver/aggregate.py bench/read/work/results.1.2.3.tsv \
  bench/read/work/aggregate.1.2.3.json
python3 bench/mktable.py bench/read/work/aggregate.1.2.3.json

BENCH_ANSWER_KEYS=/path/to/private/keys \
  BENCH_RESULTS=bench/read/work/results.1.3.0.tsv BENCH_RUNROOT=bench/read/runs/1.3.0 \
  bench/read/driver/bench.sh --ghci 1.3.0 1 5
python3 bench/read/driver/aggregate.py bench/read/work/results.1.3.0.tsv \
  bench/read/work/aggregate.1.3.0.json
python3 bench/mktable.py bench/read/work/aggregate.1.3.0.json

BENCH_ANSWER_KEYS=/path/to/private/keys \
  BENCH_RESULTS=bench/write/work/results.1.2.4.tsv BENCH_RUNROOT=bench/write/runs/1.2.4 \
  bench/write/driver/bench.sh --ghci 1.2.4 1 5
python3 bench/write/driver/aggregate.py bench/write/work/results.1.2.4.tsv \
  bench/write/work/aggregate.1.2.4.json
python3 bench/mktable.py bench/write/work/aggregate.1.2.4.json

BENCH_ANSWER_KEYS=/path/to/private/keys \
  BENCH_RESULTS=bench/write/work/results.1.3.0.tsv BENCH_RUNROOT=bench/write/runs/1.3.0 \
  bench/write/driver/bench.sh --ghci 1.3.0 1 5
python3 bench/write/driver/aggregate.py bench/write/work/results.1.3.0.tsv \
  bench/write/work/aggregate.1.3.0.json
python3 bench/mktable.py bench/write/work/aggregate.1.3.0.json

BENCH_ANSWER_KEYS=/path/to/private/keys \
  BENCH_TASKS=bench/write/tasks/tasks.named-check.tsv \
  BENCH_RESULTS=bench/write/work/results.1.3.2-t3.tsv \
  BENCH_RUNROOT=bench/write/runs/1.3.2-t3 \
  bench/write/driver/bench.sh --ghci 1.3.2 1 5
python3 bench/write/driver/aggregate.py bench/write/work/results.1.3.2-t3.tsv \
  bench/write/work/aggregate.1.3.2-t3.json
python3 bench/mktable.py bench/write/work/aggregate.1.3.2-t3.json

BENCH_ANSWER_KEYS=/path/to/private/keys \
  BENCH_RESULTS=bench/write/work/results.1.3.2-ghaxi.tsv \
  BENCH_RUNROOT=bench/write/runs/1.3.2-ghaxi \
  bench/write/driver/bench.sh --ghci 1.3.2 1 5 '' C-ghaxi
python3 bench/write/driver/aggregate.py bench/write/work/results.1.3.2-ghaxi.tsv \
  bench/write/work/aggregate.1.3.2-ghaxi.json
python3 bench/mktable.py bench/write/work/aggregate.1.3.2-ghaxi.json
```

The separate `BENCH_RESULTS` and `BENCH_RUNROOT` paths prevent version runs from
being appended together. A resumed command skips any already-recorded
repeat/condition/task cell. Pass `--redo` before the positional arguments to remove
that cell's result row and run directory and execute it again. The retained
historical 1.3.0 rerun cost was $15.02 ($8.01 read and $7.01 write), below the
$20 stop boundary. Known limitations are live read-fixture drift, Actions log
retention, and the 300-character command-summary cutoff used by the historical
judge runs; T3 was regraded with untruncated commands and compact call-log evidence.

## Retained results

All six tables intentionally use the same columns. Read success is the judge result;
write success reports call assertion and judge results. Token columns and wall time
are medians.

## Read 1.2.3

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

## Read 1.3.0

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

## Write 1.2.4

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

## Write 1.3.0

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

## Corrected gh-axi write rerun 1.3.2

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| T7 | gh-axi | call 5/5; judge 5/5 | 314,357 (312,165–356,625) | 292,985 | 21,255 | 14 | 1,405 | 21.5 | 7 | 6 |
| T8 | gh-axi | call 5/5; judge 4/5 | 212,748 (209,522–214,147) | 194,999 | 17,728 | 10 | 682 | 15.4 | 5 | 4 |
| T9 | gh-axi | call 5/5; judge 5/5 | 558,884 (462,174–633,362) | 534,401 | 23,611 | 24 | 3,097 | 55.3 | 12 | 11 |

## Named-check wait follow-up 1.3.2

| Task | Condition | Success | Total input tok (IQR) | cache_read | cache_write | input | output | Wall s | API calls | Tool calls |
|---|---|---|---|---|---|---|---|---|---|---|
| T3 | gh-ci | call 5/5; judge 5/5 | 128,140 (83,380–129,283) | 109,529 | 18,605 | 6 | 822 | 74.0 | 3 | 2 |
| T3 | `gh` | call 4/5; judge 4/5 | 152,906 (152,720–152,965) | 139,219 | 13,679 | 8 | 828 | 71.2 | 4 | 3 |
| T3 | gh-axi | call 1/5; judge 1/5 | 342,988 (299,454–551,742) | 324,725 | 18,547 | 16 | 2,620 | 58.5 | 8 | 7 |

gh-ci used one check-wait command, while plain `gh` polled in the foreground.
In four of five runs, gh-axi backgrounded its own poll and returned without
reporting a conclusion. The retained gh-axi T3 runs never requested the
single-check REST route and did receive nested rollup data, so they did not need
rerunning.

Corrections: the original 1.3.0 gh-axi rows above are preserved. The corrected
rows run without `GH_REPO`. The agent process receives `REPO_NWO` because `gh`
strips the port when matching the loopback remote against `GH_HOST`, so the mock
remote cannot supply the repository identity that a real clone would; plain
`gh` and gh-axi ignore it. gh-axi's explicit `--repo`/`-R` flags on `api` may
still be rejected and retried. The read tier was unaffected.
