.PHONY: test

TAG = latest

# build docker container
build-docker:
	docker build -f Dockerfile -t PowerModelsONM:dev ${CURDIR}

# TODO: build binary
build:
	echo "TODO"

# TODO: build unit tests, add network to docker container
test-docker:
	docker run PowerModelsONM:dev --verbose -n -o
