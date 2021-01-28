""
function prepare_network_case(network_file::String; events::Vector{Dict}=Vector{Dict}([]))::Tuple{Dict{String,Any},Dict{String,Any}}
    data_dss = PMD.parse_dss(network_file)

    # TODO: explicitly support DELTA connected generators in LPUBFDiag
    for type in ["pvsystem", "generator"]
        if haskey(data_dss, type)
            for (_,obj) in data_dss[type]
                obj["conn"] = PMD.WYE
            end
        end
    end

    data_eng = PMD.parse_opendss(data_dss)

    apply_events!(data_eng, events)

    PMD.apply_voltage_bounds!(data_eng)

    data_math = PMD.transform_data_model(data_eng; build_multinetwork=true)

    return data_eng, data_math
end


""
function parse_events(events_file::String)::Vector{Dict{String,Any}}
    open(events_file, "r") do f
        JSON.parse(f)
    end
end


""
function apply_events!(network::Dict{String,Any}, events::Vector{Dict})
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


""
function parse_protection_tables(protection_file::String)::Dict{String,DataFrames.DataFrame}
    protection_tables = Dict()

    XLSX.openxlsx(protection_file, mode="r") do xf
        for sheet_name in XLSX.sheetnames(xf)
            protection_tables[sheet_name] = DataFrames.DataFrame(XLSX.gettable(xf[sheet_name])...)
        end
    end

    return protection_tables
end
