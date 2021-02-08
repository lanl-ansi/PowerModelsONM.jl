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

    data_eng["time_elapsed"] = 1.0  # 24 hours by default, 1 hr steps

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


""
function parse_protection_tables(protection_file::String)::Dict{NamedTuple,Dict{String,Any}}
    _tables = Dict()

    XLSX.openxlsx(protection_file, mode="r") do xf
        for sheet_name in XLSX.sheetnames(xf)
            _tables[sheet_name] = DataFrames.DataFrame(XLSX.gettable(xf[sheet_name])...)
        end
    end

    _configs = _tables["Configuration"]
    _switches = names(_configs)
    _namedtuple_names = Tuple(Symbol(replace(sw, "'" => "")) for sw in _switches)

    configurations = Dict{String,NamedTuple}()
    for (i, row) in enumerate(eachrow(_configs))
        configurations["S$i"] = NamedTuple{_namedtuple_names}(Tuple(lowercase(string(PMD.SwitchState(row[sw]))) for sw in _switches))
        configurations["Sg$i"] = NamedTuple{_namedtuple_names}(Tuple(lowercase(string(PMD.SwitchState(row[sw]))) for sw in _switches))
        # TODO how to deal with Sg configs?
    end

    protection_data = Dict{NamedTuple,Dict{String,Any}}()
    for (name, table) in _tables
        if name != "Configuration"
            protection_data[configurations[name]] = Dict{String,Any}(col => table[!, col] for col in names(table))
        end
    end

    return protection_data
end
