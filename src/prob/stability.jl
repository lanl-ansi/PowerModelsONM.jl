# ""
# function analyze_stability(mn_data_eng::Dict{String,<:Any}, inverters::Dict{String,<:Any}, solver; verbose::Bool=false)::Vector{Bool}
#     @info "Running stability analysis"
#     is_stable = Vector{Bool}([])
#     for n in sort([parse(Int, n) for n in keys(mn_data_eng["nw"])])
#         @info "    running stability analysis at timestep $(n)"
#         eng_data = deepcopy(mn_data_eng["nw"]["$(n)"])

#         PowerModelsStability.add_inverters!(eng_data, inverters)

#         opfSol, mpData_math = PowerModelsStability.run_mc_opf(eng_data, PMD.ACRPowerModel, solver; solution_processors=[PMD.sol_data_model!])

#         @debug opfSol["termination_status"]

#         omega0 = get(inverters, "omega0", 376.9911)
#         rN = get(inverters, "rN", 1000)

#         Atot = PowerModelsStability.obtainGlobal_multi(mpData_math, opfSol, omega0, rN)
#         eigValList = eigvals(Atot)
#         statusTemp = true
#         for eig in eigValList
#             if eig.re > 0
#                 statusTemp = false
#             end
#         end
#         push!(is_stable, statusTemp)
#     end

#     return is_stable
# end


"""
    analyze_stability!(args::Dict{String,<:Any})

Runs small signal stability analysis using PowerModelsStability and determines if each timestep configuration is stable
"""
function analyze_stability!(args::Dict{String,<:Any})
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

    is_stable = Bool[]
    for n in sort([parse(Int, i) for i in keys(args["network"]["nw"])])
        nw = deepcopy(args["network"]["nw"]["$n"])
        nw["data_model"] = args["network"]["data_model"]
        PowerModelsStability.add_inverters!(nw, args["inverters"])

        math_model = PowerModelsStability.transform_data_model(nw)
        opf_solution = PowerModelsStability.solve_mc_opf(math_model, PMD.ACPUPowerModel, args["nlp_solver"])

        Atot = PowerModelsStability.obtainGlobal_multi(math_model, opf_solution, args["inverters"]["omega0"], args["inverters"]["rN"])
        eigValList = eigvals(Atot)
        statusTemp = true
        for eig in eigValList
            if eig.re > 0
                statusTemp = false
            end
        end
        push!(is_stable, statusTemp)
    end
    args["stability_results"] = is_stable
end
