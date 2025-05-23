function transform_data_model_ravens(ravens::T; multinetwork::Bool=false, global_keys::Set{String}=Set{String}(), ravens2math_extensions::Vector{<:Function}=Function[_ravens2math_passthrough_default_funcs!...], ravens2math_passthrough::Dict{String,<:Vector{<:String}}=Dict{String,Vector{String}}(), kwargs...)::T where T<:Dict{String,Any}
    PMD.transform_data_model_ravens(
        ravens;
        multinetwork=multinetwork,
        global_keys=union(_default_global_keys, global_keys),
        ravens2math_extensions=ravens2math_extensions,
        ravens2math_passthrough=ravens2math_passthrough,
    )
end


"helper function to passthrough keywords from RAVENS to MATHEMATICAL data models"
function ravens2math_add_root_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})

    data_math["options"] = Dict()

    # Add default switch_close_actions_ub
    data_math["switch_close_actions_ub"] = Inf

end

function ravens2math_add_load_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    for (name, load_data) in get(data_math, "load", Dict{Any,Dict{String,Any}}())
        load_name = load_data["name"]
        enrg_cnsmrs = data_ravens["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["EnergyConsumer"]
        enrg_cnsmr_data = enrg_cnsmrs[load_name]

        if haskey(enrg_cnsmr_data, "EnergyConsumer.customerCount")
            load_data["priority"] = enrg_cnsmr_data["EnergyConsumer.customerCount"]
        end
    end
end

function ravens2math_add_bus_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    # TODO: where to get the microgrid_id from RAVENS-JSON?
    for (name, bus_data) in get(data_math, "bus", Dict{Any,Dict{String,Any}}())
        bus_name = bus_data["name"]
        conn_nodes = data_ravens["ConnectivityNode"]

        if haskey(conn_nodes, bus_name)
            conn_node_data = conn_nodes[bus_name]
            if haskey(conn_node_data, "ConnectivityNode.microgridId")
                bus_data["microgrid_id"] = conn_node_data["ConnectivityNode.microgridId"]
            end
        end
    end
end

function ravens2math_add_generator_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    # TODO: where to get from RAVENS-JSON?
    for (_, gen_data) in get(data_math, "gen", Dict{Any,Dict{String,Any}}())
        gen_name = gen_data["name"]
        pecs = get(data_ravens["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["RegulatingCondEq"], "PowerElectronicsConnection", Dict())
        if haskey(pecs, gen_name)
            pec_data = pecs[gen_name]
            if haskey(pec_data, "PowerElectronicsConnection.PowerElectronicsConnectionResponse")
                gen_data["gen_model"] = pec_data["PowerElectronicsConnection.PowerElectronicsConnectionResponse"]
            end
            if haskey(pec_data, "PowerElectronicsConnection.PowerElectronicsOperatingMode")
                gen_data["inverter"] = get(pec_data["PowerElectronicsConnection.PowerElectronicsOperatingMode"], "PowerElectronicsOperatingMode.mode", "OperatingModeKind.gridFollowing") == "OperatingModeKind.gridForming" ? GRID_FORMING : GRID_FOLLOWING
            end
        end
    end
end


function ravens2math_add_storage_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    # TODO: where to get from RAVENS-JSON?
    for (_, storage_data) in get(data_math, "storage", Dict{Any,Dict{String,Any}}())
        storage_name = storage_data["name"]
        pecs = get(data_ravens["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["RegulatingCondEq"], "PowerElectronicsConnection", Dict())
        if haskey(pecs, storage_name)
            pec_data = pecs[storage_name]
            if haskey(pec_data, "PowerElectronicsConnection.PowerElectronicsUnit")
                storage_data["gen_model"] = get(pec_data, "BatteryUnit.BatteryResponse", 1)
            end
            if haskey(pec_data, "PowerElectronicsConnection.PowerElectronicsOperatingMode")
                storage_data["inverter"] = get(pec_data["PowerElectronicsConnection.PowerElectronicsOperatingMode"], "PowerElectronicsOperatingMode.mode", "OperatingModeKind.gridFollowing") == "OperatingModeKind.gridForming" ? GRID_FORMING : GRID_FOLLOWING
            end
            if haskey(pec_data, "PowerElectronicsConnection.PhaseUnbalanceLimit")
                storage_data["phase_unbalance_ub"] = pec_data["PowerElectronicsConnection.PhaseUnbalanceLimit"]
            end
        end
    end
end


function ravens2math_add_switch_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    # TODO: where to get from RAVENS-JSON?
    for (name, switch_data) in get(data_math, "switch", Dict{Any,Dict{String,Any}}())
        switch_name = switch_data["name"]
        switches = get(data_ravens["PowerSystemResource"]["Equipment"]["ConductingEquipment"], "Switch", Dict())
        if haskey(switches, switch_name)
            switch_info = switches[switch_name]
            if haskey(switch_info, "Switch.VoltageMagnitudeUpperBound")
                switch_data["vm_delta_pu_ub"] = switch_info["Switch.VoltageMagnitudeUpperBound"]
            end
            if haskey(switch_info, "Switch.VoltageAngleUpperBound")
                switch_data["va_delta_deg_ub"] = switch_info["Switch.VoltageAngleUpperBound"]
            end
        end
    end
end


### Util functions to convert from MATH to ENG model

function create_eng_nw_from_math(math_nw)
    new = Dict{String,Any}("nw" => Dict{String,Any}(),
        "mn_lookup" => Dict{String,Float64}())

    for (n, nw) in get(math_nw, "nw", Dict())
        new["nw"][n] = create_eng_from_math(nw, math_nw["bus_lookup"][n])
        if parse(Int, n) == 1
            new["mn_lookup"][n] = 0.0
        else
            new["mn_lookup"][n] = (parse(Int, n) - 1) * math_nw["nw"]["$(parse(Int, n)-1)"]["time_elapsed"]
        end
    end

    new["data_model"] = Dict{String,Any}()
    new["data_model"] = PMD.ENGINEERING

    new["multinetwork"] = Dict{Bool,Any}()
    new["multinetwork"] = true

    return new
end


function create_eng_from_math(math, bus_lookup=missing)
    new = Dict{String,Any}()

    if ismissing(bus_lookup)
        bus_lookup = math["bus_lookup"]
    end

    bus_map = Dict{Int,String}(v => k for (k, v) in bus_lookup)

    # init settings dict
    new["settings"] = deepcopy(math["settings"])

    for settings_key in ["vbases_buses", "vbases_default", "vbases_network"]
        new["settings"][settings_key] = Dict{String,Float64}()
        for (bus, val) in get(math["settings"], settings_key, Dict())
            for (math_bus, eng_bus) in bus_map
                if (string(math_bus) == bus)
                    new["settings"][settings_key]["$(eng_bus)"] = get(math["settings"][settings_key], string(math_bus), Inf)
                end
            end
        end
    end

    # TODO: correct vbases_default
    new["settings"]["vbases_default"] = new["settings"]["vbases_buses"]


    new["bus"] = Dict{String,Any}()
    for (i, bus) in get(math, "bus", Dict())
        if !startswith(bus["name"], "_virtual")
            new["bus"]["$(bus["name"])"] = Dict{String,Any}(
                "terminals" => bus["terminals"],
                "status" => bus["bus_type"] != 4 ? ENABLED : DISABLED,
                "grounded" => bus["grounded"],
                "vbase" => bus["vbase"],
            )
        end
    end

    new["line"] = Dict{String,Any}()
    for (i, br) in get(math, "branch", Dict())
        if !startswith(br["name"], "_virtual")
            new["line"]["$(br["name"])"] = Dict{String,Any}(
                "f_bus" => "$(bus_map[br["f_bus"]])",
                "t_bus" => "$(bus_map[br["t_bus"]])",
                "f_connections" => br["f_connections"],
                "t_connections" => br["t_connections"],
                "status" => Status(br["br_status"])
            )
        end
    end

    new["switch"] = Dict{String,Any}()
    for (i, sw) in get(math, "switch", Dict())
        t_bus = sw["t_bus"]
        if t_bus ∉ keys(bus_map)
            for (i, br) in get(math, "branch", Dict())
                if t_bus == br["f_bus"]
                    t_bus = br["t_bus"]
                    break
                end
            end
        end

        new["switch"][sw["name"]] = Dict{String,Any}(
            "f_bus" => bus_map[sw["f_bus"]],
            "t_bus" => bus_map[t_bus],
            "f_connections" => sw["f_connections"],
            "t_connections" => sw["t_connections"],
            "state" => SwitchState(sw["state"]),
            "dispatchable" => Dispatchable(sw["dispatchable"]),
            "status" => Status(sw["status"])
        )
    end

    new["load"] = Dict{String,Any}()
    for (i, load) in get(math, "load", Dict())
        new["load"]["$(load["name"])"] = Dict{String,Any}(
            "bus" => bus_map[load["load_bus"]],
            "connections" => load["connections"],
            "configuration" => load["configuration"],
            "model" => load["model"],
            "dispatchable" => Dispatchable(load["dispatchable"]),
            "pd_nom" => load["pd"],
            "qd_nom" => load["qd"],
            "status" => Status(load["status"])
        )
    end

    new["generator"] = Dict{String,Any}()
    new["solar"] = Dict{String,Any}()
    new["voltage_source"] = Dict{String,Any}()
    for (i, gen) in get(math, "gen", Dict())
        bus_id = gen["gen_bus"]
        if bus_id ∉ keys(bus_map)
            for (i, br) in get(math, "branch", Dict())
                if bus_id == br["f_bus"]
                    bus_id = br["t_bus"]
                    break
                end
            end
        end

        data = Dict{String,Any}(
            "bus" => bus_map[bus_id],
            "connections" => gen["connections"],
            "configuration" => gen["configuration"],
            "pg_ub" => gen["pmax"],
            "qg_ub" => gen["qmax"],
            "inverter" => get(gen, "inverter", GRID_FOLLOWING),
            "status" => Status(gen["gen_status"])
        )

        if startswith(gen["source_id"], "generator") || startswith(gen["source_id"], "rotating_machine")
            data["inverter"] = GRID_FORMING # TODO: assumption
            new["generator"][split(gen["source_id"], "."; limit=2)[end]] = data
        elseif startswith(gen["source_id"], "solar") || startswith(gen["source_id"], "photovoltaic_unit")
            new["solar"][split(gen["source_id"], "."; limit=2)[end]] = data
        elseif startswith(gen["source_id"], "voltage_source") || startswith(gen["source_id"], "energy_source")
            data["inverter"] = GRID_FORMING
            new["voltage_source"][split(gen["source_id"], "."; limit=2)[end]] = data
        end
    end

    new["storage"] = Dict{String,Any}()
    for (i, strg) in get(math, "storage", Dict())
        new["storage"][strg["name"]] = Dict{String,Any}(
            "bus" => bus_map[strg["storage_bus"]],
            "connections" => strg["connections"],
            "configuration" => strg["configuration"],
            "status" => Status(strg["status"]),
            "energy" => strg["energy"],
            "energy_ub" => strg["energy_rating"],
            "inverter" => GRID_FORMING # TODO: hack
        )
    end

    return new
end




