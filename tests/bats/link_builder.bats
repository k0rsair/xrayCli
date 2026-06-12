#!/usr/bin/env bats

setup() {
  export BATS_TEST_MODE=1
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/common.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/link-builder.sh"

  CLIENT_UUID="00000000-0000-4000-8000-000000000001"
  DOMAIN="vpn.example.com"
  WS_PATH="/xray-ws"
  REALITY_SNI="www.microsoft.com"
  REALITY_FLOW="xtls-rprx-vision"
  REALITY_FINGERPRINT="chrome"
  REALITY_PUBLIC_KEY="pubkey123"
  REALITY_SHORT_ID="aabbccdd"
}

@test "build_vless_ws_link contains required params" {
  run build_vless_ws_link
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"vless://${CLIENT_UUID}@${DOMAIN}:443"* ]]
  [[ "$output" == *"type=ws"* ]]
  [[ "$output" == *"security=tls"* ]]
}

@test "build_vless_reality_link contains reality params" {
  run build_vless_reality_link "203.0.113.1"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"security=reality"* ]]
  [[ "$output" == *"pbk=pubkey123"* ]]
  [[ "$output" == *"sni=www.microsoft.com"* ]]
}

@test "build_reality_client_json preserves hostname and custom fingerprint" {
  REALITY_FINGERPRINT="qq"
  REALITY_REMARKS="Germany"

  run build_reality_client_json "test.grey-lance.test-cdn-kkk.com" "443"
  [[ "$status" -eq 0 ]]
  [[ "$output" == *"test.grey-lance.test-cdn-kkk.com"* ]]
  [[ "$output" == *'"fingerprint": "qq"'* ]]
  [[ "$output" == *'"publicKey": "pubkey123"'* ]]
}

@test "resolve_reality_server_address prefers imported hostname" {
  REALITY_ADDRESS=""
  REALITY_REFERENCE_ADDRESS="test.grey-lance.test-cdn-kkk.com"

  run resolve_reality_server_address
  [[ "$status" -eq 0 ]]
  [[ "$output" == "test.grey-lance.test-cdn-kkk.com" ]]
}
