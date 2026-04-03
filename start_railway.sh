#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${BACKEND_DIR:-$ROOT_DIR/backend}"

PORT="${PORT:-8000}"

# Приоритет:
# 1) аргументы запуска
# 2) переменные окружения
# 3) дефолты
NODE_HOST="${1:-${NODE_HOST:-}}"
COLLECT_INTERVAL="${2:-${COLLECT_INTERVAL:-30}}"
START_COLLECTOR="${3:-${START_COLLECTOR:-1}}"

OPS_BASE_URL="${OPS_BASE_URL:-}"
LATENCY_TARGET_URL="${LATENCY_TARGET_URL:-}"
INIT_DB="${INIT_DB:-1}"

cleanup() {
  if [[ -n "${COLLECTOR_PID:-}" ]]; then
    kill "${COLLECTOR_PID}" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

cd "$BACKEND_DIR"
mkdir -p history graphs

if [[ -z "${OPS_BASE_URL}" ]]; then
  if [[ -z "${NODE_HOST}" ]]; then
    echo "ERROR: pass NODE_HOST as arg1 or env var"
    echo "Usage: bash start_railway.sh <node_host> [collect_interval] [start_collector]"
    exit 1
  fi
  OPS_BASE_URL="http://${NODE_HOST}:9153"
fi

if [[ -z "${LATENCY_TARGET_URL}" ]]; then
  LATENCY_TARGET_URL="${OPS_BASE_URL}/health"
fi

export OPS_BASE_URL
export LATENCY_TARGET_URL
export COLLECT_INTERVAL
export START_COLLECTOR
export INIT_DB
export PORT

echo "PORT=$PORT"
echo "OPS_BASE_URL=$OPS_BASE_URL"
echo "LATENCY_TARGET_URL=$LATENCY_TARGET_URL"
echo "COLLECT_INTERVAL=$COLLECT_INTERVAL"
echo "START_COLLECTOR=$START_COLLECTOR"

if [[ "$INIT_DB" == "1" ]]; then
  python3 history_sqlite.py
fi

if [[ "$START_COLLECTOR" == "1" ]]; then
  (
    while true; do
      python3 collector_sqlite.py || echo "[warn] collector failed"
      sleep "$COLLECT_INTERVAL"
    done
  ) &
  COLLECTOR_PID=$!
  echo "Collector started with PID ${COLLECTOR_PID}"
fi

exec uvicorn main:app --host 0.0.0.0 --port "$PORT"
