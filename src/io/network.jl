"""
    parse_network!(args::Dict{String,<:Any})::Dict{String,Any}

In-place version of [`parse_network`](@ref parse_network), returns the ENGINEERING multinetwork
data structure, which is available in `args` under `args["network"]`, and adds the non-expanded ENGINEERING
data structure under `args["base_network"]`
"""
function parse_network!(args::Dict{String,<:Any})::Dict{String,Any}
    if isa(args["network"], String)
        args["base_network"], args["network"] = parse_network(args["network"]; fix_small_numbers=get(args, "fix-small-numbers", false))
    end

    return args["network"]
end


"""
    parse_network(network_file::String)::Tuple{Dict{String,Any},Dict{String,Any}}

Parses network file given by runtime arguments into its base network, i.e., not expanded into a multinetwork,
and multinetwork, which is the multinetwork `ENGINEERING` representation of the network.
"""
function parse_network(network_file::String; fix_small_numbers::Bool=false)::Tuple{Dict{String,Any},Dict{String,Any}}
    eng = PMD.parse_file(network_file; dss2eng_extensions=[PowerModelsProtection._dss2eng_solar_dynamics!, PowerModelsProtection._dss2eng_gen_dynamics!, _dss2eng_protection!], transformations=[PMD.apply_kron_reduction!], import_all=true)

    if fix_small_numbers
        PMD.adjust_small_line_impedances!(eng; min_impedance_val=1e-1)
        PMD.adjust_small_line_admittances!(eng; min_admittance_val=1e-1)
        PMD.adjust_small_line_lengths!(eng; min_length_val=10.0)
    end

    # TODO: add more elegant cost model adjustments
    for (id,obj) in get(eng, "solar", Dict())
        eng["solar"][id]["cost_pg_model"] = 2
        eng["solar"][id]["cost_pg_parameters"] = [0.0, 0.0]
    end

    mn_eng = PMD.make_multinetwork(eng)

    return eng, mn_eng
end


"""
    _dss2eng_protection!(eng::Dict{String,<:Any}, dss::Dict{String,<:Any})

Extension function for converting opendss protection into protection objects for protection optimization
"""
function _dss2eng_protection!(eng::Dict{String,<:Any}, dss::Dict{String,<:Any})
    for type in ["relay", "recloser", "fuse"]
        if !isempty(get(dss, type, Dict()))
            eng[type] = Dict{String,Any}()
        end

        for (id, dss_obj) in get(dss, type, Dict())
            eng[type][id] = Dict{String,Any}(
                "location" => dss_obj["monitoredobj"],
            )
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

Builds a network data model for use in Protection settings optimization
"""
function get_protection_network_model!(args::Dict{String,<:Any})
    args["output_data"]["Protection settings"]["network_model"] = get_protection_network_model(args["base_network"])
end


"""
    get_protection_network_model(base_eng::Dict{String,<:Any})

Builds a network data model for use in Protection optimization
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
                "nphases" => length(obj["f_connections"]),
                "switch" => type == "switch",
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
            ))
        end
    end

    for type in _pnm2eng_objects["protection"]
        for (id, obj) in get(base_eng, type, Dict())
            push!(pnm["protection"], Dict{String,Any}(
                "name" => id,
                "type" => type,
                "location" => string(obj["location"]),
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
    args["output_data"]["Protection settings"]["bus_types"] = get_timestep_bus_types(get(get(args, "optimal_dispatch_result", Dict{String,Any}()), "solution", Dict{String,Any}()), get(args, "network", Dict{String,Any}()))
end


"""
    get_timestep_bus_types(optimal_dispatch_solution::Dict{String,<:Any}, network::Dict{String,<:Any})::Vector{Dict{String,String}}

Gets bus types (PQ, PV, ref, isolated) for each timestep from the optimal dispatch solution
"""
function get_timestep_bus_types(optimal_dispatch_solution::Dict{String,<:Any}, network::Dict{String,<:Any})::Vector{Dict{String,String}}
    timesteps = Dict{String,String}[]

    for n in sort(parse.(Int, collect(keys(get(optimal_dispatch_solution, "nw", Dict())))))
        vsource_buses = [vs["bus"] for (_,vs) in get(network["nw"]["$n"], "voltage_source", Dict()) if vs["status"] == PMD.ENABLED]
        timestep = Dict{String,String}()
        for (id,bus) in get(optimal_dispatch_solution["nw"]["$n"], "bus", Dict())
            timestep[id] = Dict{Int,String}(1=>"pq",2=>"pv",3=>"ref",4=>"isolated")[get(bus, "bus_type", 1)]
            if id in vsource_buses
                timestep[id] = "ref"
            end
        end
        push!(timesteps, timestep)
    end

    return timesteps
end
