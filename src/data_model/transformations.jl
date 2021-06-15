"builds a lookup list of what generators are connected to a given bus"
function bus_gen_lookup(gen_data::Dict{String,<:Any}, bus_data::Dict{String,<:Any})
    bus_gen = Dict(bus["bus_i"] => [] for (i,bus) in bus_data)
    for (i,gen) in gen_data
        push!(bus_gen[gen["gen_bus"]], gen)
    end
    return bus_gen
end


"builds a lookup list of what loads are connected to a given bus"
function bus_load_lookup(load_data::Dict{String,<:Any}, bus_data::Dict{String,<:Any})
    bus_load = Dict(bus["bus_i"] => [] for (i,bus) in bus_data)
    for (i,load) in load_data
        push!(bus_load[load["load_bus"]], load)
    end
    return bus_load
end


"builds a lookup list of what shunts are connected to a given bus"
function bus_shunt_lookup(shunt_data::Dict{String,<:Any}, bus_data::Dict{String,<:Any})
    bus_shunt = Dict(bus["bus_i"] => [] for (i,bus) in bus_data)
    for (i,shunt) in shunt_data
        push!(bus_shunt[shunt["shunt_bus"]], shunt)
    end
    return bus_shunt
end


"builds a lookup list of what storage is connected to a given bus"
function bus_storage_lookup(storage_data::Dict{String,<:Any}, bus_data::Dict{String,<:Any})
    bus_storage = Dict(bus["bus_i"] => [] for (i,bus) in bus_data)
    for (i,storage) in storage_data
        push!(bus_storage[storage["storage_bus"]], storage)
    end
    return bus_storage
end


"""
    propagate_topology_status!(data::Dict{String, <:Any})::Bool

propagates inactive active network buses status to attached components so that
the system status values are consistent.
returns true if any component was modified.
"""
function propagate_topology_status!(data::Dict{String, <:Any})::Bool
    revised = false
    pm_data = PMD.get_pmd_data(data)

    if PMD.ismultinetwork(pm_data)
        for (_, pm_nw_data) in pm_data["nw"]
            revised |= _propagate_topology_status!(pm_nw_data)
        end
    else
        revised = _propagate_topology_status!(pm_data)
    end

    return revised
end


"""
propagates inactive active network buses status to attached components so that
the system status values are consistent.
returns true if any component was modified.
"""
function _propagate_topology_status!(data::Dict{String,<:Any})::Bool
    buses = Dict(bus["bus_i"] => bus for (i,bus) in data["bus"])

    # compute what active components are incident to each bus
    incident_load = bus_load_lookup(data["load"], data["bus"])
    incident_active_load = Dict()
    for (i, load_list) in incident_load
        incident_active_load[i] = [load for load in load_list if load["status"] != 0]
    end

    incident_shunt = bus_shunt_lookup(data["shunt"], data["bus"])
    incident_active_shunt = Dict()
    for (i, shunt_list) in incident_shunt
        incident_active_shunt[i] = [shunt for shunt in shunt_list if shunt["status"] != 0]
    end

    incident_gen = bus_gen_lookup(data["gen"], data["bus"])
    incident_active_gen = Dict()
    for (i, gen_list) in incident_gen
        incident_active_gen[i] = [gen for gen in gen_list if gen["gen_status"] != 0]
    end

    incident_strg = bus_storage_lookup(data["storage"], data["bus"])
    incident_active_strg = Dict()
    for (i, strg_list) in incident_strg
        incident_active_strg[i] = [strg for strg in strg_list if strg["status"] != 0]
    end

    incident_branch = Dict(bus["bus_i"] => [] for (i,bus) in data["bus"])
    for (i,branch) in data["branch"]
        push!(incident_branch[branch["f_bus"]], branch)
        push!(incident_branch[branch["t_bus"]], branch)
    end

    incident_switch = Dict(bus["bus_i"] => [] for (i,bus) in data["bus"])
    for (i,switch) in data["switch"]
        push!(incident_switch[switch["f_bus"]], switch)
        push!(incident_switch[switch["t_bus"]], switch)
    end


    revised = false

    for (i,branch) in data["branch"]
        if branch["br_status"] != 0
            f_bus = buses[branch["f_bus"]]
            t_bus = buses[branch["t_bus"]]

            if f_bus["bus_type"] == 4 || t_bus["bus_type"] == 4
                @debug "deactivating branch $(i):($(branch["f_bus"]),$(branch["t_bus"])) due to connecting bus status"
                branch["br_status"] = 0
                revised = true
            end
        end
    end

    for (i,switch) in data["switch"]
        if switch["status"] != 0
            f_bus = buses[switch["f_bus"]]
            t_bus = buses[switch["t_bus"]]

            if f_bus["bus_type"] == 4 || t_bus["bus_type"] == 4
                @debug "deactivating switch $(i):($(switch["f_bus"]),$(switch["t_bus"])) due to connecting bus status"
                switch["status"] = 0
                revised = true
            end
        end
    end

    for (i,bus) in buses
        if bus["bus_type"] == 4
            for load in incident_active_load[i]
                if load["status"] != 0
                    @debug "deactivating load $(load["index"]) due to inactive bus $(i)"
                    load["status"] = 0
                    revised = true
                end
            end

            for shunt in incident_active_shunt[i]
                if shunt["status"] != 0
                    @debug "deactivating shunt $(shunt["index"]) due to inactive bus $(i)"
                    shunt["status"] = 0
                    revised = true
                end
            end

            for gen in incident_active_gen[i]
                if gen["gen_status"] != 0
                    @debug "deactivating generator $(gen["index"]) due to inactive bus $(i)"
                    gen["gen_status"] = 0
                    revised = true
                end
            end

            for strg in incident_active_strg[i]
                if strg["status"] != 0
                    @debug "deactivating storage $(strg["index"]) due to inactive bus $(i)"
                    strg["status"] = 0
                    revised = true
                end
            end
        end
    end

    return revised
end


# TODO: Remove once storage supported in IVRU in PMP
"""
    convert_storage!(nw::Dict{String,Any})

Helper function for PowerModelsProtection fault studies to convert storage to generators in a subnetwork;
PowerModelsProtection currently does not support storage object constraints / variables, so this is a
workaround until those constraints/variables are added.

This works on ENGINEERING subnetworks (not multinetworks).
"""
function convert_storage!(nw::Dict{String,Any})
    for (i, strg) in get(nw, "storage", Dict())
        nw["generator"]["storage.$i"] = Dict{String,Any}(
            "bus" => strg["bus"],
            "connections" => strg["connections"],
            "configuration" => strg["configuration"],
            "control_mode" => get(strg, "control_mode", PMD.FREQUENCYDROOP),
            "status" => strg["status"],

            "pg_lb" => -strg["ps"] .- 1e-9,
            "pg_ub" => -strg["ps"] .+ 1e-9,
            "qg_lb" => -strg["qs"] .- 1e-9,
            "qg_ub" => -strg["qs"] .+ 1e-9,

            "source_id" => strg["source_id"],
            "zx" => zeros(length(strg["connections"])),
        )
        delete!(nw["storage"], i)
    end
    delete!(nw, "storage")
end
