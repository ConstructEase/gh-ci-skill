# Benchmark harness

This repository contains the reproducible harness and retained aggregate results for
the gh-ci benchmark. The read tier measures T1, T2, T4, T5, and T6 against real,
unmodified GitHub state; the write Tier 1 measures T7, T8, and T9 against the local
recording mock in `tests/mock-forge/`. A prior nine-cell real-GitHub validation agreed
on 8/9 cells and is retained only as historical context.

Each condition uses Claude Code with `claude-sonnet-5`; five repeats are shuffled by
condition. M1–M7 are success, total input tokens, cache/input/output tokens, API
calls, tool calls, wall time, and spend. The judge grades the final answer against a
reference; write runs additionally assert the recorded call. Runs use a 240-second
agent timeout and 120-second judge timeout, deduplicate assistant message IDs, and
report medians/IQRs. Fixtures are identified in the manifests and are read-only for
the read tier and rerun. Pins are recorded in each versioned results directory.

To reproduce, install `gh`, `jq`, Python, Claude Code, and bats if desired, then run
`bench/read/driver/bench.sh 1 5` and `bench/write/driver/bench.sh 1 5` with the mock;
run each tier's `aggregate.py` and `mktable.py`. The write mock is env-routed, so
containment depends on `GH_HOST` and dummy tokens. Known limits include live fixture
drift, Actions log retention, and judge command truncation artifacts.

Results index: `bench/read/results/1.2.3/`, `bench/read/results/1.3.0/`,
`bench/write/results/1.2.4/`, and `bench/write/results/1.3.0/`.
