"""
    optimize_dispatch!(args::Dict{String,<:Any}; update_network_data::Bool=false, solver::String=get(args, "opt-disp-solver", "nlp_solver"))::Dict{String,Any}

Solves optimal dispatch problem in-place, for use in [`entrypoint`](@ref entrypoint), using [`optimize_dispatch`](@ref optimize_dispatch).
If you are using this to optimize after running [`optimize_switches!`](@ref optimize_switches!), this assumes that the correct
switch states from those results have already been propagated into `args["network"]`

If `update_network_data` (default: false) the results of the optimization will be automatically merged into
`args["network"]`.

`solver` (default: `"nlp_solver"`) specifies which solver to use for the OPF problem from `args["solvers"]`
"""
function optimize_dispatch!(args::Dict{String,<:Any}; update_network_data::Bool=false, solver::String=get(args, "opt-disp-solver", "nlp_solver"))::Dict{String,Any}
    args["opt-disp-formulation"] = _get_dispatch_formulation(get(args, "opt-disp-formulation", "lindistflow"))

    if update_network_data
        args["network"] = apply_switch_solutions!(args["network"], get(args, "optimal_switching_results", Dict{String,Any}()))
    end

    args["optimal_dispatch_result"] = optimize_dispatch(args["network"], args["opt-disp-formulation"], args["solvers"][solver]; switching_solutions=get(args, "optimal_switching_results", missing))

    update_network_data && recursive_merge(args["network"], get(args["optimal_dispatch_result"], "solution", Dict{String, Any}()))

    return args["optimal_dispatch_result"]
end


"""
    optimize_dispatch(network::Dict{String,<:Any}, formulation::Type, solver; switching_solutions::Union{Missing,Dict{String,<:Any}}=missing)::Dict{String,Any}

Solve a multinetwork optimal power flow (`solve_mn_mc_opf`) using `formulation` and `solver`
"""
function optimize_dispatch(network::Dict{String,<:Any}, formulation::Type, solver; switching_solutions::Union{Missing,Dict{String,<:Any}}=missing)::Dict{String,Any}
    data = _prepare_dispatch_data(network, switching_solutions)

    @info "running optimal dispatch with $(formulation)"
    solve_mn_mc_opf_oltc_capc(
        data,
        formulation,
        solver;
        solution_processors=[PMD.sol_data_model!, solution_reference_buses!],
        eng2math_passthrough=Dict{String,Vector{String}}(
            "storage"=>String["phase_unbalance_factor"]
        )
    )
end


"prepares data for running a optimal dispatch problem, copying in solutions from the switching results, if present"
function _prepare_dispatch_data(network::Dict{String,<:Any}, switching_solutions::Union{Missing,Dict{String,<:Any}}=missing)::Dict{String,Any}
    data = deepcopy(network)

    if !ismissing(switching_solutions)
        for (n, results) in switching_solutions
            shed = String[]

            nw = get(results, "solution", Dict())

            for (i,bus) in get(nw, "bus", Dict())
                if round(Int, get(bus, "status", 1)) != 1
                    data["nw"]["$n"]["bus"][i]["status"] = PMD.DISABLED
                    push!(shed, i)
                end
            end

            for type in ["load", "shunt", "generator", "solar", "voltage_source", "storage"]
                for (i,obj) in get(data["nw"]["$n"], type, Dict{String,Any}())
                    if obj["bus"] in shed
                        data["nw"]["$n"][type][i]["status"] = PMD.DISABLED
                    end
                end
            end

            for (i,line) in get(data["nw"]["$n"], "line", Dict())
                if line["f_bus"] in shed || line["t_bus"] in shed
                    data["nw"]["$n"]["line"][i]["status"] = PMD.DISABLED
                end
            end

            for (i,switch) in get(data["nw"]["$n"], "switch", Dict())
                if haskey(nw, "switch") && haskey(nw["switch"], i) && haskey(nw["switch"][i], "state")
                    data["nw"]["$n"]["switch"][i]["state"] = nw["switch"][i]["state"]
                end

                if switch["f_bus"] in shed || switch["t_bus"] in shed
                    data["nw"]["$n"]["switch"][i]["status"] = PMD.DISABLED
                end
            end

            for (i,transformer) in get(data["nw"]["$n"], "transformer", Dict())
                if any(bus in shed for bus in transformer["bus"])
                    data["nw"]["$n"]["transformer"][i]["status"] = PMD.DISABLED
                end
            end
        end
    end

    return data
end
