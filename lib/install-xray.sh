#!/usr/bin/env bash
# shellcheck shell=bash
# Install xray-core via official script.

XRAY_INSTALL_URL="https://github.com/XTLS/Xray-install/raw/main/install-release.sh"

install_xray_core() {
  log_debug "[install-xray.install_xray_core] reconfigure=${RECONFIGURE}"

  if xray_installed && [[ "${RECONFIGURE}" != "1" ]]; then
    log_warn "xray уже установлен (${XRAY_BIN}). Используйте --reconfigure для перенастройки."
    local ver
    ver="$("${XRAY_BIN}" version 2>/dev/null | head -n1 || true)"
    log_info "${ver}"
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[dry-run] установка xray-core пропущена"
    return 0
  fi

  log_info "Установка xray-core..."
  local tmp
  tmp="$(mktemp)"
  curl -fsSL "${XRAY_INSTALL_URL}" -o "${tmp}"
  chmod +x "${tmp}"
  log_debug "[install-xray] running official install script (install)"
  # @ нужен только для bash -c "$(curl ...)" @ install; для файла — просто install
  if ! bash "${tmp}" install; then
    log_debug "[install-xray] retry via bash -c pipe"
    bash -c "$(cat "${tmp}")" @ install
  fi
  rm -f "${tmp}"

  require_cmd xray
  local ver
  ver="$("${XRAY_BIN}" version 2>/dev/null | head -n1 || true)"
  log_info "xray установлен: ${ver}"
}
