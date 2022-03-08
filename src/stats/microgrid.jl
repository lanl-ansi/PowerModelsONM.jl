"""
    get_timestep_load_served!(
        args::Dict{String,<:Any}
    )::Dict{String,Vector{Real}}

Gets Load served statistics in-place in args, for use in [`entrypoint`](@ref entrypoint),
using [`get_timestep_load_served`](@ref get_timestep_load_served).
"""
function get_timestep_load_served!(args::Dict{String,<:Any})::Dict{String,Vector{Real}}
    args["output_data"]["Load served"] = get_timestep_load_served(get(get(args, "optimal_dispatch_result", Dict{String,Any}()), "solution", Dict{String,Any}()), args["network"], get(args, "optimal_switching_results", missing))
end


"""
    get_timestep_load_served(
        solution::Dict{String,<:Any},
        network::Dict{String,<:Any}
    )::Dict{String,Vector{Real}}

Returns Load statistics from an optimal dispatch `solution`, and compares to the
base load (non-shedded) in `network`, giving statistics for

- `"Feeder load (%)"`: How much load is the feeder supporting,
- `"Microgrid load (%)"`: How much load is(are) the microgrid(s) supporting,
- `"Bonus load via microgrid (%)"`: How much extra load is being supported.

## Note

Currently, because microgrids are not explicitly defined yet (see 'settings' file for initial implementation of microgrid tagging),
`"Bonus load via microgrid (%)"` only indicates how much charging is being performed on Storage.
"""
function get_timestep_load_served(dispatch_solution::Dict{String,<:Any}, network::Dict{String,<:Any}, switching_solution::Union{Missing,Dict{String,<:Any}}=missing)
    loads_served = Dict{String,Vector{Real}}(
        "Feeder load (%)" => Real[],
        "Microgrid load (%)" => Real[],
        "Bonus load via microgrid (%)" => Real[],
        "Total load (%)" => Real[],
        "Feeder customers (%)" => Real[],
        "Microgrid customers (%)" => Real[],
        "Bonus customers via microgrid (%)" => Real[],
        "Total customers (%)" => Real[],
    )

    mn_eng = _prepare_dispatch_data(network, switching_solution)

    for n in sort([parse(Int, i) for i in keys(get(dispatch_solution, "nw", Dict()))])
        graph = Graphs.SimpleGraph(length(get(network["nw"]["$n"], "bus", Dict())))
        bus2node = Dict(id => i for (i,(id,bus)) in enumerate(get(network["nw"]["$n"], "bus", Dict())))
        for edge_type in PMD._eng_edge_elements
            for (id,obj) in get(network["nw"]["$n"], edge_type, Dict())
                if mn_eng["nw"]["$n"][edge_type][id]["status"] == PMD.ENABLED
                    if (edge_type == "switch" && mn_eng["nw"]["$n"][edge_type][id]["state"] == PMD.CLOSED) || edge_type != "switch"
                        if edge_type == "transformer" && !haskey(obj, "f_bus")
                            for f_bus in obj["bus"]
                                for t_bus in obj["bus"]
                                    if f_bus != t_bus
                                        Graphs.add_edge!(graph, bus2node[f_bus], bus2node[t_bus])
                                    end
                                end
                            end
                        else
                            Graphs.add_edge!(graph, bus2node[obj["f_bus"]], bus2node[obj["t_bus"]])
                        end
                    end
                end
            end
        end
        substation_nodes = Set{Int}([bus2node[vs["bus"]] for (_,vs) in get(network["nw"]["$n"], "voltage_source", Dict())])
        der_nodes = Set{Int}([bus2node[obj["bus"]] for gen_type in ["solar", "storage", "generator"] for (_,obj) in get(network["nw"]["$n"], gen_type, Dict())])

        node2der = Dict{Int,Vector{Tuple{String,String}}}(node => Tuple{String,String}[] for node in der_nodes)
        for gen_type in ["solar", "storage", "generator"]
            for (id,obj) in get(network["nw"]["$n"], gen_type, Dict())
                push!(node2der[bus2node[obj["bus"]]], (gen_type, id))
            end
        end

        node2substation = Dict{Int,Vector{Tuple{String,String}}}(node => Tuple{String,String}[] for node in substation_nodes)
        for (id,obj) in get(network["nw"]["$n"], "voltage_source", Dict())
            push!(node2substation[bus2node[obj["bus"]]], ("voltage_source", id))
        end

        microgrids = Set([bus["microgrid_id"] for (id,bus) in get(network["nw"]["$n"], "bus", Dict()) if haskey(bus, "microgrid_id") && !isempty(bus["microgrid_id"])])
        microgrid_buses = Dict(mg => Set() for mg in microgrids)
        for (id,bus) in get(network["nw"]["$n"], "bus", Dict())
            !isempty(get(bus, "microgrid_id", "")) && push!(microgrid_buses[bus["microgrid_id"]], id)
        end
        microgrid_loads = Dict(mg => Set() for mg in microgrids)
        for (id,load) in get(network["nw"]["$n"], "load", Dict())
            for (mg,mg_buses) in microgrid_buses
                if load["bus"] ∈ mg_buses
                    push!(microgrid_loads[mg], id)
                    break
                end
            end
        end
        load2mg = Dict(load_id => mg_id for (mg_id, mg_loads) in microgrid_loads for load_id in mg_loads)

        mg_load_served = 0.0
        mg_cust_served = 0
        mg_bonus_load_served = 0.0
        mg_bonus_cust_served = 0
        feeder_load_served = 0.0
        feeder_cust_served = 0
        total_load_served = 0.0
        total_cust_served = 0

        mg_ncustomers = sum(Int64[length(mg_loads) for (mg,mg_loads) in microgrid_loads])
        total_mg_load = sum(Float64[sum(abs.(load["pd_nom"])) for (id,load) in get(network["nw"]["$n"], "load", Dict()) if id ∈ keys(load2mg) && load["status"] == PMD.ENABLED])

        mg_bonus_ncustomers = length(get(network["nw"]["$n"], "load", Dict())) - mg_ncustomers
        total_mg_bonus_load = sum(Float64[sum(abs.(load["pd_nom"])) for (id,load) in get(network["nw"]["$n"], "load", Dict()) if id ∉ keys(load2mg) && load["status"] == PMD.ENABLED])

        feeder_ncustomers = mg_bonus_ncustomers
        total_feeder_load = total_mg_bonus_load

        ncustomers = length(filter(x->x.second["status"]==PMD.ENABLED,get(network["nw"]["$n"], "load", Dict())))
        total_load = sum(Float64[sum(abs.(load["pd_nom"])) for (id,load) in get(network["nw"]["$n"], "load", Dict()) if load["status"] == PMD.ENABLED])

        sol_loads = get(dispatch_solution["nw"]["$n"], "load", Dict())
        for (id, load) in get(network["nw"]["$n"], "load", Dict())
            if mn_eng["nw"]["$n"]["load"][id]["status"] == PMD.ENABLED
                if haskey(sol_loads, id) && haskey(sol_loads[id], "pd_bus")
                    load_served = sum(abs.(sol_loads[id]["pd_bus"]))
                    cust_served = all(abs.(sol_loads[id]["pd_bus"] ./ load["pd_nom"]) .>= 1.0-1e-4) ? 1 : 0

                    total_load_served += load_served
                    total_cust_served += cust_served
                    if id ∈ keys(load2mg)
                        mg_load_served += load_served
                        mg_cust_served += cust_served
                    else
                        _total_feeder_gen = 0
                        _total_mg_gen = 0
                        for (sub_node, subs) in node2substation
                            for (gen_type, id) in subs
                                if Graphs.has_path(graph, bus2node[load["bus"]], sub_node)
                                    _total_feeder_gen += sum(get(get(get(dispatch_solution["nw"]["$n"], "voltage_source", Dict()), id, Dict()), "pg", 0.0))
                                end
                            end
                        end

                        for (der_node, ders) in node2der
                            for (gen_type, id) in ders
                                if Graphs.has_path(graph, bus2node[load["bus"]], der_node)
                                    _total_mg_gen += sum(get(get(get(dispatch_solution["nw"]["$n"], gen_type, Dict()), id, Dict()), gen_type == "storage" ? "ps" : "pg", 0.0) .* (gen_type == "storage" ? -1 : 1))
                                end
                            end
                        end

                        _mg_feeder_ratio = _total_feeder_gen <= 0.0 ? 1.0 : _total_mg_gen <= 0.0 ? 0.0 : (_total_feeder_gen + _total_mg_gen) == 0 ? 0.0 : _total_mg_gen / (_total_feeder_gen + _total_mg_gen)
                        _feeder_mg_ratio = _mg_feeder_ratio == 0.0 ? 1.0 : _total_feeder_gen / (_total_feeder_gen + _total_mg_gen)

                        mg_bonus_load_served += load_served * _mg_feeder_ratio
                        mg_bonus_cust_served += cust_served * _mg_feeder_ratio

                        feeder_load_served += load_served * _feeder_mg_ratio
                        feeder_cust_served += cust_served * _feeder_mg_ratio
                    end
                end
            end
        end

        push!(loads_served["Feeder customers (%)"], feeder_ncustomers > 0 ? feeder_cust_served/feeder_ncustomers*100.0 : 0.0)
        push!(loads_served["Feeder load (%)"], total_feeder_load > 0 ? feeder_load_served/total_feeder_load*100.0 : 0.0)

        push!(loads_served["Microgrid customers (%)"], mg_ncustomers > 0 ? mg_cust_served/mg_ncustomers*100.0 : 0.0)
        push!(loads_served["Microgrid load (%)"], total_mg_load > 0 ? mg_load_served/total_mg_load*100.0 : 0.0)

        push!(loads_served["Bonus customers via microgrid (%)"], mg_bonus_ncustomers > 0 ? mg_bonus_cust_served/mg_bonus_ncustomers*100.0 : 0.0)
        push!(loads_served["Bonus load via microgrid (%)"], total_mg_bonus_load > 0 ? mg_bonus_load_served/total_mg_bonus_load*100.0 : 0.0)

        push!(loads_served["Total customers (%)"], ncustomers > 0 ? total_cust_served/ncustomers*100.0 : 0.0)
        push!(loads_served["Total load (%)"], total_load > 0 ? total_load_served/total_load*100.0 : 0.0)
    end

    return loads_served
end


"""
    get_timestep_generator_profiles!(
        args::Dict{String,<:Any}
    )::Dict{String,Vector{Real}}

Gets generator profile statistics for each timestep in-place in args, for use in [`entrypoint`](@ref entrypoint),
using [`get_timestep_generator_profiles`](@ref get_timestep_generator_profiles)
"""
function get_timestep_generator_profiles!(args::Dict{String,<:Any})::Dict{String,Vector{Real}}
    args["output_data"]["Generator profiles"] = get_timestep_generator_profiles(get(get(args, "optimal_dispatch_result", Dict{String,Any}()), "solution", Dict{String,Any}()))
end


"""
    get_timestep_generator_profiles(
        solution::Dict{String,<:Any}
    )::Dict{String,Vector{Real}}

Returns statistics about the generator profiles from the optimal dispatch `solution`:

- `"Grid mix (kW)"`: how much power is from the substation
- `"Solar DG (kW)"`: how much power is from Solar PV DER
- `"Energy storage (kW)`: how much power is from Energy storage DER
- `"Diesel DG (kW)"`: how much power is from traditional generator DER
"""
function get_timestep_generator_profiles(solution::Dict{String,<:Any})::Dict{String,Vector{Real}}
    generator_profiles = Dict{String,Vector{Real}}(
        "Grid mix (kW)" => Real[],
        "Solar DG (kW)" => Real[],
        "Energy storage (kW)" => Real[],
        "Diesel DG (kW)" => Real[],
    )

    for n in sort([parse(Int, i) for i in keys(get(solution, "nw", Dict()))])
        push!(generator_profiles["Grid mix (kW)"], sum(Float64[sum(vsource["pg"]) for (_,vsource) in get(solution["nw"]["$n"], "voltage_source", Dict())]))
        push!(generator_profiles["Solar DG (kW)"], sum(Float64[sum(solar["pg"]) for (_,solar) in get(solution["nw"]["$n"], "solar", Dict())]))
        push!(generator_profiles["Energy storage (kW)"], sum(Float64[-sum(storage["ps"]) for (_,storage) in get(solution["nw"]["$n"], "storage", Dict())]))
        push!(generator_profiles["Diesel DG (kW)"], sum(Float64[sum(gen["pg"]) for (_,gen) in get(solution["nw"]["$n"], "generator", Dict())]))
    end

    return generator_profiles
end


"""
    get_timestep_storage_soc!(
        args::Dict{String,<:Any}
    )::Vector{Real}

Gets storage energy remaining percentage for each timestep in-place in args,
for use in [`entrypoint`](@ref entrypoint), using
[`get_timestep_storage_soc`](@ref get_timestep_storage_soc)
"""
function get_timestep_storage_soc!(args::Dict{String,<:Any})::Vector{Real}
    args["output_data"]["Storage SOC (%)"] = get_timestep_storage_soc(get(get(args, "optimal_dispatch_result", Dict{String,Any}()), "solution", Dict{String,Any}()), args["network"])
end


"""
    get_timestep_storage_soc(
        solution::Dict{String,<:Any},
        network::Dict{String,<:Any}
    )::Vector{Real}

Returns the storage state of charge, i.e., how much energy is remaining in all of the the energy storage DER
based on the optimal dispatch `solution`. Needs `network` to give percentage.
"""
function get_timestep_storage_soc(solution::Dict{String,<:Any}, network::Dict{String,<:Any})::Vector{Real}
    storage_soc = Real[]

    for (i,n) in enumerate(sort(parse.(Int, collect(keys(get(solution, "nw", Dict()))))))
        if !isempty(get(solution["nw"]["$n"], "storage", Dict()))
            energy = 0.0
            energy_ub = 0.0
            for (s,strg) in network["nw"]["$n"]["storage"]
                r = get(solution["nw"]["$n"]["storage"], s, strg)
                energy += get(r, "se", get(r, "energy", 0.0))
                energy_ub += strg["energy_ub"]
            end
            push!(storage_soc, 100.0 * (energy_ub == 0 ? 0.0 : energy / energy_ub))
        elseif i > 1
            push!(storage_soc, storage_soc[i-1])
        elseif i == 1
            energy = 0.0
            energy_ub = 0.0
            for (s,strg) in get(network["nw"]["$n"], "storage", Dict())
                energy += get(strg, "energy", 0.0)
                energy_ub += strg["energy_ub"]
            end

            push!(storage_soc, 100.0 * (energy_ub == 0 ? 0.0 : energy / energy_ub))
        else
            push!(storage_soc, NaN)
        end
    end

    return storage_soc
end
