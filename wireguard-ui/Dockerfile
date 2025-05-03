ARG BUILD_FROM
FROM $BUILD_FROM

FROM "ngoduykhanh/wireguard-ui:0.6.2" as wg-ui
FROM ${BUILD_FROM}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN \
apt-get update \
&& \
apt-get install -y --no-install-recommends \
        nginx \
	    && rm -fr \
        /tmp/* \
        /var/{cache,log}/* \
        /var/lib/apt/lists/* \
        /etc/nginx \
    \
    && mkdir -p /var/log/nginx \
    && touch /var/log/nginx/error.log

COPY --from=wg-ui /app/wg-ui /wireguard-ui

COPY rootfs /
