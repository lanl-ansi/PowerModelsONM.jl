"""
    microgrid_network_timeline(output::String, network::Dict{String,<:Any})::Vector{Vector{Vector{String}}}

Analytics for determining when microgrids network
"""
function microgrid_network_timeline(output::String, network::Dict{String,<:Any})::Vector{Vector{Vector{String}}}
    output = JSON.parsefile(output)

    actions = get(output, "Device action timeline", [])

    switch_config = Dict{String,PowerModelsDistribution.SwitchState}[]

    for timestep in actions
        _switch_config = Dict{String,PowerModelsDistribution.SwitchState}()
        for (id, state) in get(timestep, "Switch configurations", Dict())
            _switch_config[id] = Dict("closed"=>PowerModelsDistribution.CLOSED, "open"=>PowerModelsDistribution.OPEN)[lowercase(state)]
        end
        push!(switch_config, _switch_config)
    end

    return microgrid_network_timeline(switch_config, network)
end


"""
    microgrid_network_timeline(switch_config::Vector{Dict{String,PowerModelsDistribution.SwitchState}}, network::Dict{String,<:Any})::Vector{Vector{Vector{String}}}

Analytics for determining when microgrids network
"""
function microgrid_network_timeline(switch_config::Vector{Dict{String,PowerModelsDistribution.SwitchState}}, network::Dict{String,<:Any})::Vector{Vector{Vector{String}}}
    microgrid_groups = Vector{Vector{String}}[]

    mn_data = deepcopy(network)
    for (i, (n, nw)) in enumerate(mn_data["nw"])
        _microgrids_n = Vector{String}[]
        nw["data_model"] = mn_data["data_model"]
        for (id, state) in switch_config[i]
            nw["switch"][id]["state"] = state
        end

        islands = PowerModelsDistribution.identify_blocks(nw)

        for island in islands
            _microgrids = String[]
            for bus in island
                if !isempty(get(nw["bus"][bus], "microgrid_id", ""))
                    push!(_microgrids, nw["bus"][bus]["microgrid_id"])
                end
            end
            if !isempty(_microgrids)
                push!(_microgrids_n, unique(_microgrids))
            end
        end
        push!(microgrid_groups, _microgrids_n)
    end

    return microgrid_groups
end


"""
"""
function microgrid_network_timeline(args::Dict{String,<:Any})
    switching_results = get(args, "optimal_switching_results", Dict())
    network = get(args, "network", Dict{String,Any}())

    # TODO
end
