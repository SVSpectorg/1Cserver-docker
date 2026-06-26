FROM onec_base AS server

ARG VERSION
COPY setup-full*.run /tmp/setup-full.run

RUN chmod 755 /tmp/setup-full.run \
  && chmod +x /tmp/setup-full.run \
  && /tmp/setup-full.run --mode unattended --enable-components server \
  && rm /tmp/setup-full.run

ENV SERVER_VERSION=${VERSION}

# Копируем entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

RUN usermod -u 999 usr1cv8 && groupmod -g 1001 grp1cv8
USER usr1cv8
CMD ["/entrypoint.sh"]