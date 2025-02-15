SWIFT_VERSION = 6.0

format:
  swift format . --recursive --in-place

docker-build:
  docker run \
    --rm \
    -v "$(PWD):$(PWD)" \
    -w "$(PWD)" \
    swift:$(SWIFT_VERSION) \
    bash -c "swift build"

.PHONY: format
