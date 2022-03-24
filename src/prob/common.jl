"default eng2math passthrough"
const _eng2math_passthrough_default = Dict{String,Vector{String}}(
    "root"=>String[
        "max_switch_actions",
        "disable_networking",
        "disable_switch_penalty",
        "apply_switch_scores",
        "disable_radial_constraint",
        "disable_isolation_constraint",
        "disable_inverter_constraint"
    ],
    "load"=>String["priority"],
    "bus"=>String["microgrid_id"],
    "generator"=>String["inverter"],
    "solar"=>String["inverter"],
    "storage"=>String["phase_unbalance_factor", "inverter"],
    "voltage_source"=>["inverter"],
)


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
    kwargs...)::Dict{String,Any}

    return PMD.solve_mc_model(
        data,
        model_type,
        solver,
        model_builder;
        multinetwork=multinetwork,
        solution_processors=Function[
            PMD.sol_data_model!,
            solution_reference_buses!,
            solution_statuses!,
            solution_inverter!,
            solution_processors...
        ],
        ref_extensions=Function[
            ref_add_load_blocks!,
            ref_add_max_switch_actions!,
            ref_extensions...
        ],
        eng2math_passthrough=recursive_merge(_eng2math_passthrough_default, eng2math_passthrough),
        kwargs...
    )
end


"""
    build_solver_instances!(args::Dict{String,<:Any})::Dict{String,JuMP.MOI.OptimizerWithAttributes}

Creates the Optimizers in-place (within the args dict data structure), for use inside [`entrypoint`](@ref entrypoint),
using [`build_solver_instances`](@ref build_solver_instances), assigning them to `args["solvers"]``
"""
function build_solver_instances!(args::Dict{String,<:Any})::Dict{String,JuMP.MOI.OptimizerWithAttributes}
    args["solvers"] = build_solver_instances(;
        nlp_solver = get(get(args, "solvers", Dict()), "nlp_solver", missing),
        nlp_solver_options = isa(get(args, "settings", ""), String) ? missing : get(args["settings"], "nlp_solver_options", missing),
        mip_solver = get(get(args, "solvers", Dict()), "mip_solver", missing),
        mip_solver_options = isa(get(args, "settings", ""), String) ? missing : get(args["settings"], "nlp_solver_options", missing),
        minlp_solver = get(get(args, "solvers", Dict()), "minlp_solver", missing),
        minlp_solver_options = isa(get(args, "settings", ""), String) ? missing : get(args["settings"], "nlp_solver_options", missing),
        misocp_solver = get(get(args, "solvers", Dict()), "misocp_solver", missing),
        feas_tol=isa(get(args, "settings", ""), String) ? 1e-4 : get(get(args, "settings", Dict()), "nlp_solver_tol", 1e-4),
        mip_gap_tol=isa(get(args, "settings", ""), String) ? 0.05 : get(get(args, "settings", Dict()), "mip_solver_gap", 0.05),
        disable_presolver= get(get(args, "settings", Dict()), "disable_presolver", false),
        gurobi=get(args, "gurobi", false),
        knitro=get(args, "knitro", false),
        verbose=get(args, "verbose", false),
        debug=get(args, "debug", false),
    )
end


"""
    build_solver_instances(;
        nlp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
        mip_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
        minlp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
        misocp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
        nlp_solver_options::Union{Missing,Vector{Pair}}=missing,
        mip_solver_options::Union{Missing,Vector{Pair}}=missing,
        minlp_solver_options::Union{Missing,Vector{Pair}}=missing,
        feas_tol::Float64=1e-6,
        mip_gap_tol::Float64=1e-4,
        gurobi::Bool=false,
        knitro::Bool=false,
        verbose::Bool=false,
        debug::Bool=false,
    )::Dict{String,JuMP.MOI.OptimizerWithAttributes}

Returns solver instances as a Dict ready for use with JuMP Models, for NLP (`"nlp_solver"`), MIP (`"mip_solver"`), MINLP (`"minlp_solver"`), and (MI)SOC (`"misocp_solver"`) problems.

- `nlp_solver` (default: `missing`): If missing, will use Ipopt as NLP solver, or KNITRO if `knitro=true`
- `mip_solver` (default: `missing`): If missing, will use Cbc as MIP solver, or Gurobi if `gurobi==true`
- `minlp_solver` (default: `missing`): If missing, will use Juniper with `nlp_solver` and `mip_solver`, of KNITRO if `knitro=true`
- `misocp_solver` (default: `missing`): If missing will use Juniper with `mip_solver`, or Gurobi if `gurobi==true`
- `nlp_solver_options` (default: `missing`): If missing, will use some default nlp solver options
- `mip_solver_options` (default: `missing`): If missing, will use some default mip solver options
- `minlp_solver_options` (default: `missing`): If missing, will use some default minlp solver options
- `feas_tol` (default: `1e-4`): The solver tolerance
- `mip_gap_tol` (default: 0.05): The desired MIP Gap for the MIP Solver
- `gurobi` (default: `false`): Use Gurobi for MIP / MISOC solvers
- `knitro` (default: `false`): Use KNITRO for NLP / MINLP solvers
- `disable_presolver` (default: `false`): Disable the presolver on solvers that support it (Gurobi, KNITRO)
- `verbose` (default: `false`): Sets the verbosity of the solvers
- `debug` (default: `false`): Sets the verbosity of the solvers even higher (if available)
"""
function build_solver_instances(;
    nlp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
    mip_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
    minlp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
    misocp_solver::Union{Missing,JuMP.MOI.OptimizerWithAttributes}=missing,
    nlp_solver_options::Union{Missing,Vector{Pair}}=missing,
    mip_solver_options::Union{Missing,Vector{Pair}}=missing,
    minlp_solver_options::Union{Missing,Vector{Pair}}=missing,
    feas_tol::Float64=1e-6,
    mip_gap_tol::Float64=1e-4,
    disable_presolver::Bool=false,
    gurobi::Bool=false,
    knitro::Bool=false,
    verbose::Bool=false,
    debug::Bool=false,
    )::Dict{String,JuMP.MOI.OptimizerWithAttributes}

    if ismissing(nlp_solver)
        if knitro
            if ismissing(nlp_solver_options)
                nlp_solver_options = Pair[
                    "outlev" => debug ? 3 : verbose ? 2 : 0,
                    "mip_outlevel" => debug ? 2 : verbose ? 1 : 0,
                    "opttol" => mip_gap_tol,
                    "feastol" => feas_tol,
                    "algorithm" => 3,
                    "presolve" => disable_presolver ? 0 : 1,
                ]
            end
            nlp_solver = optimizer_with_attributes(
                () -> KNITRO.Optimizer(;license_manager=KN_LMC),
                nlp_solver_options...
            )
        else
            if ismissing(nlp_solver_options)
                nlp_solver_options = Pair[
                    "tol" => feas_tol,
                    "print_level" => debug ? 5 : verbose ? 3 : 0,
                    "mumps_mem_percent" => 200,
                    "mu_strategy" => "adaptive",
                ]
            end
            nlp_solver = optimizer_with_attributes(
                Ipopt.Optimizer,
                nlp_solver_options...
            )
        end
    end

    if ismissing(mip_solver)
        if gurobi
            if ismissing(mip_solver_options)
                mip_solver_options = Pair[
                    # output settings
                    "OutputFlag" => verbose || debug ? 1 : 0,
                    "GURO_PAR_DUMP" => debug ? 1 : 0,
                    # tolerance settings
                    "MIPGap" => mip_gap_tol,
                    "FeasibilityTol" => feas_tol,
                    "Quad" => 1,
                    "NumericFocus" => 3,
                    # MIP settings
                    "MIPFocus" => 2,
                    # presolve settings
                    "DualReductions" => 0,
                    "Presolve" => disable_presolver ? 0 : -1,
                ]
            end
            mip_solver = optimizer_with_attributes(
                () -> Gurobi.Optimizer(GRB_ENV),
                mip_solver_options...
            )
        else
            if ismissing(mip_solver_options)
                mip_solver_options = Pair[
                    "output_flag" => verbose || debug ? true : false,
                    "presolve" => disable_presolver ? "off" : "choose",
                    "primal_feasibility_tolerance" => feas_tol,
                    "dual_feasibility_tolerance" => feas_tol,
                    "mip_rel_gap" => mip_gap_tol,
                    "small_matrix_value" => 1e-12,
                    "allow_unbounded_or_infeasible" => true,
                ]
            end
            mip_solver = optimizer_with_attributes(
                HiGHS.Optimizer,
                mip_solver_options...
            )
        end
    end

    if ismissing(minlp_solver)
        if knitro
            if ismissing(minlp_solver_options)
                minlp_solver_options = Pair[
                    "outlev" => debug ? 3 : verbose ? 2 : 0,
                    "mip_outlevel" => debug ? 2 : verbose ? 1 : 0,
                    "opttol" => mip_gap_tol,
                    "feastol" => feas_tol,
                    "algorithm" => 3,
                    "presolve" => 0,
                ]
            end
            minlp_solver = optimizer_with_attributes(
                () -> KNITRO.Optimizer(;license_manager=KN_LMC),
                minlp_solver_options...
            )
        else
            if ismissing(minlp_solver_options)
                minlp_solver_options = Pair[
                    "nl_solver" => nlp_solver,
                    "mip_solver" => mip_solver,
                    "branch_strategy" => :MostInfeasible,
                    "log_levels" => debug ? [:Error,:Warn,:Info] : verbose ? [:Error,:Warn] : [],
                    "mip_gap" => mip_gap_tol,
                    "traverse_strategy" => :DFS,
                ]
            end
            minlp_solver = optimizer_with_attributes(
                Juniper.Optimizer,
                minlp_solver_options...
            )

        end
    end

    if ismissing(misocp_solver)
        if gurobi
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
