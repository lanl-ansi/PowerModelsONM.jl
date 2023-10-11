@doc raw"""
    constraint_switch_close_action_limit(pm::AbstractUnbalancedPowerModel, nw::Int)

Constraint for maximum allowed switch close actions in a single time step, as defined by `ref(pm, nw, :switch_close_actions_ub)`

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
    switch_close_actions_ub = ref(pm, nw, :switch_close_actions_ub)

    if switch_close_actions_ub < Inf
        Δᵞs = Dict(l => JuMP.@variable(pm.model, base_name="$(nw)_delta_switch_state_$(l)", start=0) for l in ids(pm, nw, :switch_dispatchable))
        for (s, Δᵞ) in Δᵞs
            γ = var(pm, nw, :switch_state, s)
            γ₀ = JuMP.start_value(γ)
            JuMP.@constraint(pm.model, Δᵞ >=  γ * (1 - γ₀))
            JuMP.@constraint(pm.model, Δᵞ >= -γ * (1 - γ₀))
        end

        JuMP.@constraint(pm.model, sum(Δᵞ for (l, Δᵞ) in Δᵞs) <= switch_close_actions_ub)
    end
end


@doc raw"""
    constraint_switch_close_action_limit(pm::AbstractUnbalancedPowerModel, nw_1::Int, nw_2::Int)

Constraint for maximum allowed switch close actions between time steps, as defined by `ref(pm, nw, :switch_close_actions_ub)`

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
    switch_close_actions_ub = ref(pm, nw_2, :switch_close_actions_ub)

    if switch_close_actions_ub < Inf
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

        JuMP.@constraint(pm.model, sum(Δᵞ for (l, Δᵞ) in Δᵞs) <= switch_close_actions_ub)
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
            if Int(get(ref(pm, nw, :load, load), "dispatchable", PMD.NO)) == 0
                JuMP.@constraint(pm.model, var(pm, nw, :z_demand, load) >= var(pm, nw, :z_voltage, ref(pm, nw, :load, load, "load_bus")))
            end
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

    # "real" node and branch sets
    N₀ = ids(pm, nw, :blocks)
    L₀ = ref(pm, nw, :block_pairs)

    # Add "virtual" iᵣ to N
    virtual_iᵣ = maximum(N₀)+1
    N = [N₀..., virtual_iᵣ]
    iᵣ = [virtual_iᵣ]

    # create a set L of all branches, including virtual branches between iᵣ and all other nodes in L₀
    L = [L₀..., [(virtual_iᵣ, n) for n in N₀]...]

    # create a set L′ that inlcudes the branch reverses
    L′ = union(L, Set([(j,i) for (i,j) in L]))

    # create variables fᵏ and λ over all L, including virtual branches connected to iᵣ
    for (i,j) in L′
        for k in filter(kk->kk∉iᵣ,N)
            var(pm, nw, :f)[(k, i, j)] = JuMP.@variable(pm.model, base_name="$(nw)_f_$((k,i,j))", start=(k,i,j) == (k,virtual_iᵣ,k) ? 1 : 0)
        end
        var(pm, nw, :lambda)[(i,j)] = JuMP.@variable(pm.model, base_name="$(nw)_lambda_$((i,j))", binary=!relax, lower_bound=0, upper_bound=1, start=(i,j) == (virtual_iᵣ,j) ? 1 : 0)

        # create variable β over only original set L₀
        if (i,j) ∈ L₀
            var(pm, nw, :beta)[(i,j)] = JuMP.@variable(pm.model, base_name="$(nw)_beta_$((i,j))", lower_bound=0, upper_bound=1)
        end
    end

    # create an aux varible α that maps to the switch states
    for (s,sw) in ref(pm, nw, :switch)
        (i,j) = (ref(pm, nw, :bus_block_map, sw["f_bus"]), ref(pm, nw, :bus_block_map, sw["t_bus"]))
        var(pm, nw, :alpha)[(i,j)] = var(pm, nw, :switch_state, s)
    end

    f = var(pm, nw, :f)
    λ = var(pm, nw, :lambda)
    β = var(pm, nw, :beta)
    α = var(pm, nw, :alpha)

    # Eq. (1) -> Eqs. (3-8)
    for k in filter(kk->kk∉iᵣ,N)
        # Eq. (3)
        for _iᵣ in iᵣ
            jiᵣ = filter(((j,i),)->i==_iᵣ&&i!=j,L)
            iᵣj = filter(((i,j),)->i==_iᵣ&&i!=j,L)
            if !(isempty(jiᵣ) && isempty(iᵣj))
                c = JuMP.@constraint(
                    pm.model,
                    sum(f[(k,j,i)] for (j,i) in jiᵣ) -
                    sum(f[(k,i,j)] for (i,j) in iᵣj)
                    ==
                    -1.0
                )
            end
        end

        # Eq. (4)
        jk = filter(((j,i),)->i==k&&i!=j,L′)
        kj = filter(((i,j),)->i==k&&i!=j,L′)
        if !(isempty(jk) && isempty(kj))
            c = JuMP.@constraint(
                pm.model,
                sum(f[(k,j,k)] for (j,i) in jk) -
                sum(f[(k,k,j)] for (i,j) in kj)
                ==
                1.0
            )
        end

        # Eq. (5)
        for i in filter(kk->kk∉iᵣ&&kk!=k,N)
            ji = filter(((j,ii),)->ii==i&&ii!=j,L′)
            ij = filter(((ii,j),)->ii==i&&ii!=j,L′)
            if !(isempty(ji) && isempty(ij))
                c = JuMP.@constraint(
                    pm.model,
                    sum(f[(k,j,i)] for (j,ii) in ji) -
                    sum(f[(k,i,j)] for (ii,j) in ij)
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

    # Connect λ and β, map β back to α, over only real switches (L₀)
    for (i,j) in L₀
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


@doc raw"""
    constraint_mc_storage_phase_unbalance_grid_following(
        pm::AbstractUnbalancedPowerModel,
        nw::Int,
        i::Int,
        connections::Vector{Int},
        unbalance_factor::Real
    )

Enforces that storage inputs/outputs are (approximately) balanced across each phase, by some `unbalance_factor` on grid-following
inverters only. Requires z_inverter variable

```math
S^{strg}_{i,c} \geq S^{strg}_{i,d} - f^{unbal} \left( -d^{on}_i S^{strg}_{i,d} + c^{on}_i S^{strg}_{i,d} \right) \forall c,d \in C
S^{strg}_{i,c} \leq S^{strg}_{i,d} + f^{unbal} \left( -d^{on}_i S^{strg}_{i,d} + c^{on}_i S^{strg}_{i,d} \right) \forall c,d \in C
```
"""
function constraint_mc_storage_phase_unbalance_grid_following(pm::AbstractUnbalancedPowerModel, nw::Int, i::Int, connections::Vector{Int}, unbalance_factor::Real)
    z_inverter = var(pm, nw, :z_inverter, (:storage, i))

    ps = var(pm, nw, :ps, i)
    qs = var(pm, nw, :qs, i)

    sc_on = var(pm, nw, :sc_on, i)  # ==1 charging (p,q > 0)
    sd_on = var(pm, nw, :sd_on, i)  # ==1 discharging (p,q < 0)

    sd_on_ps = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sd_on_ps_$(i)")
    sc_on_ps = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sc_on_ps_$(i)")
    sd_on_qs = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sd_on_qs_$(i)")
    sc_on_qs = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sc_on_qs_$(i)")
    for c in connections
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sd_on, ps[c], sd_on_ps[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sc_on, ps[c], sc_on_ps[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sd_on, qs[c], sd_on_qs[c], [0,1], [JuMP.lower_bound(qs[c]), JuMP.upper_bound(qs[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sc_on, qs[c], sc_on_qs[c], [0,1], [JuMP.lower_bound(qs[c]), JuMP.upper_bound(qs[c])])
    end

    ps_zinverter = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_ps_zinverter_$(i)")
    qs_zinverter = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_qs_zinverter_$(i)")
    for c in connections
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, z_inverter, ps[c], ps_zinverter[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, z_inverter, qs[c], qs_zinverter[c], [0,1], [JuMP.lower_bound(qs[c]), JuMP.upper_bound(qs[c])])
    end

    sd_on_ps_zinverter = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sd_on_ps_zinverter_$(i)")
    sc_on_ps_zinverter = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sc_on_ps_zinverter_$(i)")
    sd_on_qs_zinverter = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sd_on_qs_zinverter_$(i)")
    sc_on_qs_zinverter = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sc_on_qs_zinverter_$(i)")
    for c in connections
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, z_inverter, sd_on_ps[c], sd_on_ps_zinverter[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, z_inverter, sc_on_ps[c], sc_on_ps_zinverter[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, z_inverter, sd_on_qs[c], sd_on_qs_zinverter[c], [0,1], [JuMP.lower_bound(qs[c]), JuMP.upper_bound(qs[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, z_inverter, sc_on_qs[c], sc_on_qs_zinverter[c], [0,1], [JuMP.lower_bound(qs[c]), JuMP.upper_bound(qs[c])])
    end

    for (idx,c) in enumerate(connections)
        if idx < length(connections)
            for d in connections[idx+1:end]
                JuMP.@constraint(pm.model, ps[c]-ps_zinverter[c] >= ps[d] - unbalance_factor*(-1*sd_on_ps[d] + 1*sc_on_ps[d]) - ps_zinverter[d] + unbalance_factor*(-1*sd_on_ps_zinverter[d] + 1*sc_on_ps_zinverter[d]))
                JuMP.@constraint(pm.model, ps[c]-ps_zinverter[c] <= ps[d] + unbalance_factor*(-1*sd_on_ps[d] + 1*sc_on_ps[d]) - ps_zinverter[d] - unbalance_factor*(-1*sd_on_ps_zinverter[d] + 1*sc_on_ps_zinverter[d]))

                JuMP.@constraint(pm.model, qs[c]-qs_zinverter[c] >= qs[d] - unbalance_factor*(-1*sd_on_qs[d] + 1*sc_on_qs[d]) - qs_zinverter[d] + unbalance_factor*(-1*sd_on_qs_zinverter[d] + 1*sc_on_qs_zinverter[d]))
                JuMP.@constraint(pm.model, qs[c]-qs_zinverter[c] <= qs[d] + unbalance_factor*(-1*sd_on_qs[d] + 1*sc_on_qs[d]) - qs_zinverter[d] - unbalance_factor*(-1*sd_on_qs_zinverter[d] + 1*sc_on_qs_zinverter[d]))
            end
        end
    end
end


@doc raw"""
    constraint_grid_forming_inverter_per_cc(pm::AbstractUnbalancedPowerModel, nw::Int; relax::Bool=false)

Constrains each connected component of the load block graph to have only one grid-forming inverter, if the block is enabled

```math
\begin{align}
& \sum_{k \in {\cal B}} y^k_{ab} \le z^{sw}_{ab} &\forall ab \in {\cal E}_{sw} \\
& \sum_{ab \in {\cal T}_k} (1-z^{sw}_{ab}) - |{\cal T}_k| + z^{bl}_k \le \sum_{i \in {\cal D}_k} z^{inv}_i \le z^{bl}_k & \forall k \in {\cal B} \\
& S^g_i \le \overline{S}^g_i (\sum_{ab \in {\cal T}_k} z^{sw}_{ab} + \sum_{j \in {\cal D}_k} z^{inv}_j) & \forall i \in {\cal G} \\
& S^g_i \le \overline{S}^g_i (\sum_{ab \in {\cal T}_k} \sum_{k \in {\cal B}} y_{ab}^k + \sum_{j \in {\cal D}_k} z^{sw}_j) & \forall i \in {\cal G} \\
& S^g_i \ge \underline{S}^g_i (\sum_{ab \in {\cal T}_k} z^{sw}_{ab} + \sum_{j \in {\cal D}_k} z^{inv}_j) & \forall i \in {\cal G} \\
& S^g_i \ge \underline{S}^g_i (\sum_{ab \in {\cal T}_k} \sum_{k \in {\cal B}} y_{ab}^k + \sum_{j \in {\cal D}_k} z^{sw}_j) & \forall i \in {\cal G} \\
& y^k_{ab} - (1 - z^{sw}_{ab}) \le \sum_{i \in {\cal D}_k} z^{inv}_i \le  y^k_{ab} + (1 - z^{sw}_{ab}) & \forall k \in {\cal B},\forall ab \in {\cal E}_{sw} \\
& y^{k'}_{dc} - (1 - z^{sw}_{dc}) - (1 - z^{sw}_{ab}) \le y^{k'}_{ab} \le  y^{k'}_{dc} + (1 - z^{sw}_{dc}) + (1 - z^{sw}_{ab}) \\
& ~~~~ \forall k \in {\cal B},\forall k' \in {\cal B}/{k},\forall ab \in {\cal E}_{sw},\forall dc \in {\cal E}_{sw}/{ab} \nonumber \\
& y_{ab}^k \le \sum_{i \in {\cal D}_k} z^{inv}_i & \forall k \in {\cal B},\forall ab \in {\cal E}_{sw} \\
& -z^{sw}_{ab} |{\cal B}| \le f_{ab}^k \le z^{sw}_{ab} |{\cal B}| & \forall k \in {\cal B},\forall ab \in {\cal E}_{sw} \\
& 0 \le \xi_{ab}^k \le 1 & \forall k \in {\cal B},\forall ab \in {\cal E}_{sw} \\
& \sum_{ab \in {\cal T}_k : a = k} f_{ab}^k - \sum_{ab \in {\cal T}_k : b = k} f_{ab}^k + \sum_{ab \in {\cal E}_v^k} \xi_{ab}^k = |{\cal B}| - 1 & \forall k \in {\cal B} \\
& \sum_{ab \in {\cal T}_{k'} : a = k'} f_{ab}^k - \sum_{ab \in {\cal T}_{k'} : b = k'} f_{ab}^k  -  \xi_{kk'}^k = -1, \;\;\; \forall k' \ne k & \forall k \in {\cal B} \\
& y_{ab}^k \le 1 - \xi_{kk'}^k & \forall k' \ne k, ab \in {\cal T}_{k'} \\
& z^{bl}_k \le \sum_{i \in {\cal D}_k} z^{inv}_i + \sum_{ab \in {\cal T}_k}  \sum_{k \in {\cal B}} y^k_{ab}
\end{align}
```
"""
function constraint_grid_forming_inverter_per_cc_block(pm::AbstractUnbalancedPowerModel, nw::Int; relax::Bool=false)
    con_opts = ref(pm, nw, :options, "constraints")

    # Set of base connected components
    L = Set{Int}(ids(pm, nw, :blocks))

    # variable representing if switch ab has 'color' k
    var(pm, nw)[:y_gfm] = Dict{Tuple{Int,Int},JuMP.VariableRef}()
    for k in L
        for ab in ids(pm, nw, :switch)
            var(pm, nw, :y_gfm)[(k,ab)] = JuMP.@variable(
                pm.model,
                base_name="$(nw)_y_gfm[$k,$ab]",
                binary=!relax,
                lower_bound=0,
                upper_bound=1
            )
        end
    end

    # switch pairs to ids and vise-versa
    map_id_pairs = Dict{Int,Tuple{Int,Int}}(id => (ref(pm, nw, :bus_block_map, sw["f_bus"]),ref(pm, nw, :bus_block_map, sw["t_bus"])) for (id,sw) in ref(pm, nw, :switch))

    # set of *virtual* edges between component k and all other components k′
    Φₖ = Dict{Int,Set{Int}}(k => Set{Int}() for k in L)
    map_virtual_pairs_id = Dict{Int,Dict{Tuple{Int,Int},Int}}(k=>Dict{Tuple{Int,Int},Int}() for k in L)

    # Eqs. (9)-(10)
    var(pm, nw)[:f_gfm] = Dict{Tuple{Int,Int},JuMP.VariableRef}()
    var(pm, nw)[:phi_gfm] = Dict{Tuple{Int,Int},JuMP.VariableRef}()
    for kk in L # color
        for ab in ids(pm, nw, :switch)
            f = var(pm, nw, :f_gfm)[(kk,ab)] = JuMP.@variable(
                pm.model,
                base_name="$(nw)_f_gfm[$kk,$ab]"
            )
            JuMP.@constraint(pm.model, f >= -length(ids(pm,nw,:switch))*(var(pm,nw,:switch_state,ab)))
            JuMP.@constraint(pm.model, f <=  length(ids(pm,nw,:switch))*(var(pm,nw,:switch_state,ab)))
        end

        touched = Set{Tuple{Int,Int}}()
        ab = 1

        for k in sort(collect(L)) # fr block
            for k′ in sort(collect(filter(x->x!=k,L))) # to block
                if (k,k′) ∉ touched
                    map_virtual_pairs_id[kk][(k,k′)] = map_virtual_pairs_id[kk][(k′,k)] = ab
                    push!(touched, (k,k′), (k′,k))

                    var(pm, nw, :phi_gfm)[(kk,ab)] = JuMP.@variable(
                        pm.model,
                        base_name="$(nw)_phi_gfm[$kk,$ab]",
                        lower_bound=0,
                        upper_bound=1
                    )

                    ab += 1
                end
            end
        end

        Φₖ[kk] = Set{Int}([map_virtual_pairs_id[kk][(kk,k′)] for k′ in filter(x->x!=kk,L)])
    end

    # variables
    y = var(pm, nw, :y_gfm)
    f = var(pm, nw, :f_gfm)
    ϕ = var(pm, nw, :phi_gfm)
    z = var(pm, nw, :switch_state)
    x = var(pm, nw, :z_inverter)
    γ = var(pm, nw, :z_block)

    # voltage sources are always grid-forming
    for ((t,j), z_inv) in x
        if t == :gen && startswith(ref(pm, nw, t, j, "source_id"), "voltage_source")
            JuMP.@constraint(pm.model, z_inv == var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, ref(pm, nw, t, j, "$(t)_bus"))))
        end
    end

    # Eq. (2)
    # constrain each y to have only one color
    con(pm, nw)[:y_gfm] = Dict{Int,JuMP.ConstraintRef}()
    for ab in ids(pm, nw, :switch)
        con(pm, nw, :y_gfm)[ab] = JuMP.@constraint(pm.model, sum(y[(k,ab)] for k in L) <= z[ab])
    end

    # storage flow upper/lower bounds
    inj_lb, inj_ub = PMD.ref_calc_storage_injection_bounds(ref(pm, nw, :storage), ref(pm, nw, :bus))

    con(pm, nw)[:f_gfm_11] = Dict{Int,JuMP.ConstraintRef}()
    con(pm, nw)[:f_gfm_12] = Dict{Tuple{Int,Int},JuMP.ConstraintRef}()
    con(pm, nw)[:f_gfm_13] = Dict{Tuple{Int,Int,Int},JuMP.ConstraintRef}()
    con(pm, nw)[:f_gfm_15] = Dict{Int,JuMP.ConstraintRef}()

    # Eqs. (3)-(7)
    for k in L
        Dₖ = ref(pm, nw, :block_inverters, k)
        Tₖ = ref(pm, nw, :block_switches, k)

        if !isempty(Dₖ)
            if get(con_opts, "disable-grid-forming-constraint-block-cuts", false)
                # Eq. (13)
                n_gfm = Int(any([get(ref(pm, nw, i[1], i[2]), "inverter", GRID_FORMING) == GRID_FORMING for i in Dₖ]))
                if n_gfm > 0
                    JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) >= sum(1-z[ab] for ab in Tₖ)-length(Tₖ)+1)
                    JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) <= 1)
                end
            else
                # Eq. (24)
                JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) >= sum(1-z[ab] for ab in Tₖ)-length(Tₖ)+γ[k])
                JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) <= γ[k])
            end

            # Eq. (4)-(5)
            for (t,j) in Dₖ
                if t == :storage
                    pmin = fill(-Inf, length(ref(pm, nw, t, j, "connections")))
                    pmax = fill( Inf, length(ref(pm, nw, t, j, "connections")))
                    qmin = fill(-Inf, length(ref(pm, nw, t, j, "connections")))
                    qmax = fill( Inf, length(ref(pm, nw, t, j, "connections")))

                    for (idx,c) in enumerate(ref(pm, nw, t, j, "connections"))
                        pmin[idx] = inj_lb[j][idx]
                        pmax[idx] = inj_ub[j][idx]
                        qmin[idx] = max(inj_lb[j][idx], ref(pm, nw, t, j, "qmin"))
                        qmax[idx] = min(inj_ub[j][idx], ref(pm, nw, t, j, "qmax"))

                        if isfinite(pmax[idx]) && pmax[idx] >= 0
                            JuMP.@constraint(pm.model, var(pm, nw, :ps, j)[c] <= pmax[idx] * (sum(z[ab] for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                            JuMP.@constraint(pm.model, var(pm, nw, :ps, j)[c] <= pmax[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                        end
                        if isfinite(qmax[idx]) && qmax[idx] >= 0 && haskey(var(pm, nw), :qs)
                            JuMP.@constraint(pm.model, var(pm, nw, :qs, j)[c] <= qmax[idx] * (sum(z[ab] for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                            JuMP.@constraint(pm.model, var(pm, nw, :qs, j)[c] <= qmax[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                        end
                        if isfinite(pmin[idx]) && pmin[idx] <= 0
                            JuMP.@constraint(pm.model, var(pm, nw, :ps, j)[c] >= pmin[idx] * (sum(z[ab] for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                            JuMP.@constraint(pm.model, var(pm, nw, :ps, j)[c] >= pmin[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                        end
                        if isfinite(qmin[idx]) && qmin[idx] <= 0 && haskey(var(pm, nw), :qs)
                            JuMP.@constraint(pm.model, var(pm, nw, :qs, j)[c] >= qmin[idx] * (sum(z[ab] for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                            JuMP.@constraint(pm.model, var(pm, nw, :qs, j)[c] >= qmin[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                        end
                    end
                elseif t == :gen
                    pmin = ref(pm, nw, t, j, "pmin")
                    pmax = ref(pm, nw, t, j, "pmax")
                    qmin = ref(pm, nw, t, j, "qmin")
                    qmax = ref(pm, nw, t, j, "qmax")

                    for (idx,c) in enumerate(ref(pm, nw, t, j, "connections"))
                        if isfinite(pmax[idx]) && pmax[idx] >= 0
                            JuMP.@constraint(pm.model, var(pm, nw, :pg, j)[c] <= pmax[idx] * (sum(z[ab] for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                            JuMP.@constraint(pm.model, var(pm, nw, :pg, j)[c] <= pmax[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                        end
                        if isfinite(qmax[idx]) && qmax[idx] >= 0 && haskey(var(pm, nw), :qg)
                            JuMP.@constraint(pm.model, var(pm, nw, :qg, j)[c] <= qmax[idx] * (sum(z[ab] for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                            JuMP.@constraint(pm.model, var(pm, nw, :qg, j)[c] <= qmax[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                        end
                        if isfinite(pmin[idx]) && pmin[idx] <= 0
                            JuMP.@constraint(pm.model, var(pm, nw, :pg, j)[c] >= pmin[idx] * (sum(z[ab] for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                            JuMP.@constraint(pm.model, var(pm, nw, :pg, j)[c] >= pmin[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                        end
                        if isfinite(qmin[idx]) && qmin[idx] <= 0 && haskey(var(pm, nw), :qg)
                            JuMP.@constraint(pm.model, var(pm, nw, :qg, j)[c] >= qmin[idx] * (sum(z[ab] for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                            JuMP.@constraint(pm.model, var(pm, nw, :qg, j)[c] >= qmin[idx] * (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                        end
                    end
                end
            end
        end

        for ab in Tₖ
            # Eq. (6)
            JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) >= y[(k, ab)] - (1 - z[ab]))
            JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) <= y[(k, ab)] + (1 - z[ab]))

            for dc in filter(x->x!=ab, Tₖ)
                for k′ in L
                    # Eq. (7)
                    JuMP.@constraint(pm.model, y[(k′,ab)] >= y[(k′,dc)] - (1 - z[dc]) - (1 - z[ab]))
                    JuMP.@constraint(pm.model, y[(k′,ab)] <= y[(k′,dc)] + (1 - z[dc]) + (1 - z[ab]))
                end
            end

            # Eq. (8)
            JuMP.@constraint(pm.model, y[(k,ab)] <= sum(x[i] for i in Dₖ))
        end

        # Eq. (11)
        con(pm, nw, :f_gfm_11)[k] = JuMP.@constraint(pm.model, sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][1] == k, Tₖ)) - sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][2] == k, Tₖ)) + sum(ϕ[(k,ab)] for ab in Φₖ[k]) == length(L) - 1)

        for k′ in filter(x->x!=k, L)
            Tₖ′ = ref(pm, nw, :block_switches, k′)
            kk′ = map_virtual_pairs_id[k][(k,k′)]

            # Eq. (12)
            con(pm, nw, :f_gfm_12)[(k,k′)] = JuMP.@constraint(pm.model, sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][1]==k′, Tₖ′)) - sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][2]==k′, Tₖ′)) - ϕ[(k,(kk′))] == -1)

            # Eq. (13)
            for ab in Tₖ′
                con(pm, nw, :f_gfm_13)[(k,k′,ab)] = JuMP.@constraint(pm.model, y[k,ab] <= 1 - ϕ[(k,kk′)])
            end
        end

        if !get(con_opts, "disable-grid-forming-constraint-block-cuts", false)
            # Eq. (15), Eq. (26)
            con(pm, nw, :f_gfm_15)[k] = JuMP.@constraint(pm.model, γ[k] <= sum(x[i] for i in Dₖ) + sum(y[(k′,ab)] for k′ in L for ab in Tₖ))
        end
    end
end


@doc raw"""
    constraint_grid_forming_inverter_per_cc_traditional(pm::AbstractUnbalancedPowerModel, nw::Int; relax::Bool=false)

Constrains each connected component of the graph to have only one grid-forming inverter, if the component is enabled

```math
\begin{align}
& \sum_{k \in {\cal B}} y^k_{ab} \le z^{sw}_{ab} &\forall ab \in {\cal E}_{sw} \\
& \sum_{ab \in {\cal T}_k} (1-z^{sw}_{ab}) - |{\cal T}_k| + 1 \le \sum_{i \in {\cal D}_k} z^{inv}_i \le 1 & \forall k \in {\cal B} \\
& S^g_i \le \overline{S}^g_i (\sum_{ab \in {\cal T}_k} z^{sw}_{ab} + \sum_{j \in {\cal D}_k} z^{inv}_j) & \forall i \in {\cal G} \\
& S^g_i \le \overline{S}^g_i (\sum_{ab \in {\cal T}_k} \sum_{k \in {\cal B}} y_{ab}^k + \sum_{j \in {\cal D}_k} z^{sw}_j) & \forall i \in {\cal G} \\
& S^g_i \ge \underline{S}^g_i (\sum_{ab \in {\cal T}_k} z^{sw}_{ab} + \sum_{j \in {\cal D}_k} z^{inv}_j) & \forall i \in {\cal G} \\
& S^g_i \ge \underline{S}^g_i (\sum_{ab \in {\cal T}_k} \sum_{k \in {\cal B}} y_{ab}^k + \sum_{j \in {\cal D}_k} z^{sw}_j) & \forall i \in {\cal G} \\
& y^k_{ab} - (1 - z^{sw}_{ab}) \le \sum_{i \in {\cal D}_k} z^{inv}_i \le  y^k_{ab} + (1 - z^{sw}_{ab}) & \forall k \in {\cal B},\forall ab \in {\cal E}_{sw} \\
& y^{k'}_{dc} - (1 - z^{sw}_{dc}) - (1 - z^{sw}_{ab}) \le y^{k'}_{ab} \le  y^{k'}_{dc} + (1 - z^{sw}_{dc}) + (1 - z^{sw}_{ab}) \\
& ~~~~ \forall k \in {\cal B},\forall k' \in {\cal B}/{k},\forall ab \in {\cal E}_{sw},\forall dc \in {\cal E}_{sw}/{ab} \nonumber \\
& y_{ab}^k \le \sum_{i \in {\cal D}_k} z^{inv}_i & \forall k \in {\cal B},\forall ab \in {\cal E}_{sw} \\
& -z^{sw}_{ab} |{\cal B}| \le f_{ab}^k \le z^{sw}_{ab} |{\cal B}| & \forall k \in {\cal B},\forall ab \in {\cal E}_{sw} \\
& 0 \le \xi_{ab}^k \le 1 & \forall k \in {\cal B},\forall ab \in {\cal E}_{sw} \\
& \sum_{ab \in {\cal T}_k : a = k} f_{ab}^k - \sum_{ab \in {\cal T}_k : b = k} f_{ab}^k + \sum_{ab \in {\cal E}_v^k} \xi_{ab}^k = |{\cal B}| - 1 & \forall k \in {\cal B} \\
& \sum_{ab \in {\cal T}_{k'} : a = k'} f_{ab}^k - \sum_{ab \in {\cal T}_{k'} : b = k'} f_{ab}^k  -  \xi_{kk'}^k = -1, \;\;\; \forall k' \ne k & \forall k \in {\cal B} \\
& y_{ab}^k \le 1 - \xi_{kk'}^k & \forall k' \ne k, ab \in {\cal T}_{k'} \\
\end{align}
```
"""
function constraint_grid_forming_inverter_per_cc_traditional(pm::AbstractUnbalancedPowerModel, nw::Int; relax::Bool=false)
    con_opts = ref(pm, nw, :options, "constraints")

    # Set of base connected components
    L = Set{Int}(ids(pm, nw, :blocks))

    # variable representing if switch ab has 'color' k
    var(pm, nw)[:y_gfm] = Dict{Tuple{Int,Int},JuMP.VariableRef}()
    for k in L
        for ab in ids(pm, nw, :switch)
            var(pm, nw, :y_gfm)[(k,ab)] = JuMP.@variable(
                pm.model,
                base_name="$(nw)_y_gfm[$k,$ab]",
                binary=!relax,
                lower_bound=0,
                upper_bound=1
            )
        end
    end

    # switch pairs to ids and vise-versa
    map_id_pairs = Dict{Int,Tuple{Int,Int}}(id => (ref(pm, nw, :bus_block_map, sw["f_bus"]),ref(pm, nw, :bus_block_map, sw["t_bus"])) for (id,sw) in ref(pm, nw, :switch))

    # set of *virtual* edges between component k and all other components k′
    Φₖ = Dict{Int,Set{Int}}(k => Set{Int}() for k in L)
    map_virtual_pairs_id = Dict{Int,Dict{Tuple{Int,Int},Int}}(k=>Dict{Tuple{Int,Int},Int}() for k in L)

    # Eqs. (9)-(10)
    var(pm, nw)[:f_gfm] = Dict{Tuple{Int,Int},JuMP.VariableRef}()
    var(pm, nw)[:phi_gfm] = Dict{Tuple{Int,Int},JuMP.VariableRef}()
    for kk in L # color
        for ab in ids(pm, nw, :switch)
            f = var(pm, nw, :f_gfm)[(kk,ab)] = JuMP.@variable(
                pm.model,
                base_name="$(nw)_f_gfm[$kk,$ab]"
            )
            JuMP.@constraint(pm.model, f >= -length(ids(pm,nw,:switch))*(var(pm,nw,:switch_state,ab)))
            JuMP.@constraint(pm.model, f <=  length(ids(pm,nw,:switch))*(var(pm,nw,:switch_state,ab)))
        end

        touched = Set{Tuple{Int,Int}}()
        ab = 1

        for k in sort(collect(L)) # fr block
            for k′ in sort(collect(filter(x->x!=k,L))) # to block
                if (k,k′) ∉ touched
                    map_virtual_pairs_id[kk][(k,k′)] = map_virtual_pairs_id[kk][(k′,k)] = ab
                    push!(touched, (k,k′), (k′,k))

                    var(pm, nw, :phi_gfm)[(kk,ab)] = JuMP.@variable(
                        pm.model,
                        base_name="$(nw)_phi_gfm[$kk,$ab]",
                        lower_bound=0,
                        upper_bound=1
                    )

                    ab += 1
                end
            end
        end

        Φₖ[kk] = Set{Int}([map_virtual_pairs_id[kk][(kk,k′)] for k′ in filter(x->x!=kk,L)])
    end

    # variables
    y = var(pm, nw, :y_gfm)
    f = var(pm, nw, :f_gfm)
    ϕ = var(pm, nw, :phi_gfm)
    z = var(pm, nw, :switch_state)
    x = var(pm, nw, :z_inverter)
    γ = var(pm, nw, :z_voltage)

    # voltage sources are always grid-forming
    for ((t,j), z_inv) in x
        if t == :gen && startswith(ref(pm, nw, t, j, "source_id"), "voltage_source")
            JuMP.@constraint(pm.model, z_inv <= var(pm, nw, :z_voltage, ref(pm, nw, t, j, "gen_bus")))
        end
    end

    # Eq. (2)
    # constrain each y to have only one color
    con(pm, nw)[:y_gfm] = Dict{Int,JuMP.ConstraintRef}()
    for ab in ids(pm, nw, :switch)
        con(pm, nw, :y_gfm)[ab] = JuMP.@constraint(pm.model, sum(y[(k,ab)] for k in L) <= z[ab])
    end

    # storage flow upper/lower bounds
    inj_lb, inj_ub = PMD.ref_calc_storage_injection_bounds(ref(pm, nw, :storage), ref(pm, nw, :bus))

    con(pm, nw)[:f_gfm_11] = Dict{Int,JuMP.ConstraintRef}()
    con(pm, nw)[:f_gfm_12] = Dict{Tuple{Int,Int},JuMP.ConstraintRef}()
    con(pm, nw)[:f_gfm_13] = Dict{Tuple{Int,Int,Int},JuMP.ConstraintRef}()
    con(pm, nw)[:f_gfm_15] = Dict{Int,JuMP.ConstraintRef}()

    # Eqs. (3)-(7)
    for k in L
        Dₖ = ref(pm, nw, :block_inverters, k)
        Tₖ = ref(pm, nw, :block_switches, k)

        if !isempty(Dₖ)
            # Eq. (3)
            if !all(isa(x[i], Real) for i in Dₖ)
                if !get(con_opts, "disable-grid-forming-constraint-block-cuts", false)
                    JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) >= sum(1-z[ab] for ab in Tₖ)-length(Tₖ)+γ[first(ref(pm, nw, :blocks, k))])
                    JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) <= γ[first(ref(pm, nw, :blocks, k))])
                else
                    JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) >= sum(1-z[ab] for ab in Tₖ)-length(Tₖ)+1)
                    JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) <= 1)
                end
            elseif all(isa(x[i], Real) && x[i] == 0 for i in Dₖ)
                for (t,j) in Dₖ
                    JuMP.@constraint(pm.model, var(pm, nw, Symbol("z_$(t)"), j) <= sum(var(pm, nw, Symbol("z_$(u)"), l) for k′ in filter(x->x!=k, L) for (u,l) in ref(pm, nw, :block_inverters, k′)))
                end
            end

            # Eq. (4)-(5)
            for (t,j) in Dₖ
                JuMP.@constraint(pm.model, var(pm, nw, Symbol("z_$(t)"), j) <= (sum(z[ab] for ab in Tₖ) + sum(x[i] for i in Dₖ)))
                JuMP.@constraint(pm.model, var(pm, nw, Symbol("z_$(t)"), j) <= (sum(y[(k′,ab)] for k′ in L for ab in Tₖ) + sum(x[i] for i in Dₖ)))
            end
        end

        for ab in Tₖ
            # Eq. (6)
            JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) >= y[(k, ab)] - (1 - z[ab]))
            JuMP.@constraint(pm.model, sum(x[i] for i in Dₖ) <= y[(k, ab)] + (1 - z[ab]))

            for dc in filter(x->x!=ab, Tₖ)
                for k′ in L
                    # Eq. (7)
                    JuMP.@constraint(pm.model, y[(k′,ab)] >= y[(k′,dc)] - (1 - z[dc]) - (1 - z[ab]))
                    JuMP.@constraint(pm.model, y[(k′,ab)] <= y[(k′,dc)] + (1 - z[dc]) + (1 - z[ab]))
                end
            end

            # Eq. (8)
            JuMP.@constraint(pm.model, y[(k,ab)] <= sum(x[i] for i in Dₖ))
        end

        # Eq. (11)
        con(pm, nw, :f_gfm_11)[k] = JuMP.@constraint(pm.model, sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][1] == k, Tₖ)) - sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][2] == k, Tₖ)) + sum(ϕ[(k,ab)] for ab in Φₖ[k]) == length(L) - 1)

        for k′ in filter(x->x!=k, L)
            Tₖ′ = ref(pm, nw, :block_switches, k′)
            kk′ = map_virtual_pairs_id[k][(k,k′)]

            # Eq. (12)
            con(pm, nw, :f_gfm_12)[(k,k′)] = JuMP.@constraint(pm.model, sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][1]==k′, Tₖ′)) - sum(f[(k,ab)] for ab in filter(x->map_id_pairs[x][2]==k′, Tₖ′)) - ϕ[(k,(kk′))] == -1)

            # Eq. (13)
            for ab in Tₖ′
                con(pm, nw, :f_gfm_13)[(k,k′,ab)] = JuMP.@constraint(pm.model, y[k,ab] <= 1 - ϕ[(k,kk′)])
            end
        end
    end
end


@doc raw"""
    constraint_disable_networking(pm::AbstractUnbalancedPowerModel, nw::Int; relax::Bool=false)

Constrains each microgrid to not network with another microgrid, while still allowing them to expand.

```math
\begin{align}
\sum_{k \in |{\cal L}|} y^k_{ab} = 1, \forall ab \in {\cal S}\\
y^k_{ab} - (1 - z_{ab}) \le x_k^{mg} \le  y^k_{ab} + (1 - z_{ab}), \forall k \in {\cal L}\\
y^{k'}_{dc} - (1 - z_{dc}) - (1 - z_{ab}) \le y^{k'}_{ab} \le  y^{k'}_{dc} + (1 - z_{dc}) + (1 - z_{ab}), \forall k \in {\cal L}, \forall ab \in {\cal T}_k, \forall dc \in {\cal T}_k\setminus {ab}
\end{align}
```
"""
function constraint_disable_networking(pm::AbstractUnbalancedPowerModel, nw::Int; relax::Bool=false)
    # Set of base connected components
    L = Set{Int}(ids(pm, nw, :blocks))

    if !(haskey(var(pm, nw), :yy) && !isempty(var(pm, nw, :yy)))
        # variable representing if switch ab has 'color' k
        var(pm, nw)[:yy] = Dict{Tuple{Int,Int},JuMP.VariableRef}()
        for k in L
            for ab in ids(pm, nw, :switch)
                var(pm, nw, :yy)[(k,ab)] = JuMP.@variable(
                    pm.model,
                    base_name="$(nw)_yy",
                    binary=!relax,
                    lower_bound=0,
                    upper_bound=1
                )
            end
        end
    end

    y = var(pm, nw, :yy)
    z = var(pm, nw, :switch_state)
    x = Dict{Int,Int}(n => (n in ids(pm, nw, :microgrid_blocks) ? 1 : 0) for n in ids(pm, nw, :blocks))

    if !(haskey(con(pm, nw), :yy) && !isempty(con(pm, nw, :yy)))
        # constrain each y to have only one color
        con(pm, nw)[:yy] = Dict{Int,JuMP.ConstraintRef}()
        for ab in ids(pm, nw, :switch)
            con(pm, nw, :yy)[ab] = JuMP.@constraint(pm.model, sum(y[(k,ab)] for k in L) == 1)
        end
    end

    # Eqs. (4)-(5)
    for k in L
        Tₖ = ref(pm, nw, :block_switches, k)

        for ab in Tₖ
            # Eq. (4)
            JuMP.@constraint(pm.model, x[k] >= y[(k, ab)] - (1 - z[ab]))
            JuMP.@constraint(pm.model, x[k] <= y[(k, ab)] + (1 - z[ab]))

            for dc in filter(x->x!=ab, Tₖ)
                for k′ in L
                    # Eq. (5)
                    JuMP.@constraint(pm.model, y[(k′,ab)] >= y[(k′,dc)] - (1 - z[dc]) - (1 - z[ab]))
                    JuMP.@constraint(pm.model, y[(k′,ab)] <= y[(k′,dc)] + (1 - z[dc]) + (1 - z[ab]))
                end
            end
        end
    end
end


"""
    constraint_energized_blocks_strictly_increasing(pm::AbstractUnbalancedPowerModel, n_1::Int, n_2::Int)

Constraint to ensure that the number of energized load blocks from one timestep to another is strictly increasing
and that once energized, a load block cannot be shed in a later timestep.
"""
function constraint_energized_blocks_strictly_increasing(pm::AbstractUnbalancedPowerModel, n_1::Int, n_2::Int)
    for block_id in ids(pm, n_2, :blocks)
        z_block_n1 = var(pm, n_1, :z_block, block_id)
        z_block_n2 = var(pm, n_2, :z_block, block_id)

        JuMP.@constraint(pm.model, z_block_n2 >= z_block_n1)
    end
end
