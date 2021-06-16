"""
    run_stability_analysis!(args::Dict{String,<:Any}; validate::Bool=true, formulation::Type=PMD.ACRPowerModel)::Dict{String,Any}

Runs small signal stability analysis using PowerModelsStability and determines if each timestep configuration is stable

If `validate`, raw inverters data will be validated against JSON schema

The formulation can be specified with `formulation`, but note that it must result in `"vm"` and `"va"` variables in the
solution, or else `PowerModelsDistribution.sol_data_model!` must support converting the voltage variables into
polar coordinates.
"""
function run_stability_analysis!(args::Dict{String,<:Any}; validate::Bool=true, formulation::Type=PMD.ACRUPowerModel, solver::String="nlp_solver")::Dict{String,Any}
    if !isempty(get(args, "inverters", ""))
        if isa(args["inverters"], String)
            args["inverters"] = parse_inverters(args["inverters"]; validate=validate)
        end
    else
        # TODO what to do if no inverters are defined?
        args["inverters"] = Dict{String,Any}(
            "omega0" => 376.9911,
            "rN" => 1000,
        )
    end

    network = _prepare_stability_multinetwork_data(args["network"], args["inverters"])

    is_stable = Dict{String,Any}()
    ns = sort([parse(Int, i) for i in keys(network["nw"])])
    @showprogress length(ns) "Running stability analysis... " for n in ns
        is_stable["$n"] = run_stability_analysis(network["nw"]["$n"], args["inverters"]["omega0"], args["inverters"]["rN"], args[solver]; formulation=formulation)
    end

    args["stability_results"] = is_stable
end


"""
    run_stability_analysis(subnetwork::Dict{String,<:Any}, omega0::Real, rN::Int, solver; formulation::Type=PMD.ACRUPowerModel)::Bool

Runs stability analysis on a single subnetwork (not a multinetwork) using a nonlinear `solver`.
"""
function run_stability_analysis(subnetwork::Dict{String,<:Any}, omega0::Real, rN::Int, solver; formulation::Type=PMD.ACRUPowerModel)::Bool
    math_model = PowerModelsStability.transform_data_model(subnetwork)
    opf_solution = PowerModelsStability.solve_mc_opf(math_model, formulation, solver; solution_processors=[PMD.sol_data_model!])

    Atot = PowerModelsStability.obtainGlobal_multi(math_model, opf_solution, omega0, rN)
    eigValList = eigvals(Atot)
    statusTemp = true
    for eig in eigValList
        if eig.re > 0
            statusTemp = false
        end
    end

    return statusTemp
end


"helper function to prepare the multinetwork data for stability analysis (adds inverters, data_model)"
function _prepare_stability_multinetwork_data(network::Dict{String,<:Any}, inverters::Dict{String,<:Any})::Dict{String,Any}
    mn_data = deepcopy(network)

    for (n, nw) in mn_data["nw"]
        nw["data_model"] = mn_data["data_model"]
        PowerModelsStability.add_inverters!(nw, inverters)
    end

    return mn_data
end
