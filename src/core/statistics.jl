import Statistics: mean


function get_voltage_stats(sol_pu::Dict{Any,<:Any}, data_eng::Dict{String,<:Any})
    voltages = [get(bus, "vm", zeros(length(data_eng["bus"][id]["terminals"]))) for (id,bus) in sol_pu["bus"]]

    return minimum(minimum.(voltages)), mean(mean.(voltages)), maximum(maximum.(voltages))
end


function get_timestep_voltage_stats!(output::Dict{String,<:Any}, sol_pu::Dict{String,<:Any}, data_eng::Dict{String,<:Any})
    for i in sort([parse(Int, k) for k in keys(sol_pu["nw"])])
        min_v, mean_v, max_v = get_voltage_stats(sol_pu["nw"]["$i"], data_eng)
        push!(output["Voltages"]["Min voltage (p.u.)"], min_v)
        push!(output["Voltages"]["Mean voltage (p.u.)"], mean_v)
        push!(output["Voltages"]["Max voltage (p.u.)"], max_v)
    end
end


function get_timestep_load_served!(output::Dict{String,<:Any}, sol_si::Dict{String,<:Any}, mn_data_eng::Dict{String,<:Any})
    for i in sort([parse(Int, k) for k in keys(sol_si["nw"])])
        original_load = sum([sum(load["pd_nom"]) for (_,load) in mn_data_eng["nw"]["$i"]["load"]])
        feeder_served_load = sum([sum(vs["pg"]) for (_,vs) in sol_si["nw"]["$i"]["voltage_source"]])
        der_non_storage_served_load = sum([sum(g["pg"]) for type in ["solar", "generator"] for (_,g) in get(sol_si["nw"]["$i"], type, Dict())])
        der_storage_served_load = sum([sum(s["ps"]) for (_,s) in get(sol_si["nw"]["$i"], "storage", Dict())])
        microgrid_served_load = (der_non_storage_served_load + der_storage_served_load) / original_load * 100
        _bonus_load = (microgrid_served_load - 100)

        push!(output["Load served"]["Feeder load (%)"], feeder_served_load / original_load * 100)  # CHECK
        push!(output["Load served"]["Microgrid load (%)"], microgrid_served_load)  # CHECK
        push!(output["Load served"]["Bonus load via microgrid (%)"], _bonus_load > 0 ? _bonus_load : 0.0)  # CHECK
    end
end


function get_timestep_generator_profiles!(output::Dict{String,<:Any}, sol_si::Dict{String,<:Any})
    for i in sort([parse(Int, k) for k in keys(sol_si["nw"])])
        push!(output["Generator profiles"]["Grid mix (kW)"], sum(Float64[sum(vsource["pg"]) for (_,vsource) in get(sol_si["nw"]["$i"], "voltage_source", Dict())]))
        push!(output["Generator profiles"]["Solar DG (kW)"], sum(Float64[sum(solar["pg"]) for (_,solar) in get(sol_si["nw"]["$i"], "solar", Dict())]))
        push!(output["Generator profiles"]["Energy storage (kW)"], sum(Float64[sum(storage["ps"]) for (_,storage) in get(sol_si["nw"]["$i"], "storage", Dict())]))
        push!(output["Generator profiles"]["Diesel DG (kW)"], sum(Float64[sum(gen["pg"]) for (_,gen) in get(sol_si["nw"]["$i"], "generator", Dict())]))
    end
end


function get_timestep_powerflow_output!(output::Dict{String,<:Any}, sol_pu::Dict{String,<:Any}, data_eng::Dict{String,<:Any})
    for i in sort([parse(Int, k) for k in keys(sol_pu["nw"])])
        timestamp = "$(first(data_eng["time_series"]).second["time"][i])"
        for (id,bus) in sol_pu["nw"]["$i"]["bus"]
            output["Powerflow output"][timestamp][id]["voltage (V)"] = get(bus, "vm", zeros(length(data_eng["bus"][id]["terminals"])))
        end
    end
end


function get_timestep_device_actions!(output::Dict{String,<:Any}, mn_data_math::Dict{String,<:Any})
    switch_map = Dict{String,String}()
    for item in mn_data_math["map"]
        if endswith(item["unmap_function"], "switch!")
            math_id = isa(item["to"], Array) ? split(item["to"][end], ".")[end] : split(item["to"], ".")[end]
            switch_map[math_id] = item["from"]
        end
    end

    for i in sort([parse(Int, k) for k in keys(mn_data_math["nw"])])
        push!(output["Device action timeline"], Dict{String,Any}(
            "Switch configurations" => Dict{String,Any}(switch_map[l] => isa(switch["state"], PMD.SwitchState) ? lowercase(string(switch["state"])) : lowercase(string(PMD.SwitchState(Int(round(switch["state"]))))) for (l, switch) in get(mn_data_math["nw"]["$i"], "switch", Dict()))
        ))
    end
end


function get_timestep_storage_soc!(output::Dict{String,<:Any}, sol_si::Dict{String,<:Any}, data_eng::Dict{String,<:Any})
    for i in sort([parse(Int, k) for k in keys(sol_si["nw"])])
        push!(output["Storage SOC (%)"], 100.0 * sum(strg["se"] for strg in values(sol_si["nw"]["$i"]["storage"])) / sum(strg["energy_ub"] for strg in values(data_eng["storage"])))
    end
end


function get_timestep_protection_settings!(output_data::Dict{String,<:Any}, protection_data::Dict)
    prop_names = propertynames(first(protection_data).first)
    for device_settings in output_data["Device action timeline"]
        if haskey(device_settings, "Switch configurations")
            _config_dict = device_settings["Switch configurations"]
            sw_config = NamedTuple{prop_names}(Tuple(get(_config_dict, string(name), "open") for name in prop_names))
            push!(output_data["Protection Settings"], haskey(protection_data, sw_config) ? protection_data[sw_config] : Dict{String,Any}())
        end
    end
end
