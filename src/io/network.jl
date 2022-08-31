"""
    parse_network!(args::Dict{String,<:Any})::Dict{String,Any}

In-place version of [`parse_network`](@ref parse_network), returns the ENGINEERING multinetwork
data structure, which is available in `args` under `args["network"]`, and adds the non-expanded ENGINEERING
data structure under `args["base_network"]`
"""
function parse_network!(args::Dict{String,<:Any})::Dict{String,Any}
    if isa(args["network"], String)
        args["base_network"], args["network"] = parse_network(
            args["network"]
        )
    end

    return args["network"]
end


"""
    parse_network(
        network_file::String
    )::Tuple{Dict{String,Any},Dict{String,Any}}

Parses network file given by runtime arguments into its base network, i.e., not expanded into a multinetwork,
and multinetwork, which is the multinetwork `ENGINEERING` representation of the network.
"""
function parse_network(network_file::String; dss2eng_extensions=Function[], transformations=Function[], import_all=true, kwargs...)::Tuple{Dict{String,Any},Dict{String,Any}}
    eng = parse_file(
        network_file;
        dss2eng_extensions=dss2eng_extensions,
        transformations=transformations,
        import_all=import_all,
        kwargs...
    )

    mn_eng = make_multinetwork(eng)

    return eng, mn_eng
end


"""
    parse_file(network_file::String; dss2eng_extensions=Function[], transformations=Function[], import_all=true, kwargs...)

ONM version of `PowerModelsDistribution.parse_file`, which includes some `dss2eng_extensions` and `transformations` by default
"""
function parse_file(network_file::String; dss2eng_extensions=Function[], transformations=Function[], import_all=true, kwargs...)
    eng = PMD.parse_file(
        network_file;
        dss2eng_extensions=[
            PMP._dss2eng_solar_dynamics!,
            PMP._dss2eng_gen_dynamics!,
            PMP._dss2eng_curve!,
            PMP._dss2eng_fuse!,
            PMP._dss2eng_ct!,
            PMP._dss2eng_relay!,
            PMP._dss2eng_gen_model!,
            _dss2eng_protection_locations!,
            dss2eng_extensions...
        ],
        transformations=[PMD.apply_kron_reduction!, transformations...],
        import_all=import_all,
        kwargs...
    )

    # Add default switch_close_actions_ub
    eng["switch_close_actions_ub"] = Inf

    # TODO: add more elegant cost model adjustments
    for (id,obj) in get(eng, "solar", Dict())
        eng["solar"][id]["cost_pg_model"] = 2
        eng["solar"][id]["cost_pg_parameters"] = [0.0, 0.0]
    end

    # work-around for protection settings network model if fix-small-numbers is used
    for t in ["line", "switch"]
        for (id,obj) in get(eng, t, Dict())
            eng[t][id]["rs_orig"] = deepcopy(get(obj, "rs", zeros(length(obj["f_connections"]), length(obj["t_connections"]))))
            eng[t][id]["xs_orig"] = deepcopy(get(obj, "xs", zeros(length(obj["f_connections"]), length(obj["t_connections"]))))
        end
    end

    return eng
end


"""
    _dss2eng_protection!(
        eng::Dict{String,<:Any},
        dss::Dict{String,<:Any}
    )

Extension function for converting opendss protection into protection objects for protection optimization.
"""
function _dss2eng_protection_locations!(eng::Dict{String,<:Any}, dss::Dict{String,<:Any})
    for type in ["relay", "recloser", "fuse"]
        if !isempty(get(dss, type, Dict())) && !haskey(eng, type)
            eng[type] = Dict{String,Any}()
        end

        for (id, dss_obj) in get(dss, type, Dict())
            if !haskey(eng[type], id)
                eng[type][id] = Dict{String,Any}()
            end
            eng[type][id]["location"] = dss_obj["monitoredobj"]
            eng[type][id]["monitor_type"] = string(split(dss_obj["monitoredobj"], ".")[1])
        end
    end
end


const _pnm2eng_objects = Dict{String,Vector{String}}(
    "bus" => ["bus"],
    "line" => ["line", "switch"],
    "transformer" => ["transformer"],
    "source" => ["voltage_source", "storage", "generator", "solar"],
    "protection" => ["relay", "fuse", "recloser"],
)


"""
    get_protection_network_model!(args::Dict{String,<:Any})

Builds a network data model for use in Protection settings optimization.
"""
function get_protection_network_model!(args::Dict{String,<:Any})
    args["output_data"]["Protection settings"]["network_model"] = get_protection_network_model(get(args, "base_network", Dict{String,Any}()))
end


"""
    get_protection_network_model(base_eng::Dict{String,<:Any})

Builds a network data model for use in Protection optimization from the base network model `base_eng`.
"""
function get_protection_network_model(base_eng::Dict{String,<:Any})
    pnm = Dict{String,Vector{Dict{String,Any}}}(
        "bus" => Dict{String,Any}[],
        "line" => Dict{String,Any}[],
        "transformer" => Dict{String,Any}[],
        "source" => Dict{String,Any}[],
        "protection" => Dict{String,Any}[],
    )

    for type in _pnm2eng_objects["bus"]
        for (id,obj) in get(base_eng, type, Dict())
            push!(pnm["bus"], Dict{String,Any}(
                "name" => id,
                "phases" => obj["terminals"],
                "nphases" => length(obj["terminals"]),
                "status" => Int(obj["status"]),
            ))
        end
    end

    for type in _pnm2eng_objects["line"]
        for (id, obj) in get(base_eng, type, Dict())
            push!(pnm["line"], Dict{String,Any}(
                "name" => id,
                "f_bus" => obj["f_bus"],
                "t_bus" => obj["t_bus"],
                "f_connections" => obj["f_connections"],
                "t_connections" => obj["t_connections"],
                "rs" => get(obj, "rs_orig", obj["rs"]),
                "xs" => get(obj, "xs_orig", obj["xs"]),
                "nphases" => length(obj["f_connections"]),
                "switch" => type == "switch",
                "status" => Int(obj["status"]),
            ))
        end
    end

    for type in _pnm2eng_objects["transformer"]
        for (id, obj) in get(base_eng, type, Dict())
            push!(pnm["transformer"], Dict{String,Any}(
                "name" => id,
                "buses" => obj["bus"],
                "vbase (kV)" => obj["vm_nom"],
                "rating (kVA)" => haskey(obj, "dss") ? get(obj["dss"], "emerghkva", obj["sm_nom"][1] * 1.5) : obj["sm_nom"][1] * 1.5,
                "connections" => obj["connections"],
                "nwindings" => length(obj["bus"]),
                "nphases" => length(first(obj["connections"])),
                "configuration" => string.(obj["configuration"]),
                "status" => Int(obj["status"]),
            ))
        end
    end

    for type in _pnm2eng_objects["source"]
        for (id, obj) in get(base_eng, type, Dict())
            push!(pnm["source"], Dict{String,Any}(
                "name" => id,
                "type" => string(split(obj["source_id"], "."; limit=2)[1]),
                "bus" => obj["bus"],
                "connections" => obj["connections"],
                "nphases" => length(obj["connections"]),
                "status" => Int(obj["status"]),
            ))
        end
    end

    for type in _pnm2eng_objects["protection"]
        for (id, obj) in get(base_eng, type, Dict())
            push!(pnm["protection"], Dict{String,Any}(
                "name" => id,
                "type" => type,
                "location" => string(get(obj, "location", get(obj, "monitoredobj", ""))),
            ))
        end
    end

    return pnm
end


"""
    get_timestep_bus_types!(args::Dict{String,<:Any})::Vector{Dict{String,String}}

Gets bus types (PQ, PV, ref, isolated) for each timestep from the optimal dispatch result
and assigns it to `args["output_data"]["Protection settings"]["bus_types"]`
"""
function get_timestep_bus_types!(args::Dict{String,<:Any})::Vector{Dict{String,String}}
    args["output_data"]["Protection settings"]["bus_types"] = get_timestep_bus_types(
        get(get(args, "optimal_dispatch_result", Dict{String,Any}()), "solution", Dict{String,Any}()), get(args, "network", Dict{String,Any}())
    )
end


"""
    get_timestep_bus_types(::Dict{String,<:Any}, ::String)::Vector{Dict{String,String}}

Helper function for the variant where `args["network"]` hasn't been parsed yet.
"""
get_timestep_bus_types(::Dict{String,<:Any}, ::String)::Vector{Dict{String,String}} = Dict{String,String}[]


"""
    get_timestep_bus_types(
        optimal_dispatch_solution::Dict{String,<:Any},
        network::Dict{String,<:Any}
    )::Vector{Dict{String,String}}

Gets bus types (PQ, PV, ref, isolated) for each timestep from the `optimal_dispatch_solution`
"""
function get_timestep_bus_types(optimal_dispatch_solution::Dict{String,<:Any}, network::Dict{String,<:Any})::Vector{Dict{String,String}}
    timesteps = Dict{String,String}[]

    for n in sort(parse.(Int, collect(keys(get(optimal_dispatch_solution, "nw", Dict())))))
        nw = network["nw"]["$n"]
        buses = collect(keys(get(nw, "bus", Dict{String,Any}())))

        vsource_buses = [vs["bus"] for (_,vs) in get(network["nw"]["$n"], "voltage_source", Dict()) if vs["status"] == PMD.ENABLED]
        timestep = Dict{String,String}()
        nw_sol_bus = get(optimal_dispatch_solution["nw"]["$n"], "bus", Dict())
        for id in buses
            bus = get(nw_sol_bus, id, Dict("bus_type"=>4))

            timestep[id] = Dict{Int,String}(1=>"pq",2=>"pv",3=>"ref",4=>"isolated")[get(bus, "bus_type", 1)]
            if id in vsource_buses
                timestep[id] = "ref"
            end
        end
        push!(timesteps, timestep)
    end

    return timesteps
end


"""
    make_multinetwork(eng::Dict{String,<:Any}; global_keys::Set{String}=Set{String}(), time_elapsed::Union{Real,Vector{<:Real},Missing}=missing, kwargs...)

ONM-specific version of make_multinetwork that adds in switch_close_actions_ub
"""
function make_multinetwork(eng::Dict{String,<:Any}; global_keys::Set{String}=Set{String}(), time_elapsed::Union{Real,Vector{<:Real},Missing}=missing, kwargs...)
    mn_eng = PMD.make_multinetwork(eng; global_keys=union(global_keys, Set{String}(["options", "solvers"])), time_elapsed=ismissing(time_elapsed) ? get(eng, "time_elapsed", missing) : time_elapsed, kwargs...)

    switch_close_actions_ub = get(get(get(mn_eng, "options", Dict()), "data", Dict()), "switch-close-actions-ub", missing)
    if !ismissing(switch_close_actions_ub)
        set_switch_close_actions_ub!(mn_eng, switch_close_actions_ub)
    end

    return mn_eng
end


"""
    set_switch_close_actions_ub!(mn_eng::Dict{String,<:Any}, switch_close_actions_ub::Union{Vector{<:Real},Real})

Helper function to populate switch_close_actions_ub per timestep in a multinetwork data structure.
"""
function set_switch_close_actions_ub!(mn_eng::Dict{String,<:Any}, switch_close_actions_ub::Union{Vector{<:Real},Real})
    @assert PMD.ismultinetwork(mn_eng)

    for n in sort(parse.(Int,collect(keys(mn_eng["nw"]))))
        mn_eng["nw"]["$n"]["switch_close_actions_ub"] = isa(switch_close_actions_ub, Vector) ? switch_close_actions_ub[n] : switch_close_actions_ub
    end
end
