#!/usr/bin/env bash
# gh-ci benchmark driver — read-only half.
# Runs (task x condition x repeat) agent runs via `claude -p --output-format stream-json`,
# parses usage from the stream, and grades each run with an LLM judge.
#
# Usage: bench.sh --ghci 1.2.3|1.2.4|1.3.0 <rep-start> <rep-end> [task-filter] [cond-filter]
set -uo pipefail

D="${BENCH_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
REPO_ROOT="$(git -C "$D" rev-parse --show-toplevel)"
GHCI_VERSION=""
if [ "${1:-}" = --ghci ]; then GHCI_VERSION="${2:-}"; shift 2; fi
bash "$REPO_ROOT/bench/materialize-ghci.sh" "$REPO_ROOT" "$D/payload" "$GHCI_VERSION" || exit 1
PAYLOAD="$D/payload/$GHCI_VERSION/gh-ci"

NO_GHAXI_PATH=""
IFS=: read -r -a PATH_PARTS <<<"$PATH"
for path_index in "${!PATH_PARTS[@]}"; do
  path_part="${PATH_PARTS[$path_index]}"
  if [ -n "$path_part" ] && [ -x "$path_part/gh-axi" ]; then
    shim="$D/pathshim/$path_index"
    bash "$REPO_ROOT/bench/mkpathshim.sh" "$path_part" "$shim"
    path_part="$shim"
  fi
  NO_GHAXI_PATH="${NO_GHAXI_PATH:+$NO_GHAXI_PATH:}$path_part"
done
PATH="$NO_GHAXI_PATH" command -v claude >/dev/null || { echo "bench: claude missing from filtered PATH" >&2; exit 1; }
if PATH="$NO_GHAXI_PATH" command -v gh-axi >/dev/null; then echo "bench: gh-axi still resolves in filtered PATH" >&2; exit 1; fi

MODEL="${BENCH_MODEL:-claude-sonnet-5}"
JUDGE_MODEL="${BENCH_JUDGE_MODEL:-claude-sonnet-5}"
RUN_TIMEOUT="${BENCH_TIMEOUT:-240}"
JUDGE_TIMEOUT="${BENCH_JUDGE_TIMEOUT:-120}"

REP_START="${1:-1}"; REP_END="${2:-1}"
TASK_FILTER="${3:-}"; COND_FILTER="${4:-}"

CONDS=(C-ghci C-gh C-ghaxi)
RESULTS="${BENCH_RESULTS:-$D/work/results.tsv}"
RUNROOT="${BENCH_RUNROOT:-$D/runs/current}"
mkdir -p "$(dirname "$RESULTS")" "$RUNROOT"
if [ ! -f "$RESULTS" ]; then
  printf 'rep\tcond\ttask\texit\twall_ms\tapi_calls\ttool_calls\tin_tok\tcache_read\tcache_write\tout_tok\tverdict\tagent_usd\tjudge_usd\n' > "$RESULTS"
fi

# Deterministic-but-varied condition order per repeat: rotate + seeded shuffle.
shuffle_conds() {
  printf '%s\n' "${CONDS[@]}" | awk -v seed="$1" 'BEGIN{srand(seed)} {print rand()"\t"$0}' | sort -k1,1 | cut -f2
}

run_cell() {
  local rep="$1" cond="$2" task="$3" repo="$4" prompt="$5"
  local out="$RUNROOT/rep$rep/$cond/$task"
  mkdir -p "$out"
  local ws="$D/work/$rep-$cond-$task"
  rm -rf "$ws"; mkdir -p "$ws/.claude"

  # workspace is a git repo pointing at the fixture repo so `gh`/ci.sh resolve owner/repo
  git -C "$ws" init -q
  git -C "$ws" remote add origin "https://github.com/$repo.git"

  if [ "$cond" = C-ghci ]; then cp "$PAYLOAD/SKILL.md" "$ws/CLAUDE.md"; else cp "$D/conditions/$cond.md" "$ws/CLAUDE.md"; fi

  local runpath="$PATH"
  case "$cond" in
    C-ghci)
      mkdir -p "$ws/.claude/skills/gh-ci/resources"
      cp "$PAYLOAD/resources/ci.sh" "$ws/.claude/skills/gh-ci/resources/ci.sh"
      printf '{}\n' > "$ws/.claude/settings.json"
      runpath="$NO_GHAXI_PATH" ;;
    C-gh)
      printf '{}\n' > "$ws/.claude/settings.json"
      runpath="$NO_GHAXI_PATH" ;;
    C-ghaxi)
      # gh-axi ships a SessionStart hook that prints a repo dashboard; it is part of the product.
      cat > "$ws/.claude/settings.json" <<'JSON'
{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"gh-axi","timeout":10}]}]}}
JSON
      ;;
  esac

  local t0 t1 rc
  t0=$(date +%s%3N)
  ( cd "$ws" && PATH="$runpath" timeout "$RUN_TIMEOUT" \
      claude -p "$prompt" \
        --model "$MODEL" \
        --output-format stream-json --verbose \
        --dangerously-skip-permissions \
        --no-session-persistence \
        --disable-slash-commands \
        --setting-sources project \
        --allowedTools Bash Read Glob Grep \
        > "$out/stream.jsonl" 2> "$out/stderr.txt" )
  rc=$?
  t1=$(date +%s%3N)
  local wall=$(( t1 - t0 ))

  # --- parse usage ---
  # api_calls: distinct assistant message ids (the scout report's dedupe recipe — raw
  # stream-json repeats one message per content block, so a naive count over-counts).
  # token totals: the terminal `result` event, which is the only place the harness
  # reports final output_tokens (per-message entries are mid-stream snapshots).
  local usage
  usage=$(jq -s '
    ([ .[] | select(.type=="assistant" and (.message.usage != null)) ]
       | group_by(.message.id) | length) as $calls
    | ([ .[] | select(.type=="result") ] | last) as $r
    | ([ .[] | select(.type=="assistant" and (.message.usage != null)) ]
       | group_by(.message.id) | map(.[0]) ) as $m
    | { api_calls: $calls,
        in:          ($r.usage.input_tokens               // ([ $m[].message.usage.input_tokens               ] | add) // 0),
        cache_read:  ($r.usage.cache_read_input_tokens    // ([ $m[].message.usage.cache_read_input_tokens    ] | add) // 0),
        cache_write: ($r.usage.cache_creation_input_tokens// ([ $m[].message.usage.cache_creation_input_tokens] | add) // 0),
        out:         ($r.usage.output_tokens              // ([ $m[].message.usage.output_tokens              ] | add) // 0),
        cost:        ($r.total_cost_usd // 0) }
  ' "$out/stream.jsonl" 2>/dev/null) || usage=''
  [ -z "$usage" ] && usage='{"api_calls":0,"in":0,"cache_read":0,"cache_write":0,"out":0,"cost":0}'

  local tool_calls
  tool_calls=$(jq -s '[ .[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") ] | length' \
    "$out/stream.jsonl" 2>/dev/null) || tool_calls=0
  [ -z "$tool_calls" ] && tool_calls=0

  # final answer text
  jq -r 'select(.type=="result") | .result // empty' "$out/stream.jsonl" 2>/dev/null > "$out/answer.txt"
  if [ ! -s "$out/answer.txt" ]; then
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' \
      "$out/stream.jsonl" 2>/dev/null > "$out/answer.txt"
  fi
  # commands the agent actually ran (trajectory evidence for the judge)
  jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
         | "\(.name): \((.input.command // .input.file_path // (.input|tostring))|tostring|.[0:300])"' \
    "$out/stream.jsonl" 2>/dev/null | head -40 > "$out/commands.txt"

  # --- judge ---
  local verdict="ERROR"
  {
    printf 'You are grading one run of a benchmark. Decide PASS or FAIL.\n\n'
    printf '=== TASK GIVEN TO THE AGENT ===\n%s\n\n' "$prompt"
    printf '=== REFERENCE ANSWER (ground truth) ===\n'; cat "$D/tasks/ref/$task.txt"
    printf '\n=== COMMANDS THE AGENT RAN ===\n'; cat "$out/commands.txt"
    printf '\n=== AGENT FINAL ANSWER ===\n'; head -c 6000 "$out/answer.txt"
    printf '\n\n=== GRADING RULES ===\n'
    printf 'PASS only if the agent final answer is factually consistent with the reference answer and\n'
    printf 'satisfies every requirement the reference answer marks as required.\n'
    printf 'FAIL if it contradicts the reference, omits a required element, ran no command that could\n'
    printf 'have produced the facts (hallucination), or did not produce an answer.\n'
    printf 'Minor wording, extra detail, or extra correct context does not matter.\n'
    printf 'Reply with exactly one line: "PASS - <=15 word reason" or "FAIL - <=15 word reason".\n'
  } > "$out/judge_prompt.txt"

  timeout "$JUDGE_TIMEOUT" claude -p "$(cat "$out/judge_prompt.txt")" \
      --model "$JUDGE_MODEL" --output-format stream-json --verbose \
      --dangerously-skip-permissions --no-session-persistence \
      --disable-slash-commands --setting-sources project \
      --disallowedTools Bash Read Glob Grep Edit Write WebFetch WebSearch \
      > "$out/judge_stream.jsonl" 2>"$out/judge_err.txt"
  jq -r 'select(.type=="result") | .result // empty' "$out/judge_stream.jsonl" 2>/dev/null > "$out/judge.txt"
  local judge_cost
  judge_cost=$(jq -r 'select(.type=="result") | .total_cost_usd // 0' "$out/judge_stream.jsonl" 2>/dev/null | tail -1)
  [ -z "$judge_cost" ] && judge_cost=0
  if grep -qiE '^[^A-Za-z]*PASS' "$out/judge.txt" 2>/dev/null; then verdict=PASS
  elif grep -qiE '^[^A-Za-z]*FAIL' "$out/judge.txt" 2>/dev/null; then verdict=FAIL
  elif grep -qi 'PASS' "$out/judge.txt" 2>/dev/null; then verdict=PASS
  elif grep -qi 'FAIL' "$out/judge.txt" 2>/dev/null; then verdict=FAIL
  fi

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$rep" "$cond" "$task" "$rc" "$wall" \
    "$(jq -r .api_calls <<<"$usage")" "$tool_calls" \
    "$(jq -r .in <<<"$usage")" "$(jq -r .cache_read <<<"$usage")" \
    "$(jq -r .cache_write <<<"$usage")" "$(jq -r .out <<<"$usage")" \
    "$verdict" "$(jq -r .cost <<<"$usage")" "$judge_cost" >> "$RESULTS"

  echo "[rep$rep $cond $task] rc=$rc ${wall}ms tools=$tool_calls $verdict"
  rm -rf "$ws"
}

for rep in $(seq "$REP_START" "$REP_END"); do
  while IFS=$'\t' read -r task repo prompt; do
    [ -z "$task" ] && continue
    [ -n "$TASK_FILTER" ] && [ "$task" != "$TASK_FILTER" ] && continue
    for cond in $(shuffle_conds "$rep"); do
      [ -n "$COND_FILTER" ] && [ "$cond" != "$COND_FILTER" ] && continue
      run_cell "$rep" "$cond" "$task" "$repo" "$prompt"
    done
  done < "$D/tasks/tasks.tsv"
done
