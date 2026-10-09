FROM onec_base AS web

ARG VERSION

USER root

RUN apt-get update \
    && apt-get install -y --no-install-recommends apache2 \
    && rm -rf /var/lib/apt/lists/*

COPY server/setup-full*.run /tmp/setup-full.run

RUN chmod 755 /tmp/setup-full.run \
    && chmod +x /tmp/setup-full.run \
    && /tmp/setup-full.run --mode unattended --enable-components ws \
    && rm /tmp/setup-full.run

ENV SERVER_VERSION=${VERSION}

RUN mkdir -p /var/www/mcp-api /var/www/html \
    && printf 'ok\n' > /var/www/html/health \
    && printf 'Listen 127.0.0.1:8081\n' > /etc/apache2/ports.conf \
    && rm -f /etc/apache2/sites-enabled/000-default.conf \
    && printf '%s\n' \
       '<VirtualHost 127.0.0.1:8081>' \
       '    DocumentRoot /var/www/html' \
       '    <Directory "/var/www/html">' \
       '        Require all granted' \
       '    </Directory>' \
       '</VirtualHost>' \
       > /etc/apache2/sites-available/1c-api.conf \
    && ln -sf ../sites-available/1c-api.conf /etc/apache2/sites-enabled/1c-api.conf

COPY web/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8081

CMD ["/entrypoint.sh"]
