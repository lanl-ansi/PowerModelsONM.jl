"""
    optimize_switches!(args::Dict{String,<:Any})

Optimizes switch states (therefore shedding load or not) in-place, for use in [`entrypoint`](@ref entrypoint),
using [`optimize_switches`]

Uses LPUBFDiagPowerModel (LinDist3Flow), and therefore requires `args["solvers"]["misocp_solver"]` to be specified
"""
function optimize_switches!(args::Dict{String,<:Any})::Dict{String,Any}
    results = Dict{String,Any}()
    ns = sort([parse(Int, i) for i in keys(args["network"]["nw"])])
    @showprogress length(ns) "Running switch optimization (mld)... " for n in ns
        nw = args["network"]["nw"]["$n"]

        nw["data_model"] = args["network"]["data_model"]

        if haskey(results, "$(n-1)") && haskey(results["$(n-1)"], "solution")
            _update_switch_settings!(nw, results["$(n-1)"]["solution"])
            _update_storage_capacity!(nw, results["$(n-1)"]["solution"])
        end

        prob = get(args, "gurobi", false) ? solve_mc_osw_mld_mi_indicator : solve_mc_osw_mld_mi

        results["$n"] = optimize_switches(nw, prob, args["solvers"]["misocp_solver"])

        delete!(nw, "data_model")

        if haskey(results["$n"], "solution")
            _update_switch_settings!(nw, results["$n"]["solution"])
        end
    end

    args["optimal_switching_results"] = results
end


"""
    optimize_switches(subnetwork::Dict{String,<:Any}, prob::Function, solver; formulation=PMD.LPUBFDiagPowerModel)::Dict{String,Any}

Optimizes switch states for load shedding on a single subnetwork (not a multinetwork), using `prob` ([`solve_mc_osw_mld_mi`](@ref solve_mc_osw_mld_mi)
or [`solve_mc_osw_mld`](@ref solve_mc_osw_mld)), `solver`.

Optionally, a PowerModelsDistribution `formulation` can be set independently, but is LinDist3Flow by default.
"""
function optimize_switches(subnetwork::Dict{String,<:Any}, prob::Function, solver; formulation=PMD.LPUBFDiagPowerModel)::Dict{String,Any}
    prob(subnetwork, formulation, solver; solution_processors=[PMD.sol_data_model!], ref_extensions=[ref_add_load_blocks!])
end
