"helper function to update switch settings from a solution"
function _update_switch_settings!(data::Dict{String,<:Any}, solution::Dict{String,<:Any})
    for (id, switch) in get(solution, "switch", Dict{String,Any}())
        if haskey(switch, "state")
            data["switch"][id]["state"] = switch["state"]
        end
    end
end


"helper function to update storage capacity for the next subnetwork based on a solution"
function _update_storage_capacity!(data::Dict{String,<:Any}, solution::Dict{String,<:Any})
    for (i, strg) in get(solution, "storage", Dict())
        data["storage"][i]["_energy"] = deepcopy(data["storage"][i]["energy"])
        data["storage"][i]["energy"] = strg["se"]
    end
end


"""
    apply_switch_solutions!(network::Dict{String,<:Any}, optimal_switching_results::Dict{String,<:Any})::Dict{String,Any}

Updates a multinetwork `network` in-place with the results from optimal switching `optimal_switching_results`.

Used when not using the in-place version of [`optimize_switches!`](@ref optimize_switches!).
"""
function apply_switch_solutions!(network::Dict{String,<:Any}, optimal_switching_results::Dict{String,<:Any})::Dict{String,Any}
    network = apply_switch_solutions(network, optimal_switching_results)
end


"""
    apply_switch_solutions(network::Dict{String,<:Any}, optimal_switching_results::Dict{String,<:Any})::Dict{String,Any}

Creates a copy of the `network` with the solution copied in from `optimal_switching_results`
"""
function apply_switch_solutions(network::Dict{String,<:Any}, optimal_switching_results::Dict{String,<:Any})::Dict{String,Any}
    mn_data = deepcopy(network)
    for (n,nw) in mn_data["nw"]
        _update_switch_settings!(nw, get(get(optimal_switching_results, n, Dict{String,Any}()), "solution", Dict{String,Any}()))
        _update_storage_capacity!(nw, get(get(optimal_switching_results, n, Dict{String,Any}()), "solution", Dict{String,Any}()))
    end
    return mn_data
end


"""
    build_result(aim::AbstractUnbalancedPowerModel, solve_time; solution_processors=[])

Version of `InfrastructureModels.build_result` that includes `"mip_gap"` in the results dictionary, if it exists
"""
function _IM.build_result(aim::AbstractSwitchModels, solve_time; solution_processors=[])
    # try-catch is needed until solvers reliably support ResultCount()
    result_count = 1
    try
        result_count = JuMP.result_count(aim.model)
    catch
        @warn "the given optimizer does not provide the ResultCount() attribute, assuming the solver returned a solution which may be incorrect."
    end

    solution = Dict{String,Any}()

    if result_count > 0
        solution = _IM.build_solution(aim, post_processors=solution_processors)
    else
       @warn "model has no results, solution cannot be built"
    end

    result = Dict{String,Any}(
        "optimizer" => JuMP.solver_name(aim.model),
        "termination_status" => JuMP.termination_status(aim.model),
        "primal_status" => JuMP.primal_status(aim.model),
        "dual_status" => JuMP.dual_status(aim.model),
        "objective" => _IM._guard_objective_value(aim.model),
        "objective_lb" => _IM._guard_objective_bound(aim.model),
        "solve_time" => solve_time,
        "solution" => solution,
    )

    mip_gap = NaN
    try
        mip_gap = JuMP.relative_gap(aim.model)
    catch
    end
    result["mip_gap"] = mip_gap

    return result
end


"""
"""
function solution_reference_buses!(pm::AbstractUnbalancedPowerModel, sol::Dict{String,Any})
    PMD.apply_pmd!(_solution_reference_buses!, pm.data, sol; apply_to_subnetworks=true)
end


"""
"""
function _solution_reference_buses!(data::Dict{String,<:Any}, sol::Dict{String,<:Any})
    if !haskey(sol, "bus") && !isempty(get(data, "bus", Dict()))
        sol["bus"] = Dict{String,Any}()
    end
    for (i,bus) in get(data, "bus", Dict())
        if bus[PMD.pmd_math_component_status["bus"]] != PMD.pmd_math_component_status_inactive["bus"]
            if !haskey(sol["bus"], i)
                sol["bus"][i] = Dict{String,Any}()
            end
            sol["bus"][i]["bus_type"] = bus["bus_type"]
        end
    end
end
