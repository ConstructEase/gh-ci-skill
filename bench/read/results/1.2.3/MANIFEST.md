# gh-ci benchmark — read-only half — run artifacts

Run date: 2026-09-11. The retained harness was subsequently committed under
`bench/` with the rerun.

## Layout
- `driver/bench.sh`     — the driver (`claude -p --output-format stream-json` per cell + LLM judge)
- `driver/aggregate.py` — median/IQR aggregation -> `aggregate.json`
- `bench/mktable.py`    — renders `aggregate.json` as the README markdown tables
- `bench/conditions/`   — the shared plain-gh and gh-axi condition instruction files; gh-ci is materialized from its pinned commit
- `tasks/tasks.tsv`     — task id, fixture repo, prompt
- `$BENCH_ANSWER_KEYS/read/` — private per-task reference answers used by the judge
- `results.tsv`         — one row per run
- `aggregate.json`      — generated summary used to render the retained table

Per-run streams and the discarded single-cell smoke result were not retained in
the repository.

## Harness decision
The axi benchmark (`bench-github/` in github.com/kunchenguid/axi, cloned to `harness-eval/`)
supports a `claude` agent backend and stream-json usage parsing, but was NOT runnable as-is
for this design: it hardcodes a shallow clone of `openclaw/openclaw` as the workspace, passes
`--setting-sources ''` (so gh-axi's SessionStart hook cannot be enabled for its own condition),
has no PATH control to remove gh-axi for the other conditions, runs condition-major with no
per-repeat shuffling, pins `claude-sonnet-4-6`, and has no gh-ci condition. Per the scout
report's fallback, a driver around `claude -p --output-format stream-json` was written instead,
reusing the study's method (condition-specific instruction file, stream-json usage, LLM judge
against a reference answer).

## Deviation from the brief
`--max-turns` does not exist in Claude Code CLI 2.1.267; runs were bounded by a 240 s
`timeout` instead. No run hit it (all 75 exited 0; slowest 61 s).

## GitHub API spend
`X-RateLimit-Used` (from a live response header, not `/rate_limit`): 39 before, 139 after.
The hourly window reset during the ~2 h run, so the 100-request delta is a lower bound.

## Fixtures (read-only; nothing created, commented, resolved or pushed)
- ConstructEase/sentry-basecamp-bot PR #40, head 1312fe2c17bfcf9998a0da81030e051c49ad0a29 (T1, T2, T5)
- ConstructEase/sentry-basecamp-bot Actions run 30991856371, job scan_ruby / 92259600991 (T4)
- ConstructEase/app PR #1653, closed (T6)

## Spend
$8.47 total (agent + judge), from each run's `total_cost_usd`. Sonnet 5 list price for
reference: $2.00/MTok input, $10.00/MTok output.
