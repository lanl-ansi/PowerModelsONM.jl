"""
    optimize_switches!(args::Dict{String,<:Any})

Optimizes switch states (therefore shedding load or not) in-place, for use in [`entrypoint`](@ref entrypoint)
"""
function optimize_switches!(args::Dict{String,<:Any})::Dict{String,Any}
    @info "running switch optimization (mld)"

    results = Dict{String,Any}()
    @showprogress for n in sort([parse(Int, i) for i in keys(args["network"]["nw"])])
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
