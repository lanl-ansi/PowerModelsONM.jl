"""
    variable_mc_block_indicator(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default, relax::Bool=false, report::Bool=true)

create variables for block status by load block
"""
function variable_mc_block_indicator(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default, relax::Bool=false, report::Bool=true)
    if relax
        z_block = PMD.var(pm, nw)[:z_block] = PMD.JuMP.@variable(pm.model,
            [i in PMD.ids(pm, nw, :blocks)], base_name="$(nw)_z_block",
            lower_bound = 0,
            upper_bound = 1,
            start = 1
        )
    else
        z_block = PMD.var(pm, nw)[:z_block] = PMD.JuMP.@variable(pm.model,
            [i in PMD.ids(pm, nw, :blocks)], base_name="$(nw)_z_block",
            binary = true,
            start = 1
        )
    end

    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :bus,     :status, PMD.ids(pm, nw, :bus),     Dict{Int,Any}(i => PMD.var(pm, nw, :z_block, PMD.ref(pm, nw, :bus_block_map, i))     for i in PMD.ids(pm, nw, :bus)))
    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load,    :status, PMD.ids(pm, nw, :load),    Dict{Int,Any}(i => PMD.var(pm, nw, :z_block, PMD.ref(pm, nw, :load_block_map, i))    for i in PMD.ids(pm, nw, :load)))
    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :shunt,   :status, PMD.ids(pm, nw, :shunt),   Dict{Int,Any}(i => PMD.var(pm, nw, :z_block, PMD.ref(pm, nw, :shunt_block_map, i))   for i in PMD.ids(pm, nw, :shunt)))
    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :gen,     :status, PMD.ids(pm, nw, :gen),     Dict{Int,Any}(i => PMD.var(pm, nw, :z_block, PMD.ref(pm, nw, :gen_block_map, i))     for i in PMD.ids(pm, nw, :gen)))
    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :storage, :status, PMD.ids(pm, nw, :storage), Dict{Int,Any}(i => PMD.var(pm, nw, :z_block, PMD.ref(pm, nw, :storage_block_map, i)) for i in PMD.ids(pm, nw, :storage)))
end


"""
    variable_mc_switch_fixed(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default, report::Bool=false)

Fixed switches set to constant values for multinetwork formulation (we need all switches)
"""
function variable_mc_switch_fixed(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default, report::Bool=false)
    dispatchable_switches = collect(PMD.ids(pm, nw, :switch_dispatchable))
    fixed_switches = [i for i in PMD.ids(pm, nw, :switch) if i ∉ dispatchable_switches]

    for i in fixed_switches
        PMD.var(pm, nw, :switch_state)[i] = PMD.ref(pm, nw, :switch, i, "state")
    end

    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :switch, :status, fixed_switches, Dict{Int,Any}(i => PMD.var(pm, nw, :switch_state, i) for i in fixed_switches))
end


"switch state (open/close) variables"
function variable_mc_switch_state(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default, report::Bool=true, relax::Bool=false)
    if relax
        state = PMD.var(pm, nw)[:switch_state] = Dict{Int,Any}(l => PMD.JuMP.@variable(
            pm.model,
            base_name="$(nw)_switch_state_$(l)",
            lower_bound = 0,
            upper_bound = 1,
            start = PMD.comp_start_value(PMD.ref(pm, nw, :switch, l), "state_start", get(PMD.ref(pm, nw, :switch, l), "state", 0))
        ) for l in PMD.ids(pm, nw, :switch_dispatchable))
    else
        state = PMD.var(pm, nw)[:switch_state] = Dict{Int,Any}(l => PMD.JuMP.@variable(
            pm.model,
            base_name="$(nw)_switch_state_$(l)",
            binary = true,
            start = PMD.comp_start_value(PMD.ref(pm, nw, :switch, l), "state_start", get(PMD.ref(pm, nw, :switch, l), "state", 0))
        ) for l in PMD.ids(pm, nw, :switch_dispatchable))
    end

    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :switch, :state, PMD.ids(pm, nw, :switch_dispatchable), state)
end


"do nothing, already have z_block"
function PowerModelsDistribution.variable_mc_storage_indicator(pm::PMD.LPUBFDiagModel; nw::Int=PMD.nw_id_default, relax::Bool=false, report::Bool=true)
end


"""
The variable creation for the loads is rather complicated because Expressions
are used wherever possible instead of explicit variables.
Delta loads always need a current variable and auxilary power variable (X), and
all other load model variables are then linear transformations of these
(linear Expressions).
Wye loads however, don't need any variables when the load is modelled as
constant power or constant impedance. In all other cases (e.g. when a cone is
used to constrain the power), variables need to be created.
"""
function variable_mc_load_power_on_off(pm::PMD.LPUBFDiagModel; nw=PMD.nw_id_default)
    load_wye_ids = [id for (id, load) in PMD.ref(pm, nw, :load) if load["configuration"]==PMD.WYE]
    load_del_ids = [id for (id, load) in PMD.ref(pm, nw, :load) if load["configuration"]==PMD.DELTA]
    load_cone_ids = [id for (id, load) in PMD.ref(pm, nw, :load) if PMD._check_load_needs_cone(load)]
    # create dictionaries
    PMD.var(pm, nw)[:pd_bus] = Dict()
    PMD.var(pm, nw)[:qd_bus] = Dict()
    PMD.var(pm, nw)[:pd] = Dict()
    PMD.var(pm, nw)[:qd] = Dict()
    # now, create auxilary power variable X for delta loads
    PMD.variable_mc_load_power_delta_aux(pm, load_del_ids; nw=nw)
    # only delta loads need a current variable
    PMD.variable_mc_load_current(pm, load_del_ids; nw=nw)
    # for wye loads with a cone inclusion constraint, we need to create a variable
    variable_mc_load_power_on_off(pm, intersect(load_wye_ids, load_cone_ids); nw=nw)
end


"""
These variables reflect the power consumed by the load, NOT the power injected
into the bus nodes; these variables only coincide for wye-connected loads
with a grounded neutral.
"""
function variable_mc_load_power_on_off(pm::PMD.LPUBFDiagModel, load_ids::Vector{Int}; nw::Int=PMD.nw_id_default, bounded::Bool=true, report::Bool=true)
    @assert(bounded)
    # calculate bounds for all loads
    pmin = Dict()
    pmax = Dict()
    qmin = Dict()
    qmax = Dict()
    for id in load_ids
        load = PMD.ref(pm, nw, :load, id)
        bus = PMD.ref(pm, nw, :bus, load["load_bus"])
        pmin[id], pmax[id], qmin[id], qmax[id] = PMD._calc_load_pq_bounds(load, bus)
    end

    # create variables
    connections = Dict(i => load["connections"] for (i,load) in PMD.ref(pm, nw, :load))

    pd = Dict(i => JuMP.@variable(pm.model,
        [c in connections[i]], base_name="$(nw)_pd_$(i)"
        ) for i in load_ids
    )
    qd = Dict(i => JuMP.@variable(pm.model,
        [c in connections[i]], base_name="$(nw)_qd_$(i)"
        ) for i in load_ids
    )

    if bounded
        for i in load_ids
            load = PMD.ref(pm, nw, :load, i)
            bus = PMD.ref(pm, nw, :bus, load["load_bus"])
            pmin, pmax, qmin, qmax = PMD._calc_load_pq_bounds(load, bus)
            for (idx,c) in enumerate(connections[i])
                PMD.set_lower_bound(pd[i][c], min(pmin[idx], 0.0))
                PMD.set_upper_bound(pd[i][c], max(pmax[idx], 0.0))
                PMD.set_lower_bound(qd[i][c], min(qmin[idx], 0.0))
                PMD.set_upper_bound(qd[i][c], max(qmax[idx], 0.0))
            end
        end
    end

    #store in dict, but do not overwrite
    for i in load_ids
        PMD.var(pm, nw)[:pd][i] = pd[i]
        PMD.var(pm, nw)[:qd][i] = qd[i]
    end

    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load, :pd, load_ids, pd)
    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load, :qd, load_ids, qd)
end
