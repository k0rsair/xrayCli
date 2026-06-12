#!/usr/bin/env bash
# shellcheck shell=bash
# Secret generation and persistence.

CLIENT_UUID="${CLIENT_UUID:-}"
REALITY_PRIVATE_KEY="${REALITY_PRIVATE_KEY:-}"
REALITY_PUBLIC_KEY="${REALITY_PUBLIC_KEY:-}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"

gen_uuid() {
  log_debug "[crypto.gen_uuid] start"
  if [[ "${DRY_RUN}" == "1" ]]; then
    CLIENT_UUID="00000000-0000-4000-8000-000000000001"
  else
    require_cmd xray
    CLIENT_UUID="$("${XRAY_BIN}" uuid)"
  fi
  log_info "UUID сгенерирован: $(mask_secret "${CLIENT_UUID}")"
  echo "${CLIENT_UUID}"
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
  log_info "x25519 сгенерирован: private=$(mask_secret "${REALITY_PRIVATE_KEY}") public=$(mask_secret "${REALITY_PUBLIC_KEY}")"
}

gen_short_id() {
  log_debug "[crypto.gen_short_id] start"
  REALITY_SHORT_ID="$(openssl rand -hex 4)"
  log_info "shortId сгенерирован: $(mask_secret "${REALITY_SHORT_ID}")"
  echo "${REALITY_SHORT_ID}"
}

persist_secrets() {
  log_debug "[crypto.persist_secrets] start"
  ensure_state_dir

  cat > "${XRAY_CLI_STATE_FILE}" <<EOF
# xray-cli state — не публикуйте этот файл
ENABLE_VLESS_WS=${ENABLE_VLESS_WS}
ENABLE_REALITY=${ENABLE_REALITY}
DOMAIN=${DOMAIN:-}
CLIENT_UUID=${CLIENT_UUID}
WS_PORT=${WS_PORT}
WS_PATH=${WS_PATH}
REALITY_DEST=${REALITY_DEST:-}
REALITY_SNI=${REALITY_SNI:-}
REALITY_FINGERPRINT=${REALITY_FINGERPRINT:-chrome}
REALITY_PRIVATE_KEY=${REALITY_PRIVATE_KEY:-}
REALITY_PUBLIC_KEY=${REALITY_PUBLIC_KEY:-}
REALITY_SHORT_ID=${REALITY_SHORT_ID:-}
REALITY_INTERNAL_PORT=${REALITY_INTERNAL_PORT}
NGINX_SSL_INTERNAL_PORT=${NGINX_SSL_INTERNAL_PORT}
CERTBOT_EMAIL=${CERTBOT_EMAIL:-}
EOF

  run_cmd chmod 600 "${XRAY_CLI_STATE_FILE}"
  log_info "Секреты сохранены в ${XRAY_CLI_STATE_FILE}"
}

generate_all_secrets() {
  log_debug "[crypto.generate_all_secrets] start"
  CLIENT_UUID="$(gen_uuid)"

  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    gen_x25519
    gen_short_id
  fi

  persist_secrets
}
