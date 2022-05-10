"""
    optimize_dispatch!(
        args::Dict{String,<:Any};
        solver::Union{Missing,String}=missing
    )::Dict{String,Any}

Solves optimal dispatch problem in-place, for use in [`entrypoint`](@ref entrypoint), using [`optimize_dispatch`](@ref optimize_dispatch).
If you are using this to optimize after running [`optimize_switches!`](@ref optimize_switches!), this assumes that the correct
switch states from those results have already been propagated into `args["network"]`


`solver` (default: `"nlp_solver"`) specifies which solver to use for the OPF problem from `args["solvers"]`
"""
function optimize_dispatch!(args::Dict{String,<:Any}; solver::Union{Missing,String}=missing)::Dict{String,Any}
    prob_opts = get(get(args["network"], "options", Dict()), "problem", Dict())
    solver = ismissing(solver) ? get(prob_opts, "dispatch-solver", "nlp_solver") : solver
    formulation = _get_formulation(get(prob_opts, "dispatch-formulation", PMD.LPUBFDiagPowerModel))

    args["optimal_dispatch_result"] = optimize_dispatch(args["network"], formulation, args["solvers"][solver]; switching_solutions=get(args, "optimal_switching_results", missing))

    return args["optimal_dispatch_result"]
end


"""
    optimize_dispatch(
        network::Dict{String,<:Any},
        formulation::Type,
        solver;
        switching_solutions::Union{Missing,Dict{String,<:Any}}=missing
    )::Dict{String,Any}

Solve a multinetwork optimal power flow (`solve_mn_mc_opf`) using `formulation` and `solver`
"""
function optimize_dispatch(network::Dict{String,<:Any}, formulation::Type, solver; switching_solutions::Union{Missing,Dict{String,<:Any}}=missing)::Dict{String,Any}
    data = _prepare_dispatch_data(network, switching_solutions)

    @info "running optimal dispatch with $(formulation)"
    solve_mn_opf(data, formulation, solver)
end


"""
    _prepare_dispatch_data(
        network::Dict{String,<:Any},
        switching_solutions::Union{Missing,Dict{String,<:Any}}=missing
    )::Dict{String,Any}

Helper function to prepare data for running a optimal dispatch problem, copying in solutions from the switching results, if present.
"""
function _prepare_dispatch_data(network::Dict{String,<:Any}, switching_solutions::Union{Missing,Dict{String,<:Any}}=missing)::Dict{String,Any}
    data = deepcopy(network)

    if !ismissing(switching_solutions)
        for (n, results) in switching_solutions
            nw = get(results, "solution", Dict())

            shed = collect(keys(filter(x->x.second["status"] != PMD.ENABLED, data["nw"][n]["bus"])))

            for (i,bus) in get(data["nw"][n], "bus", Dict())
                obj_sol = get(get(nw, "bus", Dict()), i, Dict())
                if get(obj_sol, "status", PMD.DISABLED) != PMD.ENABLED
                    data["nw"]["$n"]["bus"][i]["status"] = PMD.DISABLED
                    push!(shed, i)
                end
            end

            for type in ["load", "shunt", "generator", "solar", "voltage_source", "storage"]
                for (i,obj) in get(data["nw"]["$n"], type, Dict{String,Any}())
                    obj_sol = get(get(nw, type, Dict()), i, Dict())
                    if obj["bus"] in shed || get(obj_sol, "status", obj["status"]) == PMD.DISABLED
                        data["nw"]["$n"][type][i]["status"] = PMD.DISABLED
                    end
                    if type ∈ ["storage", "solar", "voltage_source", "generator"] && haskey(obj_sol, "inverter")
                        data["nw"]["$n"][type][i]["inverter"] = obj_sol["inverter"]
                        data["nw"]["$n"][type][i]["control_mode"] = obj_sol["inverter"] == GRID_FORMING ? PMD.ISOCHRONOUS : PMD.FREQUENCYDROOP
                    end
                end
            end

            for (i,line) in get(data["nw"]["$n"], "line", Dict())
                obj_sol = get(get(nw, "line", Dict()), i, Dict())
                if line["f_bus"] in shed || line["t_bus"] in shed || get(obj_sol, "status", line["status"]) == PMD.DISABLED
                    data["nw"]["$n"]["line"][i]["status"] = PMD.DISABLED
                end
            end

            for (i,switch) in get(data["nw"]["$n"], "switch", Dict())
                obj_sol = get(get(nw, "switch", Dict()), i, Dict())

                if haskey(obj_sol, "state")
                    data["nw"]["$n"]["switch"][i]["state"] = nw["switch"][i]["state"]
                end
                data["nw"]["$n"]["switch"][i]["dispatchable"] = PMD.NO

                if switch["f_bus"] in shed || switch["t_bus"] in shed || get(obj_sol, "status", switch["status"]) == PMD.DISABLED
                    data["nw"]["$n"]["switch"][i]["status"] = PMD.DISABLED
                end
            end

            for (i,transformer) in get(data["nw"]["$n"], "transformer", Dict())
                # TODO: debug controls formulations in transformer constraints
                haskey(transformer, "controls") && delete!(data["nw"]["$n"]["transformer"][i], "controls")
                obj_sol = get(get(nw, "transformer", Dict()), i, Dict())
                if any(bus in shed for bus in transformer["bus"]) || get(obj_sol, "status", transformer["status"]) == PMD.DISABLED
                    data["nw"]["$n"]["transformer"][i]["status"] = PMD.DISABLED
                end
            end
        end
    end

    return data
end
