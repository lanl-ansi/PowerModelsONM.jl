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


"expects engineering network (multi of single)"
function apply_events!(network::Dict{String,Any}, events::Vector{<:Dict{String,Any}})
    for event in events
        source_id = event["affected_asset"]
        asset_type, asset_name = split(lowercase(source_id), ".")
        timestep = event["timestep"]

        if event["event_type"] == "switch"
            start_timestep = Int(round(parse(Float64, timestep)))
            if haskey(network, "nw")
                if any(haskey(nw["switch"], asset_name) for (_,nw) in network["nw"])
                    for (n, nw) in network["nw"]
                        if parse(Int, n) >= start_timestep
                            if haskey(nw["switch"], asset_name)
                                if haskey(event["event_data"], "status")
                                    nw["switch"][asset_name]["status"] = Dict{Int,PMD.Status}(1 => PMD.ENABLED, 0 => PMD.DISABLED)[event["event_data"]["status"]]
                                end

                                if haskey(event["event_data"], "state")
                                    nw["switch"][asset_name]["state"] = Dict{String,PMD.SwitchState}("closed"=>PMD.CLOSED, "open"=>PMD.OPEN)[lowercase(event["event_data"]["state"])]
                                end

                                if haskey(event["event_data"], "dispatchable")
                                    nw["switch"][asset_name]["dispatchable"] = event["event_data"]["dispatchable"] ? PMD.YES : PMD.NO
                                end
                            else
                                @info "switch '$(asset_name)' mentioned in events does not exist in data set at timestep $(n)"
                            end
                        end
                    end
                else
                    @info  "switch '$(asset_name)' mentioned in events does not exist in data set"
                end
            else
                network["switch"][asset_name]["state"] = Dict{String,PMD.SwitchState}("closed"=>PMD.CLOSED, "open"=>PMD.OPEN)
            end

        else
            @warn "event of type '$(event["event_type"])' at timestep $(timestep) is not yet supported in PowerModelsONM"
        end
    end
end


""
function build_device_map(map::Vector{<:Dict{String,<:Any}}, device_type::String)::Dict{String,String}
    Dict{String,String}(
        string(split(item["to"], ".")[end]) => item["from"] for item in map if endswith(item["unmap_function"], "$(device_type)!")
    )
end


""
function build_switch_map(map::Vector)::Dict{String,String}
    switch_map = Dict{String,String}()
    for item in map
        if endswith(item["unmap_function"], "switch!")
            math_id = isa(item["to"], Array) ? split(item["to"][end], ".")[end] : split(item["to"], ".")[end]
            switch_map[math_id] = item["from"]
        end
    end
    return switch_map
end


""
function propagate_switch_settings!(mn_data_eng::Dict{String,<:Any}, mn_data_math::Dict{String,<:Any})
    switch_map = build_switch_map(mn_data_math["map"])

    for (n, nw) in mn_data_math["nw"]
        for (i,sw) in get(nw, "switch", Dict())
            mn_data_eng["nw"][n]["switch"][switch_map[i]]["state"] = PMD.SwitchState(Int(round(sw["state"])))
        end
    end
end


# TODO: Remove once storage supported in IVR, assumes MATH Model, with solution already
"converts storage to generators"
function convert_storage!(nw::Dict{String,<:Any})
    for (i, strg) in get(nw, "storage", Dict())
        nw["gen"]["$(length(nw["gen"])+1)"] = Dict{String,Any}(
            "name" => strg["name"],
            "gen_bus" => strg["storage_bus"],
            "connections" => strg["connections"],
            "configuration" => PMD.WYE,
            "control_mode" => PMD.FREQUENCYDROOP,
            "gen_status" => strg["status"],

            "pmin" => strg["ps"] .- 1e-9,
            "pmax" => strg["ps"] .+ 1e-9,
            "pg" => strg["ps"],
            "qmin" => strg["qs"] .- 1e-9,
            "qmax" => strg["qs"] .+ 1e-9,
            "qg" => strg["qs"],

            "model" => 2,
            "startup" => 0,
            "shutdown" => 0,
            "cost" => [100.0, 0.0],
            "ncost" => 2,

            "index" => length(nw["gen"])+1,
            "source_id" => strg["source_id"],

            "vbase" => nw["bus"]["$(strg["storage_bus"])"]["vbase"],  # grab vbase from bus
            "zx" => [0, 0, 0], # dynamics required by PMP, treat like voltage source
        )
    end
end


"voltage angle bounds"
function apply_voltage_angle_bounds!(eng::Dict{String,<:Any}, vad::Real)
    if haskey(eng, "line")
        for (_,line) in eng["line"]
            line["vad_lb"] = fill(-vad, length(line["f_connections"]))
            line["vad_ub"] = fill( vad, length(line["f_connections"]))
        end
    end
end
