FROM julia:1.6.3

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
RUN rm -rf julia-buildpkg

# Instantiate Julia Env
RUN julia --color=yes --project=/ -e 'using Pkg; if VERSION >= v"1.1.0-rc1"; Pkg.build(verbose=true); else Pkg.build(); end'

# PackageCompiler
RUN julia -q --project=/ -e 'using PackageCompiler; create_sysimage([:PowerModelsONM]; replace_default=true, cpu_target="generic");'

# Set entrypoint
ENTRYPOINT [ "julia", "--sysimage-native-code=yes", "--project=/", "/src/cli/entrypoint.jl" ]
