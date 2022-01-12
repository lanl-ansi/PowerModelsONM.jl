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
    constraint_block_isolation(pm::AbstractSwitchModels, nw::Int; relax::Bool=false)

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

    # quick determination of blocks to shed:
    # if no generation resources (gen, storage, or negative loads (e.g., rooftop pv models))
    # and no switches connected to the block are closed, then the island must be shed,
    # otherwise, to shed or not will be determined by feasibility
    for b in ids(pm, nw, :blocks)
        z_block = var(pm, nw, :z_block, b)

        n_gen = length(ref(pm, nw, :block_gens))
        n_strg = length(ref(pm, nw, :block_storages))
        n_neg_loads = length([_b for (_b,ls) in ref(pm, nw, :block_loads) if any(any(ref(pm, nw, :load, l, "pd") .< 0) for l in ls)])

        JuMP.@constraint(pm.model, z_block <= n_gen + n_strg + n_neg_loads + sum(var(pm, nw, :switch_state, s) for s in ids(pm, nw, :block_switches) if s in ids(pm, nw, :switch_dispatchable)))
    end
end


"""
    constraint_radial_topology(pm::AbstractUnbalancedPowerModel, nw::Int; relax::Bool=false)

Constraint to enforce a radial topology
# doi: 10.1109/TSG.2020.2985087
"""
function constraint_radial_topology(pm::AbstractSwitchModels, nw::Int; relax::Bool=false)
    # doi: 10.1109/TSG.2020.2985087
    var(pm, nw)[:f] = Dict{Tuple{Int,Int,Int},JuMP.VariableRef}()
    var(pm, nw)[:lambda] = Dict{Tuple{Int,Int},JuMP.VariableRef}()
    var(pm, nw)[:beta] = Dict{Tuple{Int,Int},JuMP.VariableRef}()
    var(pm, nw)[:alpha] = Dict{Tuple{Int,Int},Union{JuMP.VariableRef,Int}}()

    N = ids(pm, nw, :blocks)
    L = ref(pm, nw, :block_pairs)

    ir = ref(pm, nw, :substation_blocks)

    for (i,j) in L
        for k in filter(k->k∉ir,N)
            var(pm, nw, :f)[(k, i, j)] = JuMP.@variable(pm.model, base_name="$(nw)_f_$((k,i,j))")
            var(pm, nw, :f)[(k, j, i)] = JuMP.@variable(pm.model, base_name="$(nw)_f_$((k,j,i))")
        end
        var(pm, nw, :lambda)[(i,j)] = relax ? JuMP.@variable(pm.model, base_name="$(nw)_lambda_$((i,j))", lower_bound=0, upper_bound=1) : JuMP.@variable(pm.model, base_name="$(nw)_lambda_$((i,j))", binary=true)
        var(pm, nw, :lambda)[(j,i)] = relax ? JuMP.@variable(pm.model, base_name="$(nw)_lambda_$((j,i))", lower_bound=0, upper_bound=1) : JuMP.@variable(pm.model, base_name="$(nw)_lambda_$((j,i))", binary=true)
        var(pm, nw, :beta)[(i,j)] = relax ? JuMP.@variable(pm.model, base_name="$(nw)_beta_$((i,j))", lower_bound=0, upper_bound=1) : JuMP.@variable(pm.model, base_name="$(nw)_beta_$((i,j))", binary=true)
    end

    for (s,sw) in get(PMD.ismultinetwork(pm.data) ? pm.data["nw"]["$(nw)"] : pm.data, "switch", Dict())
        (i,j) = (ref(pm, nw, :bus_block_map, sw["f_bus"]), ref(pm, nw, :bus_block_map, sw["t_bus"]))

        if sw[PMD.pmd_math_component_status["switch"]] != PMD.pmd_math_component_status_inactive["switch"]
            var(pm, nw, :alpha)[(i,j)] = var(pm, nw, :alpha)[(j,i)] = var(pm, nw, :switch_state, parse(Int,s))
        else
            var(pm, nw, :alpha)[(i,j)] = var(pm, nw, :alpha)[(j,i)] = 0
        end
    end

    f = var(pm, nw, :f)
    λ = var(pm, nw, :lambda)
    β = var(pm, nw, :beta)
    α = var(pm, nw, :alpha)

    # Eq. (1) -> Eqs. (3-8)
    for k in filter(kk->kk∉ir,N)
        # Eq. (3)
        bp_to = filter(((j,i),)->i∈ir&&i!=j,L)
        bp_fr = filter(((i,j),)->i∈ir&&i!=j,L)
        if !(isempty(bp_fr) && isempty(bp_to))
            c = JuMP.@constraint(
                pm.model,
                sum(f[(k,j,i)] for (j,i) in bp_to) -
                sum(f[(k,i,j)] for (i,j) in bp_fr)
                ==
                -1.0
            )
        end

        # Eq. (4)
        bp_to = filter(((j,i),)->i==k&&i!=j,L)
        bp_fr = filter(((i,j),)->i==k&&i!=j,L)
        if !(isempty(bp_fr) && isempty(bp_to))
            c = JuMP.@constraint(
                pm.model,
                sum(f[(k,j,k)] for (j,i) in bp_to) -
                sum(f[(k,k,j)] for (i,j) in bp_fr)
                ==
                1.0
            )
        end

        # Eq. (5)
        for i in filter(kk->kk∉ir&&kk!=k,N)
            bp_to = filter(((j,ii),)->ii==i&&ii!=j,L)
            bp_fr = filter(((ii,j),)->ii==i&&ii!=j,L)
            if !(isempty(bp_fr) && isempty(bp_to))
                c = JuMP.@constraint(
                    pm.model,
                    sum(f[(k,j,i)] for (j,ii) in bp_to) -
                    sum(f[(k,i,j)] for (ii,j) in bp_fr)
                    ==
                    0.0
                )
            end
        end

        # Eq. (6)
        for (i,j) in L
            JuMP.@constraint(pm.model, f[(k,i,j)] >= 0)
            JuMP.@constraint(pm.model, f[(k,i,j)] <= λ[(i,j)])
            JuMP.@constraint(pm.model, f[(k,j,i)] >= 0)
            JuMP.@constraint(pm.model, f[(k,j,i)] <= λ[(j,i)])
        end
    end

    # Eq. (7)
    JuMP.@constraint(pm.model, sum((λ[(i,j)] + λ[(j,i)]) for (i,j) in L) == length(N) - 1)

    for (i,j) in L
        # Eq. (8)
        JuMP.@constraint(pm.model, λ[(i,j)] + λ[(j,i)] == β[(i,j)])

        # Eq. (2)
        JuMP.@constraint(pm.model, α[(i,j)] <= β[(i,j)])
    end
end
