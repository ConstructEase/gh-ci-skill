#!/usr/bin/env bash
# Lifecycle helper for the recording GitHub-API mock (see forge.py).
#
#   eval "$(forge.sh start <dir>)"   start a mock rooted at <dir>, print the env
#                                    that points `gh` at it (as `export` lines)
#   forge.sh reset <dir>             reload the seed state, truncate the call log
#   forge.sh calls <dir>             print the call log (JSON lines)
#   forge.sh stop  <dir>             stop the mock and remove its runtime files
#
# <dir> holds cert.pem, key.pem, forge.pid, forge.port, calls.jsonl, forge.err.
# Everything is local: the server binds 127.0.0.1 and never dials out.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
action="${1:?usage: forge.sh start|reset|calls|stop|env <dir>}"
dir="${2:?usage: forge.sh $action <dir>}"

port_of() { cat "$dir/forge.port"; }

env_lines() {
  local port; port="$(port_of)"
  # These exports redirect well-behaved tooling to the mock and make accidental
  # github.com requests fail authentication. They are not a network sandbox and
  # a caller can unset them to use stored authentication.
  cat <<ENV
export GH_HOST=127.0.0.1:$port
export GH_ENTERPRISE_TOKEN=mock-forge-token
export GH_TOKEN=ghp_invalidinvalidinvalidinvalidinvalid
export GITHUB_TOKEN=ghp_invalidinvalidinvalidinvalidinvalid
export SSL_CERT_FILE=$dir/cert.pem
if [ "${FORGE_NO_REPO_ENV:-0}" != 1 ]; then
  export GH_REPO=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["owner"]+"/"+d["repo"])' "$HERE/seed.json")
  export REPO_NWO=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d["owner"]+"/"+d["repo"])' "$HERE/seed.json")
fi
export FORGE_DIR=$dir
export FORGE_CALLS=$dir/calls.jsonl
ENV
}

case "$action" in
  start)
    mkdir -p "$dir"
    if [ ! -f "$dir/cert.pem" ]; then
      # Throwaway self-signed cert for 127.0.0.1, generated per run so no
      # private key is ever committed to the repository.
      openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
        -keyout "$dir/key.pem" -out "$dir/cert.pem" \
        -subj "/CN=127.0.0.1" \
        -addext "subjectAltName=IP:127.0.0.1,DNS:localhost" \
        >/dev/null 2>&1
    fi
    rm -f "$dir/forge.port"
    python3 "$HERE/forge.py" \
      --cert "$dir/cert.pem" --key "$dir/key.pem" \
      --seed "$HERE/seed.json" --log "$dir/calls.jsonl" \
      --port-file "$dir/forge.port" \
      >"$dir/forge.out" 2>"$dir/forge.err" &
    echo $! > "$dir/forge.pid"
    for _ in $(seq 1 100); do
      [ -s "$dir/forge.port" ] && break
      sleep 0.1
    done
    if [ ! -s "$dir/forge.port" ]; then
      echo "forge.sh: mock did not start; see $dir/forge.err" >&2
      exit 1
    fi
    env_lines
    ;;
  env)
    env_lines
    ;;
  reset)
    curl -sS --cacert "$dir/cert.pem" -X POST \
      "https://127.0.0.1:$(port_of)/__control/reset" >/dev/null
    ;;
  calls)
    cat "$dir/calls.jsonl" 2>/dev/null || true
    ;;
  stop)
    if [ -f "$dir/forge.pid" ]; then
      kill "$(cat "$dir/forge.pid")" 2>/dev/null || true
      wait "$(cat "$dir/forge.pid")" 2>/dev/null || true
    fi
    rm -f "$dir/forge.pid" "$dir/forge.port"
    ;;
  *)
    echo "forge.sh: unknown action: $action" >&2
    exit 1
    ;;
esac
