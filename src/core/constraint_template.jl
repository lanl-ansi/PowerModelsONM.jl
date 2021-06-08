"KCL for load shed problem with transformers"
function constraint_mc_power_balance_shed(pm::PMD.AbstractUnbalancedPowerModel, i::Int; nw::Int=PMD.nw_id_default)
    bus = PMD.ref(pm, nw, :bus, i)
    bus_arcs = PMD.ref(pm, nw, :bus_arcs_conns_branch, i)
    bus_arcs_sw = PMD.ref(pm, nw, :bus_arcs_conns_switch, i)
    bus_arcs_trans = PMD.ref(pm, nw, :bus_arcs_conns_transformer, i)
    bus_gens = PMD.ref(pm, nw, :bus_conns_gen, i)
    bus_storage = PMD.ref(pm, nw, :bus_conns_storage, i)
    bus_loads = PMD.ref(pm, nw, :bus_conns_load, i)
    bus_shunts = PMD.ref(pm, nw, :bus_conns_shunt, i)

    if !haskey(PMD.con(pm, nw), :lam_kcl_r)
        PMD.con(pm, nw)[:lam_kcl_r] = Dict{Int,Array{PMD.JuMP.ConstraintRef}}()
    end

    if !haskey(PMD.con(pm, nw), :lam_kcl_i)
        PMD.con(pm, nw)[:lam_kcl_i] = Dict{Int,Array{PMD.JuMP.ConstraintRef}}()
    end

    constraint_mc_power_balance_shed(pm, nw, i, bus["terminals"], bus["grounded"], bus_arcs, bus_arcs_sw, bus_arcs_trans, bus_gens, bus_storage, bus_loads, bus_shunts)
end


"max switching actions per timestep constraint"
function constraint_switch_state_max_actions(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default)
    constraint_switch_state_max_actions(pm, nw)
end


"constraint to ensure that load blocks are properly isolated by opening switches"
function constraint_load_block_isolation(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default, relax::Bool=true)
    constraint_load_block_isolation(pm, nw; relax=relax)
end
