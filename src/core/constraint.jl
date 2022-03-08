@doc raw"""
    constraint_switch_close_action_limit(pm::AbstractUnbalancedPowerModel, nw::Int)

Constraint for maximum allowed switch close actions in a single time step, as defined by `ref(pm, nw, :max_switch_actions)`

```math
\begin{align}
\Delta^{\gamma}_i,~\forall i \in S & \\
s.t. & \\
& \Delta^{\gamma}_i \geq \gamma \left( 1 - \gamma_0 \right) \\
& \Delta^{\gamma}_i \geq -\gamma \left( 1 - \gamma_0 \right) \\
& \sum_{\substack{i \in S}} \Delta^{\gamma}_i \leq N_{\gamma=1}^{ub}
\end{align}
```
"""
function constraint_switch_close_action_limit(pm::AbstractUnbalancedPowerModel, nw::Int)
    max_switch_actions = ref(pm, nw, :max_switch_actions)

    Δᵞs = Dict(l => JuMP.@variable(pm.model, base_name="$(nw)_delta_switch_state_$(l)", start=0) for l in ids(pm, nw, :switch_dispatchable))
    for (s, Δᵞ) in Δᵞs
        γ = var(pm, nw, :switch_state, s)
        γ₀ = JuMP.start_value(γ)
        JuMP.@constraint(pm.model, Δᵞ >=  γ * (1 - γ₀))
        JuMP.@constraint(pm.model, Δᵞ >= -γ * (1 - γ₀))
    end

    if max_switch_actions < Inf
        JuMP.@constraint(pm.model, sum(Δᵞ for (l, Δᵞ) in Δᵞs) <= max_switch_actions)
    end
end


@doc raw"""
    constraint_switch_close_action_limit(pm::AbstractUnbalancedPowerModel, nw_1::Int, nw_2::Int)

Constraint for maximum allowed switch close actions between time steps, as defined by `ref(pm, nw, :max_switch_actions)`

```math
\begin{align}
\Delta^{\gamma}_i, ~\forall i \in S & \\
\gamma^{t}_i, ~\forall i \in S, ~\forall t \in T  & \\
\gamma^{t_1,t_2}_i, ~\forall i \in S, ~\forall (t_1,t_2) \in T  & \\
s.t.  & \\
& \gamma^{t_1,t_2}_i \geq 0 \\
& \gamma^{t_1,t_2}_i \geq \gamma^{t_2}_i + \gamma^{t_1}_i - 1 \\
& \gamma^{t_1,t_2}_i \leq \gamma{t_1}_i \\
& \gamma^{t_1,t_2}_i \leq \gamma{t_2}_i \\
& \Delta^{\gamma}_i \geq \gamma^{t_2}+i - \gamma^{t_1,t_2}_i \\
& \Delta^{\gamma}_i \geq \gamma^{t_2}+i + \gamma^{t_1,t_2}_i \\
& \sum_{\substack{i \in S}} \Delta^{\gamma}_i \leq N_{\gamma=1}^{ub}
\end{align}
```
"""
function constraint_switch_close_action_limit(pm::AbstractUnbalancedPowerModel, nw_1::Int, nw_2::Int)
    max_switch_actions = ref(pm, nw_2, :max_switch_actions)

    Δᵞs = Dict(l => JuMP.@variable(pm.model, base_name="$(nw_2)_delta_switch_state_$(l)", start=0) for l in ids(pm, nw_2, :switch_dispatchable))
    for (l, Δᵞ) in Δᵞs
        γᵗ¹ = var(pm, nw_1, :switch_state, l)
        γᵗ² = var(pm, nw_2, :switch_state, l)

        γᵗ¹ᵗ² = JuMP.@variable(pm.model, base_name="$(nw_1)_$(nw_2)_delta_switch_state_$(l)")
        JuMP.@constraint(pm.model, γᵗ¹ᵗ² >= 0)
        JuMP.@constraint(pm.model, γᵗ¹ᵗ² >= γᵗ² + γᵗ¹ - 1)
        JuMP.@constraint(pm.model, γᵗ¹ᵗ² <= γᵗ²)
        JuMP.@constraint(pm.model, γᵗ¹ᵗ² <= γᵗ¹)

        JuMP.@constraint(pm.model, Δᵞ >=  γᵗ² - γᵗ¹ᵗ²)
        JuMP.@constraint(pm.model, Δᵞ >= -γᵗ² + γᵗ¹ᵗ²)
    end

    if max_switch_actions < Inf
        JuMP.@constraint(pm.model, sum(Δᵞ for (l, Δᵞ) in Δᵞs) <= max_switch_actions)
    end
end


@doc raw"""
    constraint_isolate_block(pm::AbstractUnbalancedPowerModel, nw::Int)

constraint to ensure that blocks get properly isolated by open switches by comparing the states of
two neighboring blocks. If the neighboring block indicators are not either both 0 or both 1, the switch
between them should be OPEN (0)

```math
\begin{align*}
& (z^{bl}_{fr} - z^{bl}_{to}) \leq  \gamma_{i}\ ~\forall i \in S \\
& (z^{bl}_{fr} - z^{bl}_{fr}) \geq - \gamma_{i}\ ~\forall i \in S \\
& z^{bl}_b \leq N_{gen} + N_{strg} + N_{neg load} + \sum_{i \in S \in b} \gamma_i, ~\forall b \in B
\end{align*}
```

where $$z^{bl}_{fr}$$ and $$z^{bl}_{to}$$ are the indicator variables for the blocks on
either side of switch $$i$$.
"""
function constraint_isolate_block(pm::AbstractUnbalancedPowerModel, nw::Int)
    # if switch is closed, both blocks need to be the same status (on or off)
    for (s, switch) in ref(pm, nw, :switch_dispatchable)
        z_block_fr = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, switch["f_bus"]))
        z_block_to = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, switch["t_bus"]))

        γ = var(pm, nw, :switch_state, s)
        JuMP.@constraint(pm.model,  (z_block_fr - z_block_to) <=  (1-γ))
        JuMP.@constraint(pm.model,  (z_block_fr - z_block_to) >= -(1-γ))

        # indicator constraint, for reference
        # JuMP.@constraint(pm.model, γ => {z_block_fr == z_block_to})
    end

    # quick determination of blocks to shed:
    # if no generation resources (gen, storage, or negative loads (e.g., rooftop pv models))
    # and no switches connected to the block are closed, then the island must be shed,
    # otherwise, to shed or not will be determined by feasibility
    for b in ids(pm, nw, :blocks)
        z_block = var(pm, nw, :z_block, b)

        n_gen = length(ref(pm, nw, :block_gens, b))
        n_strg = length(ref(pm, nw, :block_storages, b))
        n_neg_loads = length([_b for (_b,ls) in ref(pm, nw, :block_loads) if any(any(ref(pm, nw, :load, l, "pd") .< 0) for l in ls)])

        JuMP.@constraint(pm.model, z_block <= n_gen + n_strg + n_neg_loads + sum(var(pm, nw, :switch_state, s) for s in ids(pm, nw, :block_switches) if s in ids(pm, nw, :switch_dispatchable)))
    end
end


@doc raw"""
    constraint_isolate_block_traditional(pm::AbstractUnbalancedPowerModel, nw::Int)

Constraint to simulate block isolation constraint in the traditional mld problem

```math
\begin{align}
& z^{bus}_{fr} - z^{bus}_{to} \leq  (1-\gamma_i), ~\forall i \in S \\
& z^{bus}_{fr} - z^{bus}_{to} \geq -(1-\gamma_i), ~\forall i \in S \\
& z^{d}_i \leq z^{d}_j, ~\forall (i,j) \in D \in B \\
& z^{d}_i \leq z^{bus}_j, ~\forall i \in D \in B, ~i \in j \in V \in B \\
& z^{bus}_i \leq z^{bus}_j, ~\forall (i,j) \in V \in B \\
& z^{bl}_b \leq N_{gen} + N_{strg} + N_{neg load} + \sum_{i \in S \in {b \in B}} \gamma_i, ~\forall b \in B
\end{align}
```
"""
function constraint_isolate_block_traditional(pm::AbstractUnbalancedPowerModel, nw::Int)
    # if switch is closed, both buses need to have the same status (on or off)
    for (s, switch) in ref(pm, nw, :switch_dispatchable)
        z_voltage_fr = var(pm, nw, :z_voltage, switch["f_bus"])
        z_voltage_to = var(pm, nw, :z_voltage, switch["t_bus"])

        γ = var(pm, nw, :switch_state, s)
        JuMP.@constraint(pm.model,  (z_voltage_fr - z_voltage_to) <=  (1-γ))
        JuMP.@constraint(pm.model,  (z_voltage_fr - z_voltage_to) >= -(1-γ))
        # indicator constraint, for reference
        # JuMP.@constraint(pm.model, γ => {z_voltage_fr == z_voltage_to})
    end

    # link loads in block
    for (block, loads) in ref(pm, nw, :block_loads)
        for load in loads
            JuMP.@constraint(pm.model, var(pm, nw, :z_demand, load) .<= [var(pm, nw, :z_demand, _load) for _load in filter(x->x!=load, loads)])
            JuMP.@constraint(pm.model, var(pm, nw, :z_demand, load) <= var(pm, nw, :z_voltage, ref(pm, nw, :load, load, "load_bus")))
        end
    end

    # link buses in block
    for (block, buses) in ref(pm, nw, :blocks)
        for bus in buses
            if bus in var(pm, nw, :z_voltage)
                JuMP.@constraint(pm.model, var(pm, nw, :z_voltage, bus) .<= [var(pm, nw, :z_voltage, _bus) for _bus in filter(x->x!=bus&&_bus in var(pm, nw, :z_voltage), buses)])
            end
        end
    end

    # quick determination of blocks to shed:
    # if no generation resources (gen, storage, or negative loads (e.g., rooftop pv models))
    # and no switches connected to the block are closed, then the island must be shed,
    # otherwise, to shed or not will be determined by feasibility
    for b in ids(pm, nw, :blocks)
        z_voltages = [var(pm, nw, :z_voltage, bus) for bus in ref(pm, nw, :blocks, b) if bus in var(pm, nw, :z_voltage)]

        n_gen = length(ref(pm, nw, :block_gens, b))
        n_strg = length(ref(pm, nw, :block_storages, b))
        n_neg_loads = length([_b for (_b,ls) in ref(pm, nw, :block_loads) if any(any(ref(pm, nw, :load, l, "pd") .< 0) for l in ls)])

        JuMP.@constraint(pm.model, z_voltages .<= n_gen + n_strg + n_neg_loads + sum(var(pm, nw, :switch_state, s) for s in ids(pm, nw, :block_switches) if s in ids(pm, nw, :switch_dispatchable)))
    end
end


@doc raw"""
    constraint_radial_topology(pm::AbstractUnbalancedPowerModel, nw::Int; relax::Bool=false)

Constraint to enforce a radial topology

See 10.1109/TSG.2020.2985087

```math
\begin{align}
\mathbf{\beta} \in \mathbf{\Omega} \\
\alpha_{ij} \leq \beta_{ij},\forall(i,j) \in L \\
\sum_{\substack{(j,i_r)\in L}}f^{k}_{ji_r} - \sum_{\substack{(i_r,j)\in L}}f^{k}_{i_rj}=-1,~\forall k \in N\setminus i_r \\
\sum_{\substack{(j,k)\in L}}f^{k}_{jk} - \sum_{\substack{(k,j)\in L}}f^k_{kj} = 1,~\forall k \in N\setminus i_r \\
\sum_{\substack{(j,i)\in L}}f^k_{ji}-\sum_{\substack{(i,j)\in L}}f^k_{ij}=0,~\forall k \in N\setminus i_r,\forall i \in N\setminus {i_r,k} \\
0 \leq f^k_{ij} \leq \lambda_{ij},0 \leq f^k_{ji} \leq \lambda_{ji},\forall k \in N\setminus i_r,\forall(i,j)\in L \\
\sum_{\substack{(i,j)\in L}}\left(\lambda_{ij} + \lambda_{ji} \right ) = \left | N \right | - 1 \\
\lambda_{ij} + \lambda_{ji} = \beta_{ij},\forall(i,j)\in L \\
\lambda_{ij},\lambda_{ji}\in\left \{ 0,1 \right \},\forall(i,j)\in L
\end{align}
```
"""
function constraint_radial_topology(pm::AbstractUnbalancedPowerModel, nw::Int; relax::Bool=false)
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
        var(pm, nw, :lambda)[(i,j)] = JuMP.@variable(pm.model, base_name="$(nw)_lambda_$((i,j))", binary=!relax)
        var(pm, nw, :lambda)[(j,i)] = JuMP.@variable(pm.model, base_name="$(nw)_lambda_$((j,i))", binary=!relax)
        var(pm, nw, :beta)[(i,j)] = JuMP.@variable(pm.model, base_name="$(nw)_beta_$((i,j))", binary=!relax)
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


@doc raw"""
    constraint_mc_switch_power_open_close(
        pm::AbstractUnbalancedPowerModel,
        nw::Int,
        i::Int,
        f_bus::Int,
        t_bus::Int,
        f_connections::Vector{Int},
        t_connections::Vector{Int}
    )

generic switch power open/closed constraint

```math
\begin{align}
& S^{sw}_{i,c} \leq S^{swu}_{i,c} z^{sw}_i\ \forall i \in S,\forall c \in C \\
& S^{sw}_{i,c} \geq -S^{swu}_{i,c} z^{sw}_i\ \forall i \in S,\forall c \in C
\end{align}
```
"""
function constraint_mc_switch_power_open_close(pm::AbstractUnbalancedPowerModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int})
    psw = var(pm, nw, :psw, (i, f_bus, t_bus))
    qsw = var(pm, nw, :qsw, (i, f_bus, t_bus))

    state = var(pm, nw, :switch_state, i)

    rating = min.(fill(1.0, length(f_connections)), PMD._calc_branch_power_max_frto(ref(pm, nw, :switch, i), ref(pm, nw, :bus, f_bus), ref(pm, nw, :bus, t_bus))...)

    for (idx, c) in enumerate(f_connections)
        JuMP.@constraint(pm.model, psw[c] <=  rating[idx] * state)
        JuMP.@constraint(pm.model, psw[c] >= -rating[idx] * state)
        JuMP.@constraint(pm.model, qsw[c] <=  rating[idx] * state)
        JuMP.@constraint(pm.model, qsw[c] >= -rating[idx] * state)

        # Indicator constraint version, for reference
        # JuMP.@constraint(pm.model, !state => {psw[c] == 0.0})
        # JuMP.@constraint(pm.model, !state => {qsw[c] == 0.0})
    end
end


@doc raw"""
    constraint_mc_generator_power_block_on_off(
        pm::AbstractUnbalancedPowerModel,
        nw::Int,
        i::Int,
        connections::Vector{Int},
        pmin::Vector{<:Real},
        pmax::Vector{<:Real},
        qmin::Vector{<:Real},
        qmax::Vector{<:Real}
    )

Generic block mld on/off constraint for generator power

```math
\begin{align}
S_i \geq z^{bl}_b S^{lb}_i, i \in {b \in B} \\
S_i \leq z^{bl}_b S^{ub}_i, i \in {b \in B}
\end{align}
```
"""
function constraint_mc_generator_power_block_on_off(pm::AbstractUnbalancedPowerModel, nw::Int, i::Int, connections::Vector{<:Int}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, qmin::Vector{<:Real}, qmax::Vector{<:Real})
    z_block = var(pm, nw, :z_block, ref(pm, nw, :gen_block_map, i))

    pg = var(pm, nw, :pg, i)
    qg = var(pm, nw, :qg, i)

    for (idx, c) in enumerate(connections)
        isfinite(pmin[idx]) && JuMP.@constraint(pm.model, pg[c] >= pmin[idx]*z_block)
        isfinite(qmin[idx]) && JuMP.@constraint(pm.model, qg[c] >= qmin[idx]*z_block)

        isfinite(pmax[idx]) && JuMP.@constraint(pm.model, pg[c] <= pmax[idx]*z_block)
        isfinite(qmax[idx]) && JuMP.@constraint(pm.model, qg[c] <= qmax[idx]*z_block)
    end
end


@doc raw"""
    constraint_mc_generator_power_traditional_on_off(pm::AbstractUnbalancedPowerModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, qmin::Vector{<:Real}, qmax::Vector{<:Real})

Generic traditional mld on/off constraint for generator power

```math
\begin{align}
S_i \geq z^{gen}_i S^{lb}_i \\
S_i \leq z^{gen}_i S^{ub}_i
\end{align}
```
"""
function constraint_mc_generator_power_traditional_on_off(pm::AbstractUnbalancedPowerModel, nw::Int, i::Int, connections::Vector{<:Int}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, qmin::Vector{<:Real}, qmax::Vector{<:Real})
    z_gen = var(pm, nw, :z_gen, i)

    pg = var(pm, nw, :pg, i)
    qg = var(pm, nw, :qg, i)

    for (idx, c) in enumerate(connections)
        isfinite(pmin[idx]) && JuMP.@constraint(pm.model, pg[c] >= pmin[idx]*z_gen)
        isfinite(qmin[idx]) && JuMP.@constraint(pm.model, qg[c] >= qmin[idx]*z_gen)

        isfinite(pmax[idx]) && JuMP.@constraint(pm.model, pg[c] <= pmax[idx]*z_gen)
        isfinite(qmax[idx]) && JuMP.@constraint(pm.model, qg[c] <= qmax[idx]*z_gen)
    end
end


@doc raw"""
    constraint_mc_storage_block_on_off(
        pm::AbstractUnbalancedPowerModel,
        nw::Int,
        i::Int,
        connections::Vector{Int},
        pmin::Real,
        pmax::Real,
        qmin::Real,
        qmax::Real,
        charge_ub::Real,
        discharge_ub::Real
    )

block on/off constraint for storage

```math
\begin{align}
\sum_{\substack{c \in \Gamma}} S_{i,c} \geq z^{bl}_b S^{lb}_i, i \in {b \in B} \\
\sum_{\substack{c \in \Gamma}} S_{i,c} \leq z^{bl}_b S^{ub}_i, i \in {b \in B}
\end{align}
```
"""
function constraint_mc_storage_block_on_off(pm::AbstractUnbalancedPowerModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Real, pmax::Real, qmin::Real, qmax::Real, charge_ub::Real, discharge_ub::Real)
    z_block = var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i))

    ps = [var(pm, nw, :ps, i)[c] for c in connections]
    qs = [var(pm, nw, :qs, i)[c] for c in connections]

    isfinite(pmin) && JuMP.@constraint(pm.model, sum(ps) >= z_block*pmin)
    isfinite(qmin) && JuMP.@constraint(pm.model, sum(qs) >= z_block*qmin)

    isfinite(pmax) && JuMP.@constraint(pm.model, sum(ps) <= z_block*pmax)
    isfinite(qmax) && JuMP.@constraint(pm.model, sum(qs) <= z_block*qmax)
end


@doc raw"""
    constraint_mc_storage_traditional_on_off(
        pm::AbstractUnbalancedPowerModel,
        nw::Int,
        i::Int,
        connections::Vector{Int},
        pmin::Real,
        pmax::Real,
        qmin::Real,
        qmax::Real,
        charge_ub::Real,
        discharge_ub::Real
    )

Traditional on/off constraint for storage

```math
\begin{align}
\sum_{\substack{c \in \Gamma}} S_{i,c} \geq z^{strg}_i S^{lb}_i \\
\sum_{\substack{c \in \Gamma}} S_{i,c} \leq z^{strg}_i S^{ub}_i
\end{align}
```
"""
function constraint_mc_storage_traditional_on_off(pm::AbstractUnbalancedPowerModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Real, pmax::Real, qmin::Real, qmax::Real, charge_ub::Real, discharge_ub::Real)
    z_storage = var(pm, nw, :z_storage, i)

    ps = [var(pm, nw, :ps, i)[c] for c in connections]
    qs = [var(pm, nw, :qs, i)[c] for c in connections]

    isfinite(pmin) && JuMP.@constraint(pm.model, sum(ps) >= z_storage*pmin)
    isfinite(qmin) && JuMP.@constraint(pm.model, sum(qs) >= z_storage*qmin)

    isfinite(pmax) && JuMP.@constraint(pm.model, sum(ps) <= z_storage*pmax)
    isfinite(qmax) && JuMP.@constraint(pm.model, sum(qs) <= z_storage*qmax)
end


@doc raw"""
    constraint_mc_storage_phase_unbalance(
        pm::AbstractUnbalancedPowerModel,
        nw::Int,
        i::Int,
        connections::Vector{Int},
        unbalance_factor::Real
    )

Enforces that storage inputs/outputs are (approximately) balanced across each phase, by some `unbalance_factor`

```math
S^{strg}_{i,c} \geq S^{strg}_{i,d} - f^{unbal} \left( -d^{on}_i S^{strg}_{i,d} + c^{on}_i S^{strg}_{i,d} \right) \forall c,d \in C
S^{strg}_{i,c} \leq S^{strg}_{i,d} + f^{unbal} \left( -d^{on}_i S^{strg}_{i,d} + c^{on}_i S^{strg}_{i,d} \right) \forall c,d \in C
```
"""
function constraint_mc_storage_phase_unbalance(pm::AbstractUnbalancedPowerModel, nw::Int, i::Int, connections::Vector{Int}, unbalance_factor::Real)
    ps = var(pm, nw, :ps, i)
    qs = var(pm, nw, :qs, i)

    sc_on = var(pm, nw, :sc_on, i)  # ==1 charging (p,q > 0)
    sd_on = var(pm, nw, :sd_on, i)  # ==1 discharging (p,q < 0)

    sd_on_ps = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sd_on_ps_$(i)", lower_bound=0.0)
    sc_on_ps = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sc_on_ps_$(i)", lower_bound=0.0)
    sd_on_qs = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sd_on_qs_$(i)", lower_bound=0.0)
    sc_on_qs = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sc_on_qs_$(i)", lower_bound=0.0)
    for c in connections
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sd_on, ps[c], sd_on_ps[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sc_on, ps[c], sc_on_ps[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sd_on, qs[c], sd_on_qs[c], [0,1], [JuMP.lower_bound(qs[c]), JuMP.upper_bound(qs[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sc_on, qs[c], sc_on_qs[c], [0,1], [JuMP.lower_bound(qs[c]), JuMP.upper_bound(qs[c])])
    end

    for (idx,c) in enumerate(connections)
        if idx < length(connections)
            for d in connections[idx+1:end]
                JuMP.@constraint(pm.model, ps[c] >= ps[d] - unbalance_factor*(-1*sd_on_ps[d] + 1*sc_on_ps[d]))
                JuMP.@constraint(pm.model, ps[c] <= ps[d] + unbalance_factor*(-1*sd_on_ps[d] + 1*sc_on_ps[d]))

                JuMP.@constraint(pm.model, qs[c] >= qs[d] - unbalance_factor*(-1*sd_on_qs[d] + 1*sc_on_qs[d]))
                JuMP.@constraint(pm.model, qs[c] <= qs[d] + unbalance_factor*(-1*sd_on_qs[d] + 1*sc_on_qs[d]))
            end
        end
    end
end


@doc raw"""
    constraint_storage_complementarity_mi_block_on_off(
        pm::AbstractUnbalancedPowerModel,
        n::Int,
        i::Int,
        charge_ub::Real,
        discharge_ub::Real
    )

Nonlinear storage complementarity mi constraint for block mld problem.

math```
\begin{align}
c^{on}_i * d^{on}_i == z^{bl}_b, i \in {b \in B} \\
c^{on}_i c^{ub}_i \geq c_i \\
d^{on}_i d^{ub}_i \geq d_i
\end{align}
```
"""
function constraint_storage_complementarity_mi_block_on_off(pm::AbstractUnbalancedPowerModel, n::Int, i::Int, charge_ub::Real, discharge_ub::Real)
    sc = var(pm, n, :sc, i)
    sd = var(pm, n, :sd, i)
    sc_on = var(pm, n, :sc_on, i)
    sd_on = var(pm, n, :sd_on, i)

    z_block = var(pm, n, :z_block, ref(pm, n, :storage_block_map, i))

    JuMP.@constraint(pm.model, sc_on*sd_on == z_block)
    JuMP.@constraint(pm.model, sc_on*charge_ub >= sc)
    JuMP.@constraint(pm.model, sd_on*discharge_ub >= sd)
end


@doc raw"""
    constraint_storage_complementarity_mi_traditional_on_off(
        pm::AbstractUnbalancedPowerModel,
        n::Int,
        i::Int,
        charge_ub::Real,
        discharge_ub::Real
    )

Nonlinear storage complementarity mi constraint for traditional mld problem.

math```
\begin{align}
c^{on}_i d^{on}_i = z^{strg}_i \\
c^{on}_i c^{ub}_i \geq c_i \\
d^{on}_i d^{ub}_i \geq d_i
\end{align}
```
"""
function constraint_storage_complementarity_mi_traditional_on_off(pm::AbstractUnbalancedPowerModel, n::Int, i::Int, charge_ub::Real, discharge_ub::Real)
    sc = var(pm, n, :sc, i)
    sd = var(pm, n, :sd, i)
    sc_on = var(pm, n, :sc_on, i)
    sd_on = var(pm, n, :sd_on, i)

    z_storage = var(pm, n, :z_storage, i)

    JuMP.@constraint(pm.model, sc_on*sd_on == z_storage)
    JuMP.@constraint(pm.model, sc_on*charge_ub >= sc)
    JuMP.@constraint(pm.model, sd_on*discharge_ub >= sd)
end
