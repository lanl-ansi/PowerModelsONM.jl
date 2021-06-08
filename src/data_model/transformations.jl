
"Converts current upper bounds (cm_ub) on lines / switches to power upper bounds (sm_ub)"
function convert_ub_cm2sm!(data::Dict{String,<:Any})
    for k in ["switch", "line"]
        if haskey(data, k)
            for (_,l) in data[k]
                cm_ub = pop!(l, "cm_ub")

                bus = ieee13["bus"][l["f_bus"]]
                terminals = bus["terminals"]
                connections = [findfirst(isequal(cnd), terminals) for cnd in l["f_connections"]]

                f_bus_sm_ub = cm_ub .* get(bus, "vm_ub", fill(Inf, length(terminals)))[connections]

                bus = ieee13["bus"][l["t_bus"]]
                terminals = bus["terminals"]
                connections = [findfirst(isequal(cnd), terminals) for cnd in l["t_connections"]]

                t_bus_sm_ub = cm_ub .* get(bus, "vm_ub", fill(Inf, length(terminals)))[connections]

                l["sm_ub"] = max.(f_bus_sm_ub, t_bus_sm_ub)
            end
        end
    end
end


""
function adjust_line_limits!(data_eng::Dict{String,<:Any}; scale::Real=10.0)
    for type in ["line", "switch"]
        if haskey(data_eng, type)
            for (l, line) in data_eng[type]
                for k in ["cm_ub", "cm_ub_b", "cm_ub_c"]
                    if haskey(line, k)
                        line[k] .*= scale
                    end
                end
            end
        end
    end
end


""
function propagate_switch_settings!(mn_data_eng::Dict{String,<:Any}, mn_data_math::Dict{String,<:Any})
    switch_map = build_switch_map(mn_data_math["map"])

    for (n, nw) in mn_data_math["nw"]
        for (i,sw) in get(nw, "switch", Dict())
            mn_data_eng["nw"][n]["switch"][switch_map[i]]["state"] = PMD.SwitchState(Int(round(sw["state"])))
        end

        blocks = PMD.identify_load_blocks(nw)
        warm_blocks = are_blocks_warm(nw, blocks)
        for (block, is_warm) in warm_blocks
            if is_warm != 1
                for bus in block
                    nw["bus"]["$bus"]["bus_type"] = 4
                end
            end
        end

       propagate_topology_status!(nw)
    end
end


"""
propagates inactive active network buses status to attached components so that
the system status values are consistent.
returns true if any component was modified.
"""
function propagate_topology_status!(data::Dict{String, <:Any})
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


""
function _propagate_topology_status!(data::Dict{String,<:Any})
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


# TODO: Remove once storage supported in IVR, assumes MATH Model, with solution already
"converts storage to generators"
# function convert_storage!(nw::Dict{String,<:Any})
#     for (i, strg) in get(nw, "storage", Dict())
#         nw["gen"]["$(length(nw["gen"])+1)"] = Dict{String,Any}(
#             "name" => strg["name"],
#             "gen_bus" => strg["storage_bus"],
#             "connections" => strg["connections"],
#             "configuration" => PMD.WYE,
#             "control_mode" => PMD.FREQUENCYDROOP,
#             "gen_status" => strg["status"],

#             "pmin" => strg["ps"] .- 1e-9,
#             "pmax" => strg["ps"] .+ 1e-9,
#             "pg" => strg["ps"],
#             "qmin" => strg["qs"] .- 1e-9,
#             "qmax" => strg["qs"] .+ 1e-9,
#             "qg" => strg["qs"],

#             "model" => 2,
#             "startup" => 0,
#             "shutdown" => 0,
#             "cost" => [100.0, 0.0],
#             "ncost" => 2,

#             "index" => length(nw["gen"])+1,
#             "source_id" => strg["source_id"],

#             "vbase" => nw["bus"]["$(strg["storage_bus"])"]["vbase"],  # grab vbase from bus
#             "zx" => [0, 0, 0], # dynamics required by PMP, treat like voltage source
#         )
#     end
# end


function convert_storage!(nw::Dict{String,Any})
    for (i, strg) in get(nw, "storage", Dict())
        nw["generator"]["storage.$i"] = Dict{String,Any}(
            "bus" => strg["bus"],
            "connections" => strg["connections"],
            "configuration" => strg["configuration"],
            "control_mode" => get(strg, "control_mode", PMD.FREQUENCYDROOP),
            "status" => strg["status"],

            "pg_lb" => strg["ps"] .- 1e-9,
            "pg_ub" => strg["ps"] .+ 1e-9,
            "qg_lb" => strg["qs"] .- 1e-9,
            "qg_ub" => strg["qs"] .+ 1e-9,

            "source_id" => strg["source_id"],
            "zx" => zeros(length(strg["connections"])),
        )
        delete!(nw["storage"], i)
    end
    delete!(nw, "storage")
end
