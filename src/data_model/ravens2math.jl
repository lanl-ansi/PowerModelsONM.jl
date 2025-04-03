function transform_data_model_ravens(ravens::T; global_keys::Set{String}=Set{String}(), ravens2math_extensions::Vector{<:Function}=Function[] ,ravens2math_passthrough::Dict{String,<:Vector{<:String}}=Dict{String,Vector{String}}(), kwargs...)::T where T <: Dict{String,Any}
    PMD.transform_data_model_ravens(
        ravens;
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
    for (name, gen_data) in get(data_math, "gen", Dict{Any,Dict{String,Any}}())
        gen_name = gen_data["name"]
        rotng_machns = data_ravens["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["RegulatingCondEq"]["RotatingMachine"]
        if haskey(rotng_machns, gen_name)
            gen_data = rotng_machns[gen_name]
            if haskey(gen_data, "RotatingMachine.RotatingMachineResponse")
                gen_data["gen_model"] = gen_data["RotatingMachine.RotatingMachineResponse"]
            end
            if haskey(gen_data, "RotatingMachine.Inverter")
                gen_data["inverter"] = gen_data["RotatingMachine.Inverter"] # GRID_FOLLOWING, GRID_FORMING
            end
        end
    end
end


function ravens2math_add_storage_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    # TODO: where to get from RAVENS-JSON?
    for (name, storage_data) in get(data_math, "storage", Dict{Any,Dict{String,Any}}())
        storage_name = storage_data["name"]
        storages = data_ravens["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["EnergyConnection"]["RegulatingCondEq"]["PowerElectronicsConnection"]
        if haskey(storages, storage_name)
            storage_data = storages[storage_name]
            if haskey(storage_data, "PowerElectronicsConnection.PowerElectronicsUnit")
                storage_data["gen_model"] = get(storage_data, "BatteryUnit.BatteryResponse", 1)
            end
            if haskey(storage_data, "PowerElectronicsConnection.Inverter")
                storage_data["inverter"] = storage_data["PowerElectronicsConnection.Inverter"] # GRID_FOLLOWING, GRID_FORMING
            end
            if haskey(storage_data, "PowerElectronicsConnection.PhaseUnbalanceLimit")
                storage_data["phase_unbalance_ub"] = storage_data["PowerElectronicsConnection.PhaseUnbalanceLimit"]
            end
        end
    end
end


function ravens2math_add_switch_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    # TODO: where to get from RAVENS-JSON?
    for (name, switch_data) in get(data_math, "switch", Dict{Any,Dict{String,Any}}())
        switch_name = switch_data["name"]
        switches = data_ravens["PowerSystemResource"]["Equipment"]["ConductingEquipment"]["Switch"]
        if haskey(switches, switch_name)
            switch_data = switches[switch_name]
            if haskey(switch_data, "Switch.VoltageMagnitudeUpperBound")
                switch_data["vm_delta_pu_ub"] = switch_data["Switch.VoltageMagnitudeUpperBound"]
            end
            if haskey(switch_data, "Switch.VoltageAngleUpperBound")
                switch_data["va_delta_deg_ub"] = switch_data["Switch.VoltageAngleUpperBound"]
            end
        end
    end
end






