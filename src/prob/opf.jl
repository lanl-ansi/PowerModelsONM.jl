"""
    solve_mn_opf(
        data::Dict{String,<:Any},
        model_type::Type,
        solver;
        kwargs...
    )::Dict{String,Any}

Solve multinetwork OPF with transformer tap and capacitor control
"""
function solve_mn_opf(data::Dict{String,<:Any}, model_type::Type, solver; kwargs...)::Dict{String,Any}
    solve_onm_model(data, model_type, solver, build_mn_opf; multinetwork=true, kwargs...)
end


"""
    build_mn_opf(pm::AbstractUnbalancedPowerModel)

constructor for bus injection opf
"""
function build_mn_opf(pm::AbstractUnbalancedPowerModel)
    for n in nw_ids(pm)
        var_opts = ref(pm, n, :options, "variables")
        con_opts = ref(pm, n, :options, "constraints")

        PMD.variable_mc_bus_voltage(pm; nw=n, bounded=!var_opts["unbound-voltage"])

        PMD.variable_mc_branch_power(pm; nw=n, bounded=!var_opts["unbound-line-power"])
        PMD.variable_mc_switch_power(pm; nw=n, bounded=!var_opts["unbound-switch-power"])
        PMD.variable_mc_transformer_power(pm; nw=n, bounded=!var_opts["unbound-transformer-power"])

        PMD.variable_mc_oltc_transformer_tap(pm; nw=n)

        PMD.variable_mc_generator_power(pm; nw=n, bounded=!var_opts["unbound-generation-power"])
        PMD.variable_mc_load_power(pm; nw=n)
        PMD.variable_mc_storage_power_mi(pm; nw=n, relax=true, bounded=!var_opts["unbound-storage-power"])

        PMD.variable_mc_capcontrol(pm; nw=n, relax=true)

        PMD.constraint_mc_model_voltage(pm; nw=n)

        for i in ids(pm, n, :ref_buses)
            PMD.constraint_mc_theta_ref(pm, i; nw=n)
        end

        # generators should be constrained before KCL, or Pd/Qd undefined
        for i in ids(pm, n, :gen)
            PMD.constraint_mc_generator_power(pm, i; nw=n)
        end

        # loads should be constrained before KCL, or Pd/Qd undefined
        for i in ids(pm, n, :load)
            PMD.constraint_mc_load_power(pm, i; nw=n)
        end

        for i in ids(pm, n, :bus)
            PMD.constraint_mc_power_balance_capc(pm, i; nw=n)
        end

        for i in ids(pm, n, :storage)
            PMD.constraint_storage_complementarity_mi(pm, i; nw=n)
            PMD.constraint_mc_storage_losses(pm, i; nw=n)
            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_storage_thermal_limit(pm, i; nw=n)
            if Int(get(ref(pm, n, :storage, i), "inverter", GRID_FORMING)) == Int(GRID_FOLLOWING)
                !con_opts["disable-storage-unbalance-constraint"] && constraint_mc_storage_phase_unbalance(pm, i; nw=n)
            end
        end

        for i in ids(pm, n, :branch)
            PMD.constraint_mc_ohms_yt_from(pm, i; nw=n)
            PMD.constraint_mc_ohms_yt_to(pm, i; nw=n)
            PMD.constraint_mc_voltage_angle_difference(pm, i; nw=n)

            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_thermal_limit_from(pm, i; nw=n)
            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_thermal_limit_to(pm, i; nw=n)

            !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_ampacity_from(pm, i; nw=n)
            !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_ampacity_to(pm, i; nw=n)
        end

        for i in ids(pm, n, :switch)
            PMD.constraint_mc_switch_state(pm, i; nw=n)
            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_switch_thermal_limit(pm, i; nw=n)
            !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_switch_ampacity(pm, i; nw=n)
        end

        for i in ids(pm, n, :transformer)
            PMD.constraint_mc_transformer_power(pm, i; nw=n, fix_taps=false)
        end

    end

    network_ids = sort(collect(nw_ids(pm)))

    n_1 = network_ids[1]

    for i in ids(pm, :storage; nw=n_1)
        PMD.constraint_storage_state(pm, i; nw=n_1)
    end

    for n_2 in network_ids[2:end]
        for i in ids(pm, :storage; nw=n_2)
            PMD.constraint_storage_state(pm, i, n_1, n_2)
        end

        n_1 = n_2
    end

    objective_mc_min_storage_utilization(pm)
end


"""
    build_mn_opf(pm::PMD.AbstractUBFModels)

constructor for branch flow opf
"""
function build_mn_opf(pm::PMD.AbstractUBFModels)
    for n in nw_ids(pm)
        var_opts = ref(pm, n, :options, "variables")
        con_opts = ref(pm, n, :options, "constraints")

        PMD.variable_mc_bus_voltage(pm; nw=n)

        PMD.variable_mc_branch_current(pm; nw=n, bounded=!var_opts["unbound-line-current"])
        PMD.variable_mc_branch_power(pm; nw=n, bounded=!var_opts["unbound-line-power"])

        PMD.variable_mc_switch_power(pm; nw=n, bounded=!var_opts["unbound-switch-power"])

        PMD.variable_mc_transformer_power(pm; nw=n, bounded=!var_opts["unbound-transformer-power"])
        PMD.variable_mc_oltc_transformer_tap(pm; nw=n)

        PMD.variable_mc_generator_power(pm; nw=n, bounded=!var_opts["unbound-generation-power"])

        PMD.variable_mc_storage_power_mi(pm; nw=n, relax=true, bounded=!var_opts["unbound-storage-power"])

        PMD.variable_mc_load_power(pm; nw=n)

        PMD.variable_mc_capcontrol(pm; nw=n, relax=true)

        PMD.constraint_mc_model_current(pm; nw=n)

        for i in ids(pm, n, :ref_buses)
            PMD.constraint_mc_theta_ref(pm, i; nw=n)
        end

        # gens should be constrained before KCL, or Pd/Qd undefined
        for i in ids(pm, n, :gen)
            PMD.constraint_mc_generator_power(pm, i; nw=n)
        end

        # loads should be constrained before KCL, or Pd/Qd undefined
        for i in ids(pm, n, :load)
            PMD.constraint_mc_load_power(pm, i; nw=n)
        end

        for i in ids(pm, n, :bus)
            PMD.constraint_mc_power_balance_capc(pm, i; nw=n)
        end

        for i in ids(pm, n, :storage)
            PMD.constraint_storage_complementarity_mi(pm, i; nw=n)
            PMD.constraint_mc_storage_losses(pm, i; nw=n)
            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_storage_thermal_limit(pm, i; nw=n)
            if Int(get(ref(pm, n, :storage, i), "inverter", GRID_FORMING)) == Int(GRID_FOLLOWING)
                !con_opts["disable-storage-unbalance-constraint"] && constraint_mc_storage_phase_unbalance(pm, i; nw=n)
            end
        end

        for i in ids(pm, n, :branch)
            PMD.constraint_mc_power_losses(pm, i; nw=n)
            PMD.constraint_mc_model_voltage_magnitude_difference(pm, i; nw=n)
            PMD.constraint_mc_voltage_angle_difference(pm, i; nw=n)

            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_thermal_limit_from(pm, i; nw=n)
            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_thermal_limit_to(pm, i; nw=n)

            !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_ampacity_from(pm, i; nw=n)
            !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_ampacity_to(pm, i; nw=n)
        end

        for i in ids(pm, n, :switch)
            PMD.constraint_mc_switch_state(pm, i; nw=n)
            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_switch_thermal_limit(pm, i; nw=n)
            !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_switch_ampacity(pm, i; nw=n)
        end

        for i in ids(pm, n, :transformer)
            PMD.constraint_mc_transformer_power(pm, i; nw=n, fix_taps=false)
        end
    end

    network_ids = sort(collect(nw_ids(pm)))

    n_1 = network_ids[1]

    for i in ids(pm, :storage; nw=n_1)
        PMD.constraint_storage_state(pm, i; nw=n_1)
    end

    for n_2 in network_ids[2:end]
        for i in ids(pm, :storage; nw=n_2)
            PMD.constraint_storage_state(pm, i, n_1, n_2)
        end

        n_1 = n_2
    end

    objective_mc_min_storage_utilization(pm)
end
