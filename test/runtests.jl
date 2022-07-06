using Distributed

Distributed.addprocs(3)

@everywhere using PowerModelsONM

import JSON
import PowerModelsDistribution as PMD

import Juniper
import Ipopt
import HiGHS

minlp_solver = optimizer_with_attributes(
    Juniper.Optimizer,
    "nl_solver" => optimizer_with_attributes(Ipopt.Optimizer, "tol"=>1e-4, "mu_strategy"=>"adaptive", "print_level"=>0),
    "mip_solver" => optimizer_with_attributes(
        HiGHS.Optimizer,
        "presolve" => "off",
        "primal_feasibility_tolerance" => 1e-4,
        "dual_feasibility_tolerance" => 1e-4,
        "mip_feasibility_tolerance" => 1e-4,
        "mip_rel_gap" => 0.0001,
        "small_matrix_value" => 1e-12,
        "allow_unbounded_or_infeasible" => true,
        "output_flag" => false,
        "random_seed" => 1,
    ),
    "mip_gap" => 0.0001,
    "atol" => 1e-3,
    "allow_almost_solved_integral" => true,
    "allow_almost_solved" => true,
    "feasibility_pump" => true,
    "seed" => 1,
    "log_levels" => [],
)

using Test

silence!()

@testset "PowerModelsONM" begin
    # initialization
    include("args.jl")
    include("schema.jl")

    # inputs
    include("io.jl")
    include("data.jl")
    include("graphml.jl")

    # problems
    include("mld.jl")
    include("nlp.jl")
    include("opf.jl")
    include("faults.jl")
    include("stability.jl")

    # full workflow and outputs
    include("stats.jl")
end
