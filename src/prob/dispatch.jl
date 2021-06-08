"""
    optimize_dispatch!(args::Dict{String,<:Any})

Solves optimal dispatch problem in-place, for use in [`entrypoint`](@ref entrypoint)
"""
function optimize_dispatch!(args::Dict{String,<:Any})
    args["opt-disp-formulation"] = get_formulation(get(args, "opt-disp-formulation", "lindistflow"))

    @info "running optimal dispatch : $(args["opt-disp-formulation"])"
    args["optimal_dispatch_result"] = PMD.solve_mn_mc_opf(args["network"], args["opt-disp-formulation"], args["juniper_solver"]; solution_processors=[PMD.sol_data_model!])

    PMD._IM.update_data!(args["network"], get(args["optimal_dispatch_result"], "solution", Dict{String, Any}()))
end
