#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export BATS_TEST_MODE=1
export CLIENT_UUID="00000000-0000-4000-8000-000000000001"
export DOMAIN="vpn.example.com"
export ENABLE_VLESS_WS=1
export ENABLE_REALITY=1
export REALITY_SNI="www.microsoft.com"
export REALITY_FLOW="xtls-rprx-vision"
export REALITY_FINGERPRINT="chrome"
export REALITY_PUBLIC_KEY="test-public-key"
export REALITY_SHORT_ID="aabbccdd"
export REALITY_REFERENCE_ADDRESS="test.grey-lance.test-cdn-kkk.com"
# shellcheck disable=SC1091
source "${ROOT}/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT}/lib/reality-reference.sh"
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

finalize_reality_runtime
address="$(resolve_reality_server_address)"
[[ "${address}" == "vpn.example.com" ]] || { echo "FAIL: reality address should prefer domain in combo"; exit 1; }

json="$(build_reality_client_json "test.grey-lance.test-cdn-kkk.com" "443")"
assert_contains "${json}" "test.grey-lance.test-cdn-kkk.com"
assert_contains "${json}" "\"publicKey\": \"test-public-key\""

is_valid_fqdn "vpn.example.com" || { echo "FAIL: valid fqdn"; exit 1; }
is_valid_fqdn "bad" && { echo "FAIL: invalid fqdn accepted"; exit 1; }

echo "fallback tests: OK"
