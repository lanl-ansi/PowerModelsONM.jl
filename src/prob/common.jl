"""
    build_solver_instances!(args::Dict{String,Any})

Creates the Optimizers in-place (within the args dict data structure), for use inside [`entrypoint`](@ref entrypoint)
"""
function build_solver_instances!(args::Dict{String,<:Any})::Tuple
    args["nlp_solver"] = optimizer_with_attributes(Ipopt.Optimizer, "tol" => get(get(args, "settings", Dict()), "solver_tolerance", 1e-4), "print_level" => get(args, "verbose", false) ? 3 : get(args, "debug", false) ? 5 : 0)

    if get(args, "gurobi", false)
        args["mip_solver"] = optimizer_with_attributes(() -> Gurobi.Optimizer(GRB_ENV), "OutputFlag" => get(args, "verbose", false) || get(args, "debug", false) ? 1 : 0, "NonConvex" => 2)
    else
        args["mip_solver"] = optimizer_with_attributes(Cbc.Optimizer, "logLevel" => get(args, "verbose", false) || get(args, "debug", false) ? 1 : 0)
    end

    juniper_log_levels = get(args, "verbose", false) ? [:Error, :Warn] : get(args, "debug", false) ? [:Error, :Warn, :Info] : []
    args["juniper_solver"] = optimizer_with_attributes(Juniper.Optimizer, "nl_solver" => args["nlp_solver"], "mip_solver" => args["mip_solver"], "log_levels" => juniper_log_levels)

    args["nlp_solver"], args["mip_solver"], args["juniper_solver"]
end
