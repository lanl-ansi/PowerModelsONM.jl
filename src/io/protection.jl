# "DEPRECIATED: protection optimization will take place outside of the ONM algorithm"
# function _parse_protection_tables(protection_file::String)::Dict{NamedTuple,Dict{String,Any}}
#     _tables = Dict()

#     XLSX.openxlsx(protection_file, mode="r") do xf
#         for sheet_name in XLSX.sheetnames(xf)
#             if sheet_name != "ConfigTable"
#                 _table = xf[sheet_name][:]
#                 _protection_types = Dict(idx => lowercase(strip(split(type,"-")[end])) for (idx,type) in enumerate(_table[1,:]) if !ismissing(type))
#                 type_idxs = sort([i for (i,_) in _protection_types])
#                 _col_headers = Dict(idx => lowercase(header) for (idx,header) in enumerate(_table[2,:]) if !ismissing(header))

#                 _data = _table[3:end,:]
#                 _tables[sheet_name] = Dict(type => Dict(header => [] for (jdx,header) in _col_headers) for (idx,type) in _protection_types)
#                 current_type = _protection_types[1]
#                 for (idx,header) in _col_headers
#                     current_type = haskey(_protection_types,idx) ? _protection_types[idx] : current_type
#                     for value in _data[:,idx]
#                         push!(_tables[sheet_name][current_type][header], value)
#                     end
#                 end
#             else
#                 _tables[sheet_name] = DataFrames.DataFrame(XLSX.gettable(xf[sheet_name])...)
#             end
#         end
#     end

#     _configs = _tables["ConfigTable"]
#     _config_num = _configs[!, Symbol("Config S#")]
#     _switches = [n for n in names(_configs) if !startswith(n, "Config")]
#     _namedtuple_names = Tuple(Symbol(replace(sw, "'" => "")) for sw in _switches)

#     configurations = Dict{String,NamedTuple}()
#     for (i, row) in enumerate(eachrow(_configs))
#         configurations["S$(_config_num[i])"] = NamedTuple{_namedtuple_names}(Tuple(lowercase(string(PMD.SwitchState(row[sw]))) for sw in _switches))
#     end

#     protection_data = Dict{NamedTuple,Dict{String,Any}}()
#     for (name, table) in _tables
#         if name != "ConfigTable"
#             protection_data[configurations[name]] = table
#         end
#     end

#     return protection_data
# end
