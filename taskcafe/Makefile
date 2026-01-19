.PHONY: check goss goss-shell test schema shellcheck

test: check goss shellcheck schema

check:
	  docker build --build-arg BUILD_FROM="$$(yq '.build_from.amd64' build.yaml)" -t hassio_wg .
	  docker run --rm --entrypoint '' hassio_wg nginx -v
	  docker run --rm --entrypoint '' hassio_wg /bin/bash -c "sed -i 's/%%interface%%/127.0.0.1/' /etc/nginx/servers/ingress.conf; nginx -t"

goss:
	docker run -v "$(PWD):/mnt" -w /mnt -v "$(HOME)/usr/bin/goss":/goss --rm --entrypoint '' hassio_wg /goss -g tests/goss.yaml validate

goss-shell:
	docker run -it -v "$(PWD):/mnt" -w /mnt/tests -v "$(HOME)/usr/bin/goss":/goss --rm --entrypoint '' hassio_wg /bin/bash

schema:
	yq -P . config.yaml > /dev/null
	./tests/validate-schema.sh

shellcheck:
	shellcheck -e SC1008 rootfs/etc/services.d/refresh-wg/run
	shellcheck -e SC1008 rootfs/etc/services.d/nginx/run
	shellcheck -e SC1008 rootfs/etc/services.d/wireguard-ui/run
	shellcheck -e SC1008 rootfs/usr/local/share/service-functions.sh

serve:
	mkdir -p /tmp/data
	yq -o json .options config.yaml > /tmp/options.json
	docker run -v "/tmp/options.json:/data/options.json:ro" --cap-add NET_ADMIN --cap-add SYS_ADMIN -v "/tmp/data:/data" -p 127.0.0.1:8080:8099 --rm --entrypoint '' hassio_wg /bin/bash -c "find /data -type f -exec rm -f {} +; conf=/etc/nginx/servers/ingress.conf;sed -i '/deny/d' \$$conf; sed -i '/allow/d' \$$conf; sed -i 's/%%interface%%/0.0.0.0/' \$$conf; exec /init"
