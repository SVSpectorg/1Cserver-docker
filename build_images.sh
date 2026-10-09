#!/bin/sh

set -eu

# =============================================================================
# 1C Docker image builder / copier
#
# Что собирать:
#   all     - 1cserver + 1cweb (по умолчанию)
#   server  - только 1cserver
#   web     - только 1cweb
#
# Куда копировать:
#   old | ka | both | none
#
# Примеры:
#   sh ./build_images.sh both
#   sh ./build_images.sh server both
#   sh ./build_images.sh web both
#   sh ./build_images.sh all both
#
# Только копирование, без сборки:
#   sh ./build_images.sh copy both
#   sh ./build_images.sh copy server both
#   sh ./build_images.sh copy web both
#   sh ./build_images.sh copy all both
#
# Явная версия для copy:
#   sh ./build_images.sh copy web both 8.5.1.1529
#
# Принудительно пересобрать onec_base:
#   FORCE_BASE_REBUILD=1 sh ./build_images.sh web both
#
# Обратная совместимость:
#   sh ./build_images.sh old|ka|both|none
#   sh ./build_images.sh copy old|ka|both [version]
# =============================================================================

ACTION="build"
IMAGE_TARGET="all"
TARGET=""
VERSION=""

case "${1:-}" in
    copy)
        ACTION="copy"
        case "${2:-}" in
            all|server|web)
                IMAGE_TARGET="$2"
                TARGET="${3:-}"
                VERSION="${4:-}"
                ;;
            *)
                IMAGE_TARGET="all"
                TARGET="${2:-}"
                VERSION="${3:-}"
                ;;
        esac
        ;;
    build)
        ACTION="build"
        case "${2:-}" in
            all|server|web)
                IMAGE_TARGET="$2"
                TARGET="${3:-}"
                ;;
            *)
                IMAGE_TARGET="all"
                TARGET="${2:-}"
                ;;
        esac
        ;;
    all|server|web)
        ACTION="build"
        IMAGE_TARGET="$1"
        TARGET="${2:-}"
        ;;
    old|ka|both|none|1|2|3|0)
        ACTION="build"
        IMAGE_TARGET="all"
        TARGET="$1"
        ;;
    "")
        ACTION="build"
        IMAGE_TARGET="all"
        ;;
    *)
        echo "Ошибка: неизвестная команда '$1'." >&2
        echo "Допустимо:" >&2
        echo "  sh ./build_images.sh [old|ka|both|none]" >&2
        echo "  sh ./build_images.sh [all|server|web] [old|ka|both|none]" >&2
        echo "  sh ./build_images.sh copy [old|ka|both] [version]" >&2
        echo "  sh ./build_images.sh copy [all|server|web] [old|ka|both] [version]" >&2
        exit 1
        ;;
esac

TARGET=${BUILD_TARGET:-$TARGET}
VERSION=${VERSION_OVERRIDE:-$VERSION}
IMAGE_TARGET=${IMAGE_TARGET_OVERRIDE:-$IMAGE_TARGET}

case "$IMAGE_TARGET" in
    all|server|web) ;;
    *)
        echo "Ошибка: IMAGE_TARGET='$IMAGE_TARGET'. Допустимо: all, server, web." >&2
        exit 1
        ;;
esac

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

detect_version_from_artifact() {
    prefix=$1

    set -- "./${prefix}-"*.tar
    if [ -e "$1" ] && [ "$1" != "./${prefix}-*.tar" ] && [ "$#" -eq 1 ]; then
        basename "$1" | sed -n "s/^${prefix}-\(.*\)\.tar$/\1/p"
        return 0
    fi

    image_versions=$(docker images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null \
        | sed -n "s/^${prefix}:\(.*\)$/\1/p" \
        | grep -v '^<none>$' || true)
    image_count=$(printf '%s\n' "$image_versions" | sed '/^$/d' | wc -l | tr -d ' ')

    if [ "$image_count" = "1" ]; then
        printf '%s\n' "$image_versions" | sed '/^$/d'
        return 0
    fi

    return 1
}

detect_version_for_copy() {
    if installer_version=$(get_version_from_installer 2>/dev/null); then
        printf '%s\n' "$installer_version"
        return 0
    fi

    case "$IMAGE_TARGET" in
        server)
            detect_version_from_artifact "1cserver"
            return $?
            ;;
        web)
            detect_version_from_artifact "1cweb"
            return $?
            ;;
        all)
            if detected=$(detect_version_from_artifact "1cserver" 2>/dev/null); then
                printf '%s\n' "$detected"
                return 0
            fi
            if detected=$(detect_version_from_artifact "1cweb" 2>/dev/null); then
                printf '%s\n' "$detected"
                return 0
            fi
            return 1
            ;;
    esac
}

print_selected_archives() {
    case "$IMAGE_TARGET" in
        server)
            echo "  $SERVER_ARCHIVE"
            ;;
        web)
            echo "  $WEB_ARCHIVE"
            ;;
        all)
            echo "  $SERVER_ARCHIVE"
            echo "  $WEB_ARCHIVE"
            ;;
    esac
}

choose_target() {
    echo
    echo "Куда копировать готовые архивы?"
    print_selected_archives
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

ensure_selected_archives() {
    case "$IMAGE_TARGET" in
        server)
            ensure_archive "$SERVER_IMAGE" "$SERVER_ARCHIVE"
            ;;
        web)
            ensure_archive "$WEB_IMAGE" "$WEB_ARCHIVE"
            ;;
        all)
            ensure_archive "$SERVER_IMAGE" "$SERVER_ARCHIVE"
            ensure_archive "$WEB_IMAGE" "$WEB_ARCHIVE"
            ;;
    esac
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
    print_selected_archives
    echo "Адрес: $server_user@$server_host:$server_dir/"
    echo

    case "$IMAGE_TARGET" in
        server)
            scp "$SERVER_ARCHIVE" "$server_user@$server_host:$server_dir/"
            ;;
        web)
            scp "$WEB_ARCHIVE" "$server_user@$server_host:$server_dir/"
            ;;
        all)
            scp "$SERVER_ARCHIVE" "$WEB_ARCHIVE" "$server_user@$server_host:$server_dir/"
            ;;
    esac

    echo
    echo "Готово: архивы скопированы на $server_name"
    echo "Для загрузки образов на сервере:"
    case "$IMAGE_TARGET" in
        server)
            echo "  docker load -i $server_dir/$SERVER_ARCHIVE"
            ;;
        web)
            echo "  docker load -i $server_dir/$WEB_ARCHIVE"
            ;;
        all)
            echo "  docker load -i $server_dir/$SERVER_ARCHIVE"
            echo "  docker load -i $server_dir/$WEB_ARCHIVE"
            ;;
    esac
}

if [ "$ACTION" = "build" ]; then
    VERSION=$(get_version_from_installer)
else
    if [ -z "$VERSION" ]; then
        if ! VERSION=$(detect_version_for_copy); then
            echo "Ошибка: не удалось однозначно определить версию образа." >&2
            echo "Укажите её явно, например:" >&2
            echo "  sh ./build_images.sh copy $IMAGE_TARGET both 8.5.1.1529" >&2
            exit 1
        fi
    fi
fi

SERVER_IMAGE="1cserver:${VERSION}"
WEB_IMAGE="1cweb:${VERSION}"
SERVER_ARCHIVE="1cserver-${VERSION}.tar"
WEB_ARCHIVE="1cweb-${VERSION}.tar"

echo
echo "Версия 1С:      $VERSION"
echo "Режим:           $ACTION"
echo "Компонент:       $IMAGE_TARGET"

case "$IMAGE_TARGET" in
    server)
        echo "Image:           $SERVER_IMAGE"
        echo "TAR:             $SERVER_ARCHIVE"
        ;;
    web)
        echo "Image:           $WEB_IMAGE"
        echo "TAR:             $WEB_ARCHIVE"
        ;;
    all)
        echo "Server image:    $SERVER_IMAGE"
        echo "Web image:       $WEB_IMAGE"
        echo "Server TAR:      $SERVER_ARCHIVE"
        echo "Web TAR:         $WEB_ARCHIVE"
        ;;
esac

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

    case "$IMAGE_TARGET" in
        server|all)
            echo
            echo "Сборка образа $SERVER_IMAGE..."
            docker build \
                --platform linux/x86-64 \
                --build-arg VERSION="$VERSION" \
                -t "$SERVER_IMAGE" \
                -f Docker/server/Dockerfile \
                Docker

            echo
            echo "Сохранение образа в $SERVER_ARCHIVE..."
            docker save -o "$SERVER_ARCHIVE" "$SERVER_IMAGE"
            ;;
    esac

    case "$IMAGE_TARGET" in
        web|all)
            echo
            echo "Сборка образа $WEB_IMAGE..."
            docker build \
                --platform linux/x86-64 \
                --build-arg VERSION="$VERSION" \
                -t "$WEB_IMAGE" \
                -f Docker/web/Dockerfile \
                Docker

            echo
            echo "Сохранение образа в $WEB_ARCHIVE..."
            docker save -o "$WEB_ARCHIVE" "$WEB_IMAGE"
            ;;
    esac

    echo
    echo "Готово:"
    print_selected_archives
else
    echo
    echo "Режим COPY: сборка Docker-образов пропущена."
    ensure_selected_archives
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
        print_selected_archives
        ;;
    *)
        echo "Ошибка: TARGET='$TARGET'. Допустимо: old, ka, both, none." >&2
        exit 1
        ;;
esac

case "$IMAGE_TARGET" in
    server|all)
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
        ;;
esac

case "$IMAGE_TARGET" in
    web|all)
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
        ;;
esac
