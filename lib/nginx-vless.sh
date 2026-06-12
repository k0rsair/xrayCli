#!/usr/bin/env bash
# shellcheck shell=bash
# Nginx site and stream configuration.

setup_nginx() {
  log_debug "[nginx-vless.setup_nginx] ws=${ENABLE_VLESS_WS} reality=${ENABLE_REALITY}"

  if [[ "${ENABLE_VLESS_WS}" != "1" ]]; then
    if [[ "${ENABLE_REALITY}" == "1" ]]; then
      log_info "Только Reality — nginx не настраивается"
    fi
    return 0
  fi

  setup_decoy_site
  render_nginx_site
  if [[ "${ENABLE_REALITY}" == "1" ]]; then
    render_nginx_stream
  fi

  if [[ "${DRY_RUN}" != "1" ]]; then
    run_cmd nginx -t
    run_cmd systemctl enable nginx
    run_cmd systemctl reload nginx || run_cmd systemctl restart nginx
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

render_nginx_stream() {
  local stream_conf="/etc/nginx/conf.d/xray-cli-stream.conf"
  log_debug "[nginx-vless.render_nginx_stream] file=${stream_conf}"

  cat > "${stream_conf}" <<EOF
# xray-cli stream routing for combo mode
map \$ssl_preread_server_name \$xray_cli_backend {
    ${DOMAIN}     127.0.0.1:${NGINX_SSL_INTERNAL_PORT};
    ${REALITY_SNI} 127.0.0.1:${REALITY_INTERNAL_PORT};
    default       127.0.0.1:${REALITY_INTERNAL_PORT};
}

server {
    listen 443 reuseport;
    listen [::]:443 reuseport;
    proxy_pass \$xray_cli_backend;
    ssl_preread on;
}
EOF

  if [[ -d /etc/nginx/streams-enabled ]]; then
    run_cmd ln -sf "${stream_conf}" /etc/nginx/streams-enabled/xray-cli-stream.conf
  elif ! grep -q 'xray-cli-stream.conf' /etc/nginx/nginx.conf 2>/dev/null; then
    if grep -q '^stream {' /etc/nginx/nginx.conf 2>/dev/null; then
      if ! grep -q 'xray-cli-stream' /etc/nginx/nginx.conf; then
        run_cmd sed -i '/^stream {/a \    include /etc/nginx/conf.d/xray-cli-stream.conf;' /etc/nginx/nginx.conf
      fi
    else
      cat >> /etc/nginx/nginx.conf <<'EOF'

stream {
    include /etc/nginx/conf.d/xray-cli-stream.conf;
}
EOF
    fi
    log_debug "[nginx-vless] registered stream config in nginx.conf"
  fi

  log_info "nginx stream: ${stream_conf}"
}
