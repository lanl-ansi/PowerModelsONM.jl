"""
    optimize_switches!(args::Dict{String,<:Any})::Dict{String,Any}

Optimizes switch states (therefore shedding load or not) in-place, for use in [`entrypoint`](@ref entrypoint),
using [`optimize_switches`]

Uses LPUBFDiagPowerModel (LinDist3Flow), and therefore requires `args["solvers"]["misocp_solver"]` to be specified
"""
function optimize_switches!(args::Dict{String,<:Any})::Dict{String,Any}
    prob_opts = get(get(args["network"], "options", Dict()), "problem", Dict())
    solver = get(prob_opts, "operations-solver", "mip_solver")
    formulation = _get_formulation(get(prob_opts, "operations-formulation", PMD.LPUBFDiagPowerModel))
    algorithm = get(prob_opts, "operations-algorithm", "global")
    problem_type = get(prob_opts, "operations-problem-type", "block")

    args["optimal_switching_results"] = optimize_switches(
        args["network"],
        args["solvers"][solver];
        formulation=formulation,
        algorithm=algorithm,
        problem=problem_type
    )
end


"""
    optimize_switches(
        network::Dict{String,<:Any},
        solver;
        formulation::Type=PMD.LPUBFDiagPowerModel,
        algorithm::String="global"
    )::Dict{String,Any}

- `algorithm::String`, if `"iterative"`, iterates over all subnetworks in a multinetwork data structure `network`, in order,
  and solves the optimal switching / MLD problem sequentially, updating the next timestep with the new switch configurations
  and storage energies from the solved timestep. Otherwise, if `"global"`, will solve all time steps in a single optimization
  problem (default: `"global"`)
"""
function optimize_switches(network::Dict{String,<:Any}, solver; formulation::Type=PMD.LPUBFDiagPowerModel, algorithm::String="global", problem::String="block")::Dict{String,Any}
    results = Dict{String,Any}()

    @info "running $(algorithm)-$(problem) optimal switching algorithm with $(formulation)"
    if algorithm == "global"
        prob = problem=="traditional" ? solve_mn_traditional_mld : solve_mn_block_mld
        _results = prob(
            network,
            formulation,
            solver
        )

        opt_results = filter(x->x.first!="solution", _results)
        results = Dict{String,Any}(n => merge(Dict{String,Any}("solution"=>nw), opt_results) for (n,nw) in get(get(_results, "solution", Dict{String,Any}()), "nw", Dict{String,Any}()))
    elseif algorithm == "iterative"
        mn_data = _prepare_optimal_switching_data(network)

        ns = sort([parse(Int, i) for i in keys(mn_data["nw"])])
        @showprogress length(ns) "Running switch optimization (mld)... " for n in ns
            if haskey(results, "$(n-1)") && haskey(results["$(n-1)"], "solution")
                _update_switch_settings!(mn_data["nw"]["$n"], results["$(n-1)"]["solution"])
                _update_storage_capacity!(mn_data["nw"]["$n"], results["$(n-1)"]["solution"])
            end

            results["$n"] = optimize_switches(mn_data["nw"]["$n"], problem=="traditional" ? solve_traditional_mld : solve_block_mld, solver; formulation=formulation)
        end
    else
        @warn "'algorithm=$(algorithm)' not recognized, skipping switch optimization"
    end

    return results
end


"""
    optimize_switches(
        subnetwork::Dict{String,<:Any},
        prob::Function, solver;
        formulation=PMD.LPUBFDiagPowerModel
    )::Dict{String,Any}

Optimizes switch states for load shedding on a single subnetwork (not a multinetwork), using `prob`

Optionally, a PowerModelsDistribution `formulation` can be set independently, but is LinDist3Flow by default.
"""
function optimize_switches(subnetwork::Dict{String,<:Any}, prob::Function, solver; formulation=PMD.LPUBFDiagPowerModel)::Dict{String,Any}
    prob(
        subnetwork,
        formulation,
        solver
    )
end


"""
    _prepare_optimal_switching_data(network::Dict{String,<:Any})::Dict{String,Any}

Helper function to prepare optimal switching data structure.
"""
function _prepare_optimal_switching_data(network::Dict{String,<:Any})::Dict{String,Any}
    mn_data = deepcopy(network)
    for (n,nw) in mn_data["nw"]
        nw["data_model"] = mn_data["data_model"]
    end

    return mn_data
end
