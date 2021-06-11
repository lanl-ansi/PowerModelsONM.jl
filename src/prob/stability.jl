"""
    analyze_stability!(args::Dict{String,<:Any})

Runs small signal stability analysis using PowerModelsStability and determines if each timestep configuration is stable
"""
function run_stability_analysis!(args::Dict{String,<:Any})::Dict{String,Any}
    @info "Running stability analysis"

    if !isempty(get(args, "inverters", ""))
        if isa(args["inverters"], String)
            args["inverters"] = parse_inverters(args["inverters"])
        end
    else
        # TODO what to do if no inverters are defined?
        args["inverters"] = Dict{String,Any}(
            "omega0" => 376.9911,
            "rN" => 1000,
        )
    end

    is_stable = Dict{String,Any}()
    @showprogress for n in sort([parse(Int, i) for i in keys(args["network"]["nw"])])
        nw = deepcopy(args["network"]["nw"]["$n"])
        nw["data_model"] = args["network"]["data_model"]
        PowerModelsStability.add_inverters!(nw, args["inverters"])

        math_model = PowerModelsStability.transform_data_model(nw)
        opf_solution = PowerModelsStability.solve_mc_opf(math_model, PMD.ACRUPowerModel, args["nlp_solver"]; solution_processors=[PMD.sol_data_model!])

        Atot = PowerModelsStability.obtainGlobal_multi(math_model, opf_solution, args["inverters"]["omega0"], args["inverters"]["rN"])
        eigValList = eigvals(Atot)
        statusTemp = true
        for eig in eigValList
            if eig.re > 0
                statusTemp = false
            end
        end
        is_stable["$n"] = statusTemp
    end
    args["stability_results"] = is_stable
end
