@doc raw"""
    objective_mc_min_load_setpoint_delta_switch_iterative(pm::AbstractUnbalancedPowerModel)

    minimum load delta objective with switch scores for iterative algorithm

```math
\begin{align}
\mbox{minimize: } & \nonumber \\
& \sum_{\substack{i\in N,c\in C}}{10 \left (1-z^v_i \right )} + \nonumber \\
& \sum_{\substack{i\in L,c\in C}}{10 \omega_{i,c}\left |\Re{\left (S^d_i\right )}\right |\left ( 1-z^d_i \right ) } + \nonumber \\
& \sum_{\substack{i\in S}}{\Delta^{sw}_i}
\end{align}
```
"""
function objective_mc_min_load_setpoint_delta_switch_iterative(pm::AbstractSwitchModels)
    nw_id_list = sort(collect(nw_ids(pm)))

    for (i, n) in enumerate(nw_id_list)
        nw_ref = ref(pm, n)

        var(pm, n)[:delta_sw_state] = JuMP.@variable(
            pm.model,
            [i in ids(pm, n, :switch_dispatchable)],
            base_name="$(n)_$(i)_delta_sw_state",
            start = 0
        )

        for (s,switch) in nw_ref[:switch_dispatchable]
            z_switch = var(pm, n, :switch_state, s)
            if i == 1
                JuMP.@constraint(pm.model, var(pm, n, :delta_sw_state, s) >=  (JuMP.start_value(z_switch) - z_switch))
                JuMP.@constraint(pm.model, var(pm, n, :delta_sw_state, s) >= -(JuMP.start_value(z_switch) - z_switch))
            else  # multinetwork
                z_switch_prev = var(pm, nw_id_list[i-1], :switch_state, s)
                JuMP.@constraint(pm.model, var(pm, n, :delta_sw_state, s) >=  (z_switch_prev - z_switch))
                JuMP.@constraint(pm.model, var(pm, n, :delta_sw_state, s) >= -(z_switch_prev - z_switch))
            end
        end
    end

    JuMP.@objective(pm.model, Min,
        sum(
            sum( ref(pm, n, :block_weights, i) * (1-var(pm, n, :z_block, i)) for (i,block) in nw_ref[:blocks]) +
            sum( 1e-3 * ref(pm, n, :switch_scores, l)*(1-var(pm, n, :switch_state, l)) for l in ids(pm, n, :switch_dispatchable) ) +
            sum( 1e-2 * sum(var(pm, n, :delta_sw_state, l)) for l in ids(pm, n, :switch_dispatchable)) +
            sum( strg["energy_rating"] - var(pm, n, :se, i) for (i,strg) in nw_ref[:storage]) +
            sum( sum(get(gen,  "cost", [  1.0, 0.0])[2] * var(pm, n, :pg, i)[c] + get(gen,  "cost", [  1.0, 0.0])[1] for c in gen["connections"]) for (i,gen) in nw_ref[:gen])
        for (n, nw_ref) in nws(pm))
    )
end


@doc raw"""
    objective_mc_min_load_setpoint_delta_switch_global(pm::AbstractUnbalancedPowerModel)

minimum load delta objective without switch scores for global algorithm

```math
\begin{align}
\mbox{minimize: } & \nonumber \\
& \sum_{\substack{i\in N,c\in C}}{10 \left (1-z^v_i \right )} + \nonumber \\
& \sum_{\substack{i\in S}}{\Delta^{sw}_i}
\end{align}
```
"""
function objective_mc_min_load_setpoint_delta_switch_global(pm::AbstractSwitchModels)
    nw_id_list = sort(collect(nw_ids(pm)))

    for (i, n) in enumerate(nw_id_list)
        nw_ref = ref(pm, n)

        var(pm, n)[:delta_sw_state] = JuMP.@variable(
            pm.model,
            [i in ids(pm, n, :switch_dispatchable)],
            base_name="$(n)_$(i)_delta_sw_state",
            start = 0
        )

        for (s,switch) in nw_ref[:switch_dispatchable]
            z_switch = var(pm, n, :switch_state, s)
            if i == 1
                JuMP.@constraint(pm.model, var(pm, n, :delta_sw_state, s) >=  (JuMP.start_value(z_switch) - z_switch))
                JuMP.@constraint(pm.model, var(pm, n, :delta_sw_state, s) >= -(JuMP.start_value(z_switch) - z_switch))
            else  # multinetwork
                z_switch_prev = var(pm, nw_id_list[i-1], :switch_state, s)
                JuMP.@constraint(pm.model, var(pm, n, :delta_sw_state, s) >=  (z_switch_prev - z_switch))
                JuMP.@constraint(pm.model, var(pm, n, :delta_sw_state, s) >= -(z_switch_prev - z_switch))
            end
        end
    end

    JuMP.@objective(pm.model, Min,
        sum(
            sum( ref(pm, n, :block_weights, i) * (1-var(pm, n, :z_block, i)) for (i,block) in nw_ref[:blocks]) +
            sum( 1e-1 * Int(get(ref(pm, n), :apply_switch_scores, false)) * ref(pm, n, :switch_scores, l)*(1-var(pm, n, :switch_state, l)) for l in ids(pm, n, :switch_dispatchable) ) +
            sum( Int(get(ref(pm, n), :disable_switch_penalty, false)) * sum(var(pm, n, :delta_sw_state, l)) for l in ids(pm, n, :switch_dispatchable)) +
            sum( strg["energy_rating"] - var(pm, n, :se, i) for (i,strg) in nw_ref[:storage]) +
            sum( sum(get(gen,  "cost", [1.0, 0.0])[2] * var(pm, n, :pg, i)[c] + get(gen,  "cost", [1.0, 0.0])[1] for c in  gen["connections"]) for (i,gen) in nw_ref[:gen])
        for (n, nw_ref) in nws(pm))
    )
end


"""
    objective_mc_min_storage_utilization(pm::AbstractUnbalancedPowerModel)

Minimizes the amount of storage that gets utilized in favor of using all available generation first
"""
function objective_mc_min_storage_utilization(pm::AbstractUnbalancedPowerModel)
    JuMP.@objective(pm.model, Min,
        sum(
            sum( strg["energy_rating"] - var(pm, n, :se, i) for (i,strg) in nw_ref[:storage])
        for (n, nw_ref) in nws(pm))
    )
end
