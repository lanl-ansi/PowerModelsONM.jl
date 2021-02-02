""
function _make_dict_keys_str(dict::Dict{<:Any,<:Any})
    o = Dict{String,Any}()
    for (k, v) in dict
        if isa(v, Dict)
            v = _make_dict_keys_str(v)
        end
        o[string(k)] = v
    end

    return o
end


""
function make_multinetwork!(data_eng, data_math, sol_pu, sol_si)
    if !haskey(data_eng, "time_series")
        data_eng["time_series"] = Dict{String,Any}("0" => Dict{String,Any}("time" => [0.0]))
    end

    if !haskey(data_math, "nw")
        sol_pu = Dict{String,Any}("nw" => Dict{String,Any}("0" => sol_pu))
        sol_si = Dict{String,Any}("nw" => Dict{String,Any}("0" => sol_si))
    end
end


""
function apply_events!(network::Dict{String,Any}, events::Vector{<:Dict{String,Any}})
    for event in events
        source_id = event["affected_asset"]
        asset_type, asset_name = split(source_id, ".")
        timestep = event["timestep"]

        if event["event_type"] == "switch"
            start_timestep = Int(round(parse(Float64, timestep)))
            if haskey(network, "nw")
                for (n, nw) in network["nw"]
                    if parse(Int, n) >= start_timestep
                        nw["switch"][asset_name]["state"] = Dict{String,PMD.SwitchState}("closed"=>PMD.CLOSED, "open"=>PMD.OPEN)
                        if haskey(event["event_data"], "dispatchable")
                            nw["switch"][asset_name]["dispatchable"] = event["event_data"]["dispatchable"] ? PMD.YES : PMD.NO
                        end
                    end
                end
            else
                network["switch"][asset_name]["state"] = Dict{String,PMD.SwitchState}("closed"=>PMD.CLOSED, "open"=>PMD.OPEN)
            end

        else
            @warn "event of type '$(event["event_type"])' is not yet supported in PowerModelsONM"
        end
    end
end
