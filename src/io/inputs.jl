""
function prepare_network_case(network_file::String; events::Vector{<:Dict{String,Any}}=Vector{Dict{String,Any}}([]))::Tuple{Dict{String,Any},Dict{String,Any}}
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

    # PMD.make_lossless!(data_eng)

    mn_data_eng = PMD._build_eng_multinetwork(data_eng)

    return data_eng, mn_data_eng
end


""
function parse_events(events_file::String)::Vector{Dict{String,Any}}
    open(events_file, "r") do f
        JSON.parse(f)
    end
end


