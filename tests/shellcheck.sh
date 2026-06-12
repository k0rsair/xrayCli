#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v shellcheck >/dev/null 2>&1; then
  echo "WARN: shellcheck не установлен — пропуск lint"
  exit 0
fi

mapfile -t scripts < <(find "${ROOT}" -type f \( -name '*.sh' -o -name 'install.sh' -o -name 'xray-cli' \) \
  ! -path '*/.git/*' ! -path '*/.agents/*' ! -path '*/.cursor/*' ! -path '*/.codex/*')

for script in "${scripts[@]}"; do
  shellcheck -x "${script}"
done

echo "shellcheck: OK (${#scripts[@]} files)"
