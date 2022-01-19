"""
    constraint_switch_state_max_actions(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default)

max switching actions per timestep constraint
"""
function constraint_switch_state_max_actions(pm::AbstractSwitchModels; nw::Int=nw_id_default)
    constraint_switch_state_max_actions(pm, nw)
end


"""
    constraint_block_isolation(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false)

constraint to ensure that blocks are properly isolated by open switches
"""
function constraint_block_isolation(pm::AbstractSwitchModels; nw::Int=nw_id_default, relax::Bool=false)
    constraint_block_isolation(pm, nw; relax=relax)
end


"""
    constraint_mc_storage_phase_unbalance(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Constraint template for constraint to enforce balance between phases of ps/qs on storage
"""
function constraint_mc_storage_phase_unbalance(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    strg = ref(pm, nw, :storage, i)
    phase_unbalance_factor = get(strg, "phase_unbalance_factor", Inf)

    if phase_unbalance_factor < Inf
       constraint_mc_storage_phase_unbalance(pm, nw, i, strg["connections"], phase_unbalance_factor)
    end
end


"""
    constraint_mc_transformer_power(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default, fix_taps::Bool=true)::Nothing

Template function for Transformer constraints in Power-voltage space, considering winding type, conductor order, polarity and tap settings.
"""
function constraint_mc_transformer_power_on_off(pm::AbstractSwitchModels, i::Int; nw::Int=nw_id_default, fix_taps::Bool=true)
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
        constraint_mc_transformer_power_yy_on_off(pm, nw, i, f_bus, t_bus, f_idx, t_idx, f_connections, t_connections, pol, tm_set, tm_fixed, tm_scale)
    elseif configuration == PMD.DELTA
        PMD.constraint_mc_transformer_power_dy(pm, nw, i, f_bus, t_bus, f_idx, t_idx, f_connections, t_connections, pol, tm_set, tm_fixed, tm_scale)
    elseif configuration == "zig-zag"
        error("Zig-zag not yet supported.")
    end
end


"""
    constraint_storage_complementarity_mi_on_off(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for mixed-integer storage complementarity constraints
"""
function constraint_storage_complementarity_mi_on_off(pm::AbstractSwitchModels, i::Int; nw::Int=nw_id_default)
    storage = ref(pm, nw, :storage, i)
    charge_ub = storage["charge_rating"]
    discharge_ub = storage["discharge_rating"]

    constraint_storage_complementarity_mi_on_off(pm, nw, i, charge_ub, discharge_ub)
end


"""
    constraint_radial_topology(pm::AbstractSwitchModels; nw::Int=nw_id_default, relax::Bool=false)

Constrains the network to have radial topology
"""
function constraint_radial_topology(pm::AbstractSwitchModels; nw::Int=nw_id_default, relax::Bool=false)
    constraint_radial_topology(pm, nw; relax=relax)
end


"""
    constraint_mc_branch_flow(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)

Template function for ohms constraint for branches on the from-side
"""
function constraint_mc_branch_flow(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default)
    branch = ref(pm, nw, :branch, i)
    f_bus = branch["f_bus"]
    t_bus = branch["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)

    if !haskey(con(pm, nw), :branch_flow)
        con(pm, nw)[:branch_flow] = Dict{Int,Vector{Vector{<:JuMP.ConstraintRef}}}()
    end
    PMD.constraint_mc_branch_flow(pm, nw, f_idx, t_idx, branch["f_connections"], branch["t_connections"])
end
