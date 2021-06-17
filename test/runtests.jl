using PowerModelsONM

import JSON
import PowerModelsDistribution

const PMD = PowerModelsDistribution

using Test

setup_logging!(Dict{String,Any}("quiet"=>true))

@testset "PowerModelsONM" begin
    # initialization
    include("args.jl")
    include("schema.jl")

    # inputs
    include("io.jl")
    include("data.jl")

    # problems
    include("osw.jl")
    include("opf.jl")
    include("faults.jl")
    include("stability.jl")

    # outputs
    include("stats.jl")

    # full workflow
    include("entrypoint.jl")
end
