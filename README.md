# 1C Server Docker

Проект собирает согласованные Docker-образы 1С:Enterprise одной версии:

- `1cserver:<version>` — серверный кластер 1С (`ragent`, `ras`);
- `1cweb:<version>` — Apache + web-extension 1С (`wsap24.so`, `webinst`) для HTTP/Web services.

Оба образа собираются из одного установщика `setup-full-<version>-x86_64.run`, поэтому версия серверной платформы и web-extension совпадает.

## Структура

- `build_images.sh` — сборка, сохранение TAR и копирование на серверы;
- `Docker/onec_base/Dockerfile` — общий Ubuntu base с локалью и библиотеками;
- `Docker/server/Dockerfile` — серверный компонент 1С;
- `Docker/server/entrypoint.sh` — запуск `ras` и `ragent`;
- `Docker/web/Dockerfile` — web-extension 1С и Apache;
- `Docker/web/entrypoint.sh` — проверка `wsap24.so/webinst`, подключение публикации и запуск Apache.

## Требования

- Docker;
- Linux/WSL;
- установочный файл 1С вида `setup-full-<версия>-x86_64.run`.

Установщик кладётся только сюда:

```text
Docker/server/setup-full-8.5.1.1529-x86_64.run
```

В Git установщик не добавляется.

## Сборка

По умолчанию собираются оба образа:

```bash
sh ./build_images.sh
sh ./build_images.sh both
```

Можно явно выбрать, что собирать:

```bash
# Оба образа
sh ./build_images.sh all both

# Только сервер 1С
sh ./build_images.sh server both

# Только web-extension
sh ./build_images.sh web both
```

Второй параметр определяет, куда копировать готовый TAR:

```text
old   - старый сервер 1С
ka    - сервер 1С КА
both  - оба сервера
none  - только собрать локально, не копировать
```

Примеры:

```bash
sh ./build_images.sh server old
sh ./build_images.sh server ka
sh ./build_images.sh server both
sh ./build_images.sh server none

sh ./build_images.sh web old
sh ./build_images.sh web ka
sh ./build_images.sh web both
sh ./build_images.sh web none
```

Старый синтаксис сохранён и означает сборку обоих образов:

```bash
sh ./build_images.sh old
sh ./build_images.sh ka
sh ./build_images.sh both
sh ./build_images.sh none
```

## Только копирование

Без пересборки можно выбрать конкретный образ:

```bash
# Оба
sh ./build_images.sh copy all both

# Только server
sh ./build_images.sh copy server both

# Только web
sh ./build_images.sh copy web both
```

Можно копировать на один сервер:

```bash
sh ./build_images.sh copy web old
sh ./build_images.sh copy web ka
```

Старый синтаксис также работает и означает `all`:

```bash
sh ./build_images.sh copy old
sh ./build_images.sh copy ka
sh ./build_images.sh copy both
```

Если версия не определяется автоматически:

```bash
sh ./build_images.sh copy web both 8.5.1.1529
sh ./build_images.sh copy server both 8.5.1.1529
sh ./build_images.sh copy all both 8.5.1.1529
```

Если TAR отсутствует, но соответствующий Docker image существует локально, скрипт создаст TAR через `docker save`.

## Что создаётся

Для `all`:

```text
1cserver-<version>.tar
1cweb-<version>.tar
```

Для `server`:

```text
1cserver-<version>.tar
```

Для `web`:

```text
1cweb-<version>.tar
```

На выбранный сервер копируются только архивы выбранного режима.

## Локальные настройки серверов

Создайте `build_images.local.conf` рядом со скриптом. Файл игнорируется Git.

Пример:

```sh
OLD_1C_NAME=old
OLD_1C_USER=user
OLD_1C_HOST=192.168.3.3
OLD_1C_DIR=/path/to/images

KA_1C_NAME=ka
KA_1C_USER=user
KA_1C_HOST=192.168.x.x
KA_1C_DIR=/path/to/images
```

## Запуск 1cserver

```bash
docker load -i 1cserver-<version>.tar

docker run -d \
  --name 1cserver-<version> \
  --restart unless-stopped \
  --network host \
  -v /home/usr1cv8/.1cv8:/home/usr1cv8/.1cv8 \
  -v /var/1C/licenses:/var/1C/licenses \
  -v /etc/localtime:/etc/localtime:ro \
  -v /etc/timezone:/etc/timezone:ro \
  -v /usr/share/fonts:/usr/share/fonts:ro \
  -v /etc/fonts:/etc/fonts:ro \
  -v /_SHARE/exchange:/_SHARE/exchange \
  1cserver:<version>
```

## Запуск 1cweb

```bash
docker load -i 1cweb-<version>.tar

docker run -d \
  --name 1cweb-<version> \
  --restart unless-stopped \
  --network host \
  -v /var/www/mcp-api:/var/www/mcp-api:ro \
  1cweb:<version>
```

В контейнере Apache слушает только:

```text
127.0.0.1:8081
```

Без `/var/www/mcp-api/default.vrd` контейнер запускается только с диагностическим endpoint:

```text
http://127.0.0.1:8081/health
```

Если смонтирован `default.vrd`, автоматически включается публикация:

```text
/mcp-api
```

Предполагаемая внешняя схема:

```text
MCP -> host Apache HTTPS -> 127.0.0.1:8081 -> 1cweb -> 1C server
```

TLS, IP allowlist и reverse proxy рекомендуется оставлять на Apache хоста, а web-контейнер не публиковать напрямую в сеть.

## Примечания

- `server` и `ws` устанавливаются из одного `setup-full`, чтобы исключить рассинхронизацию версий.
- `default.vrd` не хранится в образе и должен передаваться с хоста.
- Web-контейнер предназначен для API/HTTP services; публикацию web-клиента включать не требуется.
