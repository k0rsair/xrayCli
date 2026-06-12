#!/usr/bin/env bash
# shellcheck shell=bash
# Install system dependencies.

install_system_deps() {
  log_debug "[install-deps.install_system_deps] start dry_run=${DRY_RUN}"

  local packages=(curl jq openssl ufw)
  if [[ "${ENABLE_VLESS_WS}" == "1" ]]; then
    packages+=(nginx libnginx-mod-stream certbot python3-certbot-nginx)
  fi

  run_cmd apt-get update -qq
  run_cmd apt-get install -y "${packages[@]}"

  if command -v nginx >/dev/null 2>&1; then
    local nginx_ver
    nginx_ver="$(nginx -v 2>&1 || true)"
    log_info "nginx: ${nginx_ver}"
  fi

  if [[ "${ENABLE_VLESS_WS}" == "1" ]]; then
    if nginx -V 2>&1 | grep -q stream; then
      log_info "nginx stream module: OK"
    else
      log_warn "nginx stream module не обнаружен в nginx -V"
    fi
  fi

  require_cmd jq
  require_cmd curl
  log_info "Системные зависимости установлены"
}
