"""
    constraint_switch_state_max_actions(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default)

max switching actions per timestep constraint
"""
function constraint_switch_state_max_actions(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default)
    constraint_switch_state_max_actions(pm, nw)
end


"""
    constraint_block_isolation(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default, relax::Bool=false)

constraint to ensure that blocks are properly isolated by open switches
"""
function constraint_block_isolation(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default, relax::Bool=false)
    constraint_block_isolation(pm, nw; relax=relax)
end


"""
    constraint_mc_transformer_power(pm::AbstractUnbalancedPowerModel, i::Int; nw::Int=nw_id_default, fix_taps::Bool=true)::Nothing

Template function for Transformer constraints in Power-voltage space, considering winding type, conductor order, polarity and tap settings.
"""
function constraint_mc_transformer_power_on_off(pm::PMD.AbstractUnbalancedPowerModel, i::Int; nw::Int=PMD.nw_id_default, fix_taps::Bool=true)
    transformer = PMD.ref(pm, nw, :transformer, i)
    f_bus = transformer["f_bus"]
    t_bus = transformer["t_bus"]
    f_idx = (i, f_bus, t_bus)
    t_idx = (i, t_bus, f_bus)
    configuration = transformer["configuration"]
    f_connections = transformer["f_connections"]
    t_connections = transformer["t_connections"]
    tm_set = transformer["tm_set"]
    tm_fixed = fix_taps ? ones(Bool, length(tm_set)) : transformer["tm_fix"]
    tm_scale = PMD.calculate_tm_scale(transformer, PMD.ref(pm, nw, :bus, f_bus), PMD.ref(pm, nw, :bus, t_bus))
    pol = transformer["polarity"]

    if configuration == PMD.WYE
        constraint_mc_transformer_power_yy_on_off(pm, nw, i, f_bus, t_bus, f_idx, t_idx, f_connections, t_connections, pol, tm_set, tm_fixed, tm_scale)
    elseif configuration == PMD.DELTA
        PMD.constraint_mc_transformer_power_dy(pm, nw, i, f_bus, t_bus, f_idx, t_idx, f_connections, t_connections, pol, tm_set, tm_fixed, tm_scale)
    elseif configuration == "zig-zag"
        error("Zig-zag not yet supported.")
    end
end
