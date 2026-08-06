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

cp /usr/local/lsws/.conf/httpd_config.conf /usr/local/lsws/conf/httpd_config.conf

awk '
    /^[[:space:]]*vhssl[[:space:]]*\{/ { skip = 1; next }
    skip && /^[[:space:]]*\}/ { skip = 0; next }
    !skip { print }
' /usr/local/lsws/conf/templates/docker.conf \
    > /usr/local/lsws/conf/templates/proxy.conf

sed -i 's/vhDomain[[:space:]]\+localhost,[[:space:]]\*/vhDomain localhost/' \
    /usr/local/lsws/conf/httpd_config.conf

awk -v domain="$DOMAIN" '
    /^vhTemplate[[:space:]]+docker[[:space:]]*\{/ {
        in_template = 1
        template_depth = 1
        print
        next
    }
    in_template {
        line = $0
        opens = gsub(/\{/, "", line)
        closes = gsub(/\}/, "", line)
        if (closes > 0 && template_depth == closes) {
            print "    member " domain " {"
            print "        vhDomain             " domain
            print "    }"
            print
            in_template = 0
            print $0
            next
        }
        template_depth += opens - closes
    }
    { print }
' /usr/local/lsws/conf/httpd_config.conf \
    > /usr/local/lsws/conf/httpd_config.conf.tmp
mv /usr/local/lsws/conf/httpd_config.conf.tmp /usr/local/lsws/conf/httpd_config.conf

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
