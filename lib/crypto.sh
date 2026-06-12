#!/usr/bin/env bash
# shellcheck shell=bash
# Secret generation and persistence.

CLIENT_UUID="${CLIENT_UUID:-}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"
REALITY_FLOW="${REALITY_FLOW:-xtls-rprx-vision}"

gen_uuid() {
  log_debug "[crypto.gen_uuid] start"
  if [[ -n "${CLIENT_UUID:-}" ]]; then
    log_info "UUID клиента сохранён: $(mask_secret "${CLIENT_UUID}") source=${CLIENT_UUID_SOURCE:-unknown}"
    return 0
  fi
  if [[ "${DRY_RUN}" == "1" ]]; then
    CLIENT_UUID="00000000-0000-4000-8000-000000000001"
  else
    require_cmd xray
    CLIENT_UUID="$("${XRAY_BIN}" uuid)"
  fi
  CLIENT_UUID_SOURCE="generated"
  log_info "UUID сгенерирован: $(mask_secret "${CLIENT_UUID}")"
}

gen_x25519() {
  log_debug "[crypto.gen_x25519] start"
  if [[ "${DRY_RUN}" == "1" ]]; then
    REALITY_PRIVATE_KEY="dry-run-private-key"
    REALITY_PUBLIC_KEY="dry-run-public-key"
  else
    require_cmd xray
    local output
    output="$("${XRAY_BIN}" x25519)"
    REALITY_PRIVATE_KEY="$(echo "${output}" | awk -F': ' '/Private key/ {print $2}' | tr -d '[:space:]')"
    REALITY_PUBLIC_KEY="$(echo "${output}" | awk -F': ' '/Public key/ {print $2}' | tr -d '[:space:]')"
    if [[ -z "${REALITY_PRIVATE_KEY}" || -z "${REALITY_PUBLIC_KEY}" ]]; then
      REALITY_PRIVATE_KEY="$(echo "${output}" | awk 'NR==1 {print $NF}')"
      REALITY_PUBLIC_KEY="$(echo "${output}" | awk 'NR==2 {print $NF}')"
    fi
  fi
  REALITY_PRIVATE_KEY_SOURCE="generated"
  REALITY_PUBLIC_KEY_SOURCE="generated"
  log_info "x25519 сгенерирован: private=$(mask_secret "${REALITY_PRIVATE_KEY}") public=$(mask_secret "${REALITY_PUBLIC_KEY}")"
  if [[ -n "${REALITY_REFERENCE_PUBLIC_KEY:-}" && "${REALITY_REFERENCE_PUBLIC_KEY}" != "${REALITY_PUBLIC_KEY}" ]]; then
    log_warn "Reference publicKey отличается от локально сгенерированного publicKey: reference=$(mask_secret "${REALITY_REFERENCE_PUBLIC_KEY}") generated=$(mask_secret "${REALITY_PUBLIC_KEY}")"
  fi
}

gen_short_id() {
  log_debug "[crypto.gen_short_id] start"
  if [[ -n "${REALITY_SHORT_ID:-}" ]]; then
    log_info "shortId клиента сохранён: $(mask_secret "${REALITY_SHORT_ID}") source=${REALITY_SHORT_ID_SOURCE:-unknown}"
    return 0
  fi
  REALITY_SHORT_ID="$(openssl rand -hex 4)"
  REALITY_SHORT_ID_SOURCE="generated"
  log_info "shortId сгенерирован: $(mask_secret "${REALITY_SHORT_ID}")"
}

persist_secrets() {
  log_debug "[crypto.persist_secrets] start"
  ensure_state_dir

  {
    echo "# xray-cli state — не публикуйте этот файл"
    state_assignment "ENABLE_VLESS_WS" "${ENABLE_VLESS_WS}"
    state_assignment "ENABLE_REALITY" "${ENABLE_REALITY}"
    state_assignment "DOMAIN" "${DOMAIN:-}"
    state_assignment "CLIENT_UUID" "${CLIENT_UUID:-}"
    state_assignment "CLIENT_UUID_SOURCE" "${CLIENT_UUID_SOURCE:-}"
    state_assignment "WS_PORT" "${WS_PORT}"
    state_assignment "WS_PATH" "${WS_PATH}"
    state_assignment "REALITY_ADDRESS" "${REALITY_ADDRESS:-}"
    state_assignment "REALITY_ADDRESS_SOURCE" "${REALITY_ADDRESS_SOURCE:-}"
    state_assignment "REALITY_DEST" "${REALITY_DEST:-}"
    state_assignment "REALITY_DEST_SOURCE" "${REALITY_DEST_SOURCE:-}"
    state_assignment "REALITY_SNI" "${REALITY_SNI:-}"
    state_assignment "REALITY_SNI_SOURCE" "${REALITY_SNI_SOURCE:-}"
    state_assignment "REALITY_FLOW" "${REALITY_FLOW:-xtls-rprx-vision}"
    state_assignment "REALITY_FLOW_SOURCE" "${REALITY_FLOW_SOURCE:-}"
    state_assignment "REALITY_FINGERPRINT" "${REALITY_FINGERPRINT:-chrome}"
    state_assignment "REALITY_FINGERPRINT_SOURCE" "${REALITY_FINGERPRINT_SOURCE:-}"
    state_assignment "REALITY_PRIVATE_KEY" "${REALITY_PRIVATE_KEY:-}"
    state_assignment "REALITY_PRIVATE_KEY_SOURCE" "${REALITY_PRIVATE_KEY_SOURCE:-}"
    state_assignment "REALITY_PUBLIC_KEY" "${REALITY_PUBLIC_KEY:-}"
    state_assignment "REALITY_PUBLIC_KEY_SOURCE" "${REALITY_PUBLIC_KEY_SOURCE:-}"
    state_assignment "REALITY_SHORT_ID" "${REALITY_SHORT_ID:-}"
    state_assignment "REALITY_SHORT_ID_SOURCE" "${REALITY_SHORT_ID_SOURCE:-}"
    state_assignment "REALITY_REFERENCE_JSON" "${REALITY_REFERENCE_JSON:-}"
    state_assignment "REALITY_REFERENCE_JSON_SOURCE" "${REALITY_REFERENCE_JSON_SOURCE:-}"
    state_assignment "REALITY_REFERENCE_ADDRESS" "${REALITY_REFERENCE_ADDRESS:-}"
    state_assignment "REALITY_REFERENCE_ADDRESS_SOURCE" "${REALITY_REFERENCE_ADDRESS_SOURCE:-}"
    state_assignment "REALITY_REFERENCE_PORT" "${REALITY_REFERENCE_PORT:-}"
    state_assignment "REALITY_REFERENCE_PORT_SOURCE" "${REALITY_REFERENCE_PORT_SOURCE:-}"
    state_assignment "REALITY_REFERENCE_UUID" "${REALITY_REFERENCE_UUID:-}"
    state_assignment "REALITY_REFERENCE_UUID_SOURCE" "${REALITY_REFERENCE_UUID_SOURCE:-}"
    state_assignment "REALITY_REFERENCE_PUBLIC_KEY" "${REALITY_REFERENCE_PUBLIC_KEY:-}"
    state_assignment "REALITY_REFERENCE_PUBLIC_KEY_SOURCE" "${REALITY_REFERENCE_PUBLIC_KEY_SOURCE:-}"
    state_assignment "REALITY_REFERENCE_SHORT_ID" "${REALITY_REFERENCE_SHORT_ID:-}"
    state_assignment "REALITY_REFERENCE_SHORT_ID_SOURCE" "${REALITY_REFERENCE_SHORT_ID_SOURCE:-}"
    state_assignment "REALITY_REMARKS" "${REALITY_REMARKS:-}"
    state_assignment "REALITY_REMARKS_SOURCE" "${REALITY_REMARKS_SOURCE:-}"
    state_assignment "REALITY_INTERNAL_PORT" "${REALITY_INTERNAL_PORT}"
    state_assignment "NGINX_SSL_INTERNAL_PORT" "${NGINX_SSL_INTERNAL_PORT}"
    state_assignment "CERTBOT_EMAIL" "${CERTBOT_EMAIL:-}"
  } > "${XRAY_CLI_STATE_FILE}"

  run_cmd chmod 600 "${XRAY_CLI_STATE_FILE}"
  log_info "Секреты сохранены в ${XRAY_CLI_STATE_FILE}"
}

generate_all_secrets() {
  log_debug "[crypto.generate_all_secrets] start"
  gen_uuid

  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    gen_x25519
    gen_short_id
  fi

  persist_secrets
}
