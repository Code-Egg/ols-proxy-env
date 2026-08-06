#!/usr/bin/env bash
set -Eeuo pipefail

: "${BACKEND_IP:?BACKEND_IP is required}"
: "${BACKEND_PORT:?BACKEND_PORT is required}"
: "${DOMAIN:?DOMAIN is required}"

if [[ ! "$BACKEND_PORT" =~ ^[0-9]+$ ]] || (( BACKEND_PORT < 1 || BACKEND_PORT > 65535 )); then
    echo "BACKEND_PORT must be an integer between 1 and 65535" >&2
    exit 1
fi

if [[ ! "$DOMAIN" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]; then
    echo "DOMAIN contains unsupported characters" >&2
    exit 1
fi

if [[ ! "$BACKEND_IP" =~ ^[A-Za-z0-9_.:-]+$ ]]; then
    echo "BACKEND_IP contains unsupported characters" >&2
    exit 1
fi

SERVER_ROOT=/usr/local/lsws
CONF_ROOT="$SERVER_ROOT/conf"
VHOST_ROOT=/var/www/vhosts/Example
VHOST_CONF="$CONF_ROOT/vhosts/Example/vhconf.conf"
BASE_CONFIG="$CONF_ROOT/httpd_config.conf.ols-proxy-base"

if [[ ! -f "$CONF_ROOT/httpd_config.conf" ]]; then
    echo "OpenLiteSpeed configuration is missing" >&2
    exit 1
fi

if [[ ! -x "$SERVER_ROOT/admin/misc/install_acme.sh" ]]; then
    echo "OpenLiteSpeed ACME installer is missing; use an OLS 1.9+ image" >&2
    exit 1
fi

if [[ ! -f "$SERVER_ROOT/acme/acme.sh" ]]; then
    if [[ -n "${ACME_EMAIL:-}" ]]; then
        "$SERVER_ROOT/admin/misc/install_acme.sh" -e "$ACME_EMAIL"
    else
        "$SERVER_ROOT/admin/misc/install_acme.sh"
    fi
fi

mkdir -p "$CONF_ROOT/vhosts/Example" "$VHOST_ROOT/html/.well-known/acme-challenge" \
    "$SERVER_ROOT/logs"

if [[ ! -f "$BASE_CONFIG" ]]; then
    cp "$CONF_ROOT/httpd_config.conf" "$BASE_CONFIG"
fi

TLS_KEY="$SERVER_ROOT/admin/conf/webadmin.key"
TLS_CERT="$SERVER_ROOT/admin/conf/webadmin.crt"

awk '/^listener[[:space:]]+HTTP[[:space:]]*\{/ { exit } { print }' \
    "$BASE_CONFIG" > "$CONF_ROOT/httpd_config.conf.tmp"

cat >> "$CONF_ROOT/httpd_config.conf.tmp" <<EOF

virtualhost Example {
    vhRoot                  $VHOST_ROOT/
    configFile              conf/vhosts/Example/vhconf.conf
    allowSymbolLink         1
    enableScript            1
    restrained              1
    setUIDMode              0
}

listener HTTP {
    address                 *:80
    secure                  0
    map                     Example $DOMAIN
}

listener HTTPS {
    address                 *:443
    secure                  1
    keyFile                 $TLS_KEY
    certFile                $TLS_CERT
    certChain               1
    map                     Example $DOMAIN
}
EOF

mv "$CONF_ROOT/httpd_config.conf.tmp" "$CONF_ROOT/httpd_config.conf"

cat > "$VHOST_CONF" <<EOF
docRoot                 $VHOST_ROOT/html/
indexFiles              index.html

errorlog $SERVER_ROOT/logs/Example.error.log {
    useServer             1
}

accesslog $SERVER_ROOT/logs/Example.access.log {
    useServer             0
    rollingSize           10M
    keepDays              7
    compressArchive       1
}

vhssl {
    acme {
        enabled             2
    }
}

extprocessor proxy_backend {
    type                    proxy
    address                 http://${BACKEND_IP}:${BACKEND_PORT}
    maxConns                100
    pcKeepAliveTimeout      60
    initTimeout             60
    retryTimeout            0
    respBuffer              0
}

context /.well-known/acme-challenge/ {
    type                    static
    location                $VHOST_ROOT/html/.well-known/acme-challenge/
    accessible              1
    allowBrowse             0
}

rewrite  {
    enable                  1
    autoLoadHtaccess        0
    logLevel                0
    RewriteRule             ^/\.well-known/acme-challenge/ - [L]
    RewriteRule             ^(.*)$ HTTP://proxy_backend/\$1 [P,L,E=PROXY-HOST:${DOMAIN}]
}
EOF

chown -R lsadm:lsadm "$CONF_ROOT" "$VHOST_ROOT" "$SERVER_ROOT/logs"
chmod -R u=rwX,go= "$SERVER_ROOT/admin/conf"

"$SERVER_ROOT/bin/lswsctrl start"

while "$SERVER_ROOT/bin/lswsctrl" status | grep -q 'litespeed is running with PID'; do
    sleep 60
done

echo "OpenLiteSpeed stopped" >&2
exit 1
