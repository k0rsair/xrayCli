#!/usr/bin/env bats

setup() {
  export BATS_TEST_MODE=1
  PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/common.sh"
  # shellcheck disable=SC1091
  source "${PROJECT_ROOT}/lib/reality-reference.sh"
}

@test "load_reality_reference_if_configured imports reality settings from client json" {
  REALITY_REFERENCE_JSON="${BATS_TEST_TMPDIR}/reference.json"
  printf '%s\n' '{' \
    '  "remarks": "Germany",' \
    '  "outbounds": [' \
    '    {' \
    '      "protocol": "vless",' \
    '      "settings": {' \
    '        "address": "test.grey-lance.test-cdn-kkk.com",' \
    '        "port": 443,' \
    '        "id": "c217c643-7791-4ea7-a8cf-55830d76a008",' \
    '        "flow": "xtls-rprx-vision"' \
    '      },' \
    '      "streamSettings": {' \
    '        "security": "reality",' \
    '        "network": "tcp",' \
    '        "realitySettings": {' \
    '          "serverName": "tradingview.com",' \
    '          "fingerprint": "qq",' \
    '          "publicKey": "-tePObR3oZwGAUOb5kqTYkNWl6rtUKl0RFuzuu06wgw",' \
    '          "shortId": "50"' \
    '        }' \
    '      }' \
    '    }' \
    '  ]' \
    '}' > "${REALITY_REFERENCE_JSON}"

  load_reality_reference_if_configured

  [[ "${REALITY_ADDRESS}" == "test.grey-lance.test-cdn-kkk.com" ]]
  [[ "${REALITY_REFERENCE_UUID}" == "c217c643-7791-4ea7-a8cf-55830d76a008" ]]
  [[ "${REALITY_SNI}" == "tradingview.com" ]]
  [[ "${REALITY_DEST}" == "tradingview.com:443" ]]
  [[ "${REALITY_FINGERPRINT}" == "qq" ]]
  [[ -z "${CLIENT_UUID:-}" ]]
  [[ "${REALITY_REFERENCE_SHORT_ID}" == "50" ]]
  [[ -z "${REALITY_SHORT_ID:-}" ]]
  [[ "${REALITY_REFERENCE_PUBLIC_KEY}" == "-tePObR3oZwGAUOb5kqTYkNWl6rtUKl0RFuzuu06wgw" ]]
}

@test "load_reality_reference_if_configured preserves cli overrides" {
  REALITY_REFERENCE_JSON="${BATS_TEST_TMPDIR}/reference.json"
  REALITY_FINGERPRINT="chrome"
  REALITY_FINGERPRINT_SOURCE="cli"
  printf '%s\n' '{' \
    '  "outbounds": [' \
    '    {' \
    '      "protocol": "vless",' \
    '      "settings": {' \
    '        "address": "test.grey-lance.test-cdn-kkk.com",' \
    '        "port": 443,' \
    '        "id": "c217c643-7791-4ea7-a8cf-55830d76a008"' \
    '      },' \
    '      "streamSettings": {' \
    '        "security": "reality",' \
    '        "realitySettings": {' \
    '          "serverName": "tradingview.com",' \
    '          "fingerprint": "qq",' \
    '          "publicKey": "reference-public-key",' \
    '          "shortId": "50"' \
    '        }' \
    '      }' \
    '    }' \
    '  ]' \
    '}' > "${REALITY_REFERENCE_JSON}"

  load_reality_reference_if_configured

  [[ "${REALITY_FINGERPRINT}" == "chrome" ]]
  [[ "${REALITY_REFERENCE_PUBLIC_KEY}" == "reference-public-key" ]]
}
