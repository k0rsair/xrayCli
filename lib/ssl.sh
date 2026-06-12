#!/usr/bin/env bash
# shellcheck shell=bash
# SSL certificate management via certbot.

SSL_CERT_PATH=""
SSL_KEY_PATH=""

setup_ssl() {
  log_debug "[ssl.setup_ssl] domain=${DOMAIN}"
  if [[ "${ENABLE_VLESS_WS}" != "1" ]]; then
    log_debug "[ssl.setup_ssl] skip — VLESS-WS не включён"
    return 0
  fi

  local cert_dir="/etc/letsencrypt/live/${DOMAIN}"
  SSL_CERT_PATH="${cert_dir}/fullchain.pem"
  SSL_KEY_PATH="${cert_dir}/privkey.pem"

  if [[ -f "${SSL_CERT_PATH}" && -f "${SSL_KEY_PATH}" && "${RECONFIGURE}" != "1" ]]; then
    log_info "Сертификат уже существует: ${SSL_CERT_PATH}"
    install_renew_hook
    return 0
  fi

  if [[ "${DRY_RUN}" == "1" ]]; then
    log_info "[dry-run] certbot пропущен"
    return 0
  fi

  run_cmd mkdir -p "${WEB_ROOT}/.well-known/acme-challenge"

  log_info "Получение SSL-сертификата для ${DOMAIN} (webroot)..."
  certbot certonly \
    --webroot \
    -w "${WEB_ROOT}" \
    -d "${DOMAIN}" \
    --non-interactive \
    --agree-tos \
    -m "${CERTBOT_EMAIL}" \
    --no-eff-email

  if [[ ! -f "${SSL_CERT_PATH}" ]]; then
    die "Сертификат не найден после certbot: ${SSL_CERT_PATH}"
  fi

  local expiry
  expiry="$(openssl x509 -enddate -noout -in "${SSL_CERT_PATH}" 2>/dev/null | cut -d= -f2 || true)"
  log_info "Сертификат действителен до: ${expiry}"
  log_debug "[ssl.setup_ssl] cert=${SSL_CERT_PATH} key=${SSL_KEY_PATH}"

  install_renew_hook
  save_state_var "SSL_CERT_PATH" "${SSL_CERT_PATH}"
  save_state_var "SSL_KEY_PATH" "${SSL_KEY_PATH}"
}

install_renew_hook() {
  local hook_dir="/etc/letsencrypt/renewal-hooks/deploy"
  local hook="${hook_dir}/xray-cli-copy-certs.sh"
  log_debug "[ssl.install_renew_hook] hook=${hook}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    return 0
  fi

  run_cmd mkdir -p "${hook_dir}"
  cat > "${hook}" <<'HOOKEOF'
#!/usr/bin/env bash
# Copy renewed certs for xray-cli managed nginx site.
STATE="/etc/xray-cli/state.env"
if [[ -f "${STATE}" ]]; then
  # shellcheck disable=SC1090
  source "${STATE}"
  if [[ -n "${DOMAIN}" && -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    systemctl reload nginx 2>/dev/null || true
  fi
fi
HOOKEOF
  run_cmd chmod +x "${hook}"
}
