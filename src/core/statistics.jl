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


function get_timestep_load_served!(output::Dict{String,<:Any}, sol_si::Dict{String,<:Any}, data_eng::Dict{String,<:Any})
    for i in sort([parse(Int, k) for k in keys(sol_si["nw"])])
        original_load = sum([haskey(load, "time_series") ? sum(data_eng["time_series"][load["time_series"]["pd_nom"]]["values"][i]) : sum(load["pd_nom"]) for (_,load) in data_eng["load"]])
        served_load = sum([sum(load["pd"]) for (_,load) in sol_si["nw"]["$i"]["load"]])
        push!(output["Load served"]["Feeder load (%)"], served_load / original_load)  # FIX
        push!(output["Load served"]["Microgrid load (%)"], 0.0)  # TODO
        push!(output["Load served"]["Bonus load via microgrid (%)"], 0.0)  # TODO
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
