"""
    _update_switch_settings!(data::Dict{String,<:Any}, solution::Dict{String,<:Any})

Helper function to update switch settings from a solution, for the rolling horizon algorithm.
"""
function _update_switch_settings!(data::Dict{String,<:Any}, solution::Dict{String,<:Any})
    for (id, switch) in get(solution, "switch", Dict{String,Any}())
        if haskey(switch, "state")
            data["switch"][id]["state"] = switch["state"]
        end
    end
end


"""
    _update_storage_capacity!(data::Dict{String,<:Any}, solution::Dict{String,<:Any})

Helper function to update storage capacity for the next subnetwork based on a solution, for the rolling horizon algorithm.
"""
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

Creates a copy of the `network` with the solution copied in from `optimal_switching_results`.
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

Version of `InfrastructureModels.build_result` that includes `"mip_gap"` in the results dictionary, if it exists.
"""
function _IM.build_result(aim::AbstractUnbalancedPowerModel, solve_time; solution_processors=[])
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
    solution_reference_buses!(pm::AbstractUnbalancedPowerModel, sol::Dict{String,Any})

Raises `bus_type` from math model up to solution for reporting, across all time steps.
"""
function solution_reference_buses!(pm::AbstractUnbalancedPowerModel, sol::Dict{String,Any})
    if !PMD.ismultinetwork(PMD.get_pmd_data(pm.data)) && PMD.ismultinetwork(PMD.get_pmd_data(sol))
        _sol = PMD.get_pmd_data(sol)["nw"]["0"]
    else
        _sol = sol
    end

    PMD.apply_pmd!(_solution_reference_buses!, pm.data, _sol; apply_to_subnetworks=true)
end


"""
    _solution_reference_buses!(data::Dict{String,<:Any}, sol::Dict{String,<:Any})

Raises `bus_type` from math model up to solution for reporting, from a single time step.
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


"""
    solution_statuses!(pm::AbstractUnbalancedPowerModel, sol::Dict{String,Any})

Converts all `status` fields in a solution `sol` from Float64 to `Status` enum, for all time steps.
"""
function solution_statuses!(pm::AbstractUnbalancedPowerModel, sol::Dict{String,Any})
    PMD.apply_pmd!(_solution_statuses!, sol; apply_to_subnetworks=true)
end


"""
    _solution_statuses!(sol::Dict{String,<:Any})

Converts all `status` fields in a solution `sol` from Float64 to `Status` enum, for a single time step.
"""
function _solution_statuses!(sol::Dict{String,<:Any})
    for type in PMD.pmd_math_asset_types
        for (i,obj) in get(sol, type, Dict{String,Any}())
            if haskey(obj, "status") && isa(obj["status"], Real)
                sol[type][i]["status"] = PMD.Status(round(Int, obj["status"]))
            end
        end
    end
end


"""
    solution_inverter!(pm::AbstractUnbalancedPowerModel, sol::Dict{String,Any})

Converts `inverter` to Inverter enum, across all time steps.
"""
function solution_inverter!(pm::AbstractUnbalancedPowerModel, sol::Dict{String,Any})
    if !PMD.ismultinetwork(PMD.get_pmd_data(pm.data)) && PMD.ismultinetwork(PMD.get_pmd_data(sol))
        _sol = PMD.get_pmd_data(sol)["nw"]["0"]
    else
        _sol = sol
    end

    PMD.apply_pmd!(_solution_inverter!, pm.data, _sol; apply_to_subnetworks=true)
end


"""
    _solution_inverter!(data::Dict{String,<:Any}, sol::Dict{String,<:Any})

Converts `inverter` to Inverter enum, from a single time step.
"""
function _solution_inverter!(data::Dict{String,<:Any}, sol::Dict{String,<:Any})
    for t in ["gen", "storage"]
        if haskey(sol, t)
            for (_,obj) in sol[t]
                if haskey(obj, "inverter")
                    obj["inverter"] = Inverter(round(Int, obj["inverter"]))
                end
            end
        end
    end
end


"""
    solution_blocks!(pm::AbstractUnbalancedPowerModel, sol::Dict{String,Any})

Adds block ids (as generated in the ref), and microgrid_ids to the solution
"""
function solution_blocks!(pm::AbstractUnbalancedPowerModel, sol::Dict{String,Any})
    PMD.apply_pmd!(PowerModelsONM._solution_blocks!, sol, pm.ref; apply_to_subnetworks=true)
end


"""
    _solution_statuses!(sol::Dict{String,<:Any}, ref::Dict{Symbol,<:Any})

Adds block ids (as generated in the `ref`), and microgrid_ids to the solution
"""
function _solution_blocks!(sol::Dict{String,<:Any}, ref::Dict{Symbol,<:Any})
    for (id, block) in ref[:blocks]
        for bus_id in block
            sol["bus"]["$bus_id"]["block_id"] = id
            if id in keys(ref[:microgrid_blocks])
                sol["bus"]["$bus_id"]["microgrid_id"] = ref[:microgrid_blocks][id]
            end
        end
    end

    for t in [:load, :gen, :storage]
        for (id,_) in ref[t]
            block_id = ref[Symbol("$(t)_block_map")][id]
            sol[string(t)]["$id"]["block_id"] = block_id
            if block_id in keys(ref[:microgrid_blocks])
                sol[string(t)]["$id"]["microgrid_id"] = ref[:microgrid_blocks][block_id]
            end
        end
    end
end


"""
    PowerModelsDistribution.apply_pmd!(func!::Function, data::Dict{String,<:Any}, ref::Dict{Symbol,<:Any}; apply_to_subnetworks::Bool=true, kwargs...)

Version of `apply_pmd!` that supports `ref::Dict{Symbol,<:Any}`
"""
function PMD.apply_pmd!(func!::Function, data::Dict{String,<:Any}, ref::Dict{Symbol,<:Any}; apply_to_subnetworks::Bool=true, kwargs...)
    data_it = _IM.ismultiinfrastructure(data) ? data["it"][PMD.pmd_it_name] : data
    ref_it = _IM.ismultiinfrastructure(ref) ? ref[:it][PMD.pmd_it_sym] : ref

    if PMD.ismultinetwork(data_it) && apply_to_subnetworks
        @assert PMD.ismultinetwork(ref_it)
        for (nw, nw_data) in data_it["nw"]
            func!(nw_data, ref_it[:nw][parse(Int, nw)]; kwargs...)
        end
    else
        func!(data_it, ref_it; kwargs...)
    end
end


"""
    InfrastructureModels.ismultiinfrastructure(ref::Dict{Symbol,<:Any})

version of `ismultiinfrastructure` that works on `ref::Dict{Symbol,<:Any}`
"""
function _IM.ismultiinfrastructure(ref::Dict{Symbol,<:Any})
    haskey(ref, :it)
end


"""
    PowerModelsDistribution.ismultinetwork(ref::Dict{Symbol,<:Any})

Version of `ismultinetwork` that works on `ref::Dict{Symbol,<:Any}`
"""
function PMD.ismultinetwork(ref::Dict{Symbol,<:Any})
    haskey(ref, :nw)
end
