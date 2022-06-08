"default ref_extension functions"
const _default_ref_extensions = Function[
    ref_add_load_blocks!,
    ref_add_options!,
]

"default solution_processor functions"
const _default_solution_processors = Function[
    PMD.sol_data_model!,
    solution_reference_buses!,
    solution_statuses!,
    solution_inverter!,
    PowerModelsONM.solution_blocks!,
]

"""
    solve_onm_model(
        data::Union{Dict{String,<:Any}, String},
        model_type::Type,
        solver::Any,
        model_builder::Function;
        solution_processors::Vector{Function}=Function[],
        eng2math_passthrough::Dict{String,Vector{String}}=Dict{String,Vector{String}}(),
        ref_extensions::Vector{Function}=Function[],
        multinetwork::Bool=false,
        kwargs...
    )::Dict{String,Any}

Custom version of `PowerModelsDistribution.solve_mc_model` that automatically includes the solution processors,
ref extensions and eng2math_passthroughs required for ONM problems.
"""
function solve_onm_model(
    data::Union{Dict{String,<:Any}, String},
    model_type::Type,
    solver::Any,
    model_builder::Function;
    solution_processors::Vector{Function}=Function[],
    eng2math_passthrough::Dict{String,Vector{String}}=Dict{String,Vector{String}}(),
    ref_extensions::Vector{Function}=Function[],
    multinetwork::Bool=false,
    global_keys::Set{String}=Set{String}(),
    kwargs...)::Dict{String,Any}

    return PMD.solve_mc_model(
        data,
        model_type,
        solver,
        model_builder;
        multinetwork=multinetwork,
        solution_processors=Function[
            _default_solution_processors...,
            solution_processors...
        ],
        ref_extensions=Function[
            _default_ref_extensions...,
            ref_extensions...
        ],
        eng2math_passthrough=recursive_merge_including_vectors(_eng2math_passthrough_default, eng2math_passthrough),
        global_keys=union(_default_global_keys,global_keys),
        kwargs...
    )
end


"""
    instantiate_onm_model(
        data::Union{Dict{String,<:Any}, String},
        model_type::Type,
        model_builder::Function;
        eng2math_passthrough::Dict{String,Vector{String}}=Dict{String,Vector{String}}(),
        ref_extensions::Vector{Function}=Function[],
        multinetwork::Bool=false,
        kwargs...
    )

ONM-specific version of PowerModelsDistribution.instantiate_mc_model
"""
function instantiate_onm_model(
    data::Union{Dict{String,<:Any}, String},
    model_type::Type,
    model_builder::Function;
    eng2math_passthrough::Dict{String,Vector{String}}=Dict{String,Vector{String}}(),
    ref_extensions::Vector{Function}=Function[],
    multinetwork::Bool=false,
    global_keys::Set{String}=Set{String}(),
    kwargs...)

    return PMD.instantiate_mc_model(
        data,
        model_type,
        model_builder;
        multinetwork=multinetwork,
        ref_extensions=Function[
            _default_ref_extensions...,
            ref_extensions...
        ],
        eng2math_passthrough=recursive_merge_including_vectors(_eng2math_passthrough_default, eng2math_passthrough),
        global_keys=union(_default_global_keys, global_keys),
        kwargs...
    )
end


"""
    build_solver_instances!(args::Dict{String,<:Any})::Dict{String,JuMP.MOI.OptimizerWithAttributes}

Creates the Optimizers in-place (within the args dict data structure), for use inside [`entrypoint`](@ref entrypoint),
using [`build_solver_instances`](@ref build_solver_instances), assigning them to `args["solvers"]``
"""
function build_solver_instances!(args::Dict{String,<:Any})::Dict{String,Any}
    solver_opts = get(get(args, "network", Dict()), "solvers", Dict{String,Any}())
    log_level = get(args, "log-level", "warn")

    args["solvers"] = build_solver_instances(;
        nlp_solver = get(get(args, "solvers", Dict()), "nlp_solver", missing),
        mip_solver = get(get(args, "solvers", Dict()), "mip_solver", missing),
        minlp_solver = get(get(args, "solvers", Dict()), "minlp_solver", missing),
        misocp_solver = get(get(args, "solvers", Dict()), "misocp_solver", missing),
        solver_options=solver_opts,
        log_level=log_level,
    )
end


"""
    build_solver_instances(;
        nlp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
        mip_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
        minlp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
        misocp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
        log_level::String="warn",
        solver_options::Dict{String,<:Any}=Dict{String,Any}(),
    )::Dict{String,Any}

Returns solver instances as a Dict ready for use with JuMP Models, for NLP (`"nlp_solver"`), MIP (`"mip_solver"`), MINLP (`"minlp_solver"`), and (MI)SOC (`"misocp_solver"`) problems.

- `nlp_solver` (default: `missing`): If missing, will use Ipopt as NLP solver, or KNITRO if `knitro=true`
- `mip_solver` (default: `missing`): If missing, will use Cbc as MIP solver, or Gurobi if `gurobi==true`
- `minlp_solver` (default: `missing`): If missing, will use Juniper with `nlp_solver` and `mip_solver`, of KNITRO if `knitro=true`
- `misocp_solver` (default: `missing`): If missing will use Juniper with `mip_solver`, or Gurobi if `gurobi==true`
- `solver_options` (default: Dict{String,Any}())
- `log_level` (default: "warn")
"""
function build_solver_instances(;
    nlp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
    mip_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
    minlp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
    misocp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
    solver_options::Dict{String,<:Any}=Dict{String,Any}(),
    log_level::String="warn",
    )::Dict{String,Any}

    if ismissing(nlp_solver)
        if get(solver_options, "useKNITRO", false)
            opts = get(solver_options, "KNITRO", Dict{String,Any}())
            if log_level == "debug"
                opts["outlev"] = 3
            elseif log_level == "info"
                opts["outlev"] = 2
            end
            nlp_solver = optimizer_with_attributes(
                () -> KNITRO.Optimizer(;license_manager=KN_LMC),
                opts...
            )
        else
            opts = get(solver_options, "Ipopt", Dict{String,Any}())
            if log_level == "debug"
                opts["print_level"] = 5
            elseif log_level == "info"
                opts["print_level"] = 3
            end
            nlp_solver = optimizer_with_attributes(
                Ipopt.Optimizer,
                opts...
            )
        end
    end

    if ismissing(mip_solver)
        if get(solver_options, "useGurobi", false)
            opts = get(solver_options, "Gurobi", Dict{String,Any}())
            if log_level == "debug"
                opts["OutputFlag"] = 1
            elseif log_level == "info"
                opts["OutputFlag"] = 1
            end
            mip_solver = optimizer_with_attributes(
                () -> Gurobi.Optimizer(GRB_ENV),
                opts...
            )
        else
            opts = get(solver_options, "HiGHS", Dict{String,Any}())
            if log_level == "debug"
                opts["output_flag"] = true
            elseif log_level == "info"
                opts["output_flag"] = true
            end
            mip_solver = optimizer_with_attributes(
                HiGHS.Optimizer,
                opts...
            )
        end
    end

    if ismissing(minlp_solver)
        if get(solver_options, "useKNITRO", false)
            opts = get(solver_options, "KNITRO", Dict{String,Any}())
            if log_level == "debug"
                opts["outlev"] = 3
            elseif log_level == "info"
                opts["outlev"] = 2
            end
            minlp_solver = optimizer_with_attributes(
                () -> KNITRO.Optimizer(;license_manager=KN_LMC),
                opts...
            )
        else
            opts = get(solver_options, "Juniper", Dict{String,Any}())
            if log_level == "debug"
                opts["log_levels"] = [:Table,:Info,:Options]
            elseif log_level == "info"
                opts["log_levels"] = [:Info,:Options]
            end
            minlp_solver = optimizer_with_attributes(
                Juniper.Optimizer,
                "nl_solver" => nlp_solver,
                "mip_solver" => mip_solver,
                opts...
            )

        end
    end

    if ismissing(misocp_solver)
        if get(solver_options, "useKNITRO", false)
            misocp_solver = mip_solver
        else
            misocp_solver = minlp_solver
        end
    end

    return Dict{String,JuMP.MOI.OptimizerWithAttributes}(
        "nlp_solver" => nlp_solver,
        "mip_solver" => mip_solver,
        "lp_solver" => mip_solver,
        "minlp_solver" => minlp_solver,
        "misocp_solver" => misocp_solver,
    )
end
