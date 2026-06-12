#!/usr/bin/env bash
# shellcheck shell=bash
# Interactive prompts for mode selection.

ENABLE_VLESS_WS="${ENABLE_VLESS_WS:-0}"
ENABLE_REALITY="${ENABLE_REALITY:-0}"
DOMAIN="${DOMAIN:-}"
REALITY_DEST="${REALITY_DEST:-www.microsoft.com}"
REALITY_SNI="${REALITY_SNI:-www.microsoft.com}"
REALITY_FINGERPRINT="${REALITY_FINGERPRINT:-chrome}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"

REALITY_PRESETS=(
  "www.microsoft.com"
  "learn.microsoft.com"
  "www.cloudflare.com"
  "www.google.com"
)

prompt_yes_no() {
  local question="$1"
  local default="${2:-y}"
  if [[ "${NON_INTERACTIVE}" == "1" || "${ASSUME_YES}" == "1" ]]; then
  [[ "${default}" == "y" ]] && return 0 || return 1
  fi
  local hint="[Y/n]"
  [[ "${default}" == "n" ]] && hint="[y/N]"
  read -r -p "${question} ${hint}: " answer
  answer="${answer:-${default}}"
  [[ "${answer}" =~ ^[Yy] ]]
}

prompt_value() {
  local question="$1"
  local default="${2:-}"
  if [[ "${NON_INTERACTIVE}" == "1" && -n "${default}" ]]; then
    echo "${default}"
    return 0
  fi
  if [[ -n "${default}" ]]; then
    read -r -p "${question} [${default}]: " answer
    echo "${answer:-${default}}"
  else
    read -r -p "${question}: " answer
    echo "${answer}"
  fi
}

validate_domain_dns() {
  local domain="$1"
  log_debug "[prompts.validate_domain_dns] domain=${domain}"
  if ! command -v dig >/dev/null 2>&1 && ! command -v host >/dev/null 2>&1; then
    log_warn "dig/host не найдены — пропускаем проверку DNS"
    return 0
  fi

  local resolved=""
  if command -v dig >/dev/null 2>&1; then
    resolved="$(dig +short A "${domain}" 2>/dev/null | head -n1)"
    if [[ -z "${resolved}" ]]; then
      resolved="$(dig +short AAAA "${domain}" 2>/dev/null | head -n1)"
    fi
  else
    resolved="$(host -t A "${domain}" 2>/dev/null | awk '/has address/ {print $4; exit}')"
  fi

  if [[ -z "${resolved}" ]]; then
    log_warn "DNS A/AAAA для ${domain} не найден — убедитесь, что домен указывает на этот сервер"
    return 0
  fi

  local server_ip
  server_ip="$(get_server_public_ip)"
  if [[ -n "${server_ip}" && "${resolved}" != "${server_ip}" ]]; then
    log_warn "DNS ${domain} -> ${resolved}, IP сервера: ${server_ip} (не совпадают)"
    if ! prompt_yes_no "Продолжить установку?" "y"; then
      die "Установка отменена пользователем"
    fi
  else
    log_info "DNS ${domain} -> ${resolved}"
  fi
}

prompt_reality_dest() {
  log_debug "[prompts.prompt_reality_dest] start"
  if [[ "${NON_INTERACTIVE}" == "1" ]]; then
    REALITY_DEST="${REALITY_DEST:-www.microsoft.com}"
    REALITY_SNI="${REALITY_SNI:-${REALITY_DEST%%:*}}"
    return 0
  fi

  echo ""
  echo "Выберите Reality dest/SNI:"
  local i=1
  for preset in "${REALITY_PRESETS[@]}"; do
    echo "  [${i}] ${preset}"
    ((i++)) || true
  done
  echo "  [${i}] Ввести свой"

  local choice
  choice="$(prompt_value "Номер" "1")"

  if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#REALITY_PRESETS[@]} )); then
    REALITY_DEST="${REALITY_PRESETS[$((choice - 1))]}:443"
    REALITY_SNI="${REALITY_PRESETS[$((choice - 1))]}"
  else
    local custom
    custom="$(prompt_value "Введите dest (host:port)" "www.microsoft.com:443")"
    REALITY_DEST="${custom}"
    REALITY_SNI="${custom%%:*}"
  fi

  echo "Fingerprint:"
  echo "  [1] chrome (рекомендуется)"
  echo "  [2] random"
  local fp_choice
  fp_choice="$(prompt_value "Номер" "1")"
  if [[ "${fp_choice}" == "2" ]]; then
    REALITY_FINGERPRINT="random"
  else
    REALITY_FINGERPRINT="chrome"
  fi

  log_debug "[prompts.prompt_reality_dest] dest=${REALITY_DEST} sni=${REALITY_SNI} fp=${REALITY_FINGERPRINT}"
}

apply_mode_flags() {
  local mode="${1:-}"
  log_debug "[prompts.apply_mode_flags] mode=${mode}"
  case "${mode}" in
    vless-ws)
      ENABLE_VLESS_WS=1
      ENABLE_REALITY=0
      ;;
    vless-reality)
      ENABLE_VLESS_WS=0
      ENABLE_REALITY=1
      ;;
    combo)
      ENABLE_VLESS_WS=1
      ENABLE_REALITY=1
      ;;
    "")
      ;;
    *)
      die "Неизвестный режим: ${mode} (допустимо: vless-ws, vless-reality, combo)"
      ;;
  esac
}

run_prompts() {
  local mode="${1:-}"
  log_debug "[prompts.run_prompts] mode=${mode} non_interactive=${NON_INTERACTIVE}"

  apply_mode_flags "${mode}"

  if [[ "${NON_INTERACTIVE}" != "1" && -z "${mode}" ]]; then
    echo ""
    echo "=== Выбор режимов ==="
    if prompt_yes_no "Включить VLESS + WebSocket + TLS (требуется домен)?" "y"; then
      ENABLE_VLESS_WS=1
    fi
    if prompt_yes_no "Включить VLESS + Reality?" "n"; then
      ENABLE_REALITY=1
    fi
  fi

  if [[ "${ENABLE_VLESS_WS}" != "1" && "${ENABLE_REALITY}" != "1" ]]; then
    die "Выберите хотя бы один режим (VLESS-WS и/или Reality)"
  fi

  if [[ "${ENABLE_VLESS_WS}" == "1" ]]; then
    if [[ -z "${DOMAIN}" ]]; then
      DOMAIN="$(prompt_value "Введите домен для VLESS-WS" "")"
    fi
    if ! is_valid_fqdn "${DOMAIN}"; then
      die "Некорректный домен: ${DOMAIN}"
    fi
    validate_domain_dns "${DOMAIN}"

    if [[ -z "${CERTBOT_EMAIL}" ]]; then
      CERTBOT_EMAIL="$(prompt_value "Email для Let's Encrypt" "admin@${DOMAIN}")"
    fi
  fi

  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    prompt_reality_dest
  fi

  log_info "Режимы: VLESS-WS=${ENABLE_VLESS_WS} Reality=${ENABLE_REALITY}"
  [[ -n "${DOMAIN}" ]] && log_info "Домен: ${DOMAIN}"
  [[ "${ENABLE_REALITY}" == "1" ]] && log_info "Reality dest: ${REALITY_DEST}"
}
