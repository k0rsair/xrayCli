#!/usr/bin/env bash
# shellcheck shell=bash
# Nginx site and stream configuration.

reload_or_start_nginx() {
  log_debug "[nginx-vless.reload_or_start_nginx] start"
  if systemctl is-active --quiet nginx 2>/dev/null; then
    run_cmd systemctl reload nginx || run_cmd systemctl restart nginx
  else
    log_warn "nginx не запущен — выполняем start"
    run_cmd systemctl start nginx || run_cmd systemctl restart nginx
  fi
}

disable_default_nginx_site() {
  log_debug "[nginx-vless.disable_default_nginx_site] start"
  if [[ -L /etc/nginx/sites-enabled/default ]] || [[ -f /etc/nginx/sites-enabled/default ]]; then
    run_cmd rm -f /etc/nginx/sites-enabled/default
    log_info "Отключён sites-enabled/default (конфликт server_name на :80)"
  fi
}

setup_nginx() {
  log_debug "[nginx-vless.setup_nginx] ws=${ENABLE_VLESS_WS} reality=${ENABLE_REALITY}"

  if [[ "${ENABLE_VLESS_WS}" != "1" ]]; then
    if [[ "${ENABLE_REALITY}" == "1" ]]; then
      log_info "Только Reality — nginx не настраивается"
    fi
    return 0
  fi

  disable_default_nginx_site
  setup_decoy_site
  render_nginx_site
  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    render_nginx_stream
  fi

  if [[ "${DRY_RUN}" != "1" ]]; then
    run_cmd nginx -t
    run_cmd systemctl enable nginx
    reload_or_start_nginx
    log_info "nginx настроен"
  fi
}

setup_decoy_site() {
  log_debug "[nginx-vless.setup_decoy_site] root=${WEB_ROOT}"
  run_cmd mkdir -p "${WEB_ROOT}"
  if [[ ! -f "${WEB_ROOT}/index.html" ]]; then
    cat > "${WEB_ROOT}/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="utf-8"><title>Welcome</title></head>
<body><h1>Welcome</h1><p>Site is running.</p></body>
</html>
EOF
  fi
}

render_nginx_site() {
  local site_conf="/etc/nginx/sites-available/xray-cli-${DOMAIN}.conf"
  local enabled="/etc/nginx/sites-enabled/xray-cli-${DOMAIN}.conf"
  log_debug "[nginx-vless.render_nginx_site] file=${site_conf}"

  local listen_directive="listen 443 ssl http2;"
  local listen_v6="listen [::]:443 ssl http2;"
  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    listen_directive="listen 127.0.0.1:${NGINX_SSL_INTERNAL_PORT} ssl http2;"
    listen_v6="# ipv6 disabled for internal ssl"
  fi

  cat > "${site_conf}" <<EOF
# xray-cli managed — ${DOMAIN}
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    ${listen_directive}
    ${listen_v6}
    server_name ${DOMAIN};

    ssl_certificate ${SSL_CERT_PATH:-/etc/letsencrypt/live/${DOMAIN}/fullchain.pem};
    ssl_certificate_key ${SSL_KEY_PATH:-/etc/letsencrypt/live/${DOMAIN}/privkey.pem};
    ssl_protocols TLSv1.2 TLSv1.3;

    root ${WEB_ROOT};
    index index.html;

    location / {
        try_files \$uri \$uri/ =404;
    }

    location ${WS_PATH} {
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${WS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
    }
}
EOF

  run_cmd ln -sf "${site_conf}" "${enabled}"
  log_info "nginx site: ${site_conf}"
}

cleanup_legacy_nginx_stream_refs() {
  local nginx_conf="/etc/nginx/nginx.conf"
  log_debug "[nginx-vless.cleanup_legacy_nginx_stream_refs] start"

  if [[ ! -f "${nginx_conf}" ]]; then
    return 0
  fi

  if grep -q 'conf\.d/xray-cli-stream\.conf' "${nginx_conf}" 2>/dev/null; then
    run_cmd sed -i '\|conf\.d/xray-cli-stream\.conf|d' "${nginx_conf}"
    log_info "Удалена устаревшая ссылка conf.d/xray-cli-stream.conf из nginx.conf"
  fi
}

ensure_nginx_stream_block() {
  log_debug "[nginx-vless.ensure_nginx_stream_block] start"
  local nginx_conf="/etc/nginx/nginx.conf"

  cleanup_legacy_nginx_stream_refs

  if grep -q 'streams-enabled' "${nginx_conf}" 2>/dev/null; then
    log_debug "[nginx-vless.ensure_nginx_stream_block] streams-enabled include present"
    return 0
  fi

  if grep -q '^stream {' "${nginx_conf}" 2>/dev/null; then
    run_cmd sed -i '/^stream {/a \    include /etc/nginx/streams-enabled/*.conf;' "${nginx_conf}"
    log_info "Добавлен include streams-enabled в существующий блок stream"
    return 0
  fi

  cat >> "${nginx_conf}" <<'EOF'

# xray-cli: TCP/stream (must be outside http {})
stream {
    include /etc/nginx/streams-enabled/*.conf;
}
EOF
  log_info "Добавлен блок stream в nginx.conf"
}

render_nginx_stream() {
  local stream_conf="/etc/nginx/streams-available/xray-cli-stream.conf"
  local stream_enabled="/etc/nginx/streams-enabled/xray-cli-stream.conf"
  log_debug "[nginx-vless.render_nginx_stream] file=${stream_conf}"

  # Legacy path was under conf.d (included from http {}) — remove to avoid parse errors
  run_cmd rm -f /etc/nginx/conf.d/xray-cli-stream.conf

  run_cmd mkdir -p /etc/nginx/streams-available /etc/nginx/streams-enabled

  cat > "${stream_conf}" <<EOF
# xray-cli stream routing for combo mode
map_hash_bucket_size 128;
map_hash_max_size 4096;

map \$ssl_preread_server_name \$xray_cli_backend {
    ${DOMAIN}      127.0.0.1:${NGINX_SSL_INTERNAL_PORT};
    ${REALITY_SNI} 127.0.0.1:${REALITY_INTERNAL_PORT};
    default        127.0.0.1:${REALITY_INTERNAL_PORT};
}

server {
    listen 443 reuseport;
    listen [::]:443 reuseport;
    proxy_pass \$xray_cli_backend;
    ssl_preread on;
}
EOF

  run_cmd ln -sf "${stream_conf}" "${stream_enabled}"
  ensure_nginx_stream_block

  log_info "nginx stream: ${stream_conf}"
}
