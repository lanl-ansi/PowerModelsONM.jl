@doc raw"""
    constraint_switch_state_max_actions(pm::AbstractUnbalancedPowerModel, nw::Int)

max actions per timestep switch constraint

```math
\sum_{\substack{i\in S}}{\Delta^{sw}_i} \leq z^{swu}
```
"""
function constraint_switch_state_max_actions(pm::AbstractSwitchModels, nw::Int)
    max_switch_actions = ref(pm, nw, :max_switch_actions)

    delta_switch_states = Dict(l => JuMP.@variable(pm.model, base_name="$(nw)_delta_sw_state_$(l)", start=0) for l in ids(pm, nw, :switch_dispatchable))
    for (l, dsw) in delta_switch_states
        state = var(pm, nw, :switch_state, l)
        JuMP.@constraint(pm.model, dsw >=  state * (1 - JuMP.start_value(state)))
        JuMP.@constraint(pm.model, dsw >= -state * (1 - JuMP.start_value(state)))
    end

    if max_switch_actions < Inf
        JuMP.@constraint(pm.model, sum(dsw for (l, dsw) in delta_switch_states) <= max_switch_actions)
    end
end


@doc raw"""
    constraint_switch_state_max_actions(pm::AbstractUnbalancedPowerModel, nw_1::Int, nw_2::Int)

max actions per timestep switch constraint for multinetwork formulations

```math
\sum_{\substack{i\in S}}{\Delta^{sw}_i} \leq z^{swu}
```
"""
function constraint_switch_state_max_actions(pm::AbstractSwitchModels, nw_1::Int, nw_2::Int)
    max_switch_actions = ref(pm, nw_2, :max_switch_actions)

    delta_switch_states = Dict(l => JuMP.@variable(pm.model, base_name="$(nw_2)_delta_sw_state_$(l)", start=0) for l in ids(pm, nw_2, :switch_dispatchable))
    for (l, dsw) in delta_switch_states
        nw_1_state = var(pm, nw_1, :switch_state, l)
        nw_2_state = var(pm, nw_2, :switch_state, l)

        nw1_nw2_state = JuMP.@variable(pm.model, base_name="$(nw_1)_$(nw_2)_sw_state_$(l)")
        JuMP.@constraint(pm.model, nw1_nw2_state >= 0)
        JuMP.@constraint(pm.model, nw1_nw2_state >= nw_2_state + nw_1_state - 1)
        JuMP.@constraint(pm.model, nw1_nw2_state <= nw_2_state)
        JuMP.@constraint(pm.model, nw1_nw2_state <= nw_1_state)

        JuMP.@constraint(pm.model, dsw >=  nw_2_state - nw1_nw2_state)
        JuMP.@constraint(pm.model, dsw >= -nw_2_state + nw1_nw2_state)
    end

    if max_switch_actions < Inf
        JuMP.@constraint(pm.model, sum(dsw for (l, dsw) in delta_switch_states) <= max_switch_actions)
    end
end


@doc raw"""
    constraint_block_isolation(pm::PMD.LPUBFDiagModel, nw::Int; relax::Bool=false)

constraint to ensure that blocks get properly isolated by open switches by comparing the states of
two neighboring blocks. If the neighboring block indicators are not either both 0 or both 1, the switch
between them should be OPEN (0)

```math
\begin{align}
& (z^{bl}_{fr}_{i} - z^{bl}_{to}_{i}) \leq  z^{sw}_{i}\ \forall i in S \\
& (z^{bl}_{fr}_{i} - z^{bl}_{fr}_{i}) \geq -z^{sw}_{i}\ \forall i in S
\end{align}

where $$z^{bl}_{fr}_{i}$$ and $$z^{bl}_{to}_{i}$$ are the indicator variables for the blocks on
either side of switch $$i$$.
```
"""
function constraint_block_isolation(pm::AbstractSwitchModels, nw::Int; relax::Bool=false)
    # if switch is closed, both blocks need to be the same status (on or off)
    for (s, switch) in ref(pm, nw, :switch_dispatchable)
        z_block_fr = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, switch["f_bus"]))
        z_block_to = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, switch["t_bus"]))

        z_switch = var(pm, nw, :switch_state, s)
        if relax
            JuMP.@constraint(pm.model,  (z_block_fr - z_block_to) <=  (1-z_switch))
            JuMP.@constraint(pm.model,  (z_block_fr - z_block_to) >= -(1-z_switch))
        else # "indicator" constraint
            JuMP.@constraint(pm.model, z_switch => {z_block_fr == z_block_to})
        end
    end

    for b in PMD.ids(pm, nw, :blocks)
        z_block = PMD.var(pm, nw, :z_block, b)
        n_gen = length(PMD.ref(pm, nw, :block_gens)) + length(PMD.ref(pm, nw, :block_storages))

        PMD.JuMP.@constraint(pm.model, z_block <= n_gen + sum(PMD.var(pm, nw, :switch_state, s) for s in PMD.ids(pm, nw, :block_switches) if s in PMD.ids(pm, nw, :switch_dispatchable)))
    end
end
