"""
    parse_network!(args::Dict{String,<:Any})

Parses network file given by runtime arguments into its "base_network", i.e., not expanded into a multinetwork,
and "network", which is the multinetwork `ENGINEERING` representation of the network. For use inside
[`entrypoint`](@ref entrypoint).
"""
function parse_network!(args::Dict{String,<:Any})
    if isa(args["network"], String)
        args["base_network"] = PMD.parse_file(args["network"]; dss2eng_extensions=[PowerModelsProtection._dss2eng_solar_dynamics!, PowerModelsProtection._dss2eng_gen_dynamics!], transformations=[PMD.apply_kron_reduction!])

        args["network"] = PMD.make_multinetwork(args["base_network"])
    end
end


# ""
# function prepare_network_case(network_file::String; events::Vector{<:Dict{String,Any}}=Vector{Dict{String,Any}}([]), time_elapsed::Real=1.0, vad::Real=3.0, vm_lb::Real=0.9, vm_ub::Real=1.1, clpu_factor::Real=2.0)::Tuple{Dict{String,Any},Dict{String,Any},Dict{String,Any}}
#     data_dss = PMD.parse_dss(network_file)

#     # TODO: explicitly support DELTA connected generators in LPUBFDiag
#     for type in ["pvsystem", "generator"]
#         if haskey(data_dss, type)
#             for (_,obj) in data_dss[type]
#                 obj["conn"] = PMD.WYE
#             end
#         end
#     end

#     data_eng = PMD.parse_opendss(data_dss; import_all=true)

#     # Allow all loads to be sheddable
#     for (_,load) in data_eng["load"]
#         load["dispatchable"] = PMD.YES
#         load["clpu_factor"] = clpu_factor
#     end

#     data_eng["voltage_source"]["source"]["pg_lb"] = zeros(length(data_eng["voltage_source"]["source"]["connections"]))
#     data_eng["time_elapsed"] = time_elapsed  # 24 hours by default, 1 hr steps

#     PMD.apply_voltage_bounds!(data_eng; vm_lb=vm_lb, vm_ub=vm_ub)
#     PMD.apply_voltage_angle_difference_bounds!(data_eng, vad)

#     adjust_line_limits!(data_eng)

#     # PMD.make_lossless!(data_eng)

#     mn_data_eng = PMD.make_multinetwork(data_eng)

#     parsed_events = apply_events!(mn_data_eng, events)

#     return data_eng, mn_data_eng, parsed_events
# end
