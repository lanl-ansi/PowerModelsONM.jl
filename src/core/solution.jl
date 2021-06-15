"helper function to update switch settings from a solution"
function _update_switch_settings!(data::Dict{String,<:Any}, solution::Dict{String,<:Any})
    for (id, switch) in get(solution, "switch", Dict())
        if haskey(switch, "state")
            data["switch"][id]["state"] = switch["state"]
        end
    end
end


"helper function to update storage capacity for the next subnetwork based on a solution"
function _update_storage_capacity!(data::Dict{String,<:Any}, solution::Dict{String,<:Any})
    for (i, strg) in get(solution, "storage", Dict())
        data["storage"][i]["_energy"] = deepcopy(data["storage"][i]["energy"])
        data["storage"][i]["energy"] = strg["se"]
    end
end
