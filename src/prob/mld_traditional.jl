"""
    solve_mn_traditional_mld(
        data::Dict{String,<:Any},
        model_type::Type,
        solver;
        kwargs...
    )::Dict{String,Any}

Solves a __multinetwork__ multiconductor traditional mld problem using `model_type` and `solver`

Calls back to PowerModelsDistribution.solve_mc_model, and therefore will accept any valid `kwargs`
for that function. See PowerModelsDistribution [documentation](https://lanl-ansi.github.io/PowerModelsDistribution.jl/latest)
for more details.
"""
function solve_mn_traditional_mld(data::Dict{String,<:Any}, model_type::Type, solver; kwargs...)::Dict{String,Any}
    solve_onm_model(data, model_type, solver, build_mn_traditional_mld; multinetwork=true, kwargs...)
end


"""
    build_mn_traditional_mld(pm::PMD.AbstractUBFModels)

Multinetwork load shedding problem for Branch Flow model
"""
function build_mn_traditional_mld(pm::PMD.AbstractUBFModels)
    for n in nw_ids(pm)
        var_opts = ref(pm, n, :options, "variables")
        con_opts = ref(pm, n, :options, "constraints")

        !con_opts["disable-grid-forming-inverter-constraint"] && variable_inverter_indicator(pm; nw=n, relax=var_opts["relax-integer-variables"])

        variable_bus_voltage_indicator(pm; nw=n, relax=var_opts["relax-integer-variables"])
        PMD.variable_mc_bus_voltage_on_off(pm; nw=n, bounded=!var_opts["unbound-voltage"])

        PMD.variable_mc_branch_current(pm; nw=n, bounded=!var_opts["unbound-line-current"])
        PMD.variable_mc_branch_power(pm; nw=n, bounded=!var_opts["unbound-line-power"])

        PMD.variable_mc_switch_power(pm; nw=n, bounded=!var_opts["unbound-switch-power"])
        variable_switch_state(pm; nw=n, relax=var_opts["relax-integer-variables"])

        PMD.variable_mc_transformer_power(pm; nw=n, bounded=!var_opts["unbound-transformer-power"])
        PMD.variable_mc_oltc_transformer_tap(pm; nw=n)

        variable_generator_indicator(pm; nw=n, relax=var_opts["relax-integer-variables"])
        PMD.variable_mc_generator_power_on_off(pm; nw=n, bounded=!var_opts["unbound-generation-power"])

        variable_storage_indicator(pm; nw=n, relax=var_opts["relax-integer-variables"])
        variable_mc_storage_power_mi_on_off(pm; nw=n, relax=var_opts["relax-integer-variables"], bounded=!var_opts["unbound-storage-power"])

        variable_load_indicator(pm; nw=n, relax=var_opts["relax-integer-variables"])
        PMD.variable_mc_load_power(pm; nw=n)

        PMD.variable_mc_capcontrol(pm; nw=n, relax=var_opts["relax-integer-variables"])

        PMD.constraint_mc_model_current(pm; nw=n)

        !con_opts["disable-grid-forming-inverter-constraint"] && constraint_grid_forming_inverter_per_cc(pm; nw=n, relax=var_opts["relax-integer-variables"])

        for i in ids(pm, n, :bus)
            if con_opts["disable-grid-forming-inverter-constraint"]
                PMD.constraint_mc_theta_ref(pm, i; nw=n)
            else
                constraint_mc_inverter_theta_ref(pm, i; nw=n)
            end
        end

        constraint_mc_bus_voltage_traditional_on_off(pm; nw=n)

        for i in ids(pm, n, :gen)
            constraint_mc_generator_power_traditional_on_off(pm, i; nw=n)
        end

        for i in ids(pm, n, :load)
            PMD.constraint_mc_load_power(pm, i; nw=n)
        end

        for i in ids(pm, n, :bus)
            constraint_mc_power_balance_shed_traditional(pm, i; nw=n)
        end

        for i in ids(pm, n, :storage)
            constraint_storage_complementarity_mi_traditional_on_off(pm, i; nw=n)
            constraint_mc_storage_traditional_on_off(pm, i; nw=n)
            constraint_mc_storage_losses_traditional_on_off(pm, i; nw=n)
            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_storage_thermal_limit(pm, i; nw=n)
            !con_opts["disable-storage-unbalance-constraint"] && constraint_mc_storage_phase_unbalance_grid_following(pm, i; nw=n)
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

        con_opts["disable-microgrid-networking"] && constraint_disable_networking(pm; nw=n, relax=var_opts["relax-integer-variables"])
        !con_opts["disable-radiality-constraint"] && constraint_radial_topology(pm; nw=n, relax=var_opts["relax-integer-variables"])
        !con_opts["disable-block-isolation-constraint"] && constraint_isolate_block_traditional(pm; nw=n)
        for i in ids(pm, n, :switch)
            constraint_mc_switch_state_open_close(pm, i; nw=n)

            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_switch_thermal_limit(pm, i; nw=n)
            !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_switch_ampacity(pm, i; nw=n)
        end

        for i in ids(pm, n, :transformer)
            constraint_mc_transformer_power_traditional_on_off(pm, i; nw=n, fix_taps=false)
        end
    end

    network_ids = sort(collect(nw_ids(pm)))

    n_1 = network_ids[1]

    for i in ids(pm, :storage; nw=n_1)
        PMD.constraint_storage_state(pm, i; nw=n_1)
    end

    !ref(pm, n_1, :options, "constraints")["disable-switch-close-action-limit"] && constraint_switch_close_action_limit(pm; nw=n_1)

    for n_2 in network_ids[2:end]
        !ref(pm, n_2, :options, "constraints")["disable-switch-close-action-limit"] && constraint_switch_close_action_limit(pm, n_1, n_2)

        for i in ids(pm, :storage; nw=n_2)
            PMD.constraint_storage_state(pm, i, n_1, n_2)
        end

        n_1 = n_2
    end

    objective_min_shed_load_traditional(pm)
end


"""
    build_mn_traditional_mld(pm::PMD.AbstractUnbalancedPowerModel)

Multinetwork load shedding problem for Bus Injection model
"""
function build_mn_traditional_mld(pm::PMD.AbstractUnbalancedPowerModel)
    for n in nw_ids(pm)
        var_opts = ref(pm, n, :options, "variables")
        con_opts = ref(pm, n, :options, "constraints")

        !con_opts["disable-grid-forming-inverter-constraint"] && variable_inverter_indicator(pm; nw=n, relax=var_opts["relax-integer-variables"])

        variable_bus_voltage_indicator(pm; nw=n, relax=var_opts["relax-integer-variables"])
        PMD.variable_mc_bus_voltage_on_off(pm; nw=n, bounded=!var_opts["unbound-voltage"])

        PMD.variable_mc_branch_power(pm; nw=n, bounded=!var_opts["unbound-line-power"])

        PMD.variable_mc_switch_power(pm; nw=n, bounded=!var_opts["unbound-switch-power"])
        variable_switch_state(pm; nw=n, relax=var_opts["relax-integer-variables"])

        PMD.variable_mc_transformer_power(pm; nw=n, bounded=!var_opts["unbound-transformer-power"])
        PMD.variable_mc_oltc_transformer_tap(pm; nw=n)

        variable_generator_indicator(pm; nw=n, relax=var_opts["relax-integer-variables"])
        PMD.variable_mc_generator_power_on_off(pm; nw=n, bounded=!var_opts["unbound-generation-power"])

        variable_storage_indicator(pm; nw=n, relax=var_opts["relax-integer-variables"])
        variable_mc_storage_power_mi_on_off(pm; nw=n, relax=var_opts["relax-integer-variables"], bounded=!var_opts["unbound-storage-power"])

        variable_load_indicator(pm; nw=n, relax=var_opts["relax-integer-variables"])
        PMD.variable_mc_load_power(pm; nw=n)

        PMD.variable_mc_capcontrol(pm; nw=n, relax=var_opts["relax-integer-variables"])

        PMD.constraint_mc_model_voltage(pm; nw=n)

        !con_opts["disable-grid-forming-inverter-constraint"] && constraint_grid_forming_inverter_per_cc(pm; nw=n, relax=var_opts["relax-integer-variables"])

        for i in ids(pm, n, :bus)
            if con_opts["disable-grid-forming-inverter-constraint"]
                PMD.constraint_mc_theta_ref(pm, i; nw=n)
            else
                constraint_mc_inverter_theta_ref(pm, i; nw=n)
            end
        end

        constraint_mc_bus_voltage_traditional_on_off(pm; nw=n)

        for i in ids(pm, n, :gen)
            constraint_mc_generator_power_traditional_on_off(pm, i; nw=n)
        end

        for i in ids(pm, n, :load)
            PMD.constraint_mc_load_power(pm, i; nw=n)
        end

        for i in ids(pm, n, :bus)
            constraint_mc_power_balance_shed_traditional(pm, i; nw=n)
        end

        for i in ids(pm, n, :storage)
            constraint_storage_complementarity_mi_traditional_on_off(pm, i; nw=n)
            constraint_mc_storage_traditional_on_off(pm, i; nw=n)
            constraint_mc_storage_losses_traditional_on_off(pm, i; nw=n)
            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_storage_thermal_limit(pm, i; nw=n)
            !con_opts["disable-storage-unbalance-constraint"] && constraint_mc_storage_phase_unbalance_grid_following(pm, i; nw=n)
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

        con_opts["disable-microgrid-networking"] && constraint_disable_networking(pm; nw=n, relax=var_opts["relax-integer-variables"])
        !con_opts["disable-radiality-constraint"] && constraint_radial_topology(pm; nw=n, relax=var_opts["relax-integer-variables"])
        !con_opts["disable-block-isolation-constraint"] && constraint_isolate_block_traditional(pm; nw=n)
        for i in ids(pm, n, :switch)
            constraint_mc_switch_state_open_close(pm, i; nw=n)

            !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_switch_thermal_limit(pm, i; nw=n)
            !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_switch_ampacity(pm, i; nw=n)
        end

        for i in ids(pm, n, :transformer)
            constraint_mc_transformer_power_traditional_on_off(pm, i; nw=n, fix_taps=false)
        end
    end

    network_ids = sort(collect(nw_ids(pm)))

    n_1 = network_ids[1]

    for i in ids(pm, :storage; nw=n_1)
        PMD.constraint_storage_state(pm, i; nw=n_1)
    end

    !ref(pm, n_1, :options, "constraints")["disable-switch-close-action-limit"] && constraint_switch_close_action_limit(pm; nw=n_1)

    for n_2 in network_ids[2:end]
        !ref(pm, n_2, :options, "constraints")["disable-switch-close-action-limit"] && constraint_switch_close_action_limit(pm, n_1, n_2)

        for i in ids(pm, :storage; nw=n_2)
            PMD.constraint_storage_state(pm, i, n_1, n_2)
        end

        n_1 = n_2
    end

    objective_min_shed_load_traditional(pm)
end


"""
    solve_traditional_mld(
        data::Dict{String,<:Any},
        model_type::Type,
        solver;
        kwargs...
    )::Dict{String,Any}

Solves a multiconductor traditional mld problem using `model_type` and `solver`

Calls back to PowerModelsDistribution.solve_mc_model, and therefore will accept any valid `kwargs`
for that function. See PowerModelsDistribution [documentation](https://lanl-ansi.github.io/PowerModelsDistribution.jl/latest)
for more details.
"""
function solve_traditional_mld(data::Dict{String,<:Any}, model_type::Type, solver; kwargs...)::Dict{String,Any}
    solve_onm_model(data, model_type, solver, build_traditional_mld; multinetwork=false, kwargs...)
end


"""
    build_traditional_mld(pm::PMD.AbstractUBFModels)

Single-network load shedding problem for Branch Flow model
"""
function build_traditional_mld(pm::PMD.AbstractUBFModels)
    var_opts = ref(pm, :options, "variables")
    con_opts = ref(pm, :options, "constraints")

    !con_opts["disable-grid-forming-inverter-constraint"] && variable_inverter_indicator(pm; relax=var_opts["relax-integer-variables"])

    variable_bus_voltage_indicator(pm; relax=var_opts["relax-integer-variables"])
    PMD.variable_mc_bus_voltage_on_off(pm; bounded=!var_opts["unbound-voltage"])

    PMD.variable_mc_branch_current(pm; bounded=!var_opts["unbound-line-current"])
    PMD.variable_mc_branch_power(pm; bounded=!var_opts["unbound-line-power"])

    PMD.variable_mc_switch_power(pm; bounded=!var_opts["unbound-switch-power"])
    variable_switch_state(pm; relax=var_opts["relax-integer-variables"])

    PMD.variable_mc_transformer_power(pm; bounded=!var_opts["unbound-transformer-power"])
    PMD.variable_mc_oltc_transformer_tap(pm)

    variable_generator_indicator(pm; relax=var_opts["relax-integer-variables"])
    PMD.variable_mc_generator_power_on_off(pm; bounded=!var_opts["unbound-generation-power"])

    variable_storage_indicator(pm; relax=var_opts["relax-integer-variables"])
    variable_mc_storage_power_mi_on_off(pm; relax=var_opts["relax-integer-variables"], bounded=!var_opts["unbound-storage-power"])

    variable_load_indicator(pm; relax=var_opts["relax-integer-variables"])
    PMD.variable_mc_load_power(pm)

    PMD.variable_mc_capcontrol(pm; relax=var_opts["relax-integer-variables"])

    PMD.constraint_mc_model_current(pm)

    !con_opts["disable-grid-forming-inverter-constraint"] && constraint_grid_forming_inverter_per_cc(pm; relax=var_opts["relax-integer-variables"])

    for i in ids(pm, :bus)
        if con_opts["disable-grid-forming-inverter-constraint"]
            PMD.constraint_mc_theta_ref(pm, i)
        else
            constraint_mc_inverter_theta_ref(pm, i)
        end
    end

    constraint_mc_bus_voltage_traditional_on_off(pm)

    for i in ids(pm, :gen)
        constraint_mc_generator_power_traditional_on_off(pm, i)
    end

    for i in ids(pm, :load)
        PMD.constraint_mc_load_power(pm, i)
    end

    for i in ids(pm, :bus)
        constraint_mc_power_balance_shed_traditional(pm, i)
    end

    for i in ids(pm, :storage)
        PMD.constraint_storage_state(pm, i)
        constraint_storage_complementarity_mi_traditional_on_off(pm, i)
        constraint_mc_storage_traditional_on_off(pm, i)
        constraint_mc_storage_losses_traditional_on_off(pm, i)
        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_storage_thermal_limit(pm, i)
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

    !con_opts["disable-switch-close-action-limit"] && constraint_switch_close_action_limit(pm)
    con_opts["disable-microgrid-networking"] && constraint_disable_networking(pm; relax=var_opts["relax-integer-variables"])
    !con_opts["disable-radiality-constraint"] && constraint_radial_topology(pm; relax=var_opts["relax-integer-variables"])
    !con_opts["disable-block-isolation-constraint"] && constraint_isolate_block_traditional(pm)
    for i in ids(pm, :switch)
        constraint_mc_switch_state_open_close(pm, i)

        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_switch_thermal_limit(pm, i)
        !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_switch_ampacity(pm, i)
    end

    for i in ids(pm, :transformer)
        constraint_mc_transformer_power_traditional_on_off(pm, i; fix_taps=false)
    end

    objective_min_shed_load_traditional_rolling_horizon(pm)
end


"""
    build_traditional_mld(pm::PMD.AbstractUnbalancedPowerModel)

Single-network load shedding problem for Bus Injection model
"""
function build_traditional_mld(pm::PMD.AbstractUnbalancedPowerModel)
    var_opts = ref(pm, :options, "variables")
    con_opts = ref(pm, :options, "constraints")

    !con_opts["disable-grid-forming-inverter-constraint"] && variable_inverter_indicator(pm; relax=var_opts["relax-integer-variables"])

    variable_bus_voltage_indicator(pm; relax=var_opts["relax-integer-variables"])
    PMD.variable_mc_bus_voltage_on_off(pm; bounded=!var_opts["unbound-voltage"])

    PMD.variable_mc_branch_power(pm; bounded=!var_opts["unbound-line-power"])

    PMD.variable_mc_switch_power(pm; bounded=!var_opts["unbound-switch-power"])
    variable_switch_state(pm; relax=var_opts["relax-integer-variables"])

    PMD.variable_mc_transformer_power(pm; bounded=!var_opts["unbound-transformer-power"])
    PMD.variable_mc_oltc_transformer_tap(pm)

    variable_generator_indicator(pm; relax=var_opts["relax-integer-variables"])
    PMD.variable_mc_generator_power_on_off(pm; bounded=!var_opts["unbound-generation-power"])

    variable_storage_indicator(pm; relax=var_opts["relax-integer-variables"])
    variable_mc_storage_power_mi_on_off(pm; relax=var_opts["relax-integer-variables"], bounded=!var_opts["unbound-storage-power"])

    variable_load_indicator(pm; relax=var_opts["relax-integer-variables"])
    PMD.variable_mc_load_power(pm)

    PMD.variable_mc_capcontrol(pm; relax=var_opts["relax-integer-variables"])

    PMD.constraint_mc_model_voltage(pm)

    !con_opts["disable-grid-forming-inverter-constraint"] && constraint_grid_forming_inverter_per_cc(pm; relax=var_opts["relax-integer-variables"])

    for i in ids(pm, :bus)
        if con_opts["disable-grid-forming-inverter-constraint"]
            PMD.constraint_mc_theta_ref(pm, i)
        else
            constraint_mc_inverter_theta_ref(pm, i)
        end
    end

    constraint_mc_bus_voltage_traditional_on_off(pm)

    for i in ids(pm, :gen)
        constraint_mc_generator_power_traditional_on_off(pm, i)
    end

    for i in ids(pm, :load)
        PMD.constraint_mc_load_power(pm, i)
    end

    for i in ids(pm, :bus)
        constraint_mc_power_balance_shed_traditional(pm, i)
    end

    for i in ids(pm, :storage)
        PMD.constraint_storage_state(pm, i)
        constraint_storage_complementarity_mi_traditional_on_off(pm, i)
        constraint_mc_storage_traditional_on_off(pm, i)
        constraint_mc_storage_losses_traditional_on_off(pm, i)
        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_storage_thermal_limit(pm, i)
        !con_opts["disable-storage-unbalance-constraint"] && constraint_mc_storage_phase_unbalance_grid_following(pm, i)
    end

    for i in ids(pm, :branch)
        PMD.constraint_mc_ohms_yt_from(pm, i)
        PMD.constraint_mc_ohms_yt_to(pm, i)
        PMD.constraint_mc_voltage_angle_difference(pm, i)

        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_thermal_limit_from(pm, i)
        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_thermal_limit_to(pm, i)

        !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_ampacity_from(pm, i)
        !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_ampacity_to(pm, i)
    end

    !con_opts["disable-switch-close-action-limit"] && constraint_switch_close_action_limit(pm)
    con_opts["disable-microgrid-networking"] && constraint_disable_networking(pm; relax=var_opts["relax-integer-variables"])
    !con_opts["disable-radiality-constraint"] && constraint_radial_topology(pm; relax=var_opts["relax-integer-variables"])
    !con_opts["disable-block-isolation-constraint"] && constraint_isolate_block_traditional(pm)
    for i in ids(pm, :switch)
        constraint_mc_switch_state_open_close(pm, i)

        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_switch_thermal_limit(pm, i)
        !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_switch_ampacity(pm, i)
    end

    for i in ids(pm, :transformer)
        constraint_mc_transformer_power_traditional_on_off(pm, i; fix_taps=false)
    end

    objective_min_shed_load_traditional_rolling_horizon(pm)
end
