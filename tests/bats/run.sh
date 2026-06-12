#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BATS_TEST_MODE=1
export PATH="${ROOT}/tests/bats/helpers:${PATH}"

if command -v bats >/dev/null 2>&1; then
  bats "${ROOT}/tests/bats/"*.bats
else
  echo "WARN: bats не установлен — запуск fallback тестов"
  bash "${ROOT}/tests/bats/fallback.sh"
fi
