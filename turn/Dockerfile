FROM debian:bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends coturn ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY turn/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 3478/tcp 3478/udp 49160-49200/tcp 49160-49200/udp

ENTRYPOINT ["/entrypoint.sh"]
