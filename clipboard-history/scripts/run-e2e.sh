#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT="${PASTEY_PORT:-8899}"
LOG_FILE="${TMPDIR:-/tmp}/pastey-e2e.log"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required for this script." >&2
  exit 1
fi

cleanup() {
  if [[ -n "${PASTEY_PID:-}" ]]; then
    kill "${PASTEY_PID}" >/dev/null 2>&1 || true
    wait "${PASTEY_PID}" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

cd "${ROOT_DIR}"

echo "Starting Pastey (log: ${LOG_FILE})"
swift run Pastey >"${LOG_FILE}" 2>&1 &
PASTEY_PID=$!

for _ in {1..20}; do
  if curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    break
  fi
  sleep 0.25
done

if ! curl -sf "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
  echo "Pastey Local API not reachable on port ${PORT}." >&2
  echo "Enable Local API in Preferences and confirm the port, then retry." >&2
  exit 1
fi

PASTEY_E2E=1 PASTEY_PORT="${PORT}" swift test
