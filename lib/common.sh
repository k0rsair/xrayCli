#!/usr/bin/env bash
# shellcheck shell=bash
# Shared utilities for xray-cli installer.

set -euo pipefail

readonly XRAY_CLI_VERSION="0.1.0"
readonly XRAY_CLI_STATE_DIR="${XRAY_CLI_STATE_DIR:-/etc/xray-cli}"
readonly XRAY_CLI_STATE_FILE="${XRAY_CLI_STATE_DIR}/state.env"
readonly XRAY_CLI_LINKS_FILE="${XRAY_CLI_STATE_DIR}/client-links.txt"
readonly XRAY_CONFIG_PATH="${XRAY_CONFIG_PATH:-/usr/local/etc/xray/config.json}"
readonly XRAY_BIN="${XRAY_BIN:-/usr/local/bin/xray}"
WS_PORT="${WS_PORT:-10000}"
WS_PATH="${WS_PATH:-/xray-ws}"
REALITY_INTERNAL_PORT="${REALITY_INTERNAL_PORT:-10443}"
NGINX_SSL_INTERNAL_PORT="${NGINX_SSL_INTERNAL_PORT:-8443}"
WEB_ROOT="${WEB_ROOT:-/var/www/xray-cli}"

if [[ "${BATS_TEST_MODE:-0}" != "1" ]]; then
  readonly WS_PORT WS_PATH REALITY_INTERNAL_PORT NGINX_SSL_INTERNAL_PORT WEB_ROOT
fi

LOG_LEVEL="${LOG_LEVEL:-INFO}"
DRY_RUN="${DRY_RUN:-0}"
NON_INTERACTIVE="${NON_INTERACTIVE:-0}"
ASSUME_YES="${ASSUME_YES:-0}"
RECONFIGURE="${RECONFIGURE:-0}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATES_DIR="${PROJECT_ROOT}/templates"

_log_level_num() {
  local level
  level="$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')"
  case "${level}" in
    DEBUG) echo 10 ;;
    INFO)  echo 20 ;;
    WARN)  echo 30 ;;
    ERROR) echo 40 ;;
    *)     echo 20 ;;
  esac
}

_should_log() {
  local level="$1"
  [[ $(_log_level_num "${level}") -ge $(_log_level_num "${LOG_LEVEL}") ]]
}

log_debug() {
  _should_log DEBUG || return 0
  echo "[xray-cli] DEBUG $*" >&2
}

log_info() {
  _should_log INFO || return 0
  echo "[xray-cli] INFO  $*" >&2
}

log_warn() {
  _should_log WARN || return 0
  echo "[xray-cli] WARN  $*" >&2
}

log_error() {
  _should_log ERROR || return 0
  echo "[xray-cli] ERROR $*" >&2
}

die() {
  log_error "$*"
  exit 1
}

mask_secret() {
  local value="${1:-}"
  if [[ -z "${value}" ]]; then
    echo "(empty)"
  else
    echo "***${value: -4}"
  fi
}

require_root() {
  log_debug "[common.require_root] euid=${EUID}"
  if [[ "${EUID}" -ne 0 ]]; then
    die "Запустите скрипт от root: sudo $0"
  fi
}

require_cmd() {
  local cmd="$1"
  log_debug "[common.require_cmd] cmd=${cmd}"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    die "Команда не найдена: ${cmd}"
  fi
}

run_cmd() {
  log_debug "[common.run_cmd] $*"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[dry-run] $*"
    return 0
  fi
  "$@"
}

run_cmd_capture() {
  log_debug "[common.run_cmd_capture] $*"
  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[dry-run] $*"
    echo ""
    return 0
  fi
  "$@"
}

check_debian() {
  log_debug "[common.check_debian] start"
  if [[ ! -f /etc/os-release ]]; then
    die "Не удалось определить ОС (/etc/os-release отсутствует)"
  fi

  # shellcheck disable=SC1091
  source /etc/os-release

  if [[ "${ID}" != "debian" ]]; then
    die "Поддерживается только Debian (обнаружено: ${ID})"
  fi

  local codename="${VERSION_CODENAME:-}"
  local major="${VERSION_ID%%.*}"

  if [[ "${codename}" != "trixie" && "${codename}" != "bookworm" && "${major}" -lt 12 ]]; then
    log_warn "Ожидается Debian 13 (trixie) или bookworm; обнаружено: ${PRETTY_NAME:-debian}"
  fi

  log_info "ОС: ${PRETTY_NAME:-debian}"
}

ensure_state_dir() {
  log_debug "[common.ensure_state_dir] dir=${XRAY_CLI_STATE_DIR}"
  run_cmd mkdir -p "${XRAY_CLI_STATE_DIR}"
  run_cmd chmod 700 "${XRAY_CLI_STATE_DIR}"
}

load_state() {
  if [[ -f "${XRAY_CLI_STATE_FILE}" ]]; then
    log_debug "[common.load_state] loading ${XRAY_CLI_STATE_FILE}"
    # shellcheck disable=SC1090
    source "${XRAY_CLI_STATE_FILE}"
  fi
}

save_state_var() {
  local key="$1"
  local value="$2"
  ensure_state_dir
  if [[ -f "${XRAY_CLI_STATE_FILE}" ]]; then
    if grep -q "^${key}=" "${XRAY_CLI_STATE_FILE}" 2>/dev/null; then
      run_cmd sed -i "s|^${key}=.*|${key}=${value}|" "${XRAY_CLI_STATE_FILE}"
    else
      echo "${key}=${value}" >> "${XRAY_CLI_STATE_FILE}"
    fi
  else
    echo "${key}=${value}" > "${XRAY_CLI_STATE_FILE}"
  fi
  run_cmd chmod 600 "${XRAY_CLI_STATE_FILE}"
}

is_valid_fqdn() {
  local domain="$1"
  [[ "${domain}" =~ ^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\.)+[a-zA-Z]{2,}$ ]]
}

get_server_public_ip() {
  local ip=""
  ip="$(curl -4fsS --max-time 5 https://ifconfig.me 2>/dev/null || true)"
  if [[ -z "${ip}" ]]; then
    ip="$(curl -4fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  fi
  if [[ -z "${ip}" ]]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  fi
  echo "${ip}"
}

xray_installed() {
  [[ -x "${XRAY_BIN}" ]]
}

source_lib() {
  local name="$1"
  # shellcheck disable=SC1090
  source "${SCRIPT_DIR}/${name}"
}
