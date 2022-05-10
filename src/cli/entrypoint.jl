using Distributed: @everywhere, addprocs

import ArgParse

include("arguments.jl")

args = parse_commandline(; validate=false)

if get(args, "nprocs", 1) > 1
    addprocs(args["nprocs"]-1)

    @everywhere import Pkg
    @everywhere Pkg.activate(joinpath(@__DIR__), "..", "..")
end

# TODO: Remove use-gurobi when it gets removed from depreciated CLI Arguments
if get(args, "gurobi", false) || get(args, "use-gurobi", false)
    @everywhere import Gurobi
end

if get(args, "knitro", false)
    @everywhere import KNITRO
end

@everywhere import PowerModelsONM

if isinteractive() == false
    PowerModelsONM.entrypoint(args)
end
