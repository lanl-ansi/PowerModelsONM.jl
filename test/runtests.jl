using PowerModelsONM

import Ipopt

using Test

@testset "PowerModelsONM" begin
    include("inputs.jl")
    include("data.jl")
    include("osw_mld.jl")
    include("opf.jl")
    include("fault_study.jl")
    include("stability.jl")
    include("protection.jl")
    include("outputs.jl")
end
