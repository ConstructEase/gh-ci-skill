# gh-ci

An [agent skill](https://github.com/vercel-labs/skills) that wraps the GitHub CLI and GraphQL API into short, composable commands for CI monitoring and PR review.

## Install

```bash
npx skills add ConstructEase/gh-ci-skill
```

## What it does

- **CI runs** — list, check status, wait for completion, fetch failed logs
- **PR review** — read threads/comments, reply, resolve/unresolve threads, post comments
- **Smart defaults** — run ID defaults to the latest on the current branch; PR number defaults to the current branch's PR

## Requirements

- [gh](https://cli.github.com/) (authenticated)
- [jq](https://jqlang.github.io/jq/)

## Commands

Run `ci.sh help` for the full list:

```
CI run commands:
  runs [branch] [--sha <sha>] [--limit N]
  status [run-id]
  wait [run-id] [--interval 30] [--max 60]
  failed-logs [run-id]
  failed-job-logs <job-id>

PR read commands:
  threads [pr-number] [--all]
  comments [pr-number]
  review-status [pr-number]
  pr [pr-number]

PR write commands:
  reply <pr> <comment-id> [body | --file F | stdin]
  comment [pr] [body | --file F | stdin]
  resolve <thread-node-id>
  unresolve <thread-node-id>
```

## Development

Tests use [bats-core](https://github.com/bats-core/bats-core):

```bash
brew install bats-core
bats tests/
```

Note: the skill lives in the `gh-ci/` subdirectory (`gh-ci/SKILL.md` + `gh-ci/resources/ci.sh`). The skills CLI treats a directory containing a SKILL.md as the skill and copies that directory on install. Keeping the skill out of the repo root matters: current `npx skills` versions install a root-level SKILL.md as a single file and drop everything else, which would break `ci.sh` on `npx skills update`. Repo-level files (`tests/`, `.github/`, `README.md`, `LICENSE`) stay outside the skill directory and are never installed.

## License

MIT
