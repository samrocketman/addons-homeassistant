#
# Build wireguard-ui from source
#
ARG BUILD_FROM
FROM ${BUILD_FROM:-ghcr.io/hassio-addons/debian-base/amd64:7.8.3}

FROM node:14.5-alpine AS frontend
SHELL ["/bin/sh", "-exc"]
# build from https://github.com/JordanKnott/taskcafe/pull/135/commits/c12a74592941e2038ca2a63b598a53ad108f039b
RUN \
  apk --no-cache add curl git; \
  git clone https://github.com/JordanKnott/taskcafe /usr/src/taskcafe; \
  cd /usr/src/taskcafe; \
  git fetch origin +refs/pull/135/head:refs/pull/135/head; \
  git checkout c12a74592941e2038ca2a63b598a53ad108f039b
WORKDIR /usr/src/taskcafe/frontend
RUN yarn install
RUN yarn build

FROM golang:1.25.6-alpine AS builder
COPY --from=frontend /usr/src/taskcafe /usr/src/taskcafe
WORKDIR /usr/src/taskcafe
RUN go mod download
RUN go run cmd/mage/main.go backend:genFrontend backend:genMigrations backend:build

#
# Home Assistant Add-on
#
FROM ${BUILD_FROM:-ghcr.io/hassio-addons/debian-base/amd64:7.8.3}
SHELL ["/bin/bash", "-exo", "pipefail", "-c"]
RUN \
  sed -i 's/deb.debian.org\/debian$/mirror.rit.edu\/debian/' /etc/apt/sources.list.d/debian.sources; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    ca-certificates \
    nginx \
    postgresql-15; \
  rm -fr \
    /tmp/* \
    /var/{cache,log}/* \
    /var/lib/apt/lists/* \
    /etc/nginx
RUN \
  mkdir -p /var/log/nginx; \
  touch /var/log/nginx/error.log
COPY --from=builder /usr/src/taskcafe/dist/taskcafe /taskcafe
COPY rootfs /
