"""
    solve_mn_mc_osw_mld_mi(data::Union{Dict{String,<:Any}, String}, model_type::Type, solver; kwargs...)::Dict{String,Any}

Solves a __multinetwork__ multiconductor optimal switching (mixed-integer) problem using `model_type` and `solver`

Calls back to PowerModelsDistribution.solve_mc_model, and therefore will accept any valid `kwargs`
for that function. See PowerModelsDistribution [documentation](https://lanl-ansi.github.io/PowerModelsDistribution.jl/latest)
for more details.
"""
function solve_mn_mc_osw_mld_mi(data::Union{Dict{String,<:Any}, String}, model_type::Type, solver; kwargs...)::Dict{String,Any}
    return PMD.solve_mc_model(data, model_type, solver, build_mn_mc_osw_mld_mi; multinetwork=true, kwargs...)
end


"Multinetwork load shedding problem for Branch Flow model"
function build_mn_mc_osw_mld_mi(pm::AbstractUBFSwitchModels)
    for n in nw_ids(pm)
        variable_mc_block_indicator(pm; nw=n, relax=false)

        PMD.variable_mc_bus_voltage_on_off(pm; nw=n)

        PMD.variable_mc_branch_current(pm; nw=n)
        PMD.variable_mc_branch_power(pm; nw=n)
        PMD.variable_mc_switch_power(pm; nw=n)
        variable_mc_switch_state(pm; nw=n, relax=false)
        variable_mc_switch_fixed(pm; nw=n)
        PMD.variable_mc_transformer_power(pm; nw=n)

        PMD.variable_mc_oltc_transformer_tap(pm; nw=n)

        PMD.variable_mc_generator_power_on_off(pm; nw=n)
        PMD.variable_mc_storage_power_mi_on_off(pm; nw=n, relax=false)
        PMD.variable_mc_load_power(pm; nw=n)

        PMD.variable_mc_capcontrol(pm; nw=n, relax=false)

        PMD.constraint_mc_model_current(pm; nw=n)

        for i in ids(pm, n, :ref_buses)
            PMD.constraint_mc_theta_ref(pm, i; nw=n)
        end

        PMD.constraint_mc_bus_voltage_on_off(pm; nw=n)

        for i in ids(pm, n, :gen)
            PMD.constraint_mc_gen_power_on_off(pm, i; nw=n)
        end

        for i in ids(pm, n, :load)
            PMD.constraint_mc_load_power(pm, i; nw=n)
        end

        for i in ids(pm, n, :bus)
            PMD.constraint_mc_power_balance_shed(pm, i; nw=n)
        end

        for i in ids(pm, n, :storage)
            constraint_storage_complementarity_mi_on_off(pm, i; nw=n)
            PMD.constraint_mc_storage_on_off(pm, i; nw=n)
            constraint_mc_storage_losses_on_off(pm, i; nw=n)
            PMD.constraint_mc_storage_thermal_limit(pm, i; nw=n)
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
        !get(ref(pm, n), :disable_isolation_constraint, false) && constraint_block_isolation(pm; nw=n, relax=true)
        for i in ids(pm, n, :switch)
            PMD.constraint_mc_switch_state_on_off(pm, i; nw=n, relax=true)

            PMD.constraint_mc_switch_thermal_limit(pm, i; nw=n)
            PMD.constraint_mc_switch_ampacity(pm, i; nw=n)
        end

        for i in ids(pm, n, :transformer)
            constraint_mc_transformer_power_on_off(pm, i; nw=n, fix_taps=false)
        end
    end

    network_ids = sort(collect(nw_ids(pm)))

    n_1 = network_ids[1]

    for i in ids(pm, :storage; nw=n_1)
        PMD.constraint_storage_state(pm, i; nw=n_1)
    end

    constraint_switch_state_max_actions(pm; nw=n_1)

    for n_2 in network_ids[2:end]
        constraint_switch_state_max_actions(pm, n_1, n_2)

        for i in ids(pm, :storage; nw=n_2)
            PMD.constraint_storage_state(pm, i, n_1, n_2)
        end

        n_1 = n_2
    end

    objective_mc_min_load_setpoint_delta_switch_global(pm)
end


"Multinetwork load shedding problem for Bus Injection models"
function build_mn_mc_osw_mld_mi(pm::AbstractSwitchModels)
    for n in nw_ids(pm)
        variable_mc_block_indicator(pm; nw=n, relax=false)

        PMD.variable_mc_bus_voltage_on_off(pm; nw=n)

        PMD.variable_mc_branch_power(pm; nw=n)
        PMD.variable_mc_switch_power(pm; nw=n)
        variable_mc_switch_state(pm; nw=n, relax=false)
        variable_mc_switch_fixed(pm; nw=n)
        PMD.variable_mc_transformer_power(pm; nw=n)

        PMD.variable_mc_oltc_transformer_tap(pm; nw=n)

        PMD.variable_mc_generator_power_on_off(pm; nw=n)
        PMD.variable_mc_storage_power_mi_on_off(pm; nw=n, relax=false)
        PMD.variable_mc_load_power(pm; nw=n)

        PMD.variable_mc_capcontrol(pm; nw=n, relax=false)

        PMD.constraint_mc_model_voltage(pm; nw=n)

        for i in ids(pm, n, :ref_buses)
            PMD.constraint_mc_theta_ref(pm, i; nw=n)
        end

        PMD.constraint_mc_bus_voltage_on_off(pm; nw=n)

        for i in ids(pm, n, :gen)
            PMD.constraint_mc_gen_power_on_off(pm, i; nw=n)
        end

        for i in ids(pm, n, :load)
            PMD.constraint_mc_load_power(pm, i; nw=n)
        end

        for i in ids(pm, n, :bus)
            PMD.constraint_mc_power_balance_shed(pm, i; nw=n)
        end

        for i in ids(pm, n, :storage)
            constraint_storage_complementarity_mi_on_off(pm, i; nw=n)
            PMD.constraint_mc_storage_on_off(pm, i; nw=n)
            constraint_mc_storage_losses_on_off(pm, i; nw=n)
            PMD.constraint_mc_storage_thermal_limit(pm, i; nw=n)
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
        !get(ref(pm, n), :disable_isolation_constraint, false) && constraint_block_isolation(pm; nw=n, relax=true)
        for i in ids(pm, n, :switch)
            PMD.constraint_mc_switch_state_on_off(pm, i; nw=n, relax=true)

            PMD.constraint_mc_switch_thermal_limit(pm, i; nw=n)
            PMD.constraint_mc_switch_ampacity(pm, i; nw=n)
        end

        for i in ids(pm, n, :transformer)
            constraint_mc_transformer_power_on_off(pm, i; nw=n, fix_taps=false)
        end
    end

    network_ids = sort(collect(nw_ids(pm)))

    n_1 = network_ids[1]

    for i in ids(pm, :storage; nw=n_1)
        PMD.constraint_storage_state(pm, i; nw=n_1)
    end

    constraint_switch_state_max_actions(pm; nw=n_1)

    for n_2 in network_ids[2:end]
        constraint_switch_state_max_actions(pm, n_1, n_2)

        for i in ids(pm, :storage; nw=n_2)
            PMD.constraint_storage_state(pm, i, n_1, n_2)
        end

        n_1 = n_2
    end

    objective_mc_min_load_setpoint_delta_switch_global(pm)
end


"""
    solve_mc_osw_mld_mi(data::Union{Dict{String,<:Any}, String}, model_type::Type, solver; kwargs...)::Dict{String,Any}

Solves a multiconductor optimal switching (mixed-integer) problem using `model_type` and `solver`

Calls back to PowerModelsDistribution.solve_mc_model, and therefore will accept any valid `kwargs`
for that function. See PowerModelsDistribution [documentation](https://lanl-ansi.github.io/PowerModelsDistribution.jl/latest)
for more details.
"""
function solve_mc_osw_mld_mi(data::Union{Dict{String,<:Any}, String}, model_type::Type, solver; kwargs...)::Dict{String,Any}
    return PMD.solve_mc_model(data, model_type, solver, build_mc_osw_mld_mi; multinetwork=false, kwargs...)
end


"Multinetwork load shedding problem for Branch Flow model"
function build_mc_osw_mld_mi(pm::AbstractUBFSwitchModels)
    variable_mc_block_indicator(pm; relax=false)

    PMD.variable_mc_bus_voltage_on_off(pm)

    PMD.variable_mc_branch_current(pm)
    PMD.variable_mc_branch_power(pm)
    PMD.variable_mc_switch_power(pm)
    variable_mc_switch_state(pm; relax=false)
    variable_mc_switch_fixed(pm)
    PMD.variable_mc_transformer_power(pm)

    PMD.variable_mc_oltc_transformer_tap(pm)

    PMD.variable_mc_generator_power_on_off(pm)
    PMD.variable_mc_storage_power_mi_on_off(pm; relax=false)
    PMD.variable_mc_load_power(pm)

    PMD.variable_mc_capcontrol(pm, relax=false)

    PMD.constraint_mc_model_current(pm)

    for i in ids(pm, :ref_buses)
        PMD.constraint_mc_theta_ref(pm, i)
    end

    PMD.constraint_mc_bus_voltage_on_off(pm)

    for i in ids(pm, :gen)
        PMD.constraint_mc_gen_power_on_off(pm, i)
    end

    for i in ids(pm, :load)
        PMD.constraint_mc_load_power(pm, i)
    end

    for i in ids(pm, :bus)
        PMD.constraint_mc_power_balance_shed(pm, i)
    end

    for i in ids(pm, :storage)
        PMD.constraint_storage_state(pm, i)
        constraint_storage_complementarity_mi_on_off(pm, i)
        PMD.constraint_mc_storage_on_off(pm, i)
        constraint_mc_storage_losses_on_off(pm, i)
        PMD.constraint_mc_storage_thermal_limit(pm, i)
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

    constraint_switch_state_max_actions(pm)
    !get(ref(pm), :disable_radial_constraint, false) && constraint_radial_topology(pm; relax=false)
    !get(ref(pm), :disable_isolation_constraint, false) && constraint_block_isolation(pm; relax=true)
    for i in ids(pm, :switch)
        PMD.constraint_mc_switch_state_on_off(pm, i; relax=true)

        PMD.constraint_mc_switch_thermal_limit(pm, i)
        PMD.constraint_mc_switch_ampacity(pm, i)
    end

    for i in ids(pm, :transformer)
        constraint_mc_transformer_power_on_off(pm, i; fix_taps=false)
    end

    objective_mc_min_load_setpoint_delta_switch_iterative(pm)
end


"Single network load shedding problem for Bus Injection model"
function build_mc_osw_mld_mi(pm::AbstractSwitchModels)
    for n in nw_ids(pm)
        variable_mc_block_indicator(pm; relax=false)

        PMD.variable_mc_bus_voltage_on_off(pm)

        PMD.variable_mc_branch_power(pm)
        PMD.variable_mc_switch_power(pm)
        variable_mc_switch_state(pm; relax=false)
        variable_mc_switch_fixed(pm)
        PMD.variable_mc_transformer_power(pm)

        PMD.variable_mc_oltc_transformer_tap(pm)

        PMD.variable_mc_generator_power_on_off(pm)
        PMD.variable_mc_storage_power_mi_on_off(pm; relax=false)
        PMD.variable_mc_load_power(pm)

        PMD.variable_mc_capcontrol(pm; relax=false)

        PMD.constraint_mc_model_voltage(pm)

        for i in ids(pm, n, :ref_buses)
            PMD.constraint_mc_theta_ref(pm, i)
        end

        PMD.constraint_mc_bus_voltage_on_off(pm)

        for i in ids(pm, n, :gen)
            PMD.constraint_mc_gen_power_on_off(pm, i)
        end

        for i in ids(pm, n, :load)
            PMD.constraint_mc_load_power(pm, i)
        end

        for i in ids(pm, n, :bus)
            PMD.constraint_mc_power_balance_shed(pm, i)
        end

        for i in ids(pm, n, :storage)
            PMD.constraint_storage_state(pm, i)
            constraint_storage_complementarity_mi_on_off(pm, i)
            PMD.constraint_mc_storage_on_off(pm, i)
            constraint_mc_storage_losses_on_off(pm, i)
            PMD.constraint_mc_storage_thermal_limit(pm, i)
        end

        for i in ids(pm, n, :branch)
            PMD.constraint_mc_ohms_yt_from(pm, i)
            PMD.constraint_mc_ohms_yt_to(pm, i)
            PMD.constraint_mc_voltage_angle_difference(pm, i)

            PMD.constraint_mc_thermal_limit_from(pm, i)
            PMD.constraint_mc_thermal_limit_to(pm, i)

            PMD.constraint_mc_ampacity_from(pm, i)
            PMD.constraint_mc_ampacity_to(pm, i)
        end

        constraint_switch_state_max_actions(pm)
        !get(ref(pm), :disable_radial_constraint, false) && constraint_radial_topology(pm; relax=false)
        !get(ref(pm), :disable_isolation_constraint, false) && constraint_block_isolation(pm; relax=true)
        for i in ids(pm, n, :switch)
            PMD.constraint_mc_switch_state_on_off(pm, i; relax=true)

            PMD.constraint_mc_switch_thermal_limit(pm, i)
            PMD.constraint_mc_switch_ampacity(pm, i)
        end

        for i in ids(pm, n, :transformer)
            constraint_mc_transformer_power_on_off(pm, i; fix_taps=false)
        end
    end

    objective_mc_min_load_setpoint_delta_switch_iterative(pm)
end
