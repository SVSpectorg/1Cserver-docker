#!/bin/bash
set -eu

INSTALL_DIR="/opt/1cv8/x86_64/${SERVER_VERSION}"
WSAP="${INSTALL_DIR}/wsap24.so"
WEBINST="${INSTALL_DIR}/webinst"
DESCRIPTOR="/var/www/mcp-api/default.vrd"
MODULE_CONF="/etc/apache2/conf-enabled/1cws.conf"
PUBLICATION_CONF="/etc/apache2/conf-enabled/mcp-api-publication.conf"
PERSISTENT_CONF="/etc/apache2/conf-enabled/1c-persistent-publications.conf"
PUBLICATIONS_DIR="/var/www/1c-pub"

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

# Rebuild Apache publication registrations from persistent host-mounted descriptors.
# webinst may modify apache2.conf in a running container; a new container
# restores the registrations without relying on those ephemeral changes.
: > "${PERSISTENT_CONF}"
if [ -d "${PUBLICATIONS_DIR}" ]; then
    for descriptor in "${PUBLICATIONS_DIR}"/*/default.vrd; do
        [ -f "${descriptor}" ] || continue

        pub_dir=$(dirname "${descriptor}")
        pub_name=$(basename "${pub_dir}")

        # Restrict directory names before interpolating them into Apache config.
        case "${pub_name}" in
            *[!a-zA-Z0-9_-]*|"")
                echo "ERROR: invalid 1C publication name: ${pub_name}" >&2
                exit 1
                ;;
        esac

        if [ ! -r "${descriptor}" ]; then
            echo "ERROR: 1C descriptor is not readable: ${descriptor}" >&2
            exit 1
        fi

        cat >> "${PERSISTENT_CONF}" <<EOF_PUB
Alias "/${pub_name}" "${pub_dir}/"

<Directory "${pub_dir}/">
    AllowOverride None
    Options None
    Require all granted
    SetHandler 1c-application
    ManagedApplicationDescriptor "${descriptor}"
</Directory>

EOF_PUB
        echo "1C persistent publication enabled: /${pub_name} -> ${descriptor}"
    done
fi

echo "1C Web Extension version: ${SERVER_VERSION}"
echo "wsap24.so: ${WSAP}"
echo "webinst:   ${WEBINST}"

apache2ctl configtest
exec apache2ctl -D FOREGROUND
