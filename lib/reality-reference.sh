#!/usr/bin/env bash
# shellcheck shell=bash
# Import and apply reference Reality client settings.

REALITY_REFERENCE_JSON="${REALITY_REFERENCE_JSON:-}"
REALITY_REFERENCE_ADDRESS="${REALITY_REFERENCE_ADDRESS:-}"
REALITY_REFERENCE_PORT="${REALITY_REFERENCE_PORT:-}"
REALITY_REFERENCE_UUID="${REALITY_REFERENCE_UUID:-}"
REALITY_REFERENCE_PUBLIC_KEY="${REALITY_REFERENCE_PUBLIC_KEY:-}"
REALITY_REFERENCE_SHORT_ID="${REALITY_REFERENCE_SHORT_ID:-}"
REALITY_REMARKS="${REALITY_REMARKS:-}"
REALITY_ADDRESS="${REALITY_ADDRESS:-}"
REALITY_FLOW="${REALITY_FLOW:-xtls-rprx-vision}"

assign_runtime_value() {
  local key="$1"
  local value="${2-}"
  local source="${3:-}"
  local source_key="${key}_SOURCE"

  if [[ -z "${value}" ]]; then
    log_debug "[reality-reference.assign_runtime_value] skip-empty key=${key}"
    return 0
  fi

  if [[ "${!source_key:-}" == "cli" ]]; then
    log_debug "[reality-reference.assign_runtime_value] preserve-cli key=${key}"
    return 0
  fi

  printf -v "${key}" '%s' "${value}"
  if [[ -n "${source}" ]]; then
    printf -v "${source_key}" '%s' "${source}"
  fi
  log_debug "[reality-reference.assign_runtime_value] key=${key} source=${source:-unknown}"
}

load_reality_reference_if_configured() {
  log_debug "[reality-reference.load_reality_reference_if_configured] start path=${REALITY_REFERENCE_JSON:-}"
  if [[ -z "${REALITY_REFERENCE_JSON:-}" ]]; then
    return 0
  fi

  require_cmd jq
  if [[ ! -f "${REALITY_REFERENCE_JSON}" ]]; then
    die "Reality reference JSON не найден: ${REALITY_REFERENCE_JSON}"
  fi

  local parsed
  parsed="$(jq -r '
    def first_reality:
      (.outbounds // [])
      | map(select((.protocol // "") == "vless" and ((.streamSettings.security // "") == "reality")))
      | .[0];

    (first_reality) as $outbound
    | if $outbound == null then
        empty
      else
        ($outbound.settings // {}) as $settings
        | ($settings.vnext[0]? // {}) as $vnext
        | ($vnext.users[0]? // {}) as $vuser
        | {
            address: ($vnext.address // $settings.address // ""),
            port: ($vnext.port // $settings.port // 443),
            id: ($vuser.id // $settings.id // ""),
            flow: ($vuser.flow // $settings.flow // "xtls-rprx-vision"),
            serverName: ($outbound.streamSettings.realitySettings.serverName // $outbound.streamSettings.realitySettings.serverNames[0] // ""),
            fingerprint: ($outbound.streamSettings.realitySettings.fingerprint // $outbound.streamSettings.realitySettings.fp // ""),
            publicKey: ($outbound.streamSettings.realitySettings.publicKey // $outbound.streamSettings.realitySettings.pbk // ""),
            shortId: ($outbound.streamSettings.realitySettings.shortId // $outbound.streamSettings.realitySettings.shortIds[0] // $outbound.streamSettings.realitySettings.sid // ""),
            remarks: (.remarks // "")
          }
        | [
            (.address // ""),
            ((.port // 443) | tostring),
            (.id // ""),
            (.flow // "xtls-rprx-vision"),
            (.serverName // ""),
            (.fingerprint // ""),
            (.publicKey // ""),
            (.shortId // ""),
            (.remarks // "")
          ]
        | @tsv
      end
  ' "${REALITY_REFERENCE_JSON}")"

  if [[ -z "${parsed}" ]]; then
    log_warn "Reality reference JSON не содержит outbound VLESS + Reality: ${REALITY_REFERENCE_JSON}"
    die "Не удалось извлечь Reality reference профиль"
  fi

  local ref_address ref_port ref_uuid ref_flow ref_sni ref_fp ref_public_key ref_short_id ref_remarks
  IFS=$'\t' read -r ref_address ref_port ref_uuid ref_flow ref_sni ref_fp ref_public_key ref_short_id ref_remarks <<< "${parsed}"

  assign_runtime_value "REALITY_REFERENCE_ADDRESS" "${ref_address}" "reference"
  assign_runtime_value "REALITY_REFERENCE_PORT" "${ref_port}" "reference"
  assign_runtime_value "REALITY_REFERENCE_UUID" "${ref_uuid}" "reference"
  assign_runtime_value "REALITY_REFERENCE_PUBLIC_KEY" "${ref_public_key}" "reference"
  assign_runtime_value "REALITY_REFERENCE_SHORT_ID" "${ref_short_id}" "reference"
  assign_runtime_value "REALITY_ADDRESS" "${ref_address}" "reference"
  assign_runtime_value "REALITY_FLOW" "${ref_flow}" "reference"
  assign_runtime_value "REALITY_SNI" "${ref_sni}" "reference"
  assign_runtime_value "REALITY_FINGERPRINT" "${ref_fp}" "reference"
  assign_runtime_value "REALITY_REMARKS" "${ref_remarks}" "reference"

  if [[ -n "${ref_sni}" && "${REALITY_DEST_SOURCE:-}" != "cli" ]]; then
    assign_runtime_value "REALITY_DEST" "${ref_sni}:443" "derived"
  fi

  log_info "Reality reference импортирован: path=${REALITY_REFERENCE_JSON} address=${ref_address:-n/a} sni=${ref_sni:-n/a} fp=${ref_fp:-n/a} ref_uuid=$(mask_secret "${ref_uuid:-}") ref_shortId=$(mask_secret "${ref_short_id:-}")"
}

finalize_reality_runtime() {
  log_debug "[reality-reference.finalize_reality_runtime] start reality=${ENABLE_REALITY:-0}"
  if [[ "${ENABLE_REALITY:-0}" != "1" ]]; then
    return 0
  fi

  if [[ -z "${REALITY_FLOW:-}" ]]; then
    REALITY_FLOW="xtls-rprx-vision"
    REALITY_FLOW_SOURCE="${REALITY_FLOW_SOURCE:-default}"
  fi

  if [[ -z "${REALITY_SNI:-}" && -n "${REALITY_DEST:-}" ]]; then
    REALITY_SNI="${REALITY_DEST%%:*}"
    REALITY_SNI_SOURCE="${REALITY_SNI_SOURCE:-derived}"
  fi

  if [[ -z "${REALITY_DEST:-}" && -n "${REALITY_SNI:-}" ]]; then
    REALITY_DEST="${REALITY_SNI}:443"
    REALITY_DEST_SOURCE="${REALITY_DEST_SOURCE:-derived}"
  fi

  if [[ "${ENABLE_VLESS_WS:-0}" == "1" && -n "${DOMAIN:-}" && "${REALITY_ADDRESS_SOURCE:-}" != "cli" ]]; then
    REALITY_ADDRESS="${DOMAIN}"
    REALITY_ADDRESS_SOURCE="domain"
  fi

  if [[ -z "${REALITY_ADDRESS:-}" && -n "${REALITY_REFERENCE_ADDRESS:-}" ]]; then
    REALITY_ADDRESS="${REALITY_REFERENCE_ADDRESS}"
    REALITY_ADDRESS_SOURCE="${REALITY_ADDRESS_SOURCE:-reference}"
  fi

  log_info "Итоговый Reality профиль: address=${REALITY_ADDRESS:-auto} sni=${REALITY_SNI:-n/a} dest=${REALITY_DEST:-n/a} flow=${REALITY_FLOW:-n/a} fp=${REALITY_FINGERPRINT:-n/a}"
}
