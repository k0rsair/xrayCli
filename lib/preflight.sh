#!/usr/bin/env bash
# shellcheck shell=bash
# Pre-flight checks: ports, prior xray installs.

xray_holds_port() {
  local port="$1"
  ss -tlnp 2>/dev/null | grep -E ":${port}[[:space:]]" | grep -qi xray
}

port_holder_summary() {
  local port="$1"
  ss -tlnp 2>/dev/null | grep -E ":${port}[[:space:]]" || true
}

backup_existing_xray_config() {
  if [[ ! -f "${XRAY_CONFIG_PATH}" ]]; then
    return 0
  fi
  local backup="${XRAY_CONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
  log_info "Резервная копия старого config.json: ${backup}"
  run_cmd cp -a "${XRAY_CONFIG_PATH}" "${backup}"
}

stop_xray_for_nginx() {
  log_debug "[preflight.stop_xray_for_nginx] start"
  if ! systemctl is-active --quiet xray 2>/dev/null; then
    return 0
  fi
  if xray_holds_port 443 || xray_holds_port 80; then
    log_warn "xray занимает порт 80/443 (старая установка) — останавливаем сервис"
    port_holder_summary 443 >&2 || true
    run_cmd systemctl stop xray
    sleep 1
    if xray_holds_port 443; then
      log_error "Порт 443 всё ещё занят xray после stop"
      port_holder_summary 443 >&2
      die "Освободите :443 вручную: systemctl stop xray"
    fi
    log_info "xray остановлен, порт 443 свободен для nginx"
  fi
}

ensure_ports_for_nginx() {
  log_debug "[preflight.ensure_ports_for_nginx] ws=${ENABLE_VLESS_WS}"
  if [[ "${ENABLE_VLESS_WS}" != "1" ]]; then
    return 0
  fi
  stop_xray_for_nginx
}

ensure_xray_config_compatible() {
  log_debug "[preflight.ensure_xray_config_compatible] start"
  if [[ "${ENABLE_VLESS_WS}" == "1" && "${ENABLE_REALITY}" == "1" ]]; then
    log_info "Combo: xray Reality на 127.0.0.1:${REALITY_INTERNAL_PORT}, nginx stream на :443"
  elif [[ "${ENABLE_VLESS_WS}" == "1" ]]; then
    log_info "VLESS-WS: nginx на :443, xray WS на 127.0.0.1:${WS_PORT}"
  elif [[ "${ENABLE_REALITY}" == "1" ]]; then
    log_info "Только Reality: xray на :443, nginx не используется"
  fi
}
