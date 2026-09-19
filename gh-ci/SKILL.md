---
name: gh-ci
description: DEPRECATED - no longer maintained; use gh-axi or gh directly. GitHub CI and PR review helper. Use when monitoring CI runs, reading review threads, replying to PR comments, or resolving review feedback. Wraps gh CLI + GraphQL into short composable commands.
metadata:
  author: calebl
  version: "1.4.0"
---

# GitHub CI & PR Helper

> **DEPRECATED** - gh-ci is no longer maintained and will receive no further updates or fixes. Do not install it into new repositories. Existing consumers should remove the vendored `gh-ci` skill and call [`gh-axi`](https://github.com/kunchenguid/gh-axi) or the `gh` CLI directly instead.

A shell script that wraps the `gh` CLI and GitHub GraphQL API into short, composable subcommands for CI monitoring and PR review workflows.

## Prerequisites

- `gh` (GitHub CLI, authenticated)
- `jq`

## Script Location

Invoke each command with this single locate-and-run form:

```bash
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" <subcommand> ...
```

Priority rationale:
1. `$skill_dir` — runtime-injected path (Codex, Gemini CLI)
2. `/mnt/skills/user/gh-ci` — claude.ai sandbox mount
3. Project-local `.agents/` — Agent Protocol standard (Cursor, Codex, Gemini CLI)
4. Project-local `.claude/` — Claude Code project install
5. Global `~/.agents/` and `~/.claude/` — user-wide installs

## Available Commands

### CI Run Commands

| Command | Description |
|---|---|
| `ci.sh runs [branch] [--sha <sha>] [--limit N]` | List recent CI runs on a branch |
| `ci.sh status [run-id]` | Status of a run (defaults to latest on current branch) |
| `ci.sh wait [run-id] [--interval 30] [--max 60]` | Poll until run completes (exit 124 on timeout) |
| `ci.sh failed-logs [run-id]` | Logs for failed steps (defaults to latest run); output over ~20000 chars is truncated with the full log spilled to a temp file |
| `ci.sh failed-job-logs <job-id>` | Logs for a specific failed job |

### Check Run Commands

| Command | Description |
|---|---|
| `ci.sh check-runs [ref] [--name <name>] [--limit N]` | List check runs for a commit ref (SHA, branch, tag, or PR number) |
| `ci.sh check-wait <name> [ref] [--interval 30] [--max 10]` | Poll until a named check run completes (exit 124 on timeout); `ref` accepts a SHA, branch, tag, or PR number |

### PR Read Commands

| Command | Description |
|---|---|
| `ci.sh threads [pr-number] [--all]` | Unresolved review threads (JSON) |
| `ci.sh comments [pr-number]` | Top-level PR conversation comments |
| `ci.sh get-comment <url>` | Fetch a single comment by its GitHub URL |
| `ci.sh review-status [pr-number]` | Review decision + per-reviewer state |
| `ci.sh pr [pr-number]` | PR summary (number, url, branch, state, mergeable, mergeStateStatus) |

### PR Write Commands

| Command | Description |
|---|---|
| `ci.sh reply <pr> <comment-id> [body \| --file F \| -- body \| stdin]` | Reply to an inline review comment. Flag-shaped body words (`--...` or `-<letter>...`) require a preceding `--` |
| `ci.sh comment [pr] [body \| --file F \| -- body \| stdin]` | Post a top-level PR comment. Flag-shaped body words (`--...` or `-<letter>...`) require a preceding `--` |
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
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" status

# Wait for it to finish
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" wait

# If it failed, get the logs
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" failed-logs
```

### Poll a check run (e.g. third-party review bot)

```bash
# List all check runs for the current HEAD
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" check-runs

# Filter to a specific check by name
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" check-runs --name "Seer Code Review"

# Wait for a specific check to complete (max ~5 min)
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" check-wait "Seer Code Review"
```

### Review PR feedback

```bash
# See unresolved review threads
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" threads

# Fetch a specific comment by its GitHub URL (inline or top-level)
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" get-comment "https://github.com/owner/repo/pull/123#discussion_r3356824857"

# Reply to a review comment (use databaseId from threads output)
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" reply 123 456789 "Fixed in the latest commit"

# Resolve the thread (use GraphQL node id from threads output)
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" resolve PRRT_kwDOABC123
```

### Post a PR comment

```bash
# Auto-detects PR from current branch
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" comment "CI is green, ready for re-review"

# Or specify the PR number
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" comment 123 "CI is green, ready for re-review"
```

## Output

All commands output JSON where useful. Pipe to `jq` for further processing:

```bash
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" status | jq '.conclusion'
bash "$(_root="$(git rev-parse --show-toplevel 2>/dev/null)"; for _d in "${skill_dir:-}" /mnt/skills/user/gh-ci "${_root:+$_root/.agents/skills/gh-ci}" "${_root:+$_root/.claude/skills/gh-ci}" ~/.agents/skills/gh-ci ~/.claude/skills/gh-ci; do [ -n "$_d" ] && [ -f "$_d/resources/ci.sh" ] && { printf '%s\n' "$_d/resources/ci.sh"; break; }; done)" threads | jq '.threads | length'
```

## Notes

- PR number defaults to the open PR for the current branch when omitted.
- Owner/repo are detected automatically from the git remote.
- Run ID defaults to the latest run on the current branch when omitted.
- In `check-runs`/`check-wait`, a digit-only `ref` is used literally when it exists; only a not-found literal ref falls back to resolving a PR number to its head SHA.
