#!/usr/bin/env bash
set -Eeuo pipefail

: "${BACKEND_IP:?BACKEND_IP is required}"
: "${BACKEND_PORT:?BACKEND_PORT is required}"
: "${DOMAIN:?DOMAIN is required}"
: "${ACME_EMAIL:?ACME_EMAIL is required}"

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
ACME_HOME=/root/.acme.sh
ACME_ROOT="$ACME_HOME/ols-proxy/$DOMAIN"
ACME_STATE_ROOT=/var/lib/ols-proxy
ACME_ISSUED_MARKER="$ACME_STATE_ROOT/$DOMAIN.issued"
ACME_ATTEMPTED_MARKER="$ACME_STATE_ROOT/$DOMAIN.attempted"
ACME_WEBROOT="$VHOST_ROOT/html"

if [[ ! -f "$CONF_ROOT/httpd_config.conf" ]]; then
    cp -R "$SERVER_ROOT/.conf/." "$CONF_ROOT/"
fi

mkdir -p "$CONF_ROOT/vhosts/Example" "$VHOST_ROOT/html/.well-known/acme-challenge" \
    "$SERVER_ROOT/logs" "$ACME_STATE_ROOT"

if [[ ! -x "$ACME_HOME/acme.sh" ]]; then
    echo "ACME client is missing from the OpenLiteSpeed image; HTTPS will use the fallback certificate" >&2
fi

cp "$SERVER_ROOT/.conf/httpd_config.conf" "$CONF_ROOT/httpd_config.conf.ols-proxy-base"

TLS_KEY="$SERVER_ROOT/admin/conf/webadmin.key"
TLS_CERT="$SERVER_ROOT/admin/conf/webadmin.crt"
if [[ -s "$ACME_ROOT/key.pem" && -s "$ACME_ROOT/fullchain.pem" ]]; then
    TLS_KEY="$ACME_ROOT/key.pem"
    TLS_CERT="$ACME_ROOT/fullchain.pem"
fi

awk '/^listener[[:space:]]+HTTP[[:space:]]*\{/ { exit } { print }' \
    "$CONF_ROOT/httpd_config.conf.ols-proxy-base" > "$CONF_ROOT/httpd_config.conf.tmp"

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
docRoot                 $ACME_WEBROOT/
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
    location                $ACME_WEBROOT/.well-known/acme-challenge/
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

start_server() {
    "$SERVER_ROOT/bin/lswsctrl" start
}

issue_certificate() {
    if [[ ! -x "$ACME_HOME/acme.sh" || ( -s "$ACME_ROOT/key.pem" && -s "$ACME_ROOT/fullchain.pem" ) || -f "$ACME_ISSUED_MARKER" || -f "$ACME_ATTEMPTED_MARKER" ]]; then
        return 0
    fi

    touch "$ACME_ATTEMPTED_MARKER"
    echo "Requesting a Let's Encrypt certificate for ${DOMAIN}"

    if "$ACME_HOME/acme.sh" --home "$ACME_HOME" --set-default-ca --server letsencrypt \
        && "$ACME_HOME/acme.sh" --home "$ACME_HOME" --issue --server letsencrypt \
        --webroot "$ACME_WEBROOT" --domain "$DOMAIN" --keylength ec-256 \
        --accountemail "$ACME_EMAIL" \
        && "$ACME_HOME/acme.sh" --home "$ACME_HOME" --install-cert --ecc \
        --domain "$DOMAIN" --key-file "$ACME_ROOT/key.pem" \
        --fullchain-file "$ACME_ROOT/fullchain.pem" --reloadcmd "true"; then
        touch "$ACME_ISSUED_MARKER"
        rm -f "$ACME_ATTEMPTED_MARKER"
        return 0
    fi

    echo "ACME certificate issuance failed; keeping the fallback HTTPS certificate" >&2
    return 0
}

start_server
issue_certificate

if [[ -s "$ACME_ROOT/key.pem" && -s "$ACME_ROOT/fullchain.pem" ]]; then
    sed -i "s|^[[:space:]]*keyFile.*|    keyFile                 $ACME_ROOT/key.pem|" "$CONF_ROOT/httpd_config.conf"
    sed -i "s|^[[:space:]]*certFile.*|    certFile                $ACME_ROOT/fullchain.pem|" "$CONF_ROOT/httpd_config.conf"
    chown lsadm:lsadm "$CONF_ROOT/httpd_config.conf"
    "$SERVER_ROOT/bin/lswsctrl" restart
fi

while "$SERVER_ROOT/bin/lswsctrl" status | grep -q 'litespeed is running with PID'; do
    sleep 60
done

echo "OpenLiteSpeed stopped" >&2
exit 1
