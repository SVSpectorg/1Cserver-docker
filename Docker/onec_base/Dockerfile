FROM ubuntu:24.04

ENV TZ="Asia/Magadan"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    wget \
    locales \
    libicu74 \
    libfontconfig1 \
    libgtk-3-0 \
    libenchant-2-2 \
    libharfbuzz-icu0 \
    libgstreamer1.0-0 \
    libgstreamer-plugins-base1.0-0 \
    libodbc2 \
    unixodbc \
    ca-certificates \
    && locale-gen ru_RU.UTF-8 \
    && localedef -i ru_RU -c -f UTF-8 -A /usr/share/locale/locale.alias ru_RU.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=ru_RU.UTF-8
ENV LANGUAGE=ru_RU:ru
ENV LC_ALL=ru_RU.UTF-8