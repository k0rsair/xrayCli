#!/usr/bin/env bash
# shellcheck shell=bash
# Merge inbounds into final xray config.json.

build_base_config() {
  jq -n '{
    log: { loglevel: "warning" },
    inbounds: [],
    outbounds: [
      { protocol: "freedom", tag: "direct" },
      { protocol: "blackhole", tag: "block" }
    ],
    routing: {
      rules: [
        { type: "field", ip: ["geoip:private"], outboundTag: "block" }
      ]
    }
  }'
}

write_xray_config() {
  log_debug "[config-merge.write_xray_config] start"
  local inbounds=()
  local port_scheme=""

  if [[ "${ENABLE_VLESS_WS}" == "1" ]]; then
    inbounds+=("$(build_vless_ws_inbound "${WS_PORT}")")
    port_scheme+="ws:127.0.0.1:${WS_PORT}->nginx:443 "
  fi

  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    if [[ "${ENABLE_VLESS_WS}" == "1" ]]; then
      inbounds+=("$(build_reality_inbound "127.0.0.1" "${REALITY_INTERNAL_PORT}")")
      port_scheme+="reality:127.0.0.1:${REALITY_INTERNAL_PORT}->stream:443 "
    else
      inbounds+=("$(build_reality_inbound "0.0.0.0" "443")")
      port_scheme+="reality:0.0.0.0:443 "
    fi
  fi

  local config
  config="$(build_base_config)"
  local inbound
  for inbound in "${inbounds[@]}"; do
    config="$(echo "${config}" | jq --argjson ib "${inbound}" '.inbounds += [$ib]')"
  done

  log_info "Схема портов: ${port_scheme}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[dry-run] config.json не записан"
    echo "${config}" | jq .
    return 0
  fi

  run_cmd mkdir -p "$(dirname "${XRAY_CONFIG_PATH}")"
  echo "${config}" | jq . > "${XRAY_CONFIG_PATH}"
  log_debug "[config-merge.write_xray_config] written to ${XRAY_CONFIG_PATH}"

  test_xray_config
}

test_xray_config() {
  log_debug "[config-merge.test_xray_config] path=${XRAY_CONFIG_PATH}"
  if [[ "${DRY_RUN}" == "1" ]]; then
    return 0
  fi
  if ! "${XRAY_BIN}" run -test -config "${XRAY_CONFIG_PATH}" >/dev/null 2>&1; then
    log_error "xray -test не прошёл для ${XRAY_CONFIG_PATH}"
    "${XRAY_BIN}" run -test -config "${XRAY_CONFIG_PATH}" 2>&1 | tail -20 >&2 || true
    die "Невалидный config.json"
  fi
  log_info "xray config: OK"
}
