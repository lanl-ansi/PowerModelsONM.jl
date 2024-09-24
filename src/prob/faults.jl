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
function run_fault_studies!(args::Dict{String,<:Any})::Dict{String,Any}
    args["fault_studies_results"] = run_fault_studies(
        args["fault_network"],
        switching_solutions=get(args, "optimal_switching_results", missing),
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
    network::Dict{String,<:Any};
    switching_solutions::Union{Missing,Dict{String,<:Any}}=missing,
    distributed::Bool=false
)::Dict{String,Any}

    fault_studies_results = Dict{String,Any}()
    if !ismissing(switching_solutions)
        switch_states = Dict{String,Dict{String,PMD.SwitchState}}(n => Dict{String,PMD.SwitchState}(s => sw["state"] for (s, sw) in get(nw, "switch", Dict())) for (n, nw) in switching_solutions)

        ns = sort([parse(Int, i) for i in keys(switching_solutions)])

        if !distributed
            _results = []
            for n in ns
                if (n > 1 && switch_states["$(n)"] == switch_states["$(n-1)"])
                    # skip identical configurations
                    push!(_results, missing)
                else
                    push!(_results, run_fault_study(_apply_switch_results(network, switching_solutions["$n"])))
                end
            end
        else
            _results = pmap(ns; distributed=distributed) do n
                if (n > 1 && switch_states["$(n)"] == switch_states["$(n-1)"])
                    # skip identical configurations
                    missing
                else
                    run_fault_study(_apply_switch_results(network, switching_solutions["$n"]))
                end
            end
        end

        # fill skipped results
        for (i, n) in enumerate(ns)
            if ismissing(_results[i]) && i > 1
                fault_studies_results["$(n)"] = fault_studies_results["$(n-1)"]
            elseif ismissing(_results[i])
                fault_studies_results["$(n)"] = Dict{String,Any}()
            else
                fault_studies_results["$(n)"] = _results[i]
            end
        end
    else
        fault_studies_results["0"] = run_fault_study(network)
    end

    return _format_fault_results(fault_studies_results)
end


"""
    _apply_switch_results(data_in::Dict{String,<:Any}, switching_solution::Dict{String,<:Any})

Helper functing to help apply switch states and generation statuses.
"""
function _apply_switch_results(data_in::Dict{String,<:Any}, switching_solution::Dict{String,<:Any})
    data = deepcopy(data_in)

    shed = collect(keys(filter(x -> x.second["status"] != PMD.ENABLED, data["bus"])))

    if !ismissing(switching_solution)
        nw = get(switching_solution, "solution", Dict())

        for type in ["load", "shunt", "generator", "solar", "voltage_source", "storage"]
            for (i, obj) in get(data, type, Dict{String,Any}())
                obj_sol = get(get(nw, type, Dict()), i, Dict())
                if obj["bus"] in shed || get(obj_sol, "status", obj["status"]) == PMD.DISABLED
                    data[type][i]["status"] = PMD.DISABLED
                end
                if type ∈ ["storage", "solar", "voltage_source", "generator"]
                    if haskey(obj_sol, "inverter")
                        data[type][i]["grid_forming"] = obj_sol["inverter"] == GRID_FORMING ? true : false
                    else
                        data[type][i]["grid_forming"] = false
                    end
                end
            end
        end

        for (i, switch) in get(data, "switch", Dict())
            obj_sol = get(get(nw, "switch", Dict()), i, Dict())

            if haskey(obj_sol, "state")
                data["switch"][i]["state"] = nw["switch"][i]["state"]
            end
            data["switch"][i]["dispatchable"] = PMD.NO
        end
    end

    return data
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
function run_fault_study(subnetwork::Dict{String,<:Any})::Dict{String,Any}
    PMP.solve_mc_fault_study(PMP.instantiate_mc_admittance_model(subnetwork), build_output=true)
end


function _format_fault_results(fault_results)
    results = Dict{String,Any}()

    for (n, nw) in fault_results
        results[n] = Dict{String,Any}()

        for (bus, faults) in nw
            results[n][bus] = Dict{String,Any}()
            for fault_type in ["ll", "lg", "3pg", "llg", "3p"]
                if haskey(faults, fault_type)
                    results[n][bus][fault_type] = Dict{String,Any}()
                    if fault_type in ["ll", "llg"]
                        for (i, ((phase_a, phase_b), fault)) in enumerate(faults)
                            results[n][bus][fault_type]["$i"] = Dict{String,Any}("termination_status" => "SOLVED", "solution" => Dict{String,Any}())
                        end
                    elseif fault_type == "lg"
                        for (phase, fault) in faults
                            results[n][bus][fault_type]["$phase"] = Dict{String,Any}()
                        end
                    else
                        results[n][bus][fault_type]["1"] = Dict{String,Any}()
                    end
                end
            end
        end
    end

    return fault_results
end
