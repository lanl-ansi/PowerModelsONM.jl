""
function get_voltage_stats(sol::Dict{String,<:Any}, data_eng::Dict{String,<:Any}; per_unit::Bool=true)
    if !per_unit
        bus_vbase, line_vbase = PMD.calc_voltage_bases(data_eng, data_eng["settings"]["vbases_default"])
        voltages = [get(bus, "vm", zeros(length(data_eng["bus"][id]["terminals"]))) ./ bus_vbase[id] for (id,bus) in sol["bus"]]
    else
        voltages = [get(bus, "vm", zeros(length(data_eng["bus"][id]["terminals"]))) for (id,bus) in sol["bus"]]
    end

    return minimum(minimum.(voltages)), mean(mean.(voltages)), maximum(maximum.(voltages))
end


""
get_timestep_voltage_stats!(args::Dict{String,<:Any}) = get_timestep_voltage_stats!(args["output_data"], get(args["optimal_dispatch_result"], "solution", Dict{String,Any}()), args["base_network"])


""
function get_timestep_voltage_stats!(output::Dict{String,<:Any}, sol_pu::Dict{String,<:Any}, data_eng::Dict{String,<:Any})
    output["Voltages"]["Min voltage (p.u.)"] = Real[]
    output["Voltages"]["Mean voltage (p.u.)"] = Real[]
    output["Voltages"]["Max voltage (p.u.)"] = Real[]

    per_unit = sol_pu["per_unit"]
    for i in sort([parse(Int, k) for k in keys(sol_pu["nw"])])
        min_v, mean_v, max_v = get_voltage_stats(sol_pu["nw"]["$i"], data_eng; per_unit=per_unit)
        push!(output["Voltages"]["Min voltage (p.u.)"], min_v)
        push!(output["Voltages"]["Mean voltage (p.u.)"], mean_v)
        push!(output["Voltages"]["Max voltage (p.u.)"], max_v)
    end
end


""
get_timestep_load_served!(args::Dict{String,<:Any}) = get_timestep_load_served!(args["output_data"], get(args["optimal_dispatch_result"], "solution", Dict{String,Any}()), args["network"])


""
function get_timestep_load_served!(output::Dict{String,<:Any}, sol_si::Dict{String,<:Any}, mn_data_eng::Dict{String,<:Any})
    output["Load served"]["Feeder load (%)"] = Real[]
    output["Load served"]["Microgrid load (%)"] = Real[]
    output["Load served"]["Bonus load via microgrid (%)"] = Real[]

    for i in sort([parse(Int, k) for k in keys(sol_si["nw"])])
        original_load = sum([sum(load["pd_nom"]) for (_,load) in mn_data_eng["nw"]["$i"]["load"]])
        feeder_served_load = sum([sum(vs["pg"]) for (_,vs) in sol_si["nw"]["$i"]["voltage_source"]])
        der_non_storage_served_load = !isempty(get(sol_si["nw"]["$i"], "generator", Dict())) || !isempty(get(sol_si["nw"]["$i"], "solar", Dict())) ? sum([sum(g["pg"]) for type in ["solar", "generator"] for (_,g) in get(sol_si["nw"]["$i"], type, Dict())]) : 0.0
        der_storage_served_load = !isempty(get(sol_si["nw"]["$i"], "storage", Dict())) ? sum([-sum(s["ps"]) for (_,s) in get(sol_si["nw"]["$i"], "storage", Dict())]) : 0.0
        microgrid_served_load = (der_non_storage_served_load + der_storage_served_load) / original_load * 100
        _bonus_load = (microgrid_served_load - 100)

        push!(output["Load served"]["Feeder load (%)"], feeder_served_load / original_load * 100)  # CHECK
        push!(output["Load served"]["Microgrid load (%)"], microgrid_served_load)  # CHECK
        push!(output["Load served"]["Bonus load via microgrid (%)"], _bonus_load > 0 ? _bonus_load : 0.0)  # CHECK
    end
end


""
get_timestep_generator_profiles!(args::Dict{String,<:Any}) = get_timestep_generator_profiles!(args["output_data"], get(args["optimal_dispatch_result"], "solution", Dict{String,Any}()))


""
function get_timestep_generator_profiles!(output::Dict{String,<:Any}, sol_si::Dict{String,<:Any})
    output["Generator profiles"]["Grid mix (kW)"] = Real[]
    output["Generator profiles"]["Solar DG (kW)"] = Real[]
    output["Generator profiles"]["Energy storage (kW)"] = Real[]
    output["Generator profiles"]["Diesel DG (kW)"] = Real[]

    for i in sort([parse(Int, k) for k in keys(sol_si["nw"])])
        push!(output["Generator profiles"]["Grid mix (kW)"], sum(Float64[sum(vsource["pg"]) for (_,vsource) in get(sol_si["nw"]["$i"], "voltage_source", Dict())]))
        push!(output["Generator profiles"]["Solar DG (kW)"], sum(Float64[sum(solar["pg"]) for (_,solar) in get(sol_si["nw"]["$i"], "solar", Dict())]))
        push!(output["Generator profiles"]["Energy storage (kW)"], sum(Float64[-sum(storage["ps"]) for (_,storage) in get(sol_si["nw"]["$i"], "storage", Dict())]))
        push!(output["Generator profiles"]["Diesel DG (kW)"], sum(Float64[sum(gen["pg"]) for (_,gen) in get(sol_si["nw"]["$i"], "generator", Dict())]))
    end
end


""
get_timestep_powerflow_output!(args::Dict{String,<:Any}) = get_timestep_powerflow_output!(args["output_data"], get(args["optimal_dispatch_result"], "solution", Dict{String,Any}()), args["base_network"])


""
function get_timestep_powerflow_output!(output::Dict{String,<:Any}, sol_pu::Dict{String,<:Any}, data_eng::Dict{String,<:Any})
    output["Powerflow output"] = Dict{String,Any}[]

    for i in sort([parse(Int, k) for k in keys(sol_pu["nw"])])
        n = "$i"
        nw = sol_pu["nw"][n]
        nw_pf = Dict{String,Any}(
        "bus" => Dict{String,Any}()
        )
        for (id,bus) in get(nw, "bus", Dict())
            nw_pf["bus"][id] = Dict{String,Any}("voltage (V)" => get(bus, "vm", zeros(length(data_eng["bus"][id]["terminals"]))))
        end

        if !isempty(get(nw, "storage", Dict()))
            nw_pf["storage"] = Dict{String,Any}()
            for (id,strg) in nw["storage"]
                nw_pf["storage"][id] = Dict{String,Any}(
                    "real power setpoint (kW)" => get(strg, "ps", zeros(length(data_eng["storage"][id]["connections"]))),
                    "reactive power setpoint (kVar)" => get(strg, "qs", zeros(length(data_eng["storage"][id]["connections"])))
                )
            end
        end

        for gen_type in ["solar", "generator", "voltage_source"]
            if !isempty(get(nw, gen_type, Dict()))
                nw_pf[gen_type] = Dict{String,Any}()
                for (id,gen) in nw[gen_type]
                    nw_pf[gen_type][id] = Dict{String,Any}(
                        "real power setpoint (kW)" => get(gen, "pg", zeros(length(data_eng[gen_type][id]["connections"]))),
                        "reactive power setpoint (kVar)" => get(gen, "qg", zeros(length(data_eng[gen_type][id]["connections"])))
                    )
                end
            end
        end

        push!(output["Powerflow output"], nw_pf)
    end
end


get_timestep_device_actions!(args::Dict{String,<:Any}) = get_timestep_device_actions!(args["output_data"], args["optimal_switching_results"], args["network"])


function get_timestep_device_actions!(output::Dict{String,<:Any}, osw_results::Dict{String,<:Any}, mn_data_eng::Dict{String,<:Any})
    output["Device action timeline"] = Dict{String,Any}[]

    for n in sort([parse(Int, k) for k in keys(mn_data_eng["nw"])])
        _out = Dict{String,Any}(
            "Switch configurations" => Dict{String,Any}(id => lowercase(string(switch["state"])) for (id, switch) in get(mn_data_eng["nw"]["$n"], "switch", Dict()))
        )

        shedded_loads = Vector{String}([])
        for (id, load) in get(osw_results["$n"], "load", Dict())
            if round(get(load, "status", 1)) ≉ 1
               push!(shedded_loads, id)
            end
        end

        _out["Shedded loads"] = shedded_loads

        push!(output["Device action timeline"], _out)
    end
end


function get_timestep_device_actions!(output::Dict{String,<:Any}, osw_result::Vector{<:Dict{String,<:Any}}, mn_data_math::Dict{String,<:Any})
    switch_map = build_switch_map(mn_data_math["map"])
    load_map = build_device_map(mn_data_math["map"], "load")
    for i in sort([parse(Int, k) for k in keys(mn_data_math["nw"])])
        n = "$i"
        nw = mn_data_math["nw"][n]
        oswr = get(osw_result[i], "solution", Dict())

        _out = Dict{String,Any}(
            "Switch configurations" => Dict{String,Any}(switch_map[l] => isa(switch["state"], PMD.SwitchState) ? lowercase(string(switch["state"])) : lowercase(string(PMD.SwitchState(Int(round(switch["state"]))))) for (l, switch) in get(mn_data_math["nw"]["$i"], "switch", Dict()))
        )

        shedded_loads = Vector{String}([])
        for (id, load) in get(oswr, "load", Dict())
            if round(get(load, "status", 1)) ≉ 1
               push!(shedded_loads, load_map[id])
            end
        end

        _out["Shedded loads"] = shedded_loads

        push!(output["Device action timeline"], _out)
    end
end


""
get_timestep_storage_soc!(args::Dict{String,<:Any}) = get_timestep_storage_soc!(args["output_data"], get(args["optimal_dispatch_result"], "solution", Dict{String,Any}()), args["base_network"])


""
function get_timestep_storage_soc!(output::Dict{String,<:Any}, sol_si::Dict{String,<:Any}, data_eng::Dict{String,<:Any})
    for i in sort([parse(Int, k) for k in keys(sol_si["nw"])])
        push!(output["Storage SOC (%)"], 100.0 * sum(strg["se"] for strg in values(sol_si["nw"]["$i"]["storage"])) / sum(strg["energy_ub"] for strg in values(data_eng["storage"])))
    end
end


""
function get_timestep_protection_settings!(output_data::Dict{String,<:Any}, protection_data::Dict)
    if !isempty(protection_data)
        prop_names = propertynames(first(protection_data).first)
        for device_settings in output_data["Device action timeline"]
            if haskey(device_settings, "Switch configurations")
                _config_dict = device_settings["Switch configurations"]
                sw_config = NamedTuple{prop_names}(Tuple(get(_config_dict, string(name), "open") for name in prop_names))
                push!(output_data["Protection Settings"], haskey(protection_data, sw_config) ? protection_data[sw_config] : Dict{String,Any}())
            end
        end
    end
end


get_timestep_fault_currents!(args::Dict{String,<:Any}) = get_timestep_fault_currents!(args["output_data"], args["faults"], args["fault_studies_results"])


"""
"""
function get_timestep_fault_currents!(output_data::Dict{String,<:Any}, faults::Dict{String,<:Any}, fault_results::Dict{String,<:Any}, base_network::Dict{String,<:Any})
    output_data["Fault currents"] = Dict{String,Any}[]

    for n in sort([parse(Int, i) for i in keys(fault_results)])
        _output = Dict{String,Any}()
        for (bus_id, fault_types) in fault_results["$n"]
            for (fault_type, sub_faults) in fault_types
                for (fault_id, result) in sub_faults
                    # TODO support multiple faults?
                    fault = first(faults[bus_id][fault_type][fault_id]["fault"]).second

                    if !isempty(get(result, "solution", Dict()))
                        _output["$(bus_id)_$(fault_type)_$(fault_id)"] = Dict{String,Any}(
                            "fault" => Dict{String,Any}(
                                "bus" => fault["bus"],
                                "type" => fault["type"],
                                "g" => fault["g"],
                                "b" => fault["b"],
                                "connections" => fault["connections"]
                            ),
                            "switch" => Dict{String,Any}(
                                id => Dict{String,Any}(
                                    "Voltage (V)" => result["solution"]["bus"][base_network["switch"][id]["f_bus"]]["vm"],
                                    "Fault current (A)" => switch["fault_current"],
                                    "Re(I0) (A)" => get(switch, "zero_sequence_current_real", 0.0),
                                    "Re(I1) (A)" => get(switch, "positive_sequence_current_real", 0.0),
                                    "Re(I2) (A)" => get(switch, "negative_sequence_current_real", 0.0),
                                    "Im(I0) (A)" => get(switch, "zero_sequence_current_imag", 0.0),
                                    "Im(I1) (A)" => get(switch, "positive_sequence_current_imag", 0.0),
                                    "Im(I2) (A)" => get(switch, "negative_sequence_current_imag", 0.0),
                                    "|I0| (A)" => get(switch, "zero_sequence_current_mag", 0.0),
                                    "|I1| (A)" => get(switch, "positive_sequence_current_mag", 0.0),
                                    "|I2| (A)" => get(switch, "negative_sequence_current_mag", 0.0),
                                ) for (id, switch) in get(result["solution"], "switch", Dict())
                            )
                        )
                    end
                end
            end
        end
        push!(output_data, _output)
    end
end


get_timestep_stability!(args::Dict{String,<:Any}) = get_timestep_stability!(args["output_data"], Vector{<:Union{Missing,Bool}}([args["stability_results"]["$n"] for n in sort([parse(Int, i) for i in keys(args["stability_results"])])]))


""
function get_timestep_stability!(output_data::Dict{String,<:Any}, is_stable::Vector{<:Union{Bool,Missing}})
    output_data["Small signal stable"] = is_stable
end


get_timestep_switch_changes!(args::Dict{String,<:Any}) = get_switch_changes!(args["output_data"], args["network"])


""
function get_switch_changes!(output_data::Dict{String,<:Any}, mn_data_eng::Dict{String,<:Any})
    output_data["Switch changes"] = Vector{Vector{String}}([])

    _switch_configs = Dict(s => Dict(PMD.OPEN => "open", PMD.CLOSED => "closed")[sw["state"]] for (s,sw) in mn_data_eng["nw"]["1"]["switch"])
    for timestep in output_data["Device action timeline"]
        switch_configs = timestep["Switch configurations"]
        _changes = String[]
        for (switch, state) in switch_configs
            if get(_switch_configs, switch, state) != state
                push!(_changes, switch)
            end
        end
        _switch_configs = deepcopy(switch_configs)
        push!(output_data["Switch changes"], _changes)
    end
end
