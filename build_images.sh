#!/bin/sh

set -eu

# Цель можно передать аргументом: old | ka | both | none.
# BUILD_TARGET имеет приоритет над аргументом.
TARGET=${BUILD_TARGET:-${1:-}}

# -----------------------------------------------------------------------------
# Целевые серверы для копирования готового Docker-образа 1С.
# При необходимости меняются только эти переменные.
# -----------------------------------------------------------------------------
OLD_1C_NAME="Старый сервер 1С"
OLD_1C_USER="mtp_admin"
OLD_1C_HOST="192.168.3.3"
OLD_1C_DIR="/home/mtp_admin"

KA_1C_NAME="Новый сервер КА"
KA_1C_USER="adminkaserver"
KA_1C_HOST="192.168.3.198"
KA_1C_DIR="/home/adminkaserver"

# -----------------------------------------------------------------------------
# Поиск установщика и определение версии 1С.
# -----------------------------------------------------------------------------
set -- Docker/server/setup-full*.run
if [ ! -e "$1" ] || [ "$1" = 'Docker/server/setup-full*.run' ]; then
    echo "Error: installer file not found in Docker/server" >&2
    exit 1
fi
if [ "$#" -gt 1 ]; then
    echo "Warning: multiple installer files found, using $1" >&2
fi

RUN_FILE=$1
RUN_BASENAME=$(basename "$RUN_FILE")
VERSION=$(printf '%s\n' "$RUN_BASENAME" | sed -n 's/^setup-full-\(.*\)-x86_64\.run$/\1/p')
if [ -z "$VERSION" ]; then
    echo "Error: could not parse version from '$RUN_BASENAME'" >&2
    exit 1
fi

SERVER_IMAGE="1cserver:${VERSION}"
ARCHIVE="1cserver-${VERSION}.tar"

# -----------------------------------------------------------------------------
# Выбор сервера.
# Можно передать выбор аргументом:
#   sh ./build_images.sh old
#   sh ./build_images.sh ka
#   sh ./build_images.sh both
#   sh ./build_images.sh none
# Без аргумента будет показано интерактивное меню.
# -----------------------------------------------------------------------------

choose_target() {
    echo
    echo "Куда копировать готовый архив $ARCHIVE?"
    echo "  1) $OLD_1C_NAME  ($OLD_1C_USER@$OLD_1C_HOST:$OLD_1C_DIR)"
    echo "  2) $KA_1C_NAME   ($KA_1C_USER@$KA_1C_HOST:$KA_1C_DIR)"
    echo "  3) На оба сервера"
    echo "  0) Не копировать, только собрать архив"
    printf "Выберите вариант [0-3]: "
    read -r answer

    case "$answer" in
        1) TARGET="old" ;;
        2) TARGET="ka" ;;
        3) TARGET="both" ;;
        0) TARGET="none" ;;
        *)
            echo "Ошибка: неизвестный вариант '$answer'" >&2
            exit 1
            ;;
    esac
}

copy_archive() {
    server_name=$1
    server_user=$2
    server_host=$3
    server_dir=$4

    echo
    echo "Копирование $ARCHIVE -> $server_name"
    echo "Адрес: $server_user@$server_host:$server_dir/"

    scp "$ARCHIVE" "$server_user@$server_host:$server_dir/"

    echo "Готово: архив скопирован на $server_name"
    echo "Для загрузки образа на этом сервере выполнить:"
    echo "  docker load -i $server_dir/$ARCHIVE"
}

# -----------------------------------------------------------------------------
# Сборка базового образа.
# -----------------------------------------------------------------------------
echo "Сборка базового образа onec_base..."
docker build --platform linux/x86-64 -t onec_base Docker/onec_base

# -----------------------------------------------------------------------------
# Установка сервера 1С в базовый образ.
# -----------------------------------------------------------------------------
echo "Сборка образа $SERVER_IMAGE..."
docker build \
    --platform linux/x86-64 \
    --build-arg VERSION="$VERSION" \
    -t "$SERVER_IMAGE" \
    Docker/server

# -----------------------------------------------------------------------------
# Сохранение образа в TAR.
# -----------------------------------------------------------------------------
echo "Сохранение образа в $ARCHIVE..."
docker save -o "$ARCHIVE" "$SERVER_IMAGE"
echo "Built image $SERVER_IMAGE and saved archive $ARCHIVE"

# -----------------------------------------------------------------------------
# Выбор и копирование.
# -----------------------------------------------------------------------------
if [ -z "$TARGET" ]; then
    choose_target
fi

case "$TARGET" in
    old|1)
        copy_archive "$OLD_1C_NAME" "$OLD_1C_USER" "$OLD_1C_HOST" "$OLD_1C_DIR"
        ;;
    ka|2)
        copy_archive "$KA_1C_NAME" "$KA_1C_USER" "$KA_1C_HOST" "$KA_1C_DIR"
        ;;
    both|3)
        copy_archive "$OLD_1C_NAME" "$OLD_1C_USER" "$OLD_1C_HOST" "$OLD_1C_DIR"
        copy_archive "$KA_1C_NAME" "$KA_1C_USER" "$KA_1C_HOST" "$KA_1C_DIR"
        ;;
    none|0)
        echo "Копирование пропущено. Архив оставлен локально: $ARCHIVE"
        ;;
    *)
        echo "Ошибка: BUILD_TARGET='$TARGET'. Допустимо: old, ka, both, none" >&2
        exit 1
        ;;
esac

echo
echo "Команда для запуска образа:"
echo "docker run -d \\\n    --name 1cserver-$VERSION \\\n    --restart unless-stopped \\\n    --network host \\\n    -v /home/usr1cv8/.1cv8:/home/usr1cv8/.1cv8 \\\n    -v /var/1C/licenses:/var/1C/licenses \\\n    -v /etc/localtime:/etc/localtime:ro \\\n    -v /etc/timezone:/etc/timezone:ro \\\n    -v /usr/share/fonts:/usr/share/fonts:ro \\\n    -v /etc/fonts:/etc/fonts:ro \\\n    -v /_SHARE/exchange:/_SHARE/exchange \\\n    $SERVER_IMAGE"