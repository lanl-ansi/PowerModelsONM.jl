# ""
# function optimize_switches!(mn_data_math::Dict{String,Any}, osw_mld_prob::Function, solver; events::Dict{String,Any}=Dict{String,<:Any}(), solution_processors::Vector=[], max_switch_actions::Int=0)::Vector{Dict{String,Any}}
#     @info "running switching + load shed optimization"

#     filtered_logger = LoggingExtras.ActiveFilteredLogger(juniper_log_filter, Logging.global_logger())

#     results = []
#     for n in sort([parse(Int, i) for i in keys(mn_data_math["nw"])])
#         @info "    running osw+mld at timestep $n"
#         n = "$n"
#         nw = mn_data_math["nw"][n]
#         nw["per_unit"] = mn_data_math["per_unit"]
#         nw["data_model"] = PMD.MATHEMATICAL
#         if max_switch_actions > 0
#             nw["max_switch_changes"] = max_switch_actions
#         end

#         if !isempty(results)
#             update_start_values!(nw, results[end]["solution"])
#             update_switch_settings!(nw, results[end]["solution"]; events=get(events["nw"], "$n", Dict{String,Any}()))
#             update_storage_capacity!(nw, results[end]["solution"])
#         end
#         r = Logging.with_logger(filtered_logger) do
#             r = osw_mld_prob(nw, PMD.LPUBFDiagPowerModel, solver; solution_processors=solution_processors, ref_extensions=[ref_add_load_blocks!])
#         end

#         update_start_values!(nw, r["solution"])
#         update_switch_settings!(nw, r["solution"])

#         push!(results, r)
#     end

#     solution = Dict("nw" => Dict("$n" => result["solution"] for (n, result) in enumerate(results)))

#     # TODO: Multinetwork problem
#     #results = run_mn_mc_osw_mi(mn_data_math, PMD.LPUBFDiagPowerModel, solver; solution_processors=solution_processors)
#     #solution = results["solution"]

#     # TODO: moved to loop, re-enable if switching to mn problem
#     # update_start_values!(mn_data_math, solution)
#     # update_switch_settings!(mn_data_math, solution)

#     apply_load_shed!(mn_data_math, Dict{String,Any}("solution" => solution))

#     return results
# end


"""
    optimize_switches!(args::Dict{String,<:Any})

Optimizes switch states (therefore shedding load or not) in-place, for use in [`entrypoint`](@ref entrypoint)
"""
function optimize_switches!(args::Dict{String,<:Any})
    @info "running switch optimization (mld)"

    results = Dict{String,Any}()
    for n in sort([parse(Int, i) for i in keys(args["network"]["nw"])])
        nw = args["network"]["nw"]["$n"]

        nw["data_model"] = args["network"]["data_model"]

        if haskey(results, "$(n-1)") && haskey(results["$(n-1)"], "solution")
            update_switch_settings!(nw, results["$(n-1)"]["solution"])
            update_storage_capacity!(nw, results["$(n-1)"]["solution"])
        end

        prob = get(args, "gurobi", false) ? solve_mc_osw_mld_mi : solve_mc_osw_mld

        results["$n"] = prob(nw, PMD.LPUBFDiagPowerModel, get(args, "gurobi", false) ? args["mip_solver"] : args["juniper_solver"]; solution_processors=[PMD.sol_data_model!], ref_extensions=[ref_add_load_blocks!])

        delete!(nw, "data_model")

        if haskey(results["$n"], "solution")
            update_switch_settings!(nw, results["$n"]["solution"])
        end
    end

    args["optimal_switching_results"] = results
end
