"""
    run_fault_studies!(args::Dict{String,<:Any})

Runs fault studies defined in faults.json. If no faults file is provided, it will automatically generate faults
using `PowerModelsProtection.build_mc_fault_study`.

It will convert storage to limited generators, since storage is not yet supported in IVRU models in PowerModelsProtection

Uses [`run_fault_study`](@ref run_fault_study) to solve the actual fault study.

`solver` will determine which instantiated solver is used, `"nlp_solver"` or `"juniper_solver"`
"""
function run_fault_studies!(args::Dict{String,<:Any}; solver::String="nlp_solver")::Dict{String,Any}
    network = _prepare_fault_study_multinetwork_data(args["network"])

    if !isempty(get(args, "faults", ""))
        if isa(args["faults"], String)
            args["faults"] = parse_faults(args["faults"])
        end
    else
        args["faults"] = PowerModelsProtection.build_mc_fault_study(args["base_network"])
    end

    fault_studies_results = Dict{String,Any}()
    ns = sort([parse(Int, i) for i in keys(args["network"]["nw"])])
    @showprogress length(ns) "Running fault studies... " for n in ns
        fault_studies_results["$n"] = run_fault_study(network["nw"]["$n"], args["faults"], args["solvers"][solver])
    end

    args["fault_studies_results"] = fault_studies_results
end


"""
    run_fault_study(subnetwork::Dict, faults::Dict, solver)::Dict

Uses `PowerModelsProtection.solve_mc_fault_study` to solve multiple faults defined in `faults`, applied
to `subnetwork`, i.e., not a multinetwork, using a nonlinear `solver`.

Requires the use of `PowerModelsDistribution.IVRUPowerModel`.
"""
function run_fault_study(subnetwork::Dict{String,<:Any}, faults::Dict{String,<:Any}, solver)::Dict{String,Any}
    PowerModelsProtection.solve_mc_fault_study(subnetwork, faults, solver)
end


"helper function that helps to prepare all of the subnetworks for use in `PowerModelsProtection.solve_mc_fault_study`"
function _prepare_fault_study_multinetwork_data(network::Dict)
    mn_data = deepcopy(network)

    for (n,nw) in mn_data["nw"]
        nw["data_model"] = mn_data["data_model"]
        nw["method"] = "PMD"
        convert_storage!(nw)
    end

    return mn_data
end
