#!/usr/bin/env bash
# shellcheck shell=bash
# systemd services and firewall hints.

install_cli_tool() {
  local target="/usr/local/bin/xray-cli"
  log_debug "[service.install_cli_tool] root=${PROJECT_ROOT} target=${target}"
  run_cmd chmod +x "${PROJECT_ROOT}/bin/xray-cli"
  ensure_state_dir
  echo "${PROJECT_ROOT}" > "${XRAY_CLI_STATE_DIR}/install-root"
  run_cmd chmod 644 "${XRAY_CLI_STATE_DIR}/install-root"
  run_cmd ln -sf "${PROJECT_ROOT}/bin/xray-cli" "${target}"
  log_info "CLI: ${target} -> ${PROJECT_ROOT}/bin/xray-cli"
}

start_services() {
  log_debug "[service.start_services] start"

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[dry-run] запуск сервисов пропущен"
    return 0
  fi

  if [[ "${ENABLE_VLESS_WS}" == "1" ]]; then
    run_cmd systemctl enable nginx
    if systemctl is-active --quiet xray 2>/dev/null; then
      if ss -tlnp 2>/dev/null | grep xray | grep -qE ':443[[:space:]]'; then
        log_warn "xray держит :443 — останавливаем перед nginx"
        run_cmd systemctl stop xray
      fi
    fi
    run_cmd systemctl restart nginx
    check_unit nginx
  fi

  run_cmd systemctl enable xray
  run_cmd systemctl restart xray
  check_unit xray

  install_cli_tool
  suggest_firewall
}

check_unit() {
  local unit="$1"
  if systemctl is-active --quiet "${unit}"; then
    log_info "systemd ${unit}: active"
  else
    log_error "systemd ${unit}: failed"
    journalctl -u "${unit}" -n 20 --no-pager >&2 || true
    die "Сервис ${unit} не запустился"
  fi
}

suggest_firewall() {
  if ! command -v ufw >/dev/null 2>&1; then
    return 0
  fi
  if ufw status 2>/dev/null | grep -q "Status: active"; then
    log_info "UFW активен — откройте порты при необходимости:"
    echo "  ufw allow 80/tcp" >&2
    echo "  ufw allow 443/tcp" >&2
  else
    log_debug "[service.suggest_firewall] ufw inactive"
  fi
}

print_summary() {
  echo ""
  echo "╔══════════════════════════════════════════════╗"
  echo "║       Xray CLI — установка завершена          ║"
  echo "╚══════════════════════════════════════════════╝"
  echo ""
  echo "  Версия:    ${XRAY_CLI_VERSION}"
  [[ -n "${DOMAIN}" ]] && echo "  Домен:     ${DOMAIN}"
  echo "  VLESS-WS:  $([[ "${ENABLE_VLESS_WS}" == "1" ]] && echo да || echo нет)"
  echo "  Reality:   $([[ "${ENABLE_REALITY}" == "1" ]] && echo да || echo нет)"
  echo "  Ссылки:    ${XRAY_CLI_LINKS_FILE}"
  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    echo "  Reality cfg: ${XRAY_CLI_REALITY_JSON_FILE}"
    echo "  Reality addr: ${REALITY_ADDRESS:-${REALITY_REFERENCE_ADDRESS:-auto}}"
    echo "  Reality SNI:  ${REALITY_SNI:-n/a}"
    echo "  Fingerprint:  ${REALITY_FINGERPRINT:-n/a}"
    echo "  shortId:      $(mask_secret "${REALITY_SHORT_ID:-}")"
    echo "  Key mode:     ${REALITY_PUBLIC_KEY_SOURCE:-generated}"
  fi
  echo "  Состояние: ${XRAY_CLI_STATE_FILE}"
  echo ""
  echo "  Команды: xray-cli status | links | test-config | uninstall"
  echo ""
}
