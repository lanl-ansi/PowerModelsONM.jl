"""
    optimize_switches!(args::Dict{String,<:Any})::Dict{String,Any}

Optimizes switch states (therefore shedding load or not) in-place, for use in [`entrypoint`](@ref entrypoint),
using [`optimize_switches`]

Uses LPUBFDiagPowerModel (LinDist3Flow), and therefore requires `args["solvers"]["misocp_solver"]` to be specified
"""
function optimize_switches!(args::Dict{String,<:Any})::Dict{String,Any}
    args["optimal_switching_results"] = optimize_switches(
        args["network"],
        args["solvers"][get_setting(args, ("options", "problem", "operations-solver"), "mip_solver")];
        formulation=parse(AbstractUnbalancedPowerModel, (get_setting(args, ("options","problem","operations-formulation"), "LPUBFDiagPowerModel"))),
        algorithm=get_setting(args, ("options", "problem", "operations-algorithm"), "full-lookahead"),
        problem=get_setting(args, ("options", "problem", "operations-problem-type"), "block")
    )
end


"""
    optimize_switches(
        network::Dict{String,<:Any},
        solver;
        formulation::Type=PMD.LPUBFDiagPowerModel,
        algorithm::String="full-lookahead"
    )::Dict{String,Any}

- `algorithm::String`, if `"rolling-horizon"`, iterates over all subnetworks in a multinetwork data structure `network`, in order,
  and solves the optimal switching / MLD problem sequentially, updating the next timestep with the new switch configurations
  and storage energies from the solved timestep. Otherwise, if `"full-lookahead"`, will solve all time steps in a single optimization
  problem (default: `"full-lookahead"`)
"""
function optimize_switches(
    network::Dict{String,<:Any},
    solver;
    formulation::Type=PMD.LPUBFDiagPowerModel,
    algorithm::String="full-lookahead",
    problem::String="block"
    )::Dict{String,Any}
    results = Dict{String,Any}()

    @info "running $(algorithm)-$(problem) optimal switching algorithm with $(formulation)"
    if algorithm == "full-lookahead"
        prob = problem=="traditional" ? solve_mn_traditional_mld : solve_mn_block_mld
        _results = prob(
            network,
            formulation,
            solver
        )

        opt_results = filter(x->x.first!="solution", _results)
        results = Dict{String,Any}(n => merge(Dict{String,Any}("solution"=>nw), opt_results) for (n,nw) in get(get(_results, "solution", Dict{String,Any}()), "nw", Dict{String,Any}()))
    elseif algorithm == "rolling-horizon"
        mn_data = _prepare_optimal_switching_data(network)

        ns = sort([parse(Int, i) for i in keys(mn_data["nw"])])
        for n in ns
            if haskey(results, "$(n-1)") && haskey(results["$(n-1)"], "solution")
                _update_switch_settings!(mn_data["nw"]["$n"], results["$(n-1)"]["solution"])
                _update_storage_capacity!(mn_data["nw"]["$n"], results["$(n-1)"]["solution"])
            end

            results["$n"] = optimize_switches(mn_data["nw"]["$n"], problem=="traditional" ? solve_traditional_mld : solve_block_mld, solver; formulation=formulation)
        end
    elseif algorithm == "robust"
        mn_data = _prepare_optimal_switching_data(network)
        data = mn_data["nw"]["1"]
        data["switch_close_actions_ub"] = Inf
        data_math = transform_data_model(data)
        results["1"] = optimize_switches(data_math, solve_robust_block_mld, solver; formulation=formulation)
    else
        @warn "'algorithm=$(algorithm)' not recognized, skipping switch optimization"
    end

    return results
end


"""
    optimize_switches(
        subnetwork::Dict{String,<:Any},
        prob::Function,
        solver;
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
