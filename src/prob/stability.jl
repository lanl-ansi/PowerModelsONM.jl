"""
    run_stability_analysis!(
        args::Dict{String,<:Any};
        validate::Bool=true,
        formulation::Type=PMD.ACRUPowerModel,
        solver::String="nlp_solver"
    )::Dict{String,Bool}

Runs small signal stability analysis using PowerModelsStability and determines if each timestep configuration is stable,
in-place, storing the results in `args["stability_results"]`, for use in [`entrypoint`](@ref entrypoint), Uses
[`run_stability_analysis`](@ref run_stability_analysis)

If `validate`, raw inverters data will be validated against JSON schema

The formulation can be specified with `formulation`, but note that it must result in `"vm"` and `"va"` variables in the
solution, or else `PowerModelsDistribution.sol_data_model!` must support converting the voltage variables into
polar coordinates.

`solver` (default: `"nlp_solver"`) specifies which solver in `args["solvers"]` to use for the stability analysis (NLP OPF)
"""
function run_stability_analysis!(args::Dict{String,<:Any}; validate::Bool=true, formulation::Type=PMD.ACRUPowerModel, solver::String="nlp_solver")::Dict{String,Bool}
    if !isempty(get(args, "inverters", ""))
        if isa(args["inverters"], String)
            args["inverters"] = parse_inverters(args["inverters"]; validate=validate)
        end
    else
        args["inverters"] = Dict{String,Any}(
            "omega0" => 376.9911,
            "rN" => 1000,
            "inverters" => Dict{String,Any}(),
        )
    end

    args["stability_results"] = run_stability_analysis(args["network"], args["inverters"], args["solvers"][solver]; formulation=formulation, switching_solutions=get(args, "optimal_switching_results", missing), distributed=get(args, "nprcos", 1) > 1)
end


"""
    run_stability_analysis(
        network::Dict{String,<:Any},
        inverters::Dict{String,<:Any},
        solver;
        formulation::Type=PMD.ACRUPowerModel,
        switching_solutions::Union{Missing,Dict{String,<:Any}}=missing,
        distributed::Bool=false
    )::Dict{String,Bool}

Runs small signal stability analysis using PowerModelsStability and determines if each timestep configuration is stable

`inverters` is an already parsed inverters file using [`parse_inverters`](@ref parse_inverters)

The formulation can be specified with `formulation`, but note that it must result in `"vm"` and `"va"` variables in the
solution, or else `PowerModelsDistribution.sol_data_model!` must support converting the voltage variables into
polar coordinates.

`solver` for stability analysis (NLP OPF)
"""
function run_stability_analysis(network::Dict{String,<:Any}, inverters::Dict{String,<:Any}, solver; formulation::Type=PMD.ACRUPowerModel, switching_solutions::Union{Missing,Dict{String,<:Any}}=missing, distributed::Bool=false)::Dict{String,Bool}
    mn_data = _prepare_stability_multinetwork_data(network, inverters, switching_solutions)

    ns = sort([parse(Int, i) for i in keys(mn_data["nw"])])
    if !distributed
        is_stable = []
        for n in ns
            push!(is_stable, run_stability_analysis(mn_data["nw"]["$n"], inverters["omega0"], inverters["rN"], solver; formulation=formulation))
        end
    else
        is_stable = @showprogress pmap(ns; distributed=distributed) do n
            run_stability_analysis(mn_data["nw"]["$n"], inverters["omega0"], inverters["rN"], solver; formulation=formulation)
        end
    end

    return Dict{String,Bool}([(string(i),s) for (i,s) in enumerate(is_stable)])
end


"""
    run_stability_analysis(
        subnetwork::Dict{String,<:Any},
        omega0::Real,
        rN::Int,
        solver;
        formulation::Type=PMD.ACPUPowerModel
    )::Bool

Runs stability analysis on a single subnetwork (not a multinetwork) using a nonlinear `solver`.
"""
function run_stability_analysis(subnetwork::Dict{String,<:Any}, omega0::Real, rN::Int, solver; formulation::Type=PMD.ACPUPowerModel)::Bool
    math_model = PowerModelsStability.transform_data_model(subnetwork)
    opf_solution = PowerModelsStability.solve_mc_opf(math_model, formulation, solver; solution_processors=[PMD.sol_data_model!])

    Atot = PowerModelsStability.PMS.get_global_stability_matrix(math_model, opf_solution, omega0, rN)
    eigValList = LinearAlgebra.eigvals(Atot)
    statusTemp = true
    for eig in eigValList
        if eig.re > 0
            statusTemp = false
        end
    end

    return statusTemp
end


"""
    _prepare_stability_multinetwork_data(
        network::Dict{String,<:Any},
        inverters::Dict{String,<:Any},
        switching_solutions::Union{Missing,Dict{String,<:Any}}=missing,
        dispatch_solution::Union{Missing,Dict{String,<:Any}}=missing
    )::Dict{String,Any}

Helper function to prepare the multinetwork data for stability analysis (adds inverters, data_model).
"""
function _prepare_stability_multinetwork_data(network::Dict{String,<:Any}, inverters::Dict{String,<:Any}, switching_solutions::Union{Missing,Dict{String,<:Any}}=missing, dispatch_solution::Union{Missing,Dict{String,<:Any}}=missing)::Dict{String,Any}
    mn_data = _prepare_dispatch_data(network, switching_solutions)

    for (n, nw) in mn_data["nw"]
        nw["data_model"] = mn_data["data_model"]

        _inverters = Dict{String,Any}[]
        for _inv in get(inverters, "inverters", Dict{String,Any}[])
            if get(get(get(nw, "bus", Dict{String,Any}()), _inv["busID"], Dict{String,Any}()), "status", PMD.DISABLED) == PMD.ENABLED
                push!(_inverters, _inv)
            end
        end
        PowerModelsStability.add_inverters!(nw, merge(filter(x->x.first!="inverters", inverters), Dict{String,Any}("inverters" => _inverters)))
    end

    return mn_data
end
