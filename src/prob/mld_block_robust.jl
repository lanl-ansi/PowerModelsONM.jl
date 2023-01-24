"""
    solve_robust_block_mld(
        data::Dict{String,<:Any},
        model_type::Type,
        solver;
        N::Int, ΔL::Float64,
        kwargs...
    )::Dict{String,Any}

Solves a robust (N scenarios and ±ΔL load uncertainty) multiconductor optimal switching (mixed-integer) problem using `model_type` and `solver`.
The default number of scenarios is set to 2 with load uncertainty of ±10%.
"""
function solve_robust_block_mld(data::Dict{String,<:Any}, model_type::Type, solver; N::Int=2, ΔL::Float64=0.1, kwargs...)::Dict{String,Any}
    data_math = PMD.iseng(data) ? transform_data_model(data) : data
    load_factor = generate_load_scenarios(data_math::Dict{String,<:Any}, N, ΔL)     # generate load scenarios

    # setup iterative process
    violation_indicator = true
    scenarios = [1]
    result = Dict{String, Any}()
    while length(scenarios)<=N && violation_indicator
        data_all_scen = deepcopy(data_math)
        data_all_scen["uncertainty"] = Dict("load" => Dict(scen => load_factor[scen] for scen in scenarios),
                                            "feasibility_check" => false)
        # solve outer scenario model
        result = solve_onm_model(data_all_scen, model_type, solver, build_robust_block_mld; ref_extensions=Function[_ref_add_uncertainty!], multinetwork=false, kwargs...)

        # update data with solution of variables common across all scenarios
        _update_switch_settings!(data_all_scen, result["solution"])
        _update_inverter_settings!(data_all_scen, result["solution"])

        # feasibility check (inner scenario model)
        scenario = deleteat!([1:N;], sort(scenarios))
        if length(scenario)==0
            violation_indicator = false
        else
            infeasible_scen = []
            for scen in scenario
                data_scen = deepcopy(data_all_scen)
                data_scen["uncertainty"] = Dict("load" => Dict(scen => load_factor[scen]),
                                                "feasibility_check" => false)
                result_scen = solve_onm_model(data_scen, model_type, solver, build_robust_block_mld; multinetwork=false, kwargs...)
                if result_scen["termination_status"]!=OPTIMAL
                    push!(infeasible_scen,scen)
                end
            end
            if length(infeasible_scen)>0
                push!(scenarios,infeasible_scen[1])
            else
                violation_indicator = false
            end
        end
    end

    return result
end


"""
    build_robust_block_mld(pm::PMD.AbstractUBFModels; nw::Int=nw_id_default)

Build single-network robust mld problem for Branch Flow model considering all scenarios
"""
function build_robust_block_mld(pm::PMD.AbstractUBFModels; nw::Int=nw_id_default)
    var_opts = ref(pm, :options, "variables")
    con_opts = ref(pm, :options, "constraints")
    load_uncertainty = ref(pm, :uncertainty, "load")
    feas_chck = ref(pm, :uncertainty, "feasibility_check")

    # common set of variables for all scenario
    if feas_chck
        variable_robust_inverter_indicator(pm)
        variable_robust_switch_state(pm)
    else
        !con_opts["disable-grid-forming-inverter-constraint"] && variable_inverter_indicator(pm; relax=var_opts["relax-integer-variables"])
        variable_switch_state(pm; relax=var_opts["relax-integer-variables"])
    end

    # add variables and constraints for each scenario
    obj_expr = Dict()
    for (scen,_) in load_uncertainty
        build_scen_block_mld(pm, scen, obj_expr)
    end

    # combine objectives for all scenarios
    !feas_chck && JuMP.@objective(pm.model, Min, sum(obj_expr[scen] for (scen,_) in load_uncertainty))

end


"""
    build_scen_block_mld(pm::PMD.AbstractUBFModels; nw::Int=nw_id_default)

Add each scenario variables, constraints to single-network robust mld problem using Branch Flow model
"""
function build_scen_block_mld(pm::PMD.AbstractUBFModels, scen::Int, obj_expr::Dict{Any,Any}; nw::Int=nw_id_default, feas_chck::Bool=false)
    var_opts = ref(pm, :options, "variables")
    con_opts = ref(pm, :options, "constraints")
    feas_chck = ref(pm, :uncertainty, "feasibility_check")

    variable_block_indicator(pm; relax=var_opts["relax-integer-variables"], report=false)

    PMD.variable_mc_bus_voltage_on_off(pm; bounded=!var_opts["unbound-voltage"], report=false)

    PMD.variable_mc_branch_current(pm; bounded=!var_opts["unbound-line-current"], report=false)
    PMD.variable_mc_branch_power(pm; bounded=!var_opts["unbound-line-power"], report=false)

    PMD.variable_mc_switch_power(pm; bounded=!var_opts["unbound-switch-power"], report=false)

    PMD.variable_mc_transformer_power(pm; bounded=!var_opts["unbound-transformer-power"], report=false)
    PMD.variable_mc_oltc_transformer_tap(pm, report=false)

    PMD.variable_mc_generator_power_on_off(pm; bounded=!var_opts["unbound-generation-power"], report=false)

    variable_mc_storage_power_mi_on_off(pm; bounded=!var_opts["unbound-storage-power"], relax=var_opts["relax-integer-variables"], report=false)

    variable_mc_load_power(pm, scen)

    PMD.variable_mc_capcontrol(pm; relax=var_opts["relax-integer-variables"], report=false)

    PMD.constraint_mc_model_current(pm)

    !con_opts["disable-grid-forming-inverter-constraint"] && constraint_grid_forming_inverter_per_cc_block(pm; relax=var_opts["relax-integer-variables"])

    if con_opts["disable-grid-forming-inverter-constraint"]
        for i in ids(pm, :ref_buses)
            PMD.constraint_mc_theta_ref(pm, i)
        end
    else
        for i in ids(pm, :bus)
            constraint_mc_inverter_theta_ref(pm, i)
        end
    end

    constraint_mc_bus_voltage_block_on_off(pm)

    for i in ids(pm, :gen)
        !var_opts["unbound-generation-power"] && constraint_mc_generator_power_block_on_off(pm, i)
    end

    for i in ids(pm, :load)
        constraint_mc_load_power(pm, i, scen)
    end

    for i in ids(pm, :bus)
        constraint_mc_power_balance_shed_block(pm, i)
    end

    for i in ids(pm, :storage)
        PMD.constraint_storage_state(pm, i)
        constraint_storage_complementarity_mi_block_on_off(pm, i)
        constraint_mc_storage_block_on_off(pm, i)
        constraint_mc_storage_losses_block_on_off(pm, i)
        !con_opts["disable-thermal-limit-constraints"] && !var_opts["unbound-storage-power"] && PMD.constraint_mc_storage_thermal_limit(pm, i)
        !con_opts["disable-storage-unbalance-constraint"] && constraint_mc_storage_phase_unbalance_grid_following(pm, i)
    end

    for i in ids(pm, :branch)
        PMD.constraint_mc_power_losses(pm, i)
        PMD.constraint_mc_model_voltage_magnitude_difference(pm, i)
        PMD.constraint_mc_voltage_angle_difference(pm, i)

        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_thermal_limit_from(pm, i)
        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_thermal_limit_to(pm, i)

        !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_ampacity_from(pm, i)
        !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_ampacity_to(pm, i)
    end

    con_opts["disable-microgrid-networking"] &&  constraint_disable_networking(pm; relax=var_opts["relax-integer-variables"])
    if !feas_chck
        !con_opts["disable-radiality-constraint"] && constraint_radial_topology(pm; relax=var_opts["relax-integer-variables"])
        !con_opts["disable-switch-close-action-limit"] && constraint_switch_close_action_limit(pm)
    end
    !con_opts["disable-block-isolation-constraint"] && constraint_isolate_block(pm)
    for i in ids(pm, :switch)
        constraint_mc_switch_state_open_close(pm, i)

        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_switch_thermal_limit(pm, i)
        !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_switch_ampacity(pm, i)
    end

    for i in ids(pm, :transformer)
        constraint_mc_transformer_power_block_on_off(pm, i; fix_taps=false)
    end

    !feas_chck && objective_robust_min_shed_load_block_rolling_horizon(pm, obj_expr, scen)
end


"""
    generate_load_scenarios(data::Dict{String,<:Any}, N::Int, ΔL::Float64)

Generate N scenarios with ±ΔL load uncertainty.
PMD.solve_mc_opf() is solved for each scenario to check if feasible to original problem (no microgrids, all blocks connected to substation)
"""
function generate_load_scenarios(data_math::Dict{String,<:Any}, N::Int, ΔL::Float64)
    n_l = length(data_math["load"])
    load_factor = Dict(scen => Dict() for scen in 1:N)
    scen = 1
    while scen<=N
        data_scen = deepcopy(data_math)
        uncertain_scen = ΔL==0 ? ones(n_l) : SB.sample((1-ΔL):(2*ΔL/n_l):(1+ΔL), n_l, replace=false)
        for (id,load) in data_math["load"]
            if scen==1
                load_factor[scen][id] = 1
            else
                load_factor[scen][id] = uncertain_scen[parse(Int64,id)]
                data_scen["load"][id]["pd"] = load["pd"]*uncertain_scen[parse(Int64,id)]
                data_scen["load"][id]["qd"] = load["qd"]*uncertain_scen[parse(Int64,id)]
            end
        end
        result = PMD.solve_mc_opf(data_scen, PMD.LPUBFDiagPowerModel, JuMP.optimizer_with_attributes(Ipopt.Optimizer,"print_level"=>0); global_keys = Set(["options", "solvers"]))
        scen = result["termination_status"]==LOCALLY_SOLVED ? (scen+1) : scen
    end

    return load_factor
end
