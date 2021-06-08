# ""
# function run_fault_studies(mn_data_eng::Dict{String,Any}, fault_studies::Dict{String,Any}, solver; time_elapsed::Real=1.0)::Vector{Dict{String,Any}}
#     @info "Running fault studies"
#     results = []
#     for (n,nw) in get(mn_data_eng, "nw", Dict())
#         @info "    running fault studies at timestep $n"
#         nw["method"] = "PMD"
#         nw["data_model"] = PMD.ENGINEERING

#         # TODO fix storage IVR constraints in PowerModelsProtection
#         if !isempty(get(nw, "storage", Dict()))
#             @info "    PowerModelsProtection does not yet support storage in IVR formulation, converting storage to generator at timestep $n"
#             convert_storage!(nw)
#             nw["storage"] = Dict{String,Any}()
#         end

#         push!(results, PowerModelsProtection.solve_mc_fault_study(nw, fault_studies, solver))
#     end

#     return results
# end


"""
    run_fault_studies!(args::Dict{String,<:Any})

Runs fault studies defined in faults.json. If no faults file is provided, it will automatically generate faults
using `PowerModelsProtection.build_mc_fault_studies`.
"""
function run_fault_studies!(args::Dict{String,<:Any})
    @info "Running fault studies"

    if !isempty(get(args, "faults", ""))
        if isa(args["faults"], String)
            args["faults"] = parse_faults(args["faults"])
        end
    else
        args["faults"] = PowerModelsProtection.build_mc_fault_studies(args["base_network"])
    end

    fault_studies_results = Dict{String,Any}()
    for n in sort([parse(Int,i) for i in keys(args["network"]["nw"])])
        nw = deepcopy(args["network"]["nw"]["$n"])
        nw["data_model"] = args["network"]["data_model"]
        nw["method"] = "PMD"

        convert_storage!(nw)

        fault_studies_results["$n"] = PowerModelsProtection.solve_mc_fault_study(nw, args["faults"], args["nlp_solver"])
    end

    args["fault_studies_results"] = fault_studies_results
end
