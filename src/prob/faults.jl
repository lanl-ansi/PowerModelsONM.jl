"""
    run_fault_studies!(
        args::Dict{String,<:Any};
        validate::Bool=true,
        solver::String="nlp_solver"
    )::Dict{String,Any}

Runs fault studies using `args["faults"]`, if defined, and stores the results in-place in
`args["fault_stuides_results"]`, for use in [`entrypoint`](@ref entrypoint), using
[`run_fault_studies`](@ref run_fault_studies)
"""
function run_fault_studies!(args::Dict{String,<:Any}; validate::Bool=true)::Dict{String,Any}
    if !isempty(get(args, "faults", ""))
        if isa(args["faults"], String)
            args["faults"] = parse_faults(args["faults"]; validate=validate)
        end
    else
        args["faults"] = PMP.build_mc_sparse_fault_study(args["base_network"])
    end

    args["fault_studies_results"] = run_fault_studies(
        args["network"],
        args["solvers"][get_setting(args, ("options", "problem", "fault-studies-solver"), "nlp_solver")];
        faults=args["faults"],
        switching_solutions=get(args, "optimal_switching_results", missing),
        dispatch_solution=get(args, "optimal_dispatch_result", missing),
        distributed=get_setting(args, ("options", "problem", "concurrent-fault-studies"), true)
    )
end


"""
    run_fault_studies(
        network::Dict{String,<:Any},
        solver;
        faults::Dict{String,<:Any}=Dict{String,Any}(),
        switching_solutions::Union{Missing,Dict{String,<:Any}}=missing,
        dispatch_solution::Union{Missing,Dict{String,<:Any}}=missing,
        distributed::Bool=false
    )::Dict{String,Any}

Runs fault studies defined in ieee13_faults.json. If no faults file is provided, it will automatically generate faults
using `PowerModelsProtection.build_mc_fault_study`.

It will convert storage to limited generators, since storage is not yet supported in IVRU models in PowerModelsProtection

Uses [`run_fault_study`](@ref run_fault_study) to solve the actual fault study.

`solver` will determine which instantiated solver is used, `"nlp_solver"` or `"juniper_solver"`

"""
function run_fault_studies(
    network::Dict{String,<:Any},
    solver;
    faults::Dict{String,<:Any}=Dict{String,Any}(),
    switching_solutions::Union{Missing,Dict{String,<:Any}}=missing,
    dispatch_solution::Union{Missing,Dict{String,<:Any}}=missing,
    distributed::Bool=false
    )::Dict{String,Any}
    mn_data = _prepare_fault_study_multinetwork_data(network, switching_solutions, dispatch_solution)

    switch_states = Dict{String,Dict{String,PMD.SwitchState}}(n => Dict{String,PMD.SwitchState}(s => sw["state"] for (s,sw) in get(nw, "switch", Dict())) for (n,nw) in get(mn_data, "nw", Dict()))

    shedded_buses = Dict{String,Vector{String}}(n => collect(keys(filter(x->x.second["status"] == PMD.DISABLED, mn_data["nw"][n]["bus"]))) for (n,nw) in get(mn_data, "nw", Dict()))
    if !ismissing(switching_solutions)
        for (n,shed) in shedded_buses
            nw = get(switching_solutions["$n"], "solution", Dict{String,Any}())
            for (i,bus) in get(nw, "bus", Dict())
                if get(bus, "status", PMD.ENABLED) == PMD.DISABLED
                    push!(shed, i)
                end
            end
        end
    elseif !ismissing(dispatch_solution)
        for (n,shed) in shedded_buses
            solution_buses = collect(keys(get(get(get(dispatch_solution, "nw", Dict()), "$n", Dict()), "bus", Dict())))
            for (i, bus) in get(mn_data["nw"]["$n"], "bus", Dict{String,Any}())
                if !(i in solution_buses)
                    push!(shed, i)
                end
            end
        end
    end

    if isempty(faults)
        faults = PMP.build_mc_sparse_fault_study(first(network["nw"]).second)
    end

    fault_studies_results = Dict{String,Any}()
    ns = sort([parse(Int, i) for i in keys(get(mn_data, "nw", Dict()))])
    if !distributed
        _results = []
        for n in ns
            _faults = filter(x->!(x.first in shedded_buses["$(n)"]), faults)
            if (n > 1 && switch_states["$(n)"] == switch_states["$(n-1)"]) || isempty(_faults)
                # skip identical configurations or all faults missing
                push!(_results, missing)
            else
                push!(_results, run_fault_study(mn_data["nw"]["$(n)"], _faults, solver))
            end
        end
    else
        _results = pmap(ns; distributed=distributed) do n
            _faults = filter(x->!(x.first in shedded_buses["$(n)"]), faults)
            if (n > 1 && switch_states["$(n)"] == switch_states["$(n-1)"]) || isempty(_faults)
                # skip identical configurations or all faults missing
                missing
            else
                run_fault_study(mn_data["nw"]["$(n)"], _faults, solver)
            end
        end
    end

    # fill skipped results
    for (i,n) in enumerate(ns)
        if ismissing(_results[i]) && i > 1
            fault_studies_results["$(n)"] = fault_studies_results["$(n-1)"]
        elseif ismissing(_results[i])
            fault_studies_results["$(n)"] = Dict{String,Any}()
        else
            fault_studies_results["$(n)"] = _results[i]
        end
    end

    return fault_studies_results
end


"""
    run_fault_study(
        subnetwork::Dict{String,<:Any},
        faults::Dict{String,<:Any},
        solver
    )::Dict{String,Any}

Uses `PowerModelsProtection.solve_mc_fault_study` to solve multiple faults defined in `faults`, applied
to `subnetwork`, i.e., not a multinetwork, using a nonlinear `solver`.

Requires the use of `PowerModelsDistribution.IVRUPowerModel`.
"""
function run_fault_study(subnetwork::Dict{String,<:Any}, faults::Dict{String,<:Any}, solver)::Dict{String,Any}
    PMP.solve_mc_fault_study(subnetwork, faults, solver)
end


"""
    _prepare_fault_study_multinetwork_data(
        network::Dict{String,<:Any},
        switching_solutions::Union{Missing,Dict{String,<:Any}}=missing,
        dispatch_solution::Union{Missing,Dict{String,<:Any}}=missing
    )

Helper function that helps to prepare all of the subnetworks for use in `PowerModelsProtection.solve_mc_fault_study`
"""
function _prepare_fault_study_multinetwork_data(
    network::Dict{String,<:Any},
    switching_solutions::Union{Missing,Dict{String,<:Any}}=missing,
    dispatch_solution::Union{Missing,Dict{String,<:Any}}=missing
    )::Dict{String,Any}
    data = _prepare_dispatch_data(network, switching_solutions)

    if !ismissing(dispatch_solution)
        for (n, nw) in data["nw"]
            nw_sol = get(get(get(dispatch_solution, "solution", Dict()), "nw", Dict()), "$n", Dict())
            for (i, _) in get(nw, "bus", Dict())
                if haskey(nw_sol, "bus") && haskey(nw_sol["bus"], i)
                    if haskey(nw_sol["bus"][i], "vm")
                        data["nw"]["$n"]["bus"][i]["vm"] = nw_sol["bus"][i]["vm"]
                    end
                    if haskey(nw_sol["bus"][i], "va")
                        data["nw"]["$n"]["bus"][i]["va"] = nw_sol["bus"][i]["va"]
                    end
                end
            end
        end
    end

    for (n,nw) in get(data, "nw", Dict{String,Any}())
        data["nw"]["$n"]["data_model"] = data["data_model"]
        data["nw"]["$n"]["method"] = "PMD"

        for type in ["solar", "storage", "generator"]
            if haskey(nw, type)
                for (i,obj) in nw[type]
                    if haskey(obj, "inverter") && obj["inverter"] == GRID_FORMING
                        data["nw"]["$n"][type][i]["grid_forming"] = true

                        bus = data["nw"]["$n"]["bus"]["$(obj["bus"])"]
                        if !haskey(bus, "vm")
                            data["nw"]["$n"]["bus"]["$(obj["bus"])"]["vm"] = [ones(3)..., zeros(length(bus["terminals"]))...][bus["terminals"]]
                        end
                        if !haskey(bus, "va")
                            data["nw"]["$n"]["bus"]["$(obj["bus"])"]["va"] = [0.0, -120.0, 120.0, zeros(length(bus["terminals"]))...][bus["terminals"]]
                        end
                    end
                end
            end
        end
    end

    return data
end
