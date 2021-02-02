""
function run_mc_osw_mi(data::Union{Dict{String,<:Any}, String}, model_type::Type, solver; kwargs...)
    return PMD.run_mc_model(data, model_type, solver, _build_mc_osw_mi; kwargs...)
end


"constructor for mixed-integer branch flow osw"
function _build_mc_osw_mi(pm::PMD.AbstractUBFModels)
    # Variables
    PMD.variable_mc_bus_voltage(pm)
    PMD.variable_mc_branch_current(pm)
    PMD.variable_mc_branch_power(pm)

    PMD.variable_mc_switch_power(pm)
    PMD.variable_mc_switch_state(pm; relax=false)

    PMD.variable_mc_transformer_power(pm)
    PMD.variable_mc_generator_power(pm)
    PMD.variable_mc_load_power(pm)
    PMD.variable_mc_storage_power_mi(pm; relax=true)

    # Constraints
    PMD.constraint_mc_model_current(pm)

    for i in PMD.ids(pm, :ref_buses)
        PMD.constraint_mc_theta_ref(pm, i)
    end

    # gens should be constrained before KCL, or Pd/Qd undefined
    for id in PMD.ids(pm, :gen)
        PMD.constraint_mc_generator_power(pm, id)
    end

    # loads should be constrained before KCL, or Pd/Qd undefined
    for id in PMD.ids(pm, :load)
        PMD.constraint_mc_load_power(pm, id)
    end

    for i in PMD.ids(pm, :bus)
        PMD.constraint_mc_power_balance(pm, i)
    end

    for i in PMD.ids(pm, :storage)
        PMD._PM.constraint_storage_state(pm, i)
        PMD._PM.constraint_storage_complementarity_mi(pm, i)
        PMD.constraint_mc_storage_losses(pm, i)
        PMD.constraint_mc_storage_thermal_limit(pm, i)
    end

    for i in PMD.ids(pm, :branch)
        PMD.constraint_mc_power_losses(pm, i)
        PMD.constraint_mc_model_voltage_magnitude_difference(pm, i)

        PMD.constraint_mc_voltage_angle_difference(pm, i)

        PMD.constraint_mc_thermal_limit_from(pm, i)
        PMD.constraint_mc_thermal_limit_to(pm, i)
    end

    for i in PMD.ids(pm, :switch)
        PMD.constraint_mc_switch_state_on_off(pm, i; relax=true)
        PMD.constraint_mc_switch_thermal_limit(pm, i)
    end

    for i in PMD.ids(pm, :transformer)
        PMD.constraint_mc_transformer_power(pm, i)
    end

    # Objective
    PMD.objective_mc_min_fuel_cost_switch(pm)
end
