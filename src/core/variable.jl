"""
    variable_mc_block_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)

create variables for block status by load block
"""
function variable_mc_block_indicator(pm::AbstractSwitchModels; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    if relax
        z_block = var(pm, nw)[:z_block] = JuMP.@variable(pm.model,
            [i in ids(pm, nw, :blocks)], base_name="$(nw)_z_block",
            lower_bound = 0,
            upper_bound = 1,
            start = 1
        )
    else
        z_block = var(pm, nw)[:z_block] = JuMP.@variable(pm.model,
            [i in ids(pm, nw, :blocks)], base_name="$(nw)_z_block",
            lower_bound = 0,
            upper_bound = 1,
            binary = true,
            start = 1
        )
    end

    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :bus,     :status, ids(pm, nw, :bus),     Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, i))     for i in ids(pm, nw, :bus)))
    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load,    :status, ids(pm, nw, :load),    Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :load_block_map, i))    for i in ids(pm, nw, :load)))
    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :shunt,   :status, ids(pm, nw, :shunt),   Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :shunt_block_map, i))   for i in ids(pm, nw, :shunt)))
    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :gen,     :status, ids(pm, nw, :gen),     Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :gen_block_map, i))     for i in ids(pm, nw, :gen)))
    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :storage, :status, ids(pm, nw, :storage), Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i)) for i in ids(pm, nw, :storage)))
end


"""
    variable_mc_switch_fixed(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, report::Bool=false)

Fixed switches set to constant values for multinetwork formulation (we need all switches)
"""
function variable_mc_switch_fixed(pm::AbstractSwitchModels; nw::Int=nw_id_default, report::Bool=false)
    dispatchable_switches = collect(ids(pm, nw, :switch_dispatchable))
    fixed_switches = [i for i in ids(pm, nw, :switch) if i ∉ dispatchable_switches]

    for i in fixed_switches
        var(pm, nw, :switch_state)[i] = ref(pm, nw, :switch, i, "state")
    end

    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :switch, :status, fixed_switches, Dict{Int,Any}(i => var(pm, nw, :switch_state, i) for i in fixed_switches))
end


"switch state (open/close) variables"
function variable_mc_switch_state(pm::AbstractSwitchModels; nw::Int=nw_id_default, report::Bool=true, relax::Bool=false)
    if relax
        state = var(pm, nw)[:switch_state] = Dict{Int,Any}(l => JuMP.@variable(
            pm.model,
            base_name="$(nw)_switch_state_$(l)",
            lower_bound = 0,
            upper_bound = 1,
            start = PMD.comp_start_value(ref(pm, nw, :switch, l), "state_start", get(ref(pm, nw, :switch, l), "state", 0))
        ) for l in ids(pm, nw, :switch_dispatchable))
    else
        state = var(pm, nw)[:switch_state] = Dict{Int,Any}(l => JuMP.@variable(
            pm.model,
            base_name="$(nw)_switch_state_$(l)",
            lower_bound = 0,
            upper_bound = 1,
            binary = true,
            start = PMD.comp_start_value(ref(pm, nw, :switch, l), "state_start", get(ref(pm, nw, :switch, l), "state", 0))
        ) for l in ids(pm, nw, :switch_dispatchable))
    end

    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :switch, :state, ids(pm, nw, :switch_dispatchable), state)
end


"do nothing, already have z_block"
function PowerModelsDistribution.variable_mc_storage_indicator(pm::AbstractSwitchModels; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
end
