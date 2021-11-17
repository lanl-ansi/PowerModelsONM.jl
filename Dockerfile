FROM julia:latest

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
RUN git clone https://github.com/julia-actions/julia-buildpkg.git
RUN julia --color=yes julia-buildpkg/add_general_registry.jl

# Instantiate Julia Env
RUN julia -O3 --color=yes --compiled-modules=yes --sysimage-native-code=yes --project=/ -e 'using Pkg; Pkg.Registry.update(); Pkg.update(); Pkg.instantiate(); Pkg.build();'

# PackageCompiler
RUN julia -q --project=/ -e 'using PackageCompiler; create_sysimage([:PowerModelsONM]; replace_default=true, cpu_target="generic");'

# Set entrypoint
ENTRYPOINT [ "julia", "--sysimage-native-code=yes", "--project=/", "/src/cli/entrypoint.jl" ]
