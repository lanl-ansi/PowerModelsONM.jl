# Installation Guide

From Julia, PowerModelsONM is installed using the built-in package manager:

```julia
import Pkg
Pkg.add(Pkg.PackageSpec(; name="PowerModelsONM", url="https://github.com/lanl-ansi/PowerModelsONM.jl", rev="v1.0.0"))
```

From the command-line, outside Julia, one could download the repository, either via Github.com, or using git, i.e.,

```sh
git clone https://github.com/lanl-ansi/PowerModelsONM.jl.git
git checkout tags/v1.0.0
```

Then to install PowerModelsONM and its required packages

```sh
julia --project="path/to/PowerModelsONM" -e 'using Pkg; Pkg.instantiate(); Pkg.precompile();'
```

## Gurobi Configuration

To use Gurobi, and to install PowerModelsONM, a Gurobi binary in required on your system, as well as ENV variables defining where the Gurobi binary is, and where your Gurobi license file is, e.g., for Gurobi 9.10 on MacOS,

```sh
export GRB_LICENSE_FILE="$HOME/.gurobi/gurobi.lic"
export GUROBI_HOME="/Library/gurobi910/mac64"
```

## Installing __without__ Gurobi

To install PowerModelsONM without requiring a Gurobi binary / license, we need to remove Gurobi.jl from Project.toml, from the command line, before attempting to instantiate the package

```sh
julia --project="path/to/PowerModelsONM" -e 'using Pkg; Pkg.rm("Gurobi");'
```

This is not possible from within julia, so you must download the git repository locally first to install.

After Gurobi.jl is removed from the Project.toml in this way, you can install from the command line, as described above, or from within julia using

```julia
import Pkg
Pkg.add(path="path/to/PowerModelsONM")
```
