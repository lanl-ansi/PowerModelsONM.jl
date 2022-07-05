"""
    get_timestep_microgrid_networks_from_output_file(output::String, network::Dict{String,<:Any})::Vector{Vector{Vector{String}}}

Analytics for determining when microgrids network from output file
"""
function get_timestep_microgrid_networks_from_output_file(output_file::String, network::Dict{String,<:Any})::Vector{Vector{Vector{String}}}
    output = JSON.parsefile(output_file)

    actions = get(output, "Device action timestep", [])

    switch_config = Dict{String,PMD.SwitchState}[]

    for timestep in actions
        _switch_config = Dict{String,PMD.SwitchState}()
        for (id, state) in get(timestep, "Switch configurations", Dict())
            _switch_config[id] = Dict("closed"=>PMD.CLOSED, "open"=>PMD.OPEN)[lowercase(state)]
        end
        push!(switch_config, _switch_config)
    end

    return get_timestep_microgrid_networks(switch_config, network)
end


"""
    get_timestep_microgrid_networks!(args::Dict{String,<:Any})::Vector{Dict{String,Any}}

Collects microgrid networks per timestep and assigns them to 'Device action timestep'/'Microgrid networks'
"""
function get_timestep_microgrid_networks!(args::Dict{String,<:Any})::Union{Vector{Dict{String,Any}},Nothing}
    if isa(get(args, "network", ""), Dict)
        args["output_data"]["Device action timeline"] = recursive_merge_timesteps(args["output_data"]["Device action timeline"], [Dict{String,Vector{Vector{String}}}("Microgrid networks" => _mg_networks) for _mg_networks in get_timestep_microgrid_networks(get(args, "network", Dict{String,Any}()), get(args, "optimal_switching_results", Dict{String,Any}()))])
    end
end


"""
    get_timestep_microgrid_networks(network::Dict{String,Any}, switching_results::Dict{String,Any})::Vector{Vector{Vector{String}}}

Collects microgrid networks per timestep
"""
function get_timestep_microgrid_networks(network::Dict{String,Any}, switching_results::Dict{String,Any})::Vector{Vector{Vector{String}}}
    mn_data = deepcopy(network)

    microgrid_networks = Vector{Vector{Vector{String}}}()
    for n in sort(parse.(Int, collect(keys(get(mn_data, "nw", Dict())))))
        nw = mn_data["nw"]["$n"]
        nw["data_model"] = mn_data["data_model"]

        sr = get(get(switching_results, "$n", Dict{String,Any}()), "solution", Dict{String,Any}())
        switch_config = Dict{String,PMD.SwitchState}(s => get(sw, "state", nw["switch"][s]["state"]) for (s,sw) in get(sr, "switch", Dict{String,Any}()))

        push!(microgrid_networks, get_microgrid_networks(nw; switch_config=switch_config))
    end

    return microgrid_networks
end


"""
    get_microgrid_networks(network::Dict{String,Any}; switch_config::Union{Missing,Dict{String,PMD.SwitchState}}=missing)::Vector{Vector{String}}

Collects microgrid networks in a single timestep
"""
function get_microgrid_networks(network::Dict{String,Any}; switch_config::Union{Missing,Dict{String,PMD.SwitchState}}=missing)::Vector{Vector{String}}
    @assert !PMD.ismultinetwork(network)

    data = deepcopy(network)

    if !ismissing(switch_config)
        for (s, state) in switch_config
            data["switch"][s]["state"] = state
        end
    end

    mg_networks = Set{Set{String}}()
    for block in PMD.identify_blocks(data)
        _mg_network = Set{String}()
        for bus in block
            if !isempty(get(data["bus"][bus], "microgrid_id", ""))
                push!(_mg_network, data["bus"][bus]["microgrid_id"])
            end
        end
        if !isempty(_mg_network)
            push!(mg_networks, _mg_network)
        end
    end

    return collect.(mg_networks)
end
