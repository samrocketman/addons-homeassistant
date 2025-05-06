.PHONY: check

check:
	  docker build --build-arg BUILD_FROM="$$(yq '.build_from.amd64' build.yaml)" -t hassio_wg .
	  docker run --rm --entrypoint '' hassio_wg nginx -t
