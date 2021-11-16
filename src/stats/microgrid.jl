"""
    get_timestep_load_served!(args::Dict{String,<:Any})::Dict{String,Vector{Real}}

Gets Load served statistics in-place in args, for use in [`entrypoint`](@ref entrypoint),
using [`get_timestep_load_served`](@ref get_timestep_load_served).
"""
function get_timestep_load_served!(args::Dict{String,<:Any})::Dict{String,Vector{Real}}
    args["output_data"]["Load served"] = get_timestep_load_served(get(get(args, "optimal_dispatch_result", Dict{String,Any}()), "solution", Dict{String,Any}()), args["network"], get(args, "optimal_switching_results", missing))
end


"""
    get_timestep_load_served(solution::Dict{String,<:Any}, network::Dict{String,<:Any})::Dict{String,Vector{Real}}

Returns Load statistics from an optimal dispatch `solution`, and compares to the base load (non-shedded) in `network`,
giving statistics for

- `"Feeder load (%)"`: How much load is the feeder supporting,
- `"Microgrid load (%)"`: How much load is(are) the microgrid(s) supporting,
- `"Bonus load via microgrid (%)"`: How much extra load is being supported.

## Note

Currently, because microgrids are not explicitly defined yet (see 'settings' file for initial implementation of microgrid tagging),
`"Bonus load via microgrid (%)"` only indicates how much charging is being performed on Storage.
"""
function get_timestep_load_served(dispatch_solution::Dict{String,<:Any}, network::Dict{String,<:Any}, switching_solution::Union{Missing,Dict{String,<:Any}}=missing)
    load_served = Dict{String,Vector{Real}}(
        "Feeder load (%)" => Real[],
        "Microgrid load (%)" => Real[],
        "Bonus load via microgrid (%)" => Real[],
        "Total load (%)" => Real[],
    )

    mn_eng = _prepare_dispatch_data(network, switching_solution)

    for n in sort([parse(Int, i) for i in keys(get(dispatch_solution, "nw", Dict()))])
        bus2mid = Dict{String,String}(id => bus["microgrid_id"] for (id,bus) in get(network["nw"]["$n"], "bus", Dict()) if haskey(bus, "microgrid_id"))
        load2bus = Dict{String,String}(id => load["bus"] for (id,load) in get(network["nw"]["$n"], "load", Dict()))
        load2mid = Dict{String,String}(lid => bus2mid[bus] for (lid,bus) in load2bus if bus in keys(bus2mid))
        mid2loads = Dict{String,Set{String}}(mid => Set{String}([]) for mid in values(bus2mid))
        for (lid,mid) in load2mid
            push!(mid2loads[mid], lid)
        end
        n_loads = length(get(network["nw"]["$n"], "load", Dict()))
        n_microgrid_loads = length(load2mid)
        n_bonus_loads = n_loads - n_microgrid_loads
        if !isempty(load2mid)
            blocks = PMD.identify_blocks(mn_eng["nw"]["$n"])
            block_loads = Dict{Set,Set}(block=>Set{String}() for block in blocks)
            for (id,load) in get(mn_eng["nw"]["$n"], "load", Dict())
                for block in blocks
                    if load["bus"] in block
                        push!(block_loads[block], id)
                        break
                    end
                end
            end
            block_mg_ids = Dict{Set,Set{String}}(block => Set{String}([]) for block in blocks)
            for (bid,mid) in bus2mid
                for block in blocks
                    if bid in block
                        push!(block_mg_ids[block], mid)
                        break
                    end
                end
            end
            block_has_mg = Dict{Set,Bool}(block => !isempty(block_mg_ids[block]) for block in blocks)
            block_gens = Dict{Set,Dict{String,Set{String}}}(block => Dict{String,Set{String}}() for block in blocks)
            for block in blocks
                for type in ["voltage_source", "generator", "solar", "storage"]
                    for (id,obj) in get(mn_eng["nw"]["$n"], type, Dict())
                        if obj["bus"] in block
                            if !haskey(block_gens[block], type)
                                block_gens[block][type] = Set{String}([])
                            end
                            push!(block_gens[block][type], id)
                        end
                    end
                end
            end

            mg_served_load = 0.0
            mg_bonus_load = 0.0
            feeder_served_load = 0.0
            total_served_load = 0.0
            for block in blocks
                if "voltage_source" in keys(block_gens[block]) && !isempty(get(dispatch_solution["nw"]["$n"], "voltage_source", Dict()))
                    if block_has_mg[block]
                        vs_serves = 0.0
                        der_serves = 0.0
                        for (type,ids) in block_gens[block]
                            if type == "voltage_source"
                                for id in ids
                                    vsource = mn_eng["nw"]["$n"][type][id]
                                    vs_serves += sum(get(get(dispatch_solution["nw"]["$n"][type], id, Dict()), "pg", fill(0.0, length(vsource["connections"]))))
                                end
                            elseif type == "generator" || type == "solar"
                                for id in ids
                                    der = mn_eng["nw"]["$n"][type][id]
                                    der_serves += sum(get(get(dispatch_solution["nw"]["$n"][type], id, Dict()), "pg", fill(0.0, length(der["connections"]))))
                                end
                            elseif type == "storage"
                                for id in ids
                                    der = mn_eng["nw"]["$n"][type][id]
                                    ps = get(get(dispatch_solution["nw"]["$n"][type], id, Dict()), "ps", fill(0.0, length(der["connections"])))
                                    ps[ps.>0] .= 0.0
                                    der_serves += sum(ps)
                                end
                            end
                        end

                        if vs_serves >= 0
                            der_vs_ratio = der_serves / vs_serves
                        else
                            der_vs_ratio = 1.0
                        end

                        for lid in block_loads[block]
                            load = network["nw"]["$(n)"]["load"][lid]
                            if all(load["pd_nom"] .== 0) && all(load["pd_nom"] .== 0)
                                n_loads -= 1
                                if any(lid in mid2loads[mid] for mid in block_mg_ids[block])
                                    n_microgrid_loads -= 1
                                end
                                continue
                            end

                            nom_pd = load["pd_nom"]
                            act_pd = get(get(get(dispatch_solution["nw"]["$n"], "load", Dict()), lid, Dict()), "pd", fill(0.0, length(load["connections"])))

                            feeder_served_load += sum(act_pd ./ nom_pd) / length(nom_pd) / n_loads * (1-der_vs_ratio)
                            if any(lid in mid2loads[mid] for mid in block_mg_ids[block])
                                mg_served_load += sum(act_pd ./ nom_pd) / length(nom_pd) / n_microgrid_loads
                            else
                                mg_bonus_load += sum(act_pd ./ nom_pd) / length(nom_pd) / n_bonus_loads * der_vs_ratio
                            end
                            total_served_load += sum(act_pd ./ nom_pd) / length(nom_pd) / n_loads
                        end
                    else
                        for lid in block_loads[block]
                            load = mn_eng["nw"]["$(n)"]["load"][lid]
                            if all(load["pd_nom"] .== 0) && all(load["pd_nom"] .== 0)
                                n_loads -= 1
                                if any(lid in mid2loads[mid] for mid in block_mg_ids[block])
                                    n_microgrid_loads -= 1
                                end
                                continue
                            end

                            nom_pd = load["pd_nom"]
                            act_pd = get(get(get(dispatch_solution["nw"]["$n"], "load", Dict()), lid, Dict()), "pd", fill(0.0, length(load["connections"])))

                            feeder_served_load += sum(act_pd ./ nom_pd) / length(nom_pd) / (n_loads-n_microgrid_loads)
                            total_served_load += sum(act_pd ./ nom_pd) / length(nom_pd) / n_loads
                        end
                    end
                elseif block_has_mg[block]
                    for lid in block_loads[block]
                        load = mn_eng["nw"]["$(n)"]["load"][lid]
                        if all(load["pd_nom"] .== 0) && all(load["pd_nom"] .== 0)
                            n_loads -= 1
                            if any(lid in mid2loads[mid] for mid in block_mg_ids[block])
                                n_microgrid_loads -= 1
                            end
                            continue
                        end

                        nom_pd = load["pd_nom"]
                        act_pd = get(get(get(dispatch_solution["nw"]["$n"], "load", Dict()), lid, Dict()), "pd", fill(0.0, length(load["connections"])))

                        if any(lid in mid2loads[mid] for mid in block_mg_ids[block])
                            mg_served_load += sum(act_pd ./ nom_pd) / length(nom_pd) / n_microgrid_loads
                        else
                            mg_bonus_load += sum(act_pd ./ nom_pd) / length(nom_pd) / n_bonus_loads
                        end
                        total_served_load += sum(act_pd ./ nom_pd) / length(nom_pd) / n_loads
                    end
                end
            end
            push!(load_served["Feeder load (%)"], feeder_served_load*100.0)
            push!(load_served["Microgrid load (%)"], mg_served_load*100.0)
            push!(load_served["Bonus load via microgrid (%)"], mg_bonus_load*100.0)
            push!(load_served["Total load (%)"], total_served_load*100.0)
        else
            # No Microgrid information present
            original_load = sum([sum(load["pd_nom"]) for (_,load) in mn_eng["nw"]["$n"]["load"]])

            feeder_served_load = !isempty(get(dispatch_solution["nw"]["$n"], "voltage_source", Dict())) ? sum(Float64[sum(vs["pg"]) for (_,vs) in get(dispatch_solution["nw"]["$n"], "voltage_source", Dict())]) : 0.0
            der_non_storage_served_load = !isempty(get(dispatch_solution["nw"]["$n"], "generator", Dict())) || !isempty(get(dispatch_solution["nw"]["$n"], "solar", Dict())) ? sum([sum(g["pg"]) for type in ["solar", "generator"] for (_,g) in get(dispatch_solution["nw"]["$n"], type, Dict())]) : 0.0
            der_storage_served_load = !isempty(get(dispatch_solution["nw"]["$n"], "storage", Dict())) ? sum([-sum(s["ps"]) for (_,s) in get(dispatch_solution["nw"]["$n"], "storage", Dict())]) : 0.0

            # TODO once microgrids support tagging, redo load served statistics
            microgrid_served_load = (der_non_storage_served_load + der_storage_served_load) / original_load * 100
            _bonus_load = (microgrid_served_load - 100)

            push!(load_served["Feeder load (%)"], feeder_served_load / original_load * 100)  # CHECK
            push!(load_served["Microgrid load (%)"], microgrid_served_load)  # CHECK
            push!(load_served["Bonus load via microgrid (%)"], _bonus_load > 0 ? _bonus_load : 0.0)  # CHECK
            push!(load_served["Total load (%)"], (feeder_served_load / original_load + microgrid_served_load + (_bonus_load > 0 ? _bonus_load : 0.0))*100.0)
        end
    end

    return load_served
end


"""
    get_timestep_generator_profiles!(args::Dict{String,<:Any})::Dict{String,Vector{Real}}

Gets generator profile statistics for each timestep in-place in args, for use in [`entrypoint`](@ref entrypoint),
using [`get_timestep_generator_profiles`](@ref get_timestep_generator_profiles)
"""
function get_timestep_generator_profiles!(args::Dict{String,<:Any})::Dict{String,Vector{Real}}
    args["output_data"]["Generator profiles"] = get_timestep_generator_profiles(get(get(args, "optimal_dispatch_result", Dict{String,Any}()), "solution", Dict{String,Any}()))
end


"""
    get_timestep_generator_profiles(solution::Dict{String,<:Any})::Dict{String,Vector{Real}}

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
    get_timestep_storage_soc!(args::Dict{String,<:Any})::Vector{Real}

Gets storage energy remaining percentage for each timestep in-place in args, for use in [`entrypoint`](@ref entrypoint),
using [`get_timestep_storage_soc`](@ref get_timestep_storage_soc)
"""
function get_timestep_storage_soc!(args::Dict{String,<:Any})::Vector{Real}
    args["output_data"]["Storage SOC (%)"] = get_timestep_storage_soc(get(get(args, "optimal_dispatch_result", Dict{String,Any}()), "solution", Dict{String,Any}()), args["network"])
end


"""
    get_timestep_storage_soc(solution::Dict{String,<:Any}, network::Dict{String,<:Any})::Vector{Real}

Returns the storage state of charge, i.e., how much energy is remaining in all of the the energy storage DER
based on the optimal dispatch `solution`. Needs `network` to give percentage.
"""
function get_timestep_storage_soc(solution::Dict{String,<:Any}, network::Dict{String,<:Any})::Vector{Real}
    storage_soc = Real[]

    for (i,n) in enumerate(sort(parse.(Int, collect(keys(get(solution, "nw", Dict()))))))
        if !isempty(get(solution["nw"]["$n"], "storage", Dict()))
            push!(storage_soc, 100.0 * sum(strg["se"] for strg in values(solution["nw"]["$n"]["storage"])) / sum(strg["energy_ub"] for strg in values(network["nw"]["$n"]["storage"])))
        elseif i > 1
            push!(storage_soc, storage_soc[i-1])
        elseif i == 0 && !isempty(get(network["nw"]["$n"], "storage", Dict()))
            push!(storage_soc, 100.0 * sum(strg["energy"]/strg["energy_ub"] for strg in values(network["nw"]["$n"]["storage"])))
        else
            push!(storage_soc, NaN)
        end
    end

    return storage_soc
end
