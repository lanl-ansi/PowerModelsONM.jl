"""
    parse_network!(args::Dict{String,<:Any})::Dict{String,Any}

In-place version of [`parse_network`](@ref parse_network), returns the ENGINEERING multinetwork
data structure, which is available in `args` under `args["network"]`, and adds the non-expanded ENGINEERING
data structure under `args["base_network"]`
"""
function parse_network!(args::Dict{String,<:Any})
    if args["network"] isa String
        network_file = args["network"]

        args["fault_network"] = parse_fault_network(network_file)

        base_network, network = parse_network(network_file)

        args["base_network"] = base_network
        args["network"] = network
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
function parse_network(
    network_file::String;
    dss2eng_extensions=Function[],
    transformations=Function[],
    import_all=true,
    kwargs...
)
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
        bank_transformers=false,
        dss2eng_extensions=[
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
    for (id, obj) in get(eng, "solar", Dict())
        eng["solar"][id]["cost_pg_model"] = 2
        eng["solar"][id]["cost_pg_parameters"] = [0.0, 0.0]
    end

    # work-around for protection settings network model if fix-small-numbers is used
    for t in ["line", "switch"]
        for (id, obj) in get(eng, t, Dict())
            eng[t][id]["rs_orig"] = deepcopy(get(obj, "rs", zeros(length(obj["f_connections"]), length(obj["t_connections"]))))
            eng[t][id]["xs_orig"] = deepcopy(get(obj, "xs", zeros(length(obj["f_connections"]), length(obj["t_connections"]))))
        end
    end

    # Preserve the legacy ONM API boundary: PMD now returns a typed
    # EngineeringModel, while the rest of ONM still operates on Dict data.
    return deepcopy(eng.data)
end


"""
    parse_fault_network(network_file::String)

Applies special parsing specifically to do fault studies, which includes
no kron reduction, dss2eng dyanmics transformations, no transformer banking,
and adds vbases.
"""
function parse_fault_network(network_file::String)
    fault_network = PMP.parse_opendss(
        network_file;
        transformations=[_apply_vbases!, _apply_fault_models!],
        import_all=true,
    )

    return fault_network isa PMD.EngineeringModel{PMD.NetworkModel} ? deepcopy(fault_network.data) : fault_network
end


"""
    _apply_vbases!(data::Dict{String,<:Any})

Adds vbases to base network
"""
function _apply_vbases!(data::Dict{String,<:Any})
    bus_vbases = PowerModelsONM.PMD.calc_voltage_bases(data, data["settings"]["vbases_default"])[1]
    for (bus, vbase) in bus_vbases
        data["bus"][bus]["vbase"] = vbase
    end
end

_apply_vbases!(data::PMD.EngineeringModel{PMD.NetworkModel}) = _apply_vbases!(data.data)


"""
    _apply_fault_models!(data::Dict{String,<:Any})

Adds a default fault model to solar devices.
"""
function _apply_fault_models!(data::Dict{String,<:Any})
    if haskey(data, "solar")
        for solar in values(data["solar"])
            solar["fault_model"] = Dict{String,Any}(
                "standard" => PowerModelsONM.PMP.IEEE2800,
                "priority" => "active",
                "delta_ir1" => 2,
                "ir1_dead_band" => 0.1,
                "delta_ir2" => 2,
                "ir2_dead_band" => 0.1,
            )
        end
    end
end

_apply_fault_models!(data::PMD.EngineeringModel{PMD.NetworkModel}) = _apply_fault_models!(data.data)


"""
    _dss2eng_protection!(
        eng::Dict{String,<:Any},
        dss::Dict{String,<:Any}
    )

Extension function for converting opendss protection into protection objects for protection optimization.
"""
function _dss2eng_protection_locations!(eng, dss)
    for type in ["relay", "recloser", "fuse"]
        if !isempty(get(dss, type, Dict())) && !haskey(eng, type)
            eng[type] = Dict{String,Any}()
        end

        for (id, dss_obj) in get(dss, type, Dict())
            if !haskey(eng[type], id)
                eng[type][id] = Dict{String,Any}()
            end

            monitored_obj = dss_obj["monitoredobj"]

            eng[type][id]["location"] = monitored_obj
            eng[type][id]["monitor_type"] =
                string(split(monitored_obj, ".")[1])
        end
    end
end


# if Pkg.dependencies()[UUIDs.UUID("d7431456-977f-11e9-2de3-97ff7677985e")].version >= v"0.15.0"
    """
        _dss2eng_protection!(
            eng::Dict{String,<:Any},
            dss::Dict{String,<:Any}
        )

    Extension function for converting opendss protection into protection objects for protection optimization.
    """
    # function _dss2eng_protection_locations!(eng::Dict{String,<:Any}, dss::PMD.OpenDssDataModel)
    #     for type in ["relay", "recloser", "fuse"]
    #         if !isempty(get(dss, type, Dict())) && !haskey(eng, type)
    #             eng[type] = Dict{String,Any}()
    #         end

    #         for (id, dss_obj) in get(dss, type, Dict())
    #             if !haskey(eng[type], id)
    #                 eng[type][id] = Dict{String,Any}()
    #             end
    #             eng[type][id]["location"] = dss_obj["monitoredobj"]
    #             eng[type][id]["monitor_type"] = string(split(dss_obj["monitoredobj"], ".")[1])
    #         end
    #     end
    # end
# end


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
        for (id, obj) in get(base_eng, type, Dict())
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

        vsource_buses = [vs["bus"] for (_, vs) in get(network["nw"]["$n"], "voltage_source", Dict()) if vs["status"] == PMD.ENABLED]
        timestep = Dict{String,String}()
        nw_sol_bus = get(optimal_dispatch_solution["nw"]["$n"], "bus", Dict())
        for id in buses
            bus = get(nw_sol_bus, id, Dict("bus_type" => 4))

            timestep[id] = Dict{Int,String}(1 => "pq", 2 => "pv", 3 => "ref", 4 => "isolated")[get(bus, "bus_type", 1)]
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

ONM-specific version of `make_multinetwork` that preserves the legacy Dict API while
delegating multinetwork construction to PowerModelsDistribution's typed data model.
"""
function make_multinetwork(
    eng::Dict{String,<:Any};
    global_keys::Set{String}=Set{String}(),
    time_elapsed::Union{Real,Vector{<:Real},Missing}=missing,
    kwargs...
)
    model = PMD.EngineeringModel(deepcopy(Dict{String,Any}(eng)))
    mn_model = make_multinetwork(
        model;
        global_keys=global_keys,
        time_elapsed=time_elapsed,
        kwargs...
    )

    return deepcopy(mn_model.data)
end


"""
    make_multinetwork(eng::PMD.EngineeringModel{PMD.NetworkModel}; global_keys::Set{String}=Set{String}(), time_elapsed::Union{Real,Vector{<:Real},Missing}=missing, kwargs...)

ONM-specific typed-model path for `make_multinetwork`. Adds ONM global keys, preserves
`time_elapsed` behavior, and applies `switch_close_actions_ub` after PMD expands the network.
"""
function make_multinetwork(
    eng::PMD.EngineeringModel{PMD.NetworkModel};
    global_keys::Set{String}=Set{String}(),
    time_elapsed::Union{Real,Vector{<:Real},Missing}=missing,
    kwargs...
)
    effective_global_keys = union(global_keys, Set{String}(["options", "solvers"]))
    effective_time_elapsed = ismissing(time_elapsed) ? get(eng.data, "time_elapsed", missing) : time_elapsed

    mn_eng = PMD.make_multinetwork(
        eng;
        global_keys=effective_global_keys,
        time_elapsed=effective_time_elapsed,
        kwargs...
    )

    switch_close_actions_ub = get(
        get(get(mn_eng.data, "options", Dict()), "data", Dict()),
        "switch-close-actions-ub",
        missing,
    )
    if !ismissing(switch_close_actions_ub)
        set_switch_close_actions_ub!(mn_eng.data, switch_close_actions_ub)
    end

    return mn_eng
end


"""
    set_switch_close_actions_ub!(mn_eng::Dict{String,<:Any}, switch_close_actions_ub::Union{Vector{<:Real},Real})

Helper function to populate switch_close_actions_ub per timestep in a multinetwork data structure.
"""
function set_switch_close_actions_ub!(mn_eng::Dict{String,<:Any}, switch_close_actions_ub::Union{Vector{<:Real},Real})
    @assert PMD.ismultinetwork(mn_eng)

    for n in sort(parse.(Int, collect(keys(mn_eng["nw"]))))
        mn_eng["nw"]["$n"]["switch_close_actions_ub"] = isa(switch_close_actions_ub, Vector) ? switch_close_actions_ub[n] : switch_close_actions_ub
    end

    return mn_eng
end

function set_switch_close_actions_ub!(
    mn_eng::PMD.EngineeringModel{PMD.MultinetworkModel},
    switch_close_actions_ub::Union{Vector{<:Real},Real},
)
    set_switch_close_actions_ub!(mn_eng.data, switch_close_actions_ub)
    return mn_eng
end
