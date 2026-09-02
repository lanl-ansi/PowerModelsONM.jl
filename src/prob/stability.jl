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
function run_stability_analysis!(args::Dict{String,<:Any}; validate::Bool=true)::Dict{String,Bool}
    #see if this can be modified to work with pmd.engineeringmodel
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

    args["stability_results"] = run_stability_analysis(
        args["network"],
        args["inverters"],
        args["solvers"][get_setting(args, ("options", "problem", "stability-solver"), "nlp_solver")];
        formulation=parse(AbstractUnbalancedPowerModel, get_setting(args, ("options", "problem", "stability-formulation"))),
        switching_solutions=get(args, "optimal_switching_results", missing),
        distributed=get_setting(args, ("options","problem","concurrent-stability-studies"), true)
    )
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
function run_stability_analysis(
    network::Dict{String,<:Any},
    inverters::Dict{String,<:Any},
    solver;
    formulation::Type=PMD.ACRUPowerModel,
    switching_solutions::Union{Missing,Dict{String,<:Any}}=missing,
    distributed::Bool=false
    )::Dict{String,Bool}
    mn_data = _prepare_stability_multinetwork_data(network, inverters, switching_solutions)

    ns = sort([parse(Int, i) for i in keys(mn_data["nw"])])
    if !distributed
        is_stable = []
        for n in ns
            push!(is_stable, run_stability_analysis(mn_data["nw"]["$n"], inverters["omega0"], inverters["rN"], solver; formulation=formulation))
        end
    else
        is_stable = pmap(ns; distributed=distributed) do n
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

#overloading the method from pms to reduce the dependencies a bit
function PMS.transform_data_model(
    data_eng::PMD.EngineeringModel{PMD.NetworkModel};
    eng2math_extensions::Vector{<:Function}=Function[],
    kwargs...
)::Dict{String,Any}

    data_math = PMD.transform_data_model(
        data_eng;
        eng2math_extensions=[
            PMS._eng2math_inverter_bus!,
            eng2math_extensions...,
        ],
        eng2math_passthrough=PMS._pms_eng2math_passthrough,
        global_keys=PMS._pms_global_keys,
        kwargs...,
    )

    return PMD._convert_model_to_dict(data_math)
end

function PMS._eng2math_inverter_bus!(
    data_math::PMD.MathematicalModel{PMD.NetworkModel},
    data_eng::PMD.EngineeringModel{PMD.NetworkModel},
)
    return PMS._eng2math_inverter_bus!(
        data_math.data,
        data_eng.data,
    )
end

function run_stability_analysis(subnetwork::Union{Dict{String,<:Any}, PMD.EngineeringModel}, omega0::Real, rN::Int, solver; formulation::Type=PMD.ACPUPowerModel)::Bool
    math_model = PMS.transform_data_model(subnetwork)
    opf_solution = PMS.solve_mc_opf(math_model, formulation, solver; solution_processors=[PMD.sol_data_model!])

    Atot = PMS.get_global_stability_matrix(math_model, opf_solution, omega0, rN)
    eigValList = LinearAlgebra.eigvals(Atot)
    statusTemp = true
    for eig in eigValList
        if eig.re > 0
            statusTemp = false
        end
    end

    return statusTemp
end

#copying this function in from pmStability
function add_inverters!(pmd_data::Dict{String,<:Any}, inverter_data::Dict{String,<:Any}; pop_solar::Bool=false)
    for (invInd, inverter) in enumerate(get(inverter_data, "inverters", []))
        bus_gen_terms = get(pmd_data, "is_kron_reduced", false) ? collect(1:3) : collect(1:4)

        # add bus/bus_lookup
        PMD.add_bus!(
            pmd_data,
            "inverter_$(invInd)";
            terminals=bus_gen_terms,
            grounded=get(pmd_data, "is_kron_reduced", false) ? Int[] : [4],
            rg=[0.0],
            xg=[0.0],
            mp=inverter["mp"],
            mq=inverter["mq"],
            tau=inverter["tau"],
            inverter_bus=true)

        # add gen
        PMD.add_generator!(
            pmd_data,
            "invGen_$(invInd)",
            "inverter_$(invInd)",
            Int[1,2,3];
            pg=Vector{Float64}(inverter["pg"]),
            qg=Vector{Float64}(inverter["qg"]),
            pg_ub=Vector{Float64}(inverter["pg_ub"]),
            qg_ub=Vector{Float64}(inverter["qg_ub"]),
            pg_lb=Vector{Float64}(inverter["pg_lb"]),
            qg_lb=Vector{Float64}(inverter["qg_lb"]),
            vg=Vector{Float64}(inverter["vg"]),
            phases=3
        )
        # TODO bug in PMD?
        pmd_data["generator"]["invGen_$(invInd)"]["connections"] = bus_gen_terms

        # add connecting branch
        PMD.add_line!(
            pmd_data,
            "invLine_$(invInd)",
            inverter["busID"],
            "inverter_$(invInd)",
            Int[1,2,3],
            Int[1,2,3],
            rs=inverter["r"],
            xs=inverter["x"]
        )

    end

    if pop_solar
        # pop out the solar since it is replaced by the inverters
        delete!(pmd_data,"solar")
    end
end

function add_inverters!(pmd_data::PMD.EngineeringModel, inverter_data::Dict{String,<:Any}; pop_solar::Bool=false)
    for (invInd, inverter) in enumerate(get(inverter_data, "inverters", []))
        bus_gen_terms = get(pmd_data, "is_kron_reduced", false) ? collect(1:3) : collect(1:4)

        # add bus/bus_lookup
        PMD.add_bus!(
            pmd_data,
            "inverter_$(invInd)";
            terminals=bus_gen_terms,
            grounded=get(pmd_data, "is_kron_reduced", false) ? Int[] : [4],
            rg=[0.0],
            xg=[0.0],
            mp=inverter["mp"],
            mq=inverter["mq"],
            tau=inverter["tau"],
            inverter_bus=true)

        # add gen
        PMD.add_generator!(
            pmd_data,
            "invGen_$(invInd)",
            "inverter_$(invInd)",
            Int[1,2,3];
            pg=Vector{Float64}(inverter["pg"]),
            qg=Vector{Float64}(inverter["qg"]),
            pg_ub=Vector{Float64}(inverter["pg_ub"]),
            qg_ub=Vector{Float64}(inverter["qg_ub"]),
            pg_lb=Vector{Float64}(inverter["pg_lb"]),
            qg_lb=Vector{Float64}(inverter["qg_lb"]),
            vg=Vector{Float64}(inverter["vg"]),
            phases=3
        )
        # TODO bug in PMD?
        pmd_data["generator"]["invGen_$(invInd)"]["connections"] = bus_gen_terms

        # add connecting branch
        PMD.add_line!(
            pmd_data,
            "invLine_$(invInd)",
            inverter["busID"],
            "inverter_$(invInd)",
            Int[1,2,3],
            Int[1,2,3],
            rs=inverter["r"],
            xs=inverter["x"]
        )

    end

    if pop_solar
        # pop out the solar since it is replaced by the inverters
        delete!(pmd_data,"solar")
    end
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
function _prepare_stability_multinetwork_data(
    network::Dict{String,<:Any},
    inverters::Dict{String,<:Any},
    switching_solutions::Union{Missing,Dict{String,<:Any}}=missing,
    dispatch_solution::Union{Missing,Dict{String,<:Any}}=missing
    )::Dict{String,Any}
    mn_data = _prepare_dispatch_data(network, switching_solutions)

    for (n, nw) in mn_data["nw"]
        nw["data_model"] = mn_data["data_model"]

        _inverters = Dict{String,Any}[]
        for _inv in get(inverters, "inverters", Dict{String,Any}[])
            if get(get(get(nw, "bus", Dict{String,Any}()), _inv["busID"], Dict{String,Any}()), "status", PMD.DISABLED) == PMD.ENABLED
                push!(_inverters, _inv)
            end
        end
        #where tf is this function. can't find it in pmStability
        add_inverters!(nw, merge(filter(x->x.first!="inverters", inverters), Dict{String,Any}("inverters" => _inverters)))
    end

    return mn_data
end
