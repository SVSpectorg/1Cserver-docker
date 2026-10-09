#!/bin/bash
set -eu

INSTALL_DIR="/opt/1cv8/x86_64/${SERVER_VERSION}"
WSAP="${INSTALL_DIR}/wsap24.so"
WEBINST="${INSTALL_DIR}/webinst"
DESCRIPTOR="/var/www/mcp-api/default.vrd"
MODULE_CONF="/etc/apache2/conf-enabled/1cws.conf"
PUBLICATION_CONF="/etc/apache2/conf-enabled/mcp-api-publication.conf"

if [ ! -f "${WSAP}" ]; then
    echo "ERROR: 1C web module not found: ${WSAP}" >&2
    exit 1
fi

if [ ! -x "${WEBINST}" ]; then
    echo "ERROR: 1C webinst not found or not executable: ${WEBINST}" >&2
    exit 1
fi

cat > "${MODULE_CONF}" <<EOF
LoadModule _1cws_module "${WSAP}"
EOF

if [ -f "${DESCRIPTOR}" ]; then
    cat > "${PUBLICATION_CONF}" <<EOF
Alias "/mcp-api" "/var/www/mcp-api/"

<Directory "/var/www/mcp-api/">
    AllowOverride None
    Options None
    Require all granted
    SetHandler 1c-application
    ManagedApplicationDescriptor "${DESCRIPTOR}"
</Directory>
EOF
    echo "1C publication enabled: /mcp-api -> ${DESCRIPTOR}"
else
    rm -f "${PUBLICATION_CONF}"
    echo "1C descriptor is not mounted yet: ${DESCRIPTOR}"
    echo "Apache will start with /health only."
fi

echo "1C Web Extension version: ${SERVER_VERSION}"
echo "wsap24.so: ${WSAP}"
echo "webinst:   ${WEBINST}"

apache2ctl configtest
exec apache2ctl -D FOREGROUND
