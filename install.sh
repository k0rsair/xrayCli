#!/usr/bin/env bash
# xray-cli — automated Xray VPN installer for Debian 13
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/lib/common.sh"

MODE=""
SHOW_HELP=0

usage() {
  cat <<'EOF'
xray-cli installer — развёртывание Xray VPN на Debian 13

Использование:
  sudo ./install.sh [опции]

Опции:
  --help              Показать справку
  --dry-run           Показать действия без изменений
  --non-interactive   Без интерактивных вопросов (нужны --mode и --domain)
  --yes               Ответ «да» на все вопросы
  --reconfigure       Пересобрать конфиги при повторной установке
  --mode MODE         vless-ws | vless-reality | combo
  --domain DOMAIN     Домен для VLESS-WS
  --email EMAIL       Email для Let's Encrypt
  --reality-dest HOST:PORT   Reality dest (non-interactive)
  --reality-sni SNI          Reality SNI
  --fingerprint FP           chrome | random

Примеры:
  sudo ./install.sh
  sudo ./install.sh --mode combo --domain vpn.example.com --yes
  sudo ./install.sh --mode vless-reality --yes --non-interactive
EOF
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --help|-h) SHOW_HELP=1; shift ;;
      --dry-run) DRY_RUN=1; shift ;;
      --non-interactive) NON_INTERACTIVE=1; shift ;;
      --yes|-y) ASSUME_YES=1; shift ;;
      --reconfigure) RECONFIGURE=1; shift ;;
      --mode) MODE="$2"; shift 2 ;;
      --domain) DOMAIN="$2"; shift 2 ;;
      --email) CERTBOT_EMAIL="$2"; shift 2 ;;
      --reality-dest) REALITY_DEST="$2"; shift 2 ;;
      --reality-sni) REALITY_SNI="$2"; shift 2 ;;
      --fingerprint) REALITY_FINGERPRINT="$2"; shift 2 ;;
      *) die "Неизвестный аргумент: $1 (используйте --help)" ;;
    esac
  done
}

main() {
  parse_args "$@"
  [[ "${SHOW_HELP}" == "1" ]] && { usage; exit 0; }

  echo ""
  echo "=== Xray CLI Installer v${XRAY_CLI_VERSION} (Debian 13) ==="
  echo ""

  require_root
  check_debian

  source_lib prompts.sh
  source_lib install-deps.sh
  source_lib install-xray.sh
  source_lib crypto.sh
  source_lib config-vless-ws.sh
  source_lib config-reality.sh
  source_lib config-merge.sh
  source_lib ssl.sh
  source_lib nginx-vless.sh
  source_lib link-builder.sh
  source_lib service.sh
  source_lib preflight.sh

  run_prompts "${MODE}"

  log_info "Шаг 1/7: установка зависимостей"
  install_system_deps

  log_info "Шаг 2/7: установка xray-core"
  install_xray_core

  log_info "Шаг 3/7: генерация ключей"
  generate_all_secrets

  log_info "Шаг 4/7: конфигурация xray"
  ensure_xray_config_compatible
  if [[ "${RECONFIGURE}" == "1" ]]; then
    stop_xray_for_nginx
  fi
  write_xray_config

  log_info "Шаг 5/7: SSL и nginx"
  ensure_ports_for_nginx
  setup_nginx_bootstrap_http
  setup_ssl
  setup_nginx

  log_info "Шаг 6/7: ссылки для клиентов"
  write_client_links

  log_info "Шаг 7/7: запуск сервисов"
  start_services
  print_summary
}

main "$@"
