---
name: gh-ci-skill
description: GitHub CI and PR review helper. Use when monitoring CI runs, reading review threads, replying to PR comments, or resolving review feedback. Wraps gh CLI + GraphQL into short composable commands.
metadata:
  author: calebl
  version: "1.0.1"
---

# GitHub CI & PR Helper

A shell script that wraps the `gh` CLI and GitHub GraphQL API into short, composable subcommands for CI monitoring and PR review workflows.

## Prerequisites

- `gh` (GitHub CLI, authenticated)
- `jq`

## Script Location

Resolve the path to `ci.sh` based on the environment:

- **Claude Code (terminal):** `~/.claude/skills/gh-ci-skill/resources/ci.sh`
- **claude.ai (sandbox):** `/mnt/skills/user/gh-ci-skill/resources/ci.sh`
- **Codex (sandbox):** `$skill_dir/resources/ci.sh`

Store the resolved path in a variable for reuse:

```bash
CI="~/.claude/skills/gh-ci-skill/resources/ci.sh"
```

## Available Commands

### CI Run Commands

| Command | Description |
|---|---|
| `ci.sh runs [branch] [--sha <sha>] [--limit N]` | List recent CI runs on a branch |
| `ci.sh status [run-id]` | Status of a run (defaults to latest on current branch) |
| `ci.sh wait [run-id] [--interval 30] [--max 60]` | Poll until run completes (exit 124 on timeout) |
| `ci.sh failed-logs [run-id]` | Logs for failed steps (defaults to latest run) |
| `ci.sh failed-job-logs <job-id>` | Logs for a specific failed job |

### PR Read Commands

| Command | Description |
|---|---|
| `ci.sh threads [pr-number] [--all]` | Unresolved review threads (JSON) |
| `ci.sh comments [pr-number]` | Top-level PR conversation comments |
| `ci.sh review-status [pr-number]` | Review decision + per-reviewer state |
| `ci.sh pr [pr-number]` | PR summary (number, url, branch, state) |

### PR Write Commands

| Command | Description |
|---|---|
| `ci.sh reply <pr> <comment-id> [body]` | Reply to an inline review comment |
| `ci.sh comment [pr] [body]` | Post a top-level PR comment |
| `ci.sh resolve <thread-node-id>` | Mark a review thread resolved |
| `ci.sh unresolve <thread-node-id>` | Mark a review thread unresolved |

### Utility

| Command | Description |
|---|---|
| `ci.sh whoami` | Current gh login |
| `ci.sh help` | Show all commands |

## Usage Patterns

### Monitor CI for the current branch

```bash
# Check latest run status
bash $CI status

# Wait for it to finish
bash $CI wait

# If it failed, get the logs
bash $CI failed-logs
```

### Review PR feedback

```bash
# See unresolved review threads
bash $CI threads

# Reply to a review comment (use databaseId from threads output)
bash $CI reply 123 456789 "Fixed in the latest commit"

# Resolve the thread (use GraphQL node id from threads output)
bash $CI resolve PRRT_kwDOABC123
```

### Post a PR comment

```bash
# Auto-detects PR from current branch
bash $CI comment "CI is green, ready for re-review"

# Or specify the PR number
bash $CI comment 123 "CI is green, ready for re-review"
```

## Output

All commands output JSON where useful. Pipe to `jq` for further processing:

```bash
bash $CI status | jq '.conclusion'
bash $CI threads | jq '.threads | length'
```

## Notes

- PR number defaults to the open PR for the current branch when omitted.
- Owner/repo are detected automatically from the git remote.
- Run ID defaults to the latest run on the current branch when omitted.
