.PHONY: test build build-docker test-docker

TAG = latest

# build docs
docs:
	julia --project=docs -e 'using Pkg; Pkg.develop(path=".")' && julia --project=docs make.jl && julia --project=docs -e 'using Pkg; Pkg.rm("PowerModelsONM")'

# build docs without building the Pluto notebooks
docs-fast:
		julia --project=docs -e 'using Pkg; Pkg.develop(path=".")' && julia --project=docs make.jl --fast && julia --project=docs -e 'using Pkg; Pkg.rm("PowerModelsONM")'

# build docker container
build-container:
	docker build -f Dockerfile -t powermodelsonm:${TAG} ${CURDIR}

# build binary
build-binary:
	julia -q --project=. -e 'using PackageCompiler; create_app(".", "build"; force=true);'

# test docker container
test-docker:
	docker run PowerModelsONM:latest --verbose -n "test/data/ieee13_feeder.dss" -e "test/data/ieee13_events.json" -o "test_output_docker.json"

test:
	julia --project=. -e 'using Pkg; Pkg.test()'
