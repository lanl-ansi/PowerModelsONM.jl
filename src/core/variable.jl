"""
    variable_mc_load_block_indicator(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default, relax::Bool=false, report::Bool=true)

create variables for demand status by load block
"""
function variable_mc_load_block_indicator(pm::PMD.AbstractUnbalancedPowerModel; nw::Int=PMD.nw_id_default, relax::Bool=false, report::Bool=true)
    if relax
        z_demand = PMD.var(pm, nw)[:z_demand_blocks] = PMD.JuMP.@variable(pm.model,
            [i in PMD.ids(pm, nw, :load_blocks)], base_name="$(nw)_z_demand",
            lower_bound = 0,
            upper_bound = 1,
            start = 1.0
        )
    else
        z_demand = PMD.var(pm, nw)[:z_demand_blocks] = PMD.JuMP.@variable(pm.model,
            [i in PMD.ids(pm, nw, :load_blocks)], base_name="$(nw)_z_demand",
            binary = true,
            start = 1
        )
    end

    is_cold = are_blocks_warm(pm.data, values(PMD.ref(pm, nw, :load_blocks)))
    clpu_factors = Dict(l => get(load, "clpu_factor", 2.0) for (l,load) in PMD.ref(pm, nw, :load))
    load_block_map = PMD.ref(pm, nw, :load_block_map)

    PMD.var(pm, nw)[:z_demand] = Dict(l => z_demand[load_block_map[l]] for l in PMD.ids(pm, nw, :load))

    # expressions for pd and qd
    pd = PMD.var(pm, nw)[:pd] = Dict(i => PMD.var(pm, nw)[:z_demand][i].*PMD.ref(pm, nw, :load, i)["pd"] for i in PMD.ids(pm, nw, :load))
    qd = PMD.var(pm, nw)[:qd] = Dict(i => PMD.var(pm, nw)[:z_demand][i].*PMD.ref(pm, nw, :load, i)["qd"] for i in PMD.ids(pm, nw, :load))

    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load, :status, PMD.ids(pm, nw, :load), PMD.var(pm, nw)[:z_demand])
    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load, :pd, PMD.ids(pm, nw, :load), pd)
    report && PMD._IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load, :qd, PMD.ids(pm, nw, :load), qd)
end
