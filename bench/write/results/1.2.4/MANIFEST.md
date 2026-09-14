# gh-ci write-side benchmark, 1.2.4

Tier 1: 45 runs against the local recording mock, three tasks, three conditions,
five repeats. The mock was env-routed with GH_HOST on loopback and dummy tokens;
no real repository writes were part of this tier. Results are graded by call-log
assertion and LLM judge. See BENCHMARK.md for methodology and retained results.
The gh-ci payload was materialized from commit
`d70569a2fdb5662a359e1200d91a1f28514d4a30`.
Claude Code 2.1.267 used `claude-sonnet-5` for both agent and judge;
`gh` was 2.100.0 and gh-axi was 0.1.31.
