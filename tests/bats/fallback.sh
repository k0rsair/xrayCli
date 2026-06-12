#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BATS_TEST_MODE=1
export CLIENT_UUID="00000000-0000-4000-8000-000000000001"
export DOMAIN="vpn.example.com"
export ENABLE_VLESS_WS=1
export ENABLE_REALITY=1
export REALITY_SNI="www.microsoft.com"
export REALITY_FINGERPRINT="chrome"
export REALITY_PUBLIC_KEY="test-public-key"
export REALITY_SHORT_ID="aabbccdd"
# shellcheck disable=SC1091
source "${ROOT}/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT}/lib/link-builder.sh"

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "${haystack}" == *"${needle}"* ]] || { echo "FAIL: expected '${needle}' in output"; exit 1; }
}

link="$(build_vless_ws_link)"
assert_contains "${link}" "vless://${CLIENT_UUID}@${DOMAIN}:443"
assert_contains "${link}" "type=ws"

link="$(build_vless_reality_link "203.0.113.1")"
assert_contains "${link}" "security=reality"
assert_contains "${link}" "pbk=test-public-key"

is_valid_fqdn "vpn.example.com" || { echo "FAIL: valid fqdn"; exit 1; }
is_valid_fqdn "bad" && { echo "FAIL: invalid fqdn accepted"; exit 1; }

echo "fallback tests: OK"
