FROM julia:1.8.2

RUN apt-get update && \
    apt-get -y --no-install-recommends install build-essential gcc fontconfig-config git

# Julia env
ADD Project.toml /

# Source code
ADD src /src
ADD schemas /schemas
ADD test /test

# License
ADD LICENSE.md LICENSE

# Update Julia General registry
ENV JULIA_PKG_SERVER=""
RUN git clone https://github.com/julia-actions/julia-buildpkg.git
RUN julia --color=yes julia-buildpkg/add_general_registry.jl
RUN rm -rf julia-buildpkg

# Instantiate Julia Env
RUN julia --color=yes --project=/ -e 'using Pkg; Pkg.instantiate(); Pkg.build(verbose=true); Pkg.precompile();'

# Set entrypoint
ENTRYPOINT [ "julia", "--sysimage-native-code=yes", "--project=/", "/src/cli/entrypoint.jl" ]
