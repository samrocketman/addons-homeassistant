#
# Build wireguard-ui from source
#
ARG BUILD_FROM
FROM ${BUILD_FROM}
FROM golang:1.21-alpine3.19 AS builder
SHELL ["/bin/sh", "-exc"]
ENV APP_VERSION="WireGuard UI For Home Assistant"
ENV GIT_REPO=https://github.com/ngoduykhanh/wireguard-ui
ENV GIT_COMMIT=2fdafd34ca6c8f7f1415a3a1d89498bb575a7171
# you should potentially disable APPLY_PATCHES if changing GIT_COMMIT
ENV APPLY_PATCHES=true
RUN apk add --update --no-cache npm yarn curl patch
WORKDIR /build
#Download source code
RUN \
  curl -sSfL "${GIT_REPO}/archive/${GIT_COMMIT}.tar.gz" | \
    tar --no-same-owner -xzC /build --strip-components=1
# Apply patches which make sense
RUN \
  if [ ! "${APPLY_PATCHES}" = true ]; then touch /applied_patches; exit 0; fi; \
  apply_patch() { \
    if [ ! "$#" = 2 ]; then echo ERROR: apply_patch expects 2 arguments >&2; fi; \
    curl -sSfL "${GIT_REPO}/compare/${GIT_COMMIT}...${1}.patch" | \
      awk '$1 ~ /^diff/ {out=1}; out == 1 {print}' | \
      patch -p1; \
      if [ ! -f /applied_patches ]; then \
        echo 'Built from source:' >> /applied_patches; \
        echo "  Repository: ${GIT_REPO}" >> /applied_patches; \
        echo "  Git commit: ${GIT_COMMIT}" >> /applied_patches; \
        echo 'Applied Patches:' >> /applied_patches; \
      fi; \
      echo "  $2" >> /applied_patches; \
      echo "    Applied from commit: $1" >> /applied_patches; \
  }; \
  apply_patch 0035475214914514bce030df7c3cea8e4b25fed4 "PR673: Fix PreUp, PostUp, PreDown, and PostDown; https://github.com/ngoduykhanh/wireguard-ui/pull/673"; \
  apply_patch 9b0ad608086d6e491710856f0455787131f5ab5f "PR671: Dark mode UI; https://github.com/ngoduykhanh/wireguard-ui/pull/671"; \
  apply_patch 36be3a7ac9b3dcbeea3fb8724fd5db4acb94eaa1 "PR670: Rename session tokens to have wgui prefix; https://github.com/ngoduykhanh/wireguard-ui/pull/670"; \
  apply_patch b3ff328afc56bf449c022454f9a1243f167ce742 "PR660: Fix default MTU to 1420; https://github.com/ngoduykhanh/wireguard-ui/pull/660"; \
  apply_patch 8b75583a0470035d93320fc14c8d8e7f69e4a61a "PR653: Add login logging for banning brute force attacks; https://github.com/ngoduykhanh/wireguard-ui/pull/653"; \
  apply_patch 3064ec79a6710a2956596a69c80ba0c24d408ed7 "PR573: Update about.html to open page in a new tab; https://github.com/ngoduykhanh/wireguard-ui/pull/573"
# Prepare assets
RUN yarn install --pure-lockfile --production && \
    yarn cache clean
# Move admin-lte dist
RUN mkdir -p assets/dist/js assets/dist/css && \
    cp /build/node_modules/admin-lte/dist/js/adminlte.min.js \
    assets/dist/js/adminlte.min.js && \
    cp /build/node_modules/admin-lte/dist/css/adminlte.min.css \
    assets/dist/css/adminlte.min.css
# Move plugin assets
RUN mkdir -p assets/plugins && \
    cp -r /build/node_modules/admin-lte/plugins/jquery/ \
    /build/node_modules/admin-lte/plugins/fontawesome-free/ \
    /build/node_modules/admin-lte/plugins/bootstrap/ \
    /build/node_modules/admin-lte/plugins/icheck-bootstrap/ \
    /build/node_modules/admin-lte/plugins/toastr/ \
    /build/node_modules/admin-lte/plugins/jquery-validation/ \
    /build/node_modules/admin-lte/plugins/select2/ \
    /build/node_modules/jquery-tags-input/ \
    assets/plugins/
# Move custom assets
RUN cp -r /build/custom/ assets/
# Build
RUN \
  flags="-X 'main.gitRef=refs/heads/master'"; \
  flags="${flags} -X 'main.appVersion=${APP_VERSION}'"; \
  flags="${flags} -X 'main.buildTime=$(date)'"; \
  flags="${flags} -X 'main.gitCommit=${GIT_COMMIT}'"; \
  CGO_ENABLED=0 go build -ldflags="${flags}" -a -o /wireguard-ui .

#
# Home Assistant Add-on
#
FROM ${BUILD_FROM}
SHELL ["/bin/bash", "-exo", "pipefail", "-c"]
RUN \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    ca-certificates \
    inotify-tools \
    iptables \
    nginx \
    python3 \
    wireguard-tools; \
  rm -fr \
    /tmp/* \
    /var/{cache,log}/* \
    /var/lib/apt/lists/* \
    /etc/nginx
RUN \
  mkdir -p /var/log/nginx; \
  touch /var/log/nginx/error.log
COPY --from=builder /wireguard-ui /wireguard-ui
COPY --from=builder /applied_patches /applied_patches
COPY rootfs /
