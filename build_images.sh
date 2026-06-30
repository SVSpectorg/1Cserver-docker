#!/bin/sh

set -eu

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

#Сборка базового образа
docker build --platform linux/x86-64 -t onec_base Docker/onec_base

#Установка 1cserver в базовый образ
docker build --platform linux/x86-64 --build-arg VERSION="$VERSION" -t "$SERVER_IMAGE" Docker/server

#Подготовка архива образа
docker save -o "$ARCHIVE" "$SERVER_IMAGE"
echo "Built image $SERVER_IMAGE and saved archive $ARCHIVE"

#Копирование архива на сервер
scp 1cserver-$VERSION.tar mtp_admin@192.168.3.3:/home/mtp_admin

echo "Архив $ARCHIVE скопирован на сервер 1С
        Для его загрузки в Docker выполнить:
        docker load -i /home/mtp_admin/$ARCHIVE"

echo "Команда для запуска образа:
        docker run -d \\
        --name 1cserver-$VERSION \\
        --restart unless-stopped \\
        --network host \\
        -v /home/usr1cv8/.1cv8:/home/usr1cv8/.1cv8 \\
        -v /var/1C/licenses:/var/1C/licenses \\
        -v /etc/localtime:/etc/localtime:ro \\
        -v /etc/timezone:/etc/timezone:ro \\
        -v /usr/share/fonts:/usr/share/fonts:ro \\
        -v /etc/fonts:/etc/fonts:ro \\
        -v /_SHARE/exchange:/_SHARE/exchange \\
        $SERVER_IMAGE"