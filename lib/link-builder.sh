#!/usr/bin/env bash
# shellcheck shell=bash
# Build vless:// client URIs.

urlencode() {
  local raw="$1"
  jq -nr --arg v "${raw}" '$v|@uri'
}

build_vless_ws_link() {
  local encoded_path
  encoded_path="$(urlencode "${WS_PATH}")"
  echo "vless://${CLIENT_UUID}@${DOMAIN}:443?encryption=none&security=tls&type=ws&host=${DOMAIN}&path=${encoded_path}#vless-ws"
}

build_vless_reality_link() {
  local server_ip="$1"
  local params="encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SNI}&fp=${REALITY_FINGERPRINT}&pbk=${REALITY_PUBLIC_KEY}&type=tcp"
  if [[ -n "${REALITY_SHORT_ID}" ]]; then
    params="${params}&sid=${REALITY_SHORT_ID}"
  fi
  echo "vless://${CLIENT_UUID}@${server_ip}:443?${params}#vless-reality"
}

write_client_links() {
  log_debug "[link-builder.write_client_links] start"
  ensure_state_dir

  local server_ip
  server_ip="$(get_server_public_ip)"
  if [[ -z "${server_ip}" ]]; then
    log_warn "Не удалось определить публичный IP сервера"
    server_ip="YOUR_SERVER_IP"
  fi

  local links=""
  if [[ "${ENABLE_VLESS_WS}" == "1" ]]; then
    links+="[vless-ws]"$'\n'
    links+="$(build_vless_ws_link)"$'\n\n'
  fi

  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    links+="[vless-reality]"$'\n'
    links+="$(build_vless_reality_link "${server_ip}")"$'\n'
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[dry-run] ссылки не записаны"
    echo "${links}"
    return 0
  fi

  echo "${links}" > "${XRAY_CLI_LINKS_FILE}"
  run_cmd chmod 600 "${XRAY_CLI_LINKS_FILE}"
  log_info "Ссылки сохранены: ${XRAY_CLI_LINKS_FILE}"

  echo ""
  echo "========== Ссылки для подключения =========="
  echo "${links}"
  echo "==========================================="
}
