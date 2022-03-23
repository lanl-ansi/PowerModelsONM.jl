@doc raw"""
    objective_min_shed_load_block_rolling_horizon(pm::AbstractUnbalancedPowerModel)

Minimum block load shed objective for rolling horizon problem. Note that the difference between this and
[`objective_min_shed_load_block`](@ref objective_min_shed_load_block) is that the sum over the switches
in line 2 of the objective is non-optional.

```math
\begin{align*}
\mbox{minimize: } & \\
& \sum_{\substack{b \in B,t \in T}} W^{bl}_{b,t} \left(1 - z^{bl}_{b,t} \right) \\
& + \sum_{\substack{s \in S,t \in T}} \left[ W^{sw}_{s,t} \left(1 - \gamma_{s,t} \right )) +  W^{\Delta^{\gamma}}_{s,t}\Delta^{\gamma}_{s,t}\right ]\\
& + \sum_{\substack{e \in E,t \in T}} \epsilon^{ub}_{e} - \epsilon_{e,t} \\
& + \sum_{\substack{g \in G,t \in T}} f_1 P_{g,t} + f_0
\end{align*}```
"""
function objective_min_shed_load_block_rolling_horizon(pm::AbstractUnbalancedPowerModel)
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

    total_energy_ub = sum(strg["energy_rating"] for (n,nw_ref) in nws(pm) for (i,strg) in nw_ref[:storage])
    total_pmax = sum(Float64[all(.!isfinite.(gen["pmax"])) ? 0.0 : sum(gen["pmax"][isfinite.(gen["pmax"])]) for (n,nw_ref) in nws(pm) for (i, gen) in nw_ref[:gen]])

    total_energy_ub = total_energy_ub <= 1.0 ? 1.0 : total_energy_ub
    total_pmax = total_pmax <= 1.0 ? 1.0 : total_pmax

    n_dispatchable_switches = Dict(n => length(ids(pm, n, :switch_dispatchable)) for n in nw_ids(pm))
    for (n,nswitch) in n_dispatchable_switches
        if nswitch < 1
            n_dispatchable_switches[n] = 1
        end
    end

    JuMP.@objective(pm.model, Min,
        sum(
            sum( ref(pm, n, :block_weights, i) * (1-var(pm, n, :z_block, i)) for (i,block) in nw_ref[:blocks])
            + sum( ref(pm, n, :switch_scores, l)*(1-var(pm, n, :switch_state, l)) for l in ids(pm, n, :switch_dispatchable) )
            + sum( Int(get(ref(pm, n), :disable_switch_penalty, false)) * sum(var(pm, n, :delta_sw_state, l)) for l in ids(pm, n, :switch_dispatchable)) / n_dispatchable_switches[n]
            + sum( strg["energy_rating"] - var(pm, n, :se, i) for (i,strg) in nw_ref[:storage]) / total_energy_ub
            + sum( sum(get(gen,  "cost", [0.0, 0.0])[2] * var(pm, n, :pg, i)[c] + get(gen,  "cost", [0.0, 0.0])[1] for c in  gen["connections"]) for (i,gen) in nw_ref[:gen]) / total_energy_ub
        for (n, nw_ref) in nws(pm))
    )
end


@doc raw"""
    objective_min_shed_load_traditional_rolling_horizon(pm::AbstractUnbalancedPowerModel)

Minimum block load shed objective for rolling horizon problem. Note that the difference between this and
[`objective_min_shed_load_traditional`](@ref objective_min_shed_load_traditional) is that the sum over the switches
in line 2 of the objective is non-optional.

```math
\begin{align*}
\mbox{minimize: } & \\
& \sum_{\substack{l \in L,t \in T}} W^{d}_{l,t} \left(1 - z^{d}_{l,t} \right) \\
& + \sum_{\substack{s \in S,t \in T}} \left[ W^{sw}_{s,t} \left(1 - \gamma_{s,t} \right )) +  W^{\Delta^{\gamma}}_{s,t}\Delta^{\gamma}_{s,t}\right ]\\
& + \sum_{\substack{e \in E,t \in T}} \epsilon^{ub}_{e} - \epsilon_{e,t} \\
& + \sum_{\substack{g \in G,t \in T}} f_1 P_{g,t} + f_0
\end{align*}
```
"""
function objective_min_shed_load_traditional_rolling_horizon(pm::AbstractUnbalancedPowerModel)
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

    load_weights = Dict(
        n => Dict(
            l => ref(pm, n, :block_weights, b) / length(ref(pm, n, :block_loads, b)) for b in ids(pm, n, :blocks) for l in ref(pm, n, :block_loads, b)
        ) for n in nw_ids(pm)
    )

    total_energy_ub = sum(strg["energy_rating"] for (n,nw_ref) in nws(pm) for (i,strg) in nw_ref[:storage])
    total_pmax = sum(Float64[all(.!isfinite.(gen["pmax"])) ? 0.0 : sum(gen["pmax"][isfinite.(gen["pmax"])]) for (n,nw_ref) in nws(pm) for (i, gen) in nw_ref[:gen]])

    total_energy_ub = total_energy_ub <= 1.0 ? 1.0 : total_energy_ub
    total_pmax = total_pmax <= 1.0 ? 1.0 : total_pmax

    n_dispatchable_switches = Dict(n => length(ids(pm, n, :switch_dispatchable)) for n in nw_ids(pm))
    for (n,nswitch) in n_dispatchable_switches
        if nswitch < 1
            n_dispatchable_switches[n] = 1
        end
    end

    JuMP.@objective(pm.model, Min,
        sum(
            sum( load_weights[n][i] * (1-var(pm, n, :z_demand, i)) for i in ids(pm, n, :load))
            + sum( ref(pm, n, :switch_scores, l)*(1-var(pm, n, :switch_state, l)) for l in ids(pm, n, :switch_dispatchable) )
            + sum( Int(get(ref(pm, n), :disable_switch_penalty, false)) * sum(var(pm, n, :delta_sw_state, l)) for l in ids(pm, n, :switch_dispatchable)) / n_dispatchable_switches[n]
            + sum( strg["energy_rating"] - var(pm, n, :se, i) for (i,strg) in nw_ref[:storage]) / total_energy_ub
            + sum( sum(get(gen,  "cost", [0.0, 0.0])[2] * var(pm, n, :pg, i)[c] + get(gen,  "cost", [0.0, 0.0])[1] for c in  gen["connections"]) for (i,gen) in nw_ref[:gen]) / total_energy_ub
        for (n, nw_ref) in nws(pm))
    )
end


@doc raw"""
    objective_min_shed_load_block(pm::AbstractUnbalancedPowerModel)

Minimum block load shed objective for rolling horizon problem. Note that the difference between this and
[`objective_min_shed_load_block_rolling_horizon`](@ref objective_min_shed_load_block_rolling_horizon) is that the
sum over the switches in line 2 of the objective is optional, as determined by user inputs in the model, i.e.,
`apply_switch_scores` (default: false), and `disable_switch_penalty` (default: false).

```math
\begin{align*}
\mbox{minimize: } & \\
& \sum_{\substack{b \in B,t \in T}} W^{bl}_{b,t} \left(1 - z^{bl}_{b,t} \right) \\
& + \sum_{\substack{s \in S,t \in T}} \left[ W^{sw}_{s,t} \left(1 - \gamma_{s,t} \right )) +  W^{\Delta^{\gamma}}_{s,t}\Delta^{\gamma}_{s,t}\right ]\\
& + \sum_{\substack{e \in E,t \in T}} \epsilon^{ub}_{e} - \epsilon_{e,t} \\
& + \sum_{\substack{g \in G,t \in T}} f_1 P_{g,t} + f_0
\end{align*}```
"""
function objective_min_shed_load_block(pm::AbstractUnbalancedPowerModel)
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

    total_energy_ub = sum(strg["energy_rating"] for (n,nw_ref) in nws(pm) for (i,strg) in nw_ref[:storage])
    total_pmax = sum(Float64[all(.!isfinite.(gen["pmax"])) ? 0.0 : sum(gen["pmax"][isfinite.(gen["pmax"])]) for (n,nw_ref) in nws(pm) for (i, gen) in nw_ref[:gen]])

    total_energy_ub = total_energy_ub <= 1.0 ? 1.0 : total_energy_ub
    total_pmax = total_pmax <= 1.0 ? 1.0 : total_pmax

    n_dispatchable_switches = Dict(n => length(ids(pm, n, :switch_dispatchable)) for n in nw_ids(pm))
    for (n,nswitch) in n_dispatchable_switches
        if nswitch < 1
            n_dispatchable_switches[n] = 1
        end
    end

    JuMP.@objective(pm.model, Min,
        sum(
            sum( ref(pm, n, :block_weights, i) * (1-var(pm, n, :z_block, i)) for (i,block) in nw_ref[:blocks])
            + sum( Int(get(ref(pm, n), :apply_switch_scores, false)) * ref(pm, n, :switch_scores, l)*(1-var(pm, n, :switch_state, l)) for l in ids(pm, n, :switch_dispatchable) )
            + sum( Int(get(ref(pm, n), :disable_switch_penalty, false)) * sum(var(pm, n, :delta_sw_state, l)) for l in ids(pm, n, :switch_dispatchable)) / n_dispatchable_switches[n]
            + sum( strg["energy_rating"] - var(pm, n, :se, i) for (i,strg) in nw_ref[:storage]) / total_energy_ub
            + sum( sum(get(gen,  "cost", [0.0, 0.0])[2] * var(pm, n, :pg, i)[c] + get(gen,  "cost", [0.0, 0.0])[1] for c in  gen["connections"]) for (i,gen) in nw_ref[:gen]) / total_energy_ub
        for (n, nw_ref) in nws(pm))
    )
end


@doc raw"""
    objective_min_shed_load_traditional(pm::AbstractUnbalancedPowerModel)

Minimum block load shed objective for rolling horizon problem. Note that the difference between this and
[`objective_min_shed_load_traditional_rolling_horizon`](@ref objective_min_shed_load_traditional_rolling_horizon) is that the
sum over the switches in line 2 of the objective is optional, as determined by user inputs in the model, i.e.,
`apply_switch_scores` (default: false), and `disable_switch_penalty` (default: false).

```math
\begin{align*}
\mbox{minimize: } & \\
& \sum_{\substack{l \in L,t \in T}} W^{d}_{l,t} \left(1 - z^{d}_{l,t} \right) \\
& + \sum_{\substack{s \in S,t \in T}} \left[ W^{sw}_{s,t} \left(1 - \gamma_{s,t} \right )) +  W^{\Delta^{\gamma}}_{s,t}\Delta^{\gamma}_{s,t}\right ]\\
& + \sum_{\substack{e \in E,t \in T}} \epsilon^{ub}_{e} - \epsilon_{e,t} \\
& + \sum_{\substack{g \in G,t \in T}} f_1 P_{g,t} + f_0
\end{align*}
```
"""
function objective_min_shed_load_traditional(pm::AbstractUnbalancedPowerModel)
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

    load_weights = Dict(
        n => Dict(
            l => ref(pm, n, :block_weights, b) / length(ref(pm, n, :block_loads, b)) for b in ids(pm, n, :blocks) for l in ref(pm, n, :block_loads, b)
        ) for n in nw_ids(pm)
    )

    total_energy_ub = sum(strg["energy_rating"] for (n,nw_ref) in nws(pm) for (i,strg) in nw_ref[:storage])
    total_pmax = sum(Float64[all(.!isfinite.(gen["pmax"])) ? 0.0 : sum(gen["pmax"][isfinite.(gen["pmax"])]) for (n,nw_ref) in nws(pm) for (i, gen) in nw_ref[:gen]])

    total_energy_ub = total_energy_ub <= 1.0 ? 1.0 : total_energy_ub
    total_pmax = total_pmax <= 1.0 ? 1.0 : total_pmax

    n_dispatchable_switches = Dict(n => length(ids(pm, n, :switch_dispatchable)) for n in nw_ids(pm))
    for (n,nswitch) in n_dispatchable_switches
        if nswitch < 1
            n_dispatchable_switches[n] = 1
        end
    end

    JuMP.@objective(pm.model, Min,
        sum(
            sum( load_weights[n][i] * (1-var(pm, n, :z_demand, i)) for i in ids(pm, n, :load))
            + sum( Int(get(ref(pm, n), :apply_switch_scores, false)) * ref(pm, n, :switch_scores, l)*(1-var(pm, n, :switch_state, l)) for l in ids(pm, n, :switch_dispatchable) )
            + sum( Int(get(ref(pm, n), :disable_switch_penalty, false)) * sum(var(pm, n, :delta_sw_state, l)) for l in ids(pm, n, :switch_dispatchable)) / n_dispatchable_switches[n]
            + sum( strg["energy_rating"] - var(pm, n, :se, i) for (i,strg) in nw_ref[:storage]) / total_energy_ub
            + sum( sum(get(gen,  "cost", [0.0, 0.0])[2] * var(pm, n, :pg, i)[c] + get(gen,  "cost", [0.0, 0.0])[1] for c in  gen["connections"]) for (i,gen) in nw_ref[:gen]) / total_energy_ub
        for (n, nw_ref) in nws(pm))
    )
end


@doc raw"""
    objective_mc_min_storage_utilization(pm::AbstractUnbalancedPowerModel)

Minimizes the amount of storage that gets utilized in favor of using all available generation first

```math
\begin{align*}
\mbox{minimize: } & \\
& \sum_{\substack{e \in E,t \in T}} \epsilon^{ub}_{e} - \epsilon_{e,t} \\
\end{align*}
```
"""
function objective_mc_min_storage_utilization(pm::AbstractUnbalancedPowerModel)
    JuMP.@objective(pm.model, Min,
        sum(
            sum( strg["energy_rating"] - var(pm, n, :se, i) for (i,strg) in nw_ref[:storage])
        for (n, nw_ref) in nws(pm))
    )
end
