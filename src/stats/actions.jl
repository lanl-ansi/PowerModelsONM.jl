"""
    get_timestep_device_actions!(args::Dict{String,<:Any})::Vector{Dict{String,Any}}

Gets the device actions at every timestep using [`get_timestep_device_actions`](@ref get_timestep_device_actions)
and applies it in place to args, for use in [`entrypoint`](@ref entrypoint).
"""
function get_timestep_device_actions!(args::Dict{String,<:Any})::Vector{Dict{String,Any}}
    args["output_data"]["Device action timeline"] = get_timestep_device_actions(get(args, "network", Dict{String,Any}()), get(args, "optimal_switching_results", Dict{String,Any}()))
end


"""
    get_timestep_device_actions(network::Dict{String,<:Any}, mld_results::Dict{String,<:Any})::Vector{Dict{String,Any}}

From the multinetwork `network`, determines the switch configuration at each timestep. If the switch does not exist
in `mld_results`, the state will default back to the state given in the original network. This could happen if the switch
is not dispatchable, and therefore `state` would not be expected in the results.

Will output Vector{Dict} where each Dict will contain `"Switch configurations"`, which is a Dict with switch names as keys,
and the switch state, `"open"` or `"closed"` as values, and `"Shedded loads"`, which is a list of load names that have been
shed at that timestep.
"""
function get_timestep_device_actions(network::Dict{String,<:Any}, optimal_switching_results::Dict{String,<:Any})::Vector{Dict{String,Any}}
    device_action_timeline = Dict{String,Any}[]

    for n in sort([parse(Int, k) for k in keys(get(network, "nw", Dict{String,Any}()))])
        _out = Dict{String,Any}(
            "Switch configurations" => Dict{String,String}(),
            "Shedded loads" => String[],
        )
        for (id, switch) in get(network["nw"]["$n"], "switch", Dict())
            switch_solution = get(get(get(get(optimal_switching_results, "$n", Dict()), "solution", Dict()), "switch", Dict()), id, Dict())
            _out["Switch configurations"][id] = lowercase(string(get(switch_solution, "state", switch["state"])))
        end

        for (id, load) in get(network["nw"]["$n"], "load", Dict())
            load_solution = get(get(get(get(optimal_switching_results, "$n", Dict()), "solution", Dict()), "load", Dict()), id, Dict())
            if round(Int, get(load_solution, "status", 1)) != 1
                push!(_out["Shedded loads"], id)
            end
        end

        push!(device_action_timeline, _out)
    end

    return device_action_timeline
end


"""
    get_timestep_switch_changes!(args::Dict{String,<:Any})::Vector{Vector{String}}

Gets the switch changes via [`get_timestep_switch_changes`](@ref get_timestep_switch_changes)
and applies it in-place to args, for use with [`entrypoint`](@ref entrypoint)
"""
function get_timestep_switch_changes!(args::Dict{String,<:Any})::Vector{Vector{String}}
    args["output_data"]["Switch changes"] = get_timestep_switch_changes(get(args, "network", Dict{String,Any}()), get(args, "optimal_switching_results", Dict{String,Any}()))
end


"""
    get_timestep_switch_changes(network::Dict{String,<:Any})::Vector{Vector{String}}

Gets a list of switches whose state has changed between timesteps (always expect the first timestep to be an empty list).
This expects the solutions from the MLD problem to have been merged into `network`
"""
function get_timestep_switch_changes(network::Dict{String,<:Any}, optimal_switching_results::Dict{String,<:Any}=Dict{String,Any}())::Vector{Vector{String}}
    switch_changes = Vector{String}[]

    _switch_states = Dict(parse(Int,n) => Dict(id => get(switch, "state", missing) for (id, switch) in get(nw, "switch", Dict())) for (n,nw) in get(network, "nw", Dict()))
    ns = sort([n for n in keys(_switch_states)])
    for (i,n) in enumerate(ns)
        _switch_changes = String[]
        for (id, switch_state0) in _switch_states[n]
            new_state = get(get(get(get(get(optimal_switching_results, "$n", Dict()), "solution", Dict()), "switch", Dict()), id, Dict()), "state", missing)
            if !ismissing(new_state)
                if new_state != switch_state0
                    push!(_switch_changes, id)
                    for j in ns[i]:ns[end]
                        _switch_states[j][id] = deepcopy(new_state)
                    end
                end
            end
        end
        push!(switch_changes, _switch_changes)
    end

    return switch_changes
end
