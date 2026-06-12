#!/usr/bin/env bash
# shellcheck shell=bash
# VLESS + Reality inbound JSON fragment.

build_reality_inbound() {
  local listen_addr="$1"
  local listen_port="$2"
  log_debug "[config-reality.build_reality_inbound] addr=${listen_addr} port=${listen_port}"

  if [[ "${ENABLE_VLESS_WS}" == "1" && "${listen_port}" == "443" ]]; then
    log_warn "Reality на 443 при включённом VLESS-WS — будет использован внутренний порт ${REALITY_INTERNAL_PORT}"
    listen_port="${REALITY_INTERNAL_PORT}"
    listen_addr="127.0.0.1"
  fi

  jq -n \
    --arg tag "vless-reality" \
    --arg uuid "${CLIENT_UUID}" \
    --argjson port "${listen_port}" \
    --arg listen "${listen_addr}" \
    --arg dest "${REALITY_DEST}" \
    --arg sni "${REALITY_SNI}" \
    --arg flow "${REALITY_FLOW:-xtls-rprx-vision}" \
    --arg privateKey "${REALITY_PRIVATE_KEY}" \
    --arg shortId "${REALITY_SHORT_ID}" \
    '{
      tag: $tag,
      listen: $listen,
      port: $port,
      protocol: "vless",
      settings: {
        clients: [{
          id: $uuid,
          email: "vless-reality@xray-cli",
          flow: $flow
        }],
        decryption: "none"
      },
      streamSettings: {
        network: "tcp",
        security: "reality",
        realitySettings: {
          show: false,
          dest: $dest,
          xver: 0,
          serverNames: [$sni],
          privateKey: $privateKey,
          shortIds: [$shortId]
        }
      }
    }'
}
