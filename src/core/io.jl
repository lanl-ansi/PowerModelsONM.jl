""
function prepare_network_case(network_file::String)::Tuple{Dict{String,Any},Dict{String,Any}}
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

    PMD.apply_voltage_bounds!(data_eng)

    data_math = PMD.transform_data_model(data_eng; build_multinetwork=true)

    return data_eng, data_math
end
