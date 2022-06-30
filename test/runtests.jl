using Distributed

Distributed.addprocs(3)

@everywhere using PowerModelsONM

import JSON
import PowerModelsDistribution as PMD

using Test

silence!()

@testset "PowerModelsONM" begin
    # initialization
    include("args.jl")
    include("schema.jl")

    # inputs
    include("io.jl")
    include("data.jl")

    # problems
    include("mld.jl")
    include("opf.jl")
    include("faults.jl")
    include("stability.jl")

    # full workflow and outputs
    include("stats.jl")
end
