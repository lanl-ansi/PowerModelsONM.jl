"Create variables for demand status"
function variable_mc_load_indicator(pm::PMD._PM.AbstractPowerModel; nw::Int=pm.cnw, relax::Bool=false, report::Bool=true)
    if relax
        z_demand = PMD.var(pm, nw)[:z_demand] = PMD.JuMP.@variable(pm.model,
            [i in PMD.ids(pm, nw, :load)], base_name="$(nw)_z_demand",
            lower_bound = 0,
            upper_bound = 1,
            start = PMD.comp_start_value(PMD.ref(pm, nw, :load, i), "z_demand_on_start", 1.0)
        )
    else
        z_demand = PMD.var(pm, nw)[:z_demand] = PMD.JuMP.@variable(pm.model,
            [i in PMD.ids(pm, nw, :load)], base_name="$(nw)_z_demand",
            binary = true,
            start = PMD.comp_start_value(PMD.ref(pm, nw, :load, i), "z_demand_on_start", 1.0)
        )
    end

    is_cold = identify_cold_loads(pm.data)
    clpu_factors = Dict(l => get(load, "clpu_factor", 2.0) for (l,load) in PMD.ref(pm, nw, :load))

    # expressions for pd and qd
    pd = PMD.var(pm, nw)[:pd] = Dict(i => PMD.var(pm, nw)[:z_demand][i].*PMD.ref(pm, nw, :load, i)["pd"]*(is_cold[i] ? clpu_factors[i] : 1.0) for i in PMD.ids(pm, nw, :load))
    qd = PMD.var(pm, nw)[:qd] = Dict(i => PMD.var(pm, nw)[:z_demand][i].*PMD.ref(pm, nw, :load, i)["qd"]*(is_cold[i] ? clpu_factors[i] : 1.0) for i in PMD.ids(pm, nw, :load))

    report && PMD._IM.sol_component_value(pm, nw, :load, :status, PMD.ids(pm, nw, :load), z_demand)
    report && PMD._IM.sol_component_value(pm, nw, :load, :pd, PMD.ids(pm, nw, :load), pd)
    report && PMD._IM.sol_component_value(pm, nw, :load, :qd, PMD.ids(pm, nw, :load), qd)
end
