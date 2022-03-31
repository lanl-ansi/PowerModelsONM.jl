"""
    solve_mn_block_mld(
        data::Dict{String,<:Any},
        model_type::Type,
        solver;
        kwargs...
    )::Dict{String,Any}

Solves a __multinetwork__ multiconductor optimal switching (mixed-integer) problem using `model_type` and `solver`

Calls back to PowerModelsDistribution.solve_mc_model, and therefore will accept any valid `kwargs`
for that function. See PowerModelsDistribution [documentation](https://lanl-ansi.github.io/PowerModelsDistribution.jl/latest)
for more details.
"""
function solve_mn_block_mld(data::Dict{String,<:Any}, model_type::Type, solver; kwargs...)::Dict{String,Any}
    solve_onm_model(data, model_type, solver, build_mn_block_mld; multinetwork=true, kwargs...)
end


"""
    build_mn_block_mld(pm::PMD.AbstractUBFModels)

Multinetwork load shedding problem for Branch Flow model
"""
function build_mn_block_mld(pm::PMD.AbstractUBFModels)
    for n in nw_ids(pm)
        variable_block_indicator(pm; nw=n, relax=false)
        variable_inverter_indicator(pm; nw=n, relax=false)

        PMD.variable_mc_bus_voltage_on_off(pm; nw=n)

        PMD.variable_mc_branch_current(pm; nw=n)
        PMD.variable_mc_branch_power(pm; nw=n)

        PMD.variable_mc_switch_power(pm; nw=n)
        variable_switch_state(pm; nw=n, relax=false)

        PMD.variable_mc_transformer_power(pm; nw=n)
        PMD.variable_mc_oltc_transformer_tap(pm; nw=n)

        PMD.variable_mc_generator_power_on_off(pm; nw=n)

        variable_mc_storage_power_mi_on_off(pm; nw=n, relax=false)

        PMD.variable_mc_load_power(pm; nw=n)

        PMD.variable_mc_capcontrol(pm; nw=n, relax=false)

        PMD.constraint_mc_model_current(pm; nw=n)

        !get(ref(pm, n), :disable_inverter_constraint, false) && constraint_grid_forming_inverter_per_cc_block(pm; nw=n, relax=false)

        for i in ids(pm, n, :bus)
            constraint_mc_inverter_theta_ref(pm, i; nw=n)
        end

        constraint_mc_bus_voltage_block_on_off(pm; nw=n)

        for i in ids(pm, n, :gen)
            constraint_mc_generator_power_block_on_off(pm, i; nw=n)
        end

        for i in ids(pm, n, :load)
            PMD.constraint_mc_load_power(pm, i; nw=n)
        end

        for i in ids(pm, n, :bus)
            constraint_mc_power_balance_shed_block(pm, i; nw=n)
        end

        for i in ids(pm, n, :storage)
            constraint_storage_complementarity_mi_block_on_off(pm, i; nw=n)
            constraint_mc_storage_block_on_off(pm, i; nw=n)
            constraint_mc_storage_losses_block_on_off(pm, i; nw=n)
            PMD.constraint_mc_storage_thermal_limit(pm, i; nw=n)
            constraint_mc_storage_phase_unbalance_grid_following(pm, i; nw=n)
        end

        for i in ids(pm, n, :branch)
            PMD.constraint_mc_power_losses(pm, i; nw=n)
            PMD.constraint_mc_model_voltage_magnitude_difference(pm, i; nw=n)
            PMD.constraint_mc_voltage_angle_difference(pm, i; nw=n)

            PMD.constraint_mc_thermal_limit_from(pm, i; nw=n)
            PMD.constraint_mc_thermal_limit_to(pm, i; nw=n)

            PMD.constraint_mc_ampacity_from(pm, i; nw=n)
            PMD.constraint_mc_ampacity_to(pm, i; nw=n)
        end

        !get(ref(pm, n), :disable_radial_constraint, false) && constraint_radial_topology(pm; nw=n, relax=false)
        !get(ref(pm, n), :disable_isolation_constraint, false) && constraint_isolate_block(pm; nw=n)
        for i in ids(pm, n, :switch)
            constraint_mc_switch_state_open_close(pm, i; nw=n)

            PMD.constraint_mc_switch_thermal_limit(pm, i; nw=n)
            PMD.constraint_mc_switch_ampacity(pm, i; nw=n)
        end

        for i in ids(pm, n, :transformer)
            constraint_mc_transformer_power_block_on_off(pm, i; nw=n, fix_taps=false)
        end
    end

    network_ids = sort(collect(nw_ids(pm)))

    n_1 = network_ids[1]

    for i in ids(pm, :storage; nw=n_1)
        PMD.constraint_storage_state(pm, i; nw=n_1)
    end

    constraint_switch_close_action_limit(pm; nw=n_1)

    for n_2 in network_ids[2:end]
        constraint_switch_close_action_limit(pm, n_1, n_2)

        for i in ids(pm, :storage; nw=n_2)
            PMD.constraint_storage_state(pm, i, n_1, n_2)
        end

        n_1 = n_2
    end

    objective_min_shed_load_block(pm)
end


"""
    build_mn_block_mld(pm::AbstractUnbalancedPowerModel)

Multinetwork load shedding problem for Bus Injection models
"""
function build_mn_block_mld(pm::AbstractUnbalancedPowerModel)
    for n in nw_ids(pm)
        variable_block_indicator(pm; nw=n, relax=false)
        variable_inverter_indicator(pm; nw=n, relax=false)

        PMD.variable_mc_bus_voltage_on_off(pm; nw=n)

        PMD.variable_mc_branch_power(pm; nw=n)

        PMD.variable_mc_switch_power(pm; nw=n)
        variable_switch_state(pm; nw=n, relax=false)

        PMD.variable_mc_transformer_power(pm; nw=n)
        PMD.variable_mc_oltc_transformer_tap(pm; nw=n)

        PMD.variable_mc_generator_power_on_off(pm; nw=n)

        variable_mc_storage_power_mi_on_off(pm; nw=n, relax=false)

        PMD.variable_mc_load_power(pm; nw=n)

        PMD.variable_mc_capcontrol(pm; nw=n, relax=false)

        PMD.constraint_mc_model_voltage(pm; nw=n)

        !get(ref(pm, n), :disable_inverter_constraint, false) && constraint_grid_forming_inverter_per_cc_block(pm; nw=n, relax=false)

        for i in ids(pm, n, :bus)
            constraint_mc_inverter_theta_ref(pm, i; nw=n)
        end

        constraint_mc_bus_voltage_block_on_off(pm; nw=n)

        for i in ids(pm, n, :gen)
            constraint_mc_generator_power_block_on_off(pm, i; nw=n)
        end

        for i in ids(pm, n, :load)
            PMD.constraint_mc_load_power(pm, i; nw=n)
        end

        for i in ids(pm, n, :bus)
            constraint_mc_power_balance_shed_block(pm, i; nw=n)
        end

        for i in ids(pm, n, :storage)
            constraint_storage_complementarity_mi_block_on_off(pm, i; nw=n)
            constraint_mc_storage_block_on_off(pm, i; nw=n)
            constraint_mc_storage_losses_block_on_off(pm, i; nw=n)
            PMD.constraint_mc_storage_thermal_limit(pm, i; nw=n)
            constraint_mc_storage_phase_unbalance_grid_following(pm, i; nw=n)
        end

        for i in ids(pm, n, :branch)
            PMD.constraint_mc_ohms_yt_from(pm, i; nw=n)
            PMD.constraint_mc_ohms_yt_to(pm, i; nw=n)
            PMD.constraint_mc_voltage_angle_difference(pm, i; nw=n)

            PMD.constraint_mc_thermal_limit_from(pm, i; nw=n)
            PMD.constraint_mc_thermal_limit_to(pm, i; nw=n)

            PMD.constraint_mc_ampacity_from(pm, i; nw=n)
            PMD.constraint_mc_ampacity_to(pm, i; nw=n)
        end

        !get(ref(pm, n), :disable_radial_constraint, false) && constraint_radial_topology(pm; nw=n, relax=false)
        !get(ref(pm, n), :disable_isolation_constraint, false) && constraint_isolate_block(pm; nw=n)
        for i in ids(pm, n, :switch)
            constraint_mc_switch_state_open_close(pm, i; nw=n)

            PMD.constraint_mc_switch_thermal_limit(pm, i; nw=n)
            PMD.constraint_mc_switch_ampacity(pm, i; nw=n)
        end

        for i in ids(pm, n, :transformer)
            constraint_mc_transformer_power_block_on_off(pm, i; nw=n, fix_taps=false)
        end
    end

    network_ids = sort(collect(nw_ids(pm)))

    n_1 = network_ids[1]

    for i in ids(pm, :storage; nw=n_1)
        PMD.constraint_storage_state(pm, i; nw=n_1)
    end

    constraint_switch_close_action_limit(pm; nw=n_1)

    for n_2 in network_ids[2:end]
        constraint_switch_close_action_limit(pm, n_1, n_2)

        for i in ids(pm, :storage; nw=n_2)
            PMD.constraint_storage_state(pm, i, n_1, n_2)
        end

        n_1 = n_2
    end

    objective_min_shed_load_block(pm)
end


"""
    solve_block_mld(
        data::Dict{String,<:Any},
        model_type::Type,
        solver;
        kwargs...
    )::Dict{String,Any}

Solves a multiconductor optimal switching (mixed-integer) problem using `model_type` and `solver`

Calls back to PowerModelsDistribution.solve_mc_model, and therefore will accept any valid `kwargs`
for that function. See PowerModelsDistribution [documentation](https://lanl-ansi.github.io/PowerModelsDistribution.jl/latest)
for more details.
"""
function solve_block_mld(data::Dict{String,<:Any}, model_type::Type, solver; kwargs...)::Dict{String,Any}
    solve_onm_model(data, model_type, solver, build_block_mld; multinetwork=false, kwargs...)
end


"""
    build_block_mld(pm::PMD.AbstractUBFModels)

Single-network load shedding problem for Branch Flow model
"""
function build_block_mld(pm::PMD.AbstractUBFModels)
    variable_block_indicator(pm; relax=false)
    variable_inverter_indicator(pm; relax=false)

    PMD.variable_mc_bus_voltage_on_off(pm)

    PMD.variable_mc_branch_current(pm)
    PMD.variable_mc_branch_power(pm)

    PMD.variable_mc_switch_power(pm)
    variable_switch_state(pm; relax=false)

    PMD.variable_mc_transformer_power(pm)
    PMD.variable_mc_oltc_transformer_tap(pm)

    PMD.variable_mc_generator_power_on_off(pm)

    variable_mc_storage_power_mi_on_off(pm; relax=false)

    PMD.variable_mc_load_power(pm)

    PMD.variable_mc_capcontrol(pm; relax=false)

    PMD.constraint_mc_model_current(pm)

    !get(ref(pm), :disable_inverter_constraint, false) && constraint_grid_forming_inverter_per_cc_block(pm; relax=false)

    for i in ids(pm, :bus)
        constraint_mc_inverter_theta_ref(pm, i)
    end

    constraint_mc_bus_voltage_block_on_off(pm)

    for i in ids(pm, :gen)
        constraint_mc_generator_power_block_on_off(pm, i)
    end

    for i in ids(pm, :load)
        PMD.constraint_mc_load_power(pm, i)
    end

    for i in ids(pm, :bus)
        constraint_mc_power_balance_shed_block(pm, i)
    end

    for i in ids(pm, :storage)
        PMD.constraint_storage_state(pm, i)
        constraint_storage_complementarity_mi_block_on_off(pm, i)
        constraint_mc_storage_block_on_off(pm, i)
        constraint_mc_storage_losses_block_on_off(pm, i)
        PMD.constraint_mc_storage_thermal_limit(pm, i)
        constraint_mc_storage_phase_unbalance_grid_following(pm, i)
    end

    for i in ids(pm, :branch)
        PMD.constraint_mc_power_losses(pm, i)
        PMD.constraint_mc_model_voltage_magnitude_difference(pm, i)
        PMD.constraint_mc_voltage_angle_difference(pm, i)

        PMD.constraint_mc_thermal_limit_from(pm, i)
        PMD.constraint_mc_thermal_limit_to(pm, i)

        PMD.constraint_mc_ampacity_from(pm, i)
        PMD.constraint_mc_ampacity_to(pm, i)
    end

    constraint_switch_close_action_limit(pm)
    !get(ref(pm), :disable_radial_constraint, false) && constraint_radial_topology(pm; relax=false)
    !get(ref(pm), :disable_isolation_constraint, false) && constraint_isolate_block(pm)
    for i in ids(pm, :switch)
        constraint_mc_switch_state_open_close(pm, i)

        PMD.constraint_mc_switch_thermal_limit(pm, i)
        PMD.constraint_mc_switch_ampacity(pm, i)
    end

    for i in ids(pm, :transformer)
        constraint_mc_transformer_power_block_on_off(pm, i; fix_taps=false)
    end

    objective_min_shed_load_block_rolling_horizon(pm)
end


"""
    build_block_mld(pm::AbstractUnbalancedPowerModel)

Single network load shedding problem for Bus Injection model
"""
function build_block_mld(pm::AbstractUnbalancedPowerModel)
    variable_block_indicator(pm; relax=false)
    variable_inverter_indicator(pm; relax=false)

    PMD.variable_mc_bus_voltage_on_off(pm)

    PMD.variable_mc_branch_power(pm)

    PMD.variable_mc_switch_power(pm)
    variable_switch_state(pm; relax=false)

    PMD.variable_mc_transformer_power(pm)
    PMD.variable_mc_oltc_transformer_tap(pm)

    PMD.variable_mc_generator_power_on_off(pm)

    variable_mc_storage_power_mi_on_off(pm; relax=false)

    PMD.variable_mc_load_power(pm)

    PMD.variable_mc_capcontrol(pm; relax=false)

    PMD.constraint_mc_model_voltage(pm)

    !get(ref(pm), :disable_inverter_constraint, false) && constraint_grid_forming_inverter_per_cc_block(pm; relax=false)

    for i in ids(pm, :bus)
        constraint_mc_inverter_theta_ref(pm, i)
    end

    constraint_mc_bus_voltage_block_on_off(pm)

    for i in ids(pm, :gen)
        constraint_mc_generator_power_block_on_off(pm, i)
    end

    for i in ids(pm, :load)
        PMD.constraint_mc_load_power(pm, i)
    end

    for i in ids(pm, :bus)
        constraint_mc_power_balance_shed_block(pm, i)
    end

    for i in ids(pm, :storage)
        PMD.constraint_storage_state(pm, i)
        constraint_storage_complementarity_mi_block_on_off(pm, i)
        constraint_mc_storage_block_on_off(pm, i)
        constraint_mc_storage_losses_block_on_off(pm, i)
        PMD.constraint_mc_storage_thermal_limit(pm, i)
        constraint_mc_storage_phase_unbalance_grid_following(pm, i)
    end

    for i in ids(pm, :branch)
        PMD.constraint_mc_ohms_yt_from(pm, i)
        PMD.constraint_mc_ohms_yt_to(pm, i)
        PMD.constraint_mc_voltage_angle_difference(pm, i)

        PMD.constraint_mc_thermal_limit_from(pm, i)
        PMD.constraint_mc_thermal_limit_to(pm, i)

        PMD.constraint_mc_ampacity_from(pm, i)
        PMD.constraint_mc_ampacity_to(pm, i)
    end

    constraint_switch_close_action_limit(pm)
    !get(ref(pm), :disable_radial_constraint, false) && constraint_radial_topology(pm; relax=false)
    !get(ref(pm), :disable_isolation_constraint, false) && constraint_isolate_block(pm)
    for i in ids(pm, :switch)
        constraint_mc_switch_state_open_close(pm, i)

        PMD.constraint_mc_switch_thermal_limit(pm, i)
        PMD.constraint_mc_switch_ampacity(pm, i)
    end

    for i in ids(pm, :transformer)
        constraint_mc_transformer_power_block_on_off(pm, i; fix_taps=false)
    end

    objective_min_shed_load_block_rolling_horizon(pm)
end
