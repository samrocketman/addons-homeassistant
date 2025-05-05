ARG BUILD_FROM
FROM $BUILD_FROM

FROM alpine as wg-ui
SHELL ["/bin/sh", "-exc"]
COPY download-utilities.yml ./
RUN \
  apk add bash; \
  wget -P /usr/local/bin https://raw.githubusercontent.com/samrocketman/yml-install-files/33f873043002ef1923859046652b284581b988b6/download-utilities.sh; \
  chmod 755 /usr/local/bin/download-utilities.sh; \
  download-utilities.sh
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-exo", "pipefail", "-c"]

RUN \
  apt-get update; \
  apt-get install -y --no-install-recommends \
        nginx \
        ca-certificates \
        wireguard-tools \
        iptables \
        inotify-tools \
        uuidgen-runtime \
	    && rm -fr \
        /tmp/* \
        /var/{cache,log}/* \
        /var/lib/apt/lists/* \
        /etc/nginx \
    \
    && mkdir -p /var/log/nginx \
    && touch /var/log/nginx/error.log

COPY --from=wg-ui /wireguard-ui /wireguard-ui

COPY rootfs /
