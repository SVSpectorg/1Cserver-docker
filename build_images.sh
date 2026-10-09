#!/bin/sh

set -eu

# =============================================================================
# 1C Docker image builder / copier
#
# Собираются два образа одной версии:
#   1cserver:<version>
#   1cweb:<version>
#
# Обычная сборка:
#   sh ./build_images.sh
#   sh ./build_images.sh ka
#   sh ./build_images.sh old
#   sh ./build_images.sh both
#   sh ./build_images.sh none
#
# Только копирование, без сборки:
#   sh ./build_images.sh copy ka
#   sh ./build_images.sh copy old
#   sh ./build_images.sh copy both
#
# Если нужно явно указать версию для copy:
#   sh ./build_images.sh copy both 8.5.1.1529
#
# Принудительно пересобрать onec_base:
#   FORCE_BASE_REBUILD=1 sh ./build_images.sh both
# =============================================================================

ACTION="build"
TARGET=""
VERSION=""

case "${1:-}" in
    copy)
        ACTION="copy"
        TARGET="${2:-}"
        VERSION="${3:-}"
        ;;
    build)
        ACTION="build"
        TARGET="${2:-}"
        ;;
    old|ka|both|none|1|2|3|0)
        ACTION="build"
        TARGET="$1"
        ;;
    "")
        ACTION="build"
        ;;
    *)
        echo "Ошибка: неизвестная команда '$1'." >&2
        echo "Допустимо:" >&2
        echo "  sh ./build_images.sh [old|ka|both|none]" >&2
        echo "  sh ./build_images.sh copy [old|ka|both] [version]" >&2
        exit 1
        ;;
esac

TARGET=${BUILD_TARGET:-$TARGET}
VERSION=${VERSION_OVERRIDE:-$VERSION}

# Необязательный локальный shell-конфиг рядом со скриптом (не хранить в Git).
# Загружать только доверенный файл; его значения имеют приоритет над окружением.
LOCAL_CONFIG="$(dirname "$0")/build_images.local.conf"
if [ -f "$LOCAL_CONFIG" ]; then
    . "$LOCAL_CONFIG"
fi

OLD_1C_NAME=${OLD_1C_NAME:-old}
OLD_1C_USER=${OLD_1C_USER:-}
OLD_1C_HOST=${OLD_1C_HOST:-}
OLD_1C_DIR=${OLD_1C_DIR:-}

KA_1C_NAME=${KA_1C_NAME:-ka}
KA_1C_USER=${KA_1C_USER:-}
KA_1C_HOST=${KA_1C_HOST:-}
KA_1C_DIR=${KA_1C_DIR:-}

get_version_from_installer() {
    set -- Docker/server/setup-full*.run

    if [ ! -e "$1" ] || [ "$1" = 'Docker/server/setup-full*.run' ]; then
        return 1
    fi

    if [ "$#" -gt 1 ]; then
        echo "Ошибка: найдено несколько установщиков 1С:" >&2
        for f in "$@"; do
            echo "  $f" >&2
        done
        echo "Оставьте в Docker/server только один setup-full-*.run." >&2
        exit 1
    fi

    run_basename=$(basename "$1")
    parsed_version=$(printf '%s\n' "$run_basename" | sed -n 's/^setup-full-\(.*\)-x86_64\.run$/\1/p')

    if [ -z "$parsed_version" ]; then
        echo "Ошибка: не удалось определить версию из '$run_basename'." >&2
        exit 1
    fi

    printf '%s\n' "$parsed_version"
}

detect_version_for_copy() {
    if installer_version=$(get_version_from_installer 2>/dev/null); then
        printf '%s\n' "$installer_version"
        return 0
    fi

    set -- ./1cserver-*.tar
    if [ -e "$1" ] && [ "$1" != './1cserver-*.tar' ] && [ "$#" -eq 1 ]; then
        basename "$1" | sed -n 's/^1cserver-\(.*\)\.tar$/\1/p'
        return 0
    fi

    image_versions=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | sed -n 's/^1cserver:\(.*\)$/\1/p' | grep -v '^<none>$' || true)
    image_count=$(printf '%s\n' "$image_versions" | sed '/^$/d' | wc -l | tr -d ' ')

    if [ "$image_count" = "1" ]; then
        printf '%s\n' "$image_versions" | sed '/^$/d'
        return 0
    fi

    return 1
}

choose_target() {
    echo
    echo "Куда копировать готовые архивы?"
    echo "  $SERVER_ARCHIVE"
    echo "  $WEB_ARCHIVE"
    echo
    echo "  1) $OLD_1C_NAME  ($OLD_1C_USER@$OLD_1C_HOST:$OLD_1C_DIR)"
    echo "  2) $KA_1C_NAME   ($KA_1C_USER@$KA_1C_HOST:$KA_1C_DIR)"
    echo "  3) На оба сервера"

    if [ "$ACTION" = "build" ]; then
        echo "  0) Не копировать, только собрать архивы"
        printf "Выберите вариант [0-3]: "
    else
        printf "Выберите вариант [1-3]: "
    fi

    read -r answer

    case "$answer" in
        1) TARGET="old" ;;
        2) TARGET="ka" ;;
        3) TARGET="both" ;;
        0)
            if [ "$ACTION" = "build" ]; then
                TARGET="none"
            else
                echo "Ошибка: в режиме copy вариант 0 недоступен." >&2
                exit 1
            fi
            ;;
        *)
            echo "Ошибка: неизвестный вариант '$answer'." >&2
            exit 1
            ;;
    esac
}

ensure_archive() {
    image=$1
    archive=$2

    if [ -f "$archive" ]; then
        echo "Найден готовый архив: $archive"
        return 0
    fi

    if docker image inspect "$image" >/dev/null 2>&1; then
        echo "Архив $archive не найден, но Docker-образ $image существует."
        echo "Создаём TAR без пересборки..."
        docker save -o "$archive" "$image"
        echo "Готово: создан $archive"
        return 0
    fi

    echo "Ошибка: не найден ни архив '$archive', ни Docker-образ '$image'." >&2
    return 1
}

copy_archives() {
    server_name=$1
    server_user=$2
    server_host=$3
    server_dir=$4

    echo
    echo "============================================================"
    echo "Копирование на: $server_name"
    echo "============================================================"
    echo "Файлы:"
    echo "  $SERVER_ARCHIVE"
    echo "  $WEB_ARCHIVE"
    echo "Адрес: $server_user@$server_host:$server_dir/"
    echo

    scp "$SERVER_ARCHIVE" "$WEB_ARCHIVE" "$server_user@$server_host:$server_dir/"

    echo
    echo "Готово: оба архива скопированы на $server_name"
    echo "Для загрузки образов на сервере:"
    echo "  docker load -i $server_dir/$SERVER_ARCHIVE"
    echo "  docker load -i $server_dir/$WEB_ARCHIVE"
}

if [ "$ACTION" = "build" ]; then
    VERSION=$(get_version_from_installer)
else
    if [ -z "$VERSION" ]; then
        if ! VERSION=$(detect_version_for_copy); then
            echo "Ошибка: не удалось однозначно определить версию образов." >&2
            echo "Укажите её явно, например:" >&2
            echo "  sh ./build_images.sh copy both 8.5.1.1529" >&2
            exit 1
        fi
    fi
fi

SERVER_IMAGE="1cserver:${VERSION}"
WEB_IMAGE="1cweb:${VERSION}"
SERVER_ARCHIVE="1cserver-${VERSION}.tar"
WEB_ARCHIVE="1cweb-${VERSION}.tar"

echo
echo "Версия 1С:   $VERSION"
echo "Server image: $SERVER_IMAGE"
echo "Web image:    $WEB_IMAGE"
echo "Server TAR:   $SERVER_ARCHIVE"
echo "Web TAR:      $WEB_ARCHIVE"
echo "Режим:        $ACTION"

if [ "$ACTION" = "build" ]; then
    if [ "${FORCE_BASE_REBUILD:-0}" = "1" ]; then
        echo
        echo "Принудительная пересборка базового образа onec_base..."
        docker build --platform linux/x86-64 -t onec_base Docker/onec_base
    elif docker image inspect onec_base:latest >/dev/null 2>&1; then
        echo
        echo "Базовый образ onec_base:latest уже существует."
        echo "Сборка onec_base пропущена."
    else
        echo
        echo "Базовый образ onec_base:latest не найден."
        echo "Сборка базового образа..."
        docker build --platform linux/x86-64 -t onec_base Docker/onec_base
    fi

    echo
    echo "Сборка образа $SERVER_IMAGE..."
    docker build \
        --platform linux/x86-64 \
        --build-arg VERSION="$VERSION" \
        -t "$SERVER_IMAGE" \
        -f Docker/server/Dockerfile \
        Docker

    echo
    echo "Сборка образа $WEB_IMAGE..."
    docker build \
        --platform linux/x86-64 \
        --build-arg VERSION="$VERSION" \
        -t "$WEB_IMAGE" \
        -f Docker/web/Dockerfile \
        Docker

    echo
    echo "Сохранение образа в $SERVER_ARCHIVE..."
    docker save -o "$SERVER_ARCHIVE" "$SERVER_IMAGE"

    echo "Сохранение образа в $WEB_ARCHIVE..."
    docker save -o "$WEB_ARCHIVE" "$WEB_IMAGE"

    echo
    echo "Готово:"
    echo "  $SERVER_ARCHIVE"
    echo "  $WEB_ARCHIVE"
else
    echo
    echo "Режим COPY: сборка Docker-образов пропущена."
    ensure_archive "$SERVER_IMAGE" "$SERVER_ARCHIVE"
    ensure_archive "$WEB_IMAGE" "$WEB_ARCHIVE"
fi

if [ -z "$TARGET" ]; then
    choose_target
fi

# Проверить все выбранные серверы до первого scp, включая режим both.
case "$TARGET" in
    old|1|both|3)
        : "${OLD_1C_USER:?Задайте OLD_1C_USER}"
        : "${OLD_1C_HOST:?Задайте OLD_1C_HOST}"
        : "${OLD_1C_DIR:?Задайте OLD_1C_DIR}"
        ;;
esac

case "$TARGET" in
    ka|2|both|3)
        : "${KA_1C_USER:?Задайте KA_1C_USER}"
        : "${KA_1C_HOST:?Задайте KA_1C_HOST}"
        : "${KA_1C_DIR:?Задайте KA_1C_DIR}"
        ;;
esac

case "$TARGET" in
    old|1)
        copy_archives "$OLD_1C_NAME" "$OLD_1C_USER" "$OLD_1C_HOST" "$OLD_1C_DIR"
        ;;
    ka|2)
        copy_archives "$KA_1C_NAME" "$KA_1C_USER" "$KA_1C_HOST" "$KA_1C_DIR"
        ;;
    both|3)
        copy_archives "$OLD_1C_NAME" "$OLD_1C_USER" "$OLD_1C_HOST" "$OLD_1C_DIR"
        copy_archives "$KA_1C_NAME" "$KA_1C_USER" "$KA_1C_HOST" "$KA_1C_DIR"
        ;;
    none|0)
        if [ "$ACTION" = "copy" ]; then
            echo "Ошибка: target 'none' недопустим в режиме copy." >&2
            exit 1
        fi
        echo
        echo "Копирование пропущено. Архивы оставлены локально:"
        echo "  $SERVER_ARCHIVE"
        echo "  $WEB_ARCHIVE"
        ;;
    *)
        echo "Ошибка: TARGET='$TARGET'. Допустимо: old, ka, both, none." >&2
        exit 1
        ;;
esac

echo
echo "============================================================"
echo "Команда для запуска образа $SERVER_IMAGE:"
echo "============================================================"
cat <<EOF_SERVER
docker run -d \
    --name 1cserver-$VERSION \
    --restart unless-stopped \
    --network host \
    -v /home/usr1cv8/.1cv8:/home/usr1cv8/.1cv8 \
    -v /var/1C/licenses:/var/1C/licenses \
    -v /etc/localtime:/etc/localtime:ro \
    -v /etc/timezone:/etc/timezone:ro \
    -v /usr/share/fonts:/usr/share/fonts:ro \
    -v /etc/fonts:/etc/fonts:ro \
    -v /_SHARE/exchange:/_SHARE/exchange \
    $SERVER_IMAGE
EOF_SERVER

echo
echo "============================================================"
echo "Команда для запуска образа $WEB_IMAGE:"
echo "============================================================"
cat <<EOF_WEB
docker run -d \
    --name 1cweb-$VERSION \
    --restart unless-stopped \
    --network host \
    -v /var/www/mcp-api:/var/www/mcp-api:ro \
    $WEB_IMAGE
EOF_WEB
