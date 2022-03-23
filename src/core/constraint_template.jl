"""
    constraint_mc_bus_voltage_block_on_off(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)

Template function for bus voltage block on/off constraint.
"""
function constraint_mc_bus_voltage_block_on_off(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)
    for (i,bus) in ref(pm, nw, :bus)
        constraint_mc_bus_voltage_block_on_off(pm, nw, i, bus["vmin"], bus["vmax"])
    end
end


"""
    constraint_mc_bus_voltage_traditional_on_off(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)

Template function for bus voltage traditional on/off constraint.
"""
function constraint_mc_bus_voltage_traditional_on_off(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)
    for (i,bus) in ref(pm, nw, :bus)
        constraint_mc_bus_voltage_traditional_on_off(pm, nw, i, bus["vmin"], bus["vmax"])
    end
end


"""
    constraint_mc_generator_power_block_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for generator power block on/off constraint.
"""
function constraint_mc_generator_power_block_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    gen = ref(pm, nw, :gen, i)
    ncnds = length(gen["connections"])

    pmin = get(gen, "pmin", fill(-Inf, ncnds))
    pmax = get(gen, "pmax", fill( Inf, ncnds))
    qmin = get(gen, "qmin", fill(-Inf, ncnds))
    qmax = get(gen, "qmax", fill( Inf, ncnds))

    constraint_mc_generator_power_block_on_off(pm, nw, i, gen["connections"], pmin, pmax, qmin, qmax)
end


"""
    constraint_mc_generator_power_traditional_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for generator power traditional on/off constraint.
"""
function constraint_mc_generator_power_traditional_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    gen = ref(pm, nw, :gen, i)
    ncnds = length(gen["connections"])

    pmin = get(gen, "pmin", fill(-Inf, ncnds))
    pmax = get(gen, "pmax", fill( Inf, ncnds))
    qmin = get(gen, "qmin", fill(-Inf, ncnds))
    qmax = get(gen, "qmax", fill( Inf, ncnds))

    constraint_mc_generator_power_traditional_on_off(pm, nw, i, gen["connections"], pmin, pmax, qmin, qmax)
end


"""
    constraint_mc_power_balance_shed_block(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for power balance constraints for block load shed.
"""
function constraint_mc_power_balance_shed_block(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    bus = ref(pm, nw, :bus, i)
    bus_arcs = ref(pm, nw, :bus_arcs_conns_branch, i)
    bus_arcs_sw = ref(pm, nw, :bus_arcs_conns_switch, i)
    bus_arcs_trans = ref(pm, nw, :bus_arcs_conns_transformer, i)
    bus_gens = ref(pm, nw, :bus_conns_gen, i)
    bus_storage = ref(pm, nw, :bus_conns_storage, i)
    bus_loads = ref(pm, nw, :bus_conns_load, i)
    bus_shunts = ref(pm, nw, :bus_conns_shunt, i)

    if !haskey(con(pm, nw), :lam_kcl_r)
        con(pm, nw)[:lam_kcl_r] = Dict{Int,Array{JuMP.ConstraintRef}}()
    end

    if !haskey(con(pm, nw), :lam_kcl_i)
        con(pm, nw)[:lam_kcl_i] = Dict{Int,Array{JuMP.ConstraintRef}}()
    end

    constraint_mc_power_balance_shed_block(pm, nw, i, bus["terminals"], bus["grounded"], bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_storage, bus_loads, bus_shunts)
end


"""
    constraint_mc_power_balance_shed_traditional(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for power balance constraints for traditional load shed.
"""
function constraint_mc_power_balance_shed_traditional(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    bus = ref(pm, nw, :bus, i)
    bus_arcs = ref(pm, nw, :bus_arcs_conns_branch, i)
    bus_arcs_sw = ref(pm, nw, :bus_arcs_conns_switch, i)
    bus_arcs_trans = ref(pm, nw, :bus_arcs_conns_transformer, i)
    bus_gens = ref(pm, nw, :bus_conns_gen, i)
    bus_storage = ref(pm, nw, :bus_conns_storage, i)
    bus_loads = ref(pm, nw, :bus_conns_load, i)
    bus_shunts = ref(pm, nw, :bus_conns_shunt, i)

    if !haskey(con(pm, nw), :lam_kcl_r)
        con(pm, nw)[:lam_kcl_r] = Dict{Int,Array{JuMP.ConstraintRef}}()
    end

    if !haskey(con(pm, nw), :lam_kcl_i)
        con(pm, nw)[:lam_kcl_i] = Dict{Int,Array{JuMP.ConstraintRef}}()
    end

    constraint_mc_power_balance_shed_traditional(pm, nw, i, bus["terminals"], bus["grounded"], bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_storage, bus_loads, bus_shunts)
end


"""
    constraint_storage_complementarity_mi_block_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for mixed-integer storage complementarity constraints.
"""
function constraint_storage_complementarity_mi_block_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    storage = ref(pm, nw, :storage, i)
    charge_ub = storage["charge_rating"]
    discharge_ub = storage["discharge_rating"]

    constraint_storage_complementarity_mi_block_on_off(pm, nw, i, charge_ub, discharge_ub)
end


"""
    constraint_storage_complementarity_mi_traditional_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for mixed-integer storage complementarity constraints.
"""
function constraint_storage_complementarity_mi_traditional_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    storage = ref(pm, nw, :storage, i)
    charge_ub = storage["charge_rating"]
    discharge_ub = storage["discharge_rating"]

    constraint_storage_complementarity_mi_traditional_on_off(pm, nw, i, charge_ub, discharge_ub)
end


"""
    constraint_mc_storage_block_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for storage block on/off constraint
"""
function constraint_mc_storage_block_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    storage = ref(pm, nw, :storage, i)
    charge_ub = storage["charge_rating"]
    discharge_ub = storage["discharge_rating"]

    ncnds = length(storage["connections"])
    pmin = zeros(ncnds)
    pmax = zeros(ncnds)
    qmin = zeros(ncnds)
    qmax = zeros(ncnds)

    inj_lb, inj_ub = PMD.ref_calc_storage_injection_bounds(ref(pm, nw, :storage), ref(pm, nw, :bus))
    for (idx,c) in enumerate(storage["connections"])
        pmin[idx] = inj_lb[i][idx]
        pmax[idx] = inj_ub[i][idx]
        qmin[idx] = max(inj_lb[i][idx], ref(pm, nw, :storage, i, "qmin"))
        qmax[idx] = min(inj_ub[i][idx], ref(pm, nw, :storage, i, "qmax"))
    end

    constraint_mc_storage_block_on_off(pm, nw, i, storage["connections"], maximum(pmin), minimum(pmax), maximum(qmin), minimum(qmax), charge_ub, discharge_ub)
end


"""
    constraint_mc_storage_traditional_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for storage traditional on/off constraint.
"""
function constraint_mc_storage_traditional_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    storage = ref(pm, nw, :storage, i)
    charge_ub = storage["charge_rating"]
    discharge_ub = storage["discharge_rating"]

    ncnds = length(storage["connections"])
    pmin = zeros(ncnds)
    pmax = zeros(ncnds)
    qmin = zeros(ncnds)
    qmax = zeros(ncnds)

    inj_lb, inj_ub = PMD.ref_calc_storage_injection_bounds(ref(pm, nw, :storage), ref(pm, nw, :bus))
    for (idx,c) in enumerate(storage["connections"])
        pmin[idx] = inj_lb[i][idx]
        pmax[idx] = inj_ub[i][idx]
        qmin[idx] = max(inj_lb[i][idx], ref(pm, nw, :storage, i, "qmin"))
        qmax[idx] = min(inj_ub[i][idx], ref(pm, nw, :storage, i, "qmax"))
    end

    constraint_mc_storage_traditional_on_off(pm, nw, i, storage["connections"], maximum(pmin), minimum(pmax), maximum(qmin), minimum(qmax), charge_ub, discharge_ub)
end



"""
    constraint_mc_storage_losses_block_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for storage losses block on/off constraint.
"""
function constraint_mc_storage_losses_block_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    storage = ref(pm, nw, :storage, i)
    constraint_mc_storage_losses_block_on_off(pm, nw, i, storage["storage_bus"], storage["connections"], storage["r"], storage["x"], storage["p_loss"], storage["q_loss"])
end


"""
    constraint_mc_storage_losses_traditional_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for storage losses traditional on/off constraint.
"""
function constraint_mc_storage_losses_traditional_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    storage = ref(pm, nw, :storage, i)
    constraint_mc_storage_losses_traditional_on_off(pm, nw, i, storage["storage_bus"], storage["connections"], storage["r"], storage["x"], storage["p_loss"], storage["q_loss"])
end


"""
    constraint_mc_storage_phase_unbalance(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Constraint template for constraint to enforce balance between phases of ps/qs on storage.
"""
function constraint_mc_storage_phase_unbalance(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    strg = ref(pm, nw, :storage, i)
    phase_unbalance_factor = get(strg, "phase_unbalance_factor", Inf)

    if phase_unbalance_factor < Inf
       constraint_mc_storage_phase_unbalance(pm, nw, i, strg["connections"], phase_unbalance_factor)
    end
end


"""
    constraint_mc_storage_phase_unbalance_grid_following(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Constraint template for constraint to enforce balance between phases of ps/qs on storage for grid-following inverters only.
Requires `z_inverter` variables to indicate if a DER is grid-forming or grid-following
"""
function constraint_mc_storage_phase_unbalance_grid_following(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    strg = ref(pm, nw, :storage, i)
    phase_unbalance_factor = get(strg, "phase_unbalance_factor", Inf)

    if phase_unbalance_factor < Inf
        constraint_mc_storage_phase_unbalance_grid_following(pm, nw, i, strg["connections"], phase_unbalance_factor)
    end
end


"""
    constraint_switch_close_action_limit(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)

Template function for constraint of maximum switch closes per timestep (allows unlimited switch opens).
"""
function constraint_switch_close_action_limit(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)
    constraint_switch_close_action_limit(pm, nw)
end


"""
    constraint_isolate_block(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)

Template function of constraint to ensure that blocks are properly isolated by open switches in block mld problem.
"""
function constraint_isolate_block(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)
    constraint_isolate_block(pm, nw)
end


"""
    constraint_isolate_block_traditional(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)

Template function for constraint to ensure that blocks are properly isolated by open switches in a traditional mld problem.
"""
function constraint_isolate_block_traditional(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)
    constraint_isolate_block_traditional(pm, nw)
end



"""
    constraint_radial_topology(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false)

Template function radial topology constraint.
"""
function constraint_radial_topology(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false)
    constraint_radial_topology(pm, nw; relax=relax)
end


"""
    constraint_mc_switch_state_open_close(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Voltage and power constraints for open/close switches
"""
function constraint_mc_switch_state_open_close(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    switch = ref(pm, nw, :switch, i)

    f_bus = switch["f_bus"]
    t_bus = switch["t_bus"]

    f_connections = switch["f_connections"]
    t_connections = switch["t_connections"]

    constraint_mc_switch_voltage_open_close(pm, nw, i, f_bus, t_bus, f_connections, t_connections)
    constraint_mc_switch_power_open_close(pm, nw, i, f_bus, t_bus, f_connections, t_connections)
end


"""
    constraint_mc_transformer_power_block_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default, fix_taps::Bool=true)

Template function for transformer power constraints for block mld problem.
"""
function constraint_mc_transformer_power_block_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default, fix_taps::Bool=true)
    transformer = ref(pm, nw, :transformer, i)
    f_bus = transformer["f_bus"]
    t_bus = transformer["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)
    configuration = transformer["configuration"]
    f_connections = transformer["f_connections"]
    t_connections = transformer["t_connections"]
    tm_set = transformer["tm_set"]
    tm_fixed = fix_taps ? ones(Bool, length(tm_set)) : transformer["tm_fix"]
    tm_scale = PMD.calculate_tm_scale(transformer, ref(pm, nw, :bus, f_bus), ref(pm, nw, :bus, t_bus))
    pol = transformer["polarity"]

    if configuration == PMD.WYE
        constraint_mc_transformer_power_yy_block_on_off(pm, nw, i, f_bus, t_bus, f_idx, t_idx, f_connections, t_connections, pol, tm_set, tm_fixed, tm_scale)
    elseif configuration == PMD.DELTA
        PMD.constraint_mc_transformer_power_dy(pm, nw, i, f_bus, t_bus, f_idx, t_idx, f_connections, t_connections, pol, tm_set, tm_fixed, tm_scale)
    elseif configuration == "zig-zag"
        error("Zig-zag not yet supported.")
    end
end


"""
    constraint_mc_transformer_power_traditional_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default, fix_taps::Bool=true)

Template function for transformer power constraints for traditional mld problem.
"""
function constraint_mc_transformer_power_traditional_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default, fix_taps::Bool=true)
    transformer = ref(pm, nw, :transformer, i)
    f_bus = transformer["f_bus"]
    t_bus = transformer["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)
    configuration = transformer["configuration"]
    f_connections = transformer["f_connections"]
    t_connections = transformer["t_connections"]
    tm_set = transformer["tm_set"]
    tm_fixed = fix_taps ? ones(Bool, length(tm_set)) : transformer["tm_fix"]
    tm_scale = PMD.calculate_tm_scale(transformer, ref(pm, nw, :bus, f_bus), ref(pm, nw, :bus, t_bus))
    pol = transformer["polarity"]

    if configuration == PMD.WYE
        constraint_mc_transformer_power_yy_traditional_on_off(pm, nw, i, f_bus, t_bus, f_idx, t_idx, f_connections, t_connections, pol, tm_set, tm_fixed, tm_scale)
    elseif configuration == PMD.DELTA
        PMD.constraint_mc_transformer_power_dy(pm, nw, i, f_bus, t_bus, f_idx, t_idx, f_connections, t_connections, pol, tm_set, tm_fixed, tm_scale)
    elseif configuration == "zig-zag"
        error("Zig-zag not yet supported.")
    end
end


"""
    constraint_grid_forming_inverter_per_cc_block(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false)

Template function for constraining the number of grid-forming inverters per connected component in the block mld problem
"""
function constraint_grid_forming_inverter_per_cc_block(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false)
    constraint_grid_forming_inverter_per_cc_block(pm, nw; relax=relax)
end


"""
    constraint_grid_forming_inverter_per_cc_traditional(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false)

Template function for constraining the number of grid-forming inverters per connected component in the traditional mld formulation
"""
function constraint_grid_forming_inverter_per_cc_traditional(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false)
    constraint_grid_forming_inverter_per_cc_traditional(pm, nw; relax=relax)
end


