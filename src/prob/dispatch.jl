"""
    optimize_dispatch!(args::Dict{String,<:Any})

Solves optimal dispatch problem in-place, for use in [`entrypoint`](@ref entrypoint), using [`optimize_dispatch`](@ref optimize_dispatch)
"""
function optimize_dispatch!(args::Dict{String,<:Any}; update_network_data::Bool=true)::Dict{String,Any}
    args["opt-disp-formulation"] = get_formulation(get(args, "opt-disp-formulation", "lindistflow"))

    args["optimal_dispatch_result"] = optimize_dispatch(args["network"], args["opt-disp-formulation"], args["juniper_solver"])

    update_network_data && PMD._IM.update_data!(args["network"], get(args["optimal_dispatch_result"], "solution", Dict{String, Any}()))

    return args["optimal_dispatch_result"]
end


"""
    optimize_dispatch(network::Dict{String,<:Any}, formulation::Type, solver)::Dict{String,Any}

Solve a multinetwork optimal power flow using `formulation` and `solver`
"""
function optimize_dispatch(network::Dict{String,<:Any}, formulation::Type, solver)::Dict{String,Any}
    @info "running optimal dispatch with $(formulation)"
    PMD.solve_mn_mc_opf(network, formulation, solver; solution_processors=[PMD.sol_data_model!])
end
