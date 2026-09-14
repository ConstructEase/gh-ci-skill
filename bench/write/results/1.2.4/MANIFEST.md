# gh-ci write-side benchmark, 1.2.4

Tier 1: 45 runs against the local recording mock, three tasks, three conditions,
five repeats. The mock was env-routed with GH_HOST on loopback and dummy tokens;
no real repository writes were part of this tier. Results are graded by call-log
assertion and LLM judge. See BENCHMARK.md for methodology and retained results.
