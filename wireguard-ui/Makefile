.PHONY: check goss

check:
	  docker build --build-arg BUILD_FROM="$$(yq '.build_from.amd64' build.yaml)" -t hassio_wg .
	  docker run --rm --entrypoint '' hassio_wg nginx -v
	  docker run --rm --entrypoint '' hassio_wg /bin/bash -c "sed -i 's/%%interface%%/127.0.0.1/' /etc/nginx/servers/ingress.conf; nginx -t"

goss:
	docker run -v "$(PWD):/mnt" -w /mnt -v "$(HOME)/usr/bin/goss":/goss --rm --entrypoint '' hassio_wg /goss validate
