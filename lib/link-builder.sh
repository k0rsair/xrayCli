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
  local server_address="$1"
  local params="encryption=none&flow=${REALITY_FLOW:-xtls-rprx-vision}&security=reality&sni=${REALITY_SNI}&fp=${REALITY_FINGERPRINT}&pbk=${REALITY_PUBLIC_KEY}&type=tcp"
  if [[ -n "${REALITY_SHORT_ID}" ]]; then
    params="${params}&sid=${REALITY_SHORT_ID}"
  fi
  echo "vless://${CLIENT_UUID}@${server_address}:443?${params}#vless-reality"
}

resolve_reality_server_address() {
  log_debug "[link-builder.resolve_reality_server_address] start address=${REALITY_ADDRESS:-} reference=${REALITY_REFERENCE_ADDRESS:-}"
  if [[ -n "${REALITY_ADDRESS:-}" ]]; then
    echo "${REALITY_ADDRESS}"
    return 0
  fi
  if [[ -n "${REALITY_REFERENCE_ADDRESS:-}" ]]; then
    echo "${REALITY_REFERENCE_ADDRESS}"
    return 0
  fi
  get_server_public_ip
}

build_reality_client_json() {
  local server_address="$1"
  local server_port="${2:-443}"
  jq -n \
    --arg address "${server_address}" \
    --argjson port "${server_port}" \
    --arg uuid "${CLIENT_UUID}" \
    --arg flow "${REALITY_FLOW:-xtls-rprx-vision}" \
    --arg sni "${REALITY_SNI}" \
    --arg fingerprint "${REALITY_FINGERPRINT}" \
    --arg publicKey "${REALITY_PUBLIC_KEY}" \
    --arg shortId "${REALITY_SHORT_ID:-}" \
    --arg remarks "${REALITY_REMARKS:-xray-cli Reality}" \
    '{
      remarks: $remarks,
      log: { loglevel: "info" },
      inbounds: [{
        tag: "socks",
        listen: "[::1]",
        port: 1080,
        protocol: "socks",
        settings: { udp: true },
        sniffing: {
          enabled: true,
          routeOnly: false,
          destOverride: ["quic", "tls", "http"]
        }
      }],
      outbounds: [
        {
          protocol: "vless",
          tag: "proxy",
          settings: {
            address: $address,
            port: $port,
            id: $uuid,
            encryption: "none",
            flow: $flow
          },
          streamSettings: {
            security: "reality",
            network: "tcp",
            realitySettings: {
              serverName: $sni,
              fingerprint: $fingerprint,
              publicKey: $publicKey,
              shortId: $shortId,
              spiderX: ""
            },
            tcpSettings: {
              header: { type: "none" }
            }
          }
        },
        {
          protocol: "blackhole",
          tag: "block",
          settings: { response: { type: "none" } }
        },
        {
          protocol: "freedom",
          tag: "direct",
          settings: {}
        }
      ]
    }'
}

write_client_links() {
  log_debug "[link-builder.write_client_links] start"
  ensure_state_dir

  local reality_address
  reality_address="$(resolve_reality_server_address)"
  if [[ -z "${reality_address}" ]]; then
    log_warn "Не удалось определить адрес сервера Reality"
    reality_address="YOUR_SERVER_IP"
  fi
  if [[ -z "${REALITY_ADDRESS:-}" && -z "${REALITY_REFERENCE_ADDRESS:-}" ]]; then
    log_warn "Reality address не импортирован — используем fallback адрес ${reality_address}"
  fi
  local reality_port="${REALITY_REFERENCE_PORT:-443}"

  local links=""
  if [[ "${ENABLE_VLESS_WS}" == "1" ]]; then
    links+="[vless-ws]"$'\n'
    links+="$(build_vless_ws_link)"$'\n\n'
  fi

  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    links+="[vless-reality]"$'\n'
    links+="$(build_vless_reality_link "${reality_address}")"$'\n'
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[dry-run] ссылки не записаны"
    echo "${links}"
    if [[ "${ENABLE_REALITY}" == "1" ]]; then
      echo ""
      echo "[client-reality.json]"
      build_reality_client_json "${reality_address}" "${reality_port}" | jq .
    fi
    return 0
  fi

  echo "${links}" > "${XRAY_CLI_LINKS_FILE}"
  run_cmd chmod 600 "${XRAY_CLI_LINKS_FILE}"
  log_info "Ссылки сохранены: ${XRAY_CLI_LINKS_FILE}"

  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    build_reality_client_json "${reality_address}" "${reality_port}" | jq . > "${XRAY_CLI_REALITY_JSON_FILE}"
    run_cmd chmod 600 "${XRAY_CLI_REALITY_JSON_FILE}"
    log_info "Reality client JSON сохранён: ${XRAY_CLI_REALITY_JSON_FILE} address_type=$([[ "${reality_address}" =~ [A-Za-z] ]] && echo hostname || echo ip)"
  fi

  echo ""
  echo "========== Ссылки для подключения =========="
  echo "${links}"
  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    echo "Reality JSON: ${XRAY_CLI_REALITY_JSON_FILE}"
  fi
  echo "==========================================="
}
