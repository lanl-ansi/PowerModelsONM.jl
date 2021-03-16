"max actions per timestep switch constraint"
function constraint_switch_state_max_actions(pm::PMD._PM.AbstractPowerModel, nw::Int)
    max_switch_changes = get(pm.data, "max_switch_changes", length(get(pm.data, "switch", Dict())))

    state_start = Dict(
        l => PMD.ref(pm, nw, :switch, l, "state") for l in PMD.ids(pm, nw, :switch)
    )

    PMD.JuMP.@constraint(pm.model, sum((state_start[l] - PMD.var(pm, nw, :switch_state, l)) * (round(state_start[l]) == 0 ? -1 : 1) for l in PMD.ids(pm, nw, :switch_dispatchable)) <= max_switch_changes)
end


""
function constraint_load_block_isolation(pm::PMD._PM.AbstractPowerModel, nw::Int)
    for (b, block) in PMD.ref(pm, nw, :load_blocks)
        for s in PMD.ref(pm, nw, :load_block_switches, b)
            if s in PMD.ids(pm, nw, :switch_dispatchable) && !is_block_warm(pm.data, block)
                PMD.JuMP.@constraint(pm.model, !PMD.var(pm, nw, :z_demand_blocks, b) => {PMD.var(pm, nw, :switch_state, s) == 0})
            end
        end
    end
end
