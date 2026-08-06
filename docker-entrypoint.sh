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

if [[ ! -f /usr/local/lsws/conf/httpd_config.conf ]]; then
    cp -R /usr/local/lsws/.conf/. /usr/local/lsws/conf/
fi

awk '
    /^[[:space:]]*vhssl[[:space:]]*\{/ { skip = 1; next }
    skip && /^[[:space:]]*\}/ { skip = 0; next }
    !skip { print }
' /usr/local/lsws/conf/templates/docker.conf \
    > /usr/local/lsws/conf/templates/proxy.conf

cat > /usr/local/lsws/conf/httpd_config.conf <<EOF
listener HTTP {
    address                 *:80
    secure                  0
}

listener HTTPS {
    address                 *:443
    secure                  1
    keyFile                 /usr/local/lsws/admin/conf/webadmin.key
    certFile                /usr/local/lsws/admin/conf/webadmin.crt
}

vhTemplate docker {
    templateFile            conf/templates/proxy.conf
    listeners               HTTP, HTTPS
    member ${DOMAIN} {
        vhDomain             ${DOMAIN}
    }
}
EOF

mkdir -p "/usr/local/lsws/conf/vhosts/${DOMAIN}" /usr/local/lsws/logs

cat > "/usr/local/lsws/conf/vhosts/${DOMAIN}/vhconf.conf" <<EOF
extprocessor proxy_backend {
    type                    proxy
    address                 http://${BACKEND_IP}:${BACKEND_PORT}
    maxConns                100
    pcKeepAliveTimeout      60
    initTimeout             60
    retryTimeout            0
    respBuffer              0
}

rewrite  {
    enable                  1
    autoLoadHtaccess        0
    logLevel                0
    RewriteRule             ^(.*)$ HTTP://proxy_backend/\$1 [P,L,E=PROXY-HOST:${DOMAIN}]
}
EOF

chown -R lsadm:lsadm /usr/local/lsws/conf /usr/local/lsws/logs
chmod -R u=rwX,go= /usr/local/lsws/admin/conf

/usr/local/lsws/bin/lswsctrl start

while /usr/local/lsws/bin/lswsctrl status | grep -q 'litespeed is running with PID'; do
    sleep 60
done

echo "OpenLiteSpeed stopped" >&2
exit 1
