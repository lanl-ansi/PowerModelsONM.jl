"""
    run_fault_studies!(args::Dict{String,<:Any})

Runs fault studies defined in faults.json. If no faults file is provided, it will automatically generate faults
using `PowerModelsProtection.build_mc_fault_study`.
"""
function run_fault_studies!(args::Dict{String,<:Any})::Dict{String,Any}
    @info "Running fault studies"

    if !isempty(get(args, "faults", ""))
        if isa(args["faults"], String)
            args["faults"] = parse_faults(args["faults"])
        end
    else
        args["faults"] = PowerModelsProtection.build_mc_fault_study(args["base_network"])
    end

    fault_studies_results = Dict{String,Any}()
    @showprogress for n in sort([parse(Int,i) for i in keys(args["network"]["nw"])])
        nw = deepcopy(args["network"]["nw"]["$n"])
        nw["data_model"] = args["network"]["data_model"]
        nw["method"] = "PMD"

        convert_storage!(nw)

        fault_studies_results["$n"] = PowerModelsProtection.solve_mc_fault_study(nw, args["faults"], args["nlp_solver"])
    end

    args["fault_studies_results"] = fault_studies_results
end
