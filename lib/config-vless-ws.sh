#!/usr/bin/env bash
# shellcheck shell=bash
# VLESS + WebSocket inbound JSON fragment.

build_vless_ws_inbound() {
  local listen_port="${1:-${WS_PORT}}"
  log_debug "[config-vless-ws.build_vless_ws_inbound] port=${listen_port} path=${WS_PATH}"

  jq -n \
    --arg tag "vless-ws" \
    --arg uuid "${CLIENT_UUID}" \
    --argjson port "${listen_port}" \
    --arg path "${WS_PATH}" \
    '{
      tag: $tag,
      listen: "127.0.0.1",
      port: $port,
      protocol: "vless",
      settings: {
        clients: [{ id: $uuid, email: "vless-ws@xray-cli" }],
        decryption: "none"
      },
      streamSettings: {
        network: "ws",
        wsSettings: { path: $path }
      }
    }'
}
