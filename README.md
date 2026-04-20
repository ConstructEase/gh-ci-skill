# gh-ci-skill

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

## License

MIT
