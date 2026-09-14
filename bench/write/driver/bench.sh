#!/usr/bin/env bash
# gh-ci benchmark driver — write-side half (T7 reply, T8 comment, T9 resolve).
#
# Same rig as the read half: one `claude -p --output-format stream-json` per
# (task x condition x repeat), usage parsed from the stream, an LLM judge
# against a reference answer. Two things are added, both because these tasks
# write:
#
#   * a recording GitHub-API mock stands behind GH_HOST, so tier 1 cannot reach
#     github.com at all, and the mock's state is reset before every cell;
#   * a deterministic call-log assertion runs beside the judge, because the
#     write-side failure that matters -- "replied to the thread" when the agent
#     actually posted a top-level comment -- is invisible in prose.
#
# Usage: bench.sh --ghci 1.2.3|1.2.4|1.3.0 <rep-start> <rep-end> [task-filter] [cond-filter]
set -uo pipefail

D="${BENCH_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
FORGE="${MOCK_FORGE:-$D/../../tests/mock-forge}"
REPO_ROOT="$(git -C "$D" rev-parse --show-toplevel)"
GHCI_VERSION=""
if [ "${1:-}" = --ghci ]; then GHCI_VERSION="${2:-}"; shift 2; fi
case "$GHCI_VERSION" in
  1.2.3) GHCI_COMMIT=3be16034aacffaefa462a61d269d8224b9a158a4 ;;
  1.2.4) GHCI_COMMIT=d70569a2fdb5662a359e1200d91a1f28514d4a30 ;;
  1.3.0) GHCI_COMMIT=cf2528060c34c16c838e247780f748fe5ab13dc3 ;;
  *) echo "bench: --ghci must be 1.2.3, 1.2.4, or 1.3.0" >&2; exit 2 ;;
esac
PAYLOAD="$D/payload/$GHCI_VERSION/gh-ci"
mkdir -p "$PAYLOAD/resources"
git -C "$REPO_ROOT" show "$GHCI_COMMIT:gh-ci/SKILL.md" > "$PAYLOAD/SKILL.md"
git -C "$REPO_ROOT" show "$GHCI_COMMIT:gh-ci/resources/ci.sh" > "$PAYLOAD/resources/ci.sh"
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
RESULTS="${BENCH_RESULTS:-$D/results.tier1.tsv}"
RUNROOT="${BENCH_RUNROOT:-$D/runs/tier1}"
TARGETS="${BENCH_TARGETS:-$D/tasks/targets.tier1.tsv}"
FORGE_RUN="$D/forge-run"

REP_START="${1:-1}"; REP_END="${2:-1}"
TASK_FILTER="${3:-}"; COND_FILTER="${4:-}"

CONDS=(C-ghci C-gh C-ghaxi)

if [ ! -f "$RESULTS" ]; then
  printf 'tier\trep\tcond\ttask\ttarget\texit\twall_ms\tapi_calls\ttool_calls\tin_tok\tcache_read\tcache_write\tout_tok\tcall_assert\tverdict\tagent_usd\tjudge_usd\n' > "$RESULTS"
fi

# Deterministic-but-varied condition order per repeat, as in the read half.
shuffle_conds() {
  printf '%s\n' "${CONDS[@]}" | awk -v seed="$1" 'BEGIN{srand(seed)} {print rand()"\t"$0}' | sort -k1,1 | cut -f2
}

cond_index() {
  case "$1" in C-ghci) echo 0 ;; C-gh) echo 1 ;; C-ghaxi) echo 2 ;; esac
}

rm -rf "$FORGE_RUN"; mkdir -p "$FORGE_RUN"
forge_env="$(bash "$FORGE/forge.sh" start "$FORGE_RUN")" || { echo "driver: mock forge failed to start" >&2; exit 1; }
eval "$forge_env"
trap 'bash "$FORGE/forge.sh" stop "$FORGE_RUN"' EXIT
echo "driver: recording mock at $GH_HOST"

run_cell() {
  local rep="$1" cond="$2" task="$3" offset="$4" prompt_tpl="$5"
  local ci; ci="$(cond_index "$cond")"
  local tidx=$(( (offset + (rep - 1) * 3 + ci) % 15 ))

  local target_line comment_id thread_id text expected_body
  target_line="$(awk -F'\t' -v i="$tidx" '$1==i' "$TARGETS")"
  comment_id="$(cut -f2 <<<"$target_line")"
  thread_id="$(cut -f3 <<<"$target_line")"
  text="$(cut -f4- <<<"$target_line")"

  local repo="$GH_REPO" pr=1

  local mark="WSB-t1-r$rep-$cond-$task"
  local prompt="$prompt_tpl"
  prompt="${prompt//\{\{REPO\}\}/$repo}"
  prompt="${prompt//\{\{PR\}\}/$pr}"
  prompt="${prompt//\{\{TEXT\}\}/$text}"
  prompt="${prompt//\{\{MARK\}\}/$mark}"
  prompt="$(printf '%b' "$prompt")"
  case "$task" in
    T7) expected_body="Fixed in 1312fe2 — bounded the loop at 5 attempts. (ref $mark)" ;;
    T8) expected_body="CI is green on this branch: lint, test and scan all passed. (ref $mark)" ;;
    T9) expected_body="" ;;
  esac

  local out="$RUNROOT/rep$rep/$cond/$task"
  mkdir -p "$out"
  jq -n --arg pr "$pr" --arg mark "$mark" --arg cid "$comment_id" \
        --arg tid "$thread_id" --arg text "$text" \
    --arg expected_body "$expected_body" \
    '{pr:$pr, mark:$mark, comment_id:$cid, thread_id:$tid, comment_text:$text, expected_body:$expected_body}' \
    > "$out/expected.json"
  printf '%s' "$prompt" > "$out/prompt.txt"

  local ws="$D/work/$rep-$cond-$task"
  rm -rf "$ws"; mkdir -p "$ws/.claude"
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
      cat > "$ws/.claude/settings.json" <<'JSON'
{"hooks":{"SessionStart":[{"matcher":"","hooks":[{"type":"command","command":"gh-axi","timeout":10}]}]}}
JSON
      ;;
  esac

  bash "$FORGE/forge.sh" reset "$FORGE_RUN"

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

  cp "$FORGE_CALLS" "$out/calls.jsonl" 2>/dev/null || : > "$out/calls.jsonl"
  local call_assert="$(python3 "$D/driver/assert_calls.py" "$task" "$out/calls.jsonl" "$out/expected.json")"
  printf '%s\n' "$call_assert" > "$out/call_assert.txt"
  local call_verdict="ERROR"
  case "$call_assert" in PASS*) call_verdict=PASS ;; FAIL*) call_verdict=FAIL ;; esac

  # --- usage (same dedupe recipe as the read half) --------------------------
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

  jq -r 'select(.type=="result") | .result // empty' "$out/stream.jsonl" 2>/dev/null > "$out/answer.txt"
  if [ ! -s "$out/answer.txt" ]; then
    jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text' \
      "$out/stream.jsonl" 2>/dev/null > "$out/answer.txt"
  fi
  jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use")
         | "\(.name): \((.input.command // .input.file_path // (.input|tostring))|tostring|.[0:300])"' \
    "$out/stream.jsonl" 2>/dev/null | head -40 > "$out/commands.txt"

  # --- judge ---------------------------------------------------------------
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
    printf 'have performed the write (hallucination), performed the wrong kind of write, or did not\n'
    printf 'produce an answer.\n'
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

  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "1" "$rep" "$cond" "$task" "$tidx" "$rc" "$wall" \
    "$(jq -r .api_calls <<<"$usage")" "$tool_calls" \
    "$(jq -r .in <<<"$usage")" "$(jq -r .cache_read <<<"$usage")" \
    "$(jq -r .cache_write <<<"$usage")" "$(jq -r .out <<<"$usage")" \
    "$call_verdict" "$verdict" "$(jq -r .cost <<<"$usage")" "$judge_cost" >> "$RESULTS"

  echo "[rep$rep $cond $task tgt$tidx] rc=$rc ${wall}ms tools=$tool_calls call=$call_verdict judge=$verdict"
  [ "$call_verdict" != PASS ] && echo "    $call_assert"
  rm -rf "$ws"
  return 0
}

for rep in $(seq "$REP_START" "$REP_END"); do
  while IFS=$'\t' read -r task offset prompt; do
    [ -z "$task" ] && continue
    [ -n "$TASK_FILTER" ] && [ "$task" != "$TASK_FILTER" ] && continue
    for cond in $(shuffle_conds "$rep"); do
      [ -n "$COND_FILTER" ] && [ "$cond" != "$COND_FILTER" ] && continue
      run_cell "$rep" "$cond" "$task" "$offset" "$prompt"
    done
  done < "$D/tasks/tasks.tsv"
done
