# mock-forge — a recording GitHub-API mock

A local-only test fixture. It serves a small, stateful slice of the GitHub API
over HTTPS on `127.0.0.1` and writes every request it receives to a call log.
It has no code path that reaches `github.com`.

It exists because the write verbs (`reply`, `comment`, `resolve`, `unresolve`)
cannot be tested honestly at the `gh`-argument layer. The `tests/stubs/gh`
recorder sees what `ci.sh` passed to `gh`; it cannot see the HTTP request that
`gh` then builds, and it cannot see anything at all when the caller is `gh` or
`gh-axi` rather than `ci.sh`. The distinction that matters most on the write
side — replying *into a review thread* versus posting a *top-level comment* —
lives in the request path, so that is where the assertion has to be.

## Files

| File | What it is |
|---|---|
| `forge.py` | the server: REST + GraphQL routes, fixture state, call log |
| `gql.py` | a minimal GraphQL selection-set parser and response projector |
| `seed.json` | the fixture: one open PR with 15 unresolved review threads |
| `forge.sh` | lifecycle helper — `start` / `reset` / `calls` / `stop` |

## Using it

```bash
eval "$(tests/mock-forge/forge.sh start /tmp/forge)"   # exports GH_HOST etc.
gh-ci/resources/ci.sh threads 1
gh-ci/resources/ci.sh reply 1 3408268489 "Fixed in abc123"
tests/mock-forge/forge.sh calls /tmp/forge             # the recorded requests
tests/mock-forge/forge.sh reset /tmp/forge             # back to seed state
tests/mock-forge/forge.sh stop  /tmp/forge
```

`start` prints `export` lines, so it is meant to be `eval`'d. It sets
`GH_HOST` to the loopback address the mock bound, `GH_ENTERPRISE_TOKEN` to a
dummy for that host, `SSL_CERT_FILE` to the throwaway cert it just generated,
and `GH_REPO`/`REPO_NWO` to the seeded repository. It also sets `GH_TOKEN` and
`GITHUB_TOKEN` to an invalid value on purpose: if a call is ever misrouted to
`github.com`, it fails with `Bad credentials` instead of writing anything.

## The three plumbing facts that make it work

Each was found by running `gh` against it, and each is load-bearing:

1. **`gh` refuses plain HTTP** (`http: server gave HTTP response to HTTPS
   client`), and rejects a self-signed cert (`x509: certificate signed by
   unknown authority`). `SSL_CERT_FILE` pointing at the cert resolves both, with
   no patching of `gh`.
2. **Against a host that is not `github.com`, `gh` uses GitHub Enterprise
   paths**: REST at `/api/v3/<path>`, GraphQL at `/api/graphql`.
3. **`gh pr <sub>` compares the git remote against `GH_HOST`** and refuses on a
   mismatch, including when the remote is right but carries a port. `GH_REPO`
   bypasses that check and is the supported way to drive it.

## Why there is a GraphQL projector

`gh` unmarshals GraphQL responses into Go structs strictly: a field the query
did not select is an error, not extra credit. So `forge.py` builds one generous
universe of data and `gql.py` projects it down to exactly the selection set the
caller sent. That also means a hand-written mutation — with a selection set
nobody anticipated — gets a well-formed answer rather than a parse failure.

## Requirements

The lifecycle helper requires `python3` (standard library only), `openssl` for
the throwaway cert, and `curl` for `forge.sh reset`. The bats tests additionally
require `gh` and `jq`; they skip themselves when any required tool is missing.
All five tools are present on `ubuntu-latest`, which is what
`.github/workflows/test.yml` runs on.

## Fidelity

The mock answers whether the client **issued** the right call. It does not
answer whether GitHub would **accept** it — real 403/422/secondary-rate-limit
behaviour exists only where it is modelled here. Keep the canned shapes built
from responses recorded against real GitHub, and re-record when a real-API run
disagrees with the mock.
