using Distributed

Distributed.addprocs(3)

@everywhere using PowerModelsONM

# DEBUGGING
# cd("test"); import Gurobi; using PowerModelsONM

import JSON
import EzXML
import PowerModelsDistribution as PMD

import Juniper
import Ipopt
import HiGHS

minlp_solver = optimizer_with_attributes(
    Juniper.Optimizer,
    "nl_solver" => optimizer_with_attributes(Ipopt.Optimizer, "tol"=>1e-6, "print_level"=>0),
    "mip_solver" => optimizer_with_attributes(
        HiGHS.Optimizer,
        "primal_feasibility_tolerance" => 1e-6,
        "dual_feasibility_tolerance" => 1e-6,
        "mip_feasibility_tolerance" => 1e-6,
        "mip_rel_gap" => 0.0001,
        "small_matrix_value" => 1e-12,
        "allow_unbounded_or_infeasible" => true,
        "output_flag" => false,
        "random_seed" => 1,
    ),
    "mip_gap" => 0.0001,
    "atol" => 1e-6,
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
    @info "Running tests in args.jl"
    include("args.jl")
    @info "Running tests in schema.jl"
    include("schema.jl")

    # inputs
    @info "Running tests in io.jl"
    include("io.jl")
    @info "Running tests in data.jl"
    include("data.jl")
    @info "Running tests in graphml.jl"
    include("graphml.jl")

    # problems
    @info "Running tests in mld.jl"
    include("mld.jl")
    @info "Running tests in nlp.jl"
    include("nlp.jl")
    @info "Running tests in opf.jl"
    include("opf.jl")
    @info "Running tests in faults.jl"
    include("faults.jl")
    @info "Running tests in stability.jl"
    include("stability.jl")

    # full workflow and outputs
    @info "Running tests in stats.jl"
    include("stats.jl")
end
