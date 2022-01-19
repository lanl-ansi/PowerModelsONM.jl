@doc raw"""
    constraint_mc_switch_state_on_off(pm::AbstractUnbalancedActivePowerSwitchModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)

No voltage variables, do nothing
"""
function PowerModelsDistribution.constraint_mc_switch_state_on_off(pm::AbstractUnbalancedNFASwitchModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)
end


@doc raw"""
    constraint_mc_switch_power_on_off(pm::AbstractSwitchModels, nw::Int, f_idx::Tuple{Int,Int,Int}; relax::Bool=false)

Linear switch power on/off constraint for Active Power Only Models. If `relax`, an [indicator constraint](https://jump.dev/JuMP.jl/stable/manual/constraints/#Indicator-constraints) is used.

```math
\begin{align}
& P^{sw}_{i,c} \leq P^{swu}_{i,c} z^{sw}_i\ \forall i \in P,\forall c \in C \\
& P^{sw}_{i,c} \geq -P^{swu}_{i,c} z^{sw}_i\ \forall i \in P,\forall c \in C
\end{align}
```
"""
function PowerModelsDistribution.constraint_mc_switch_power_on_off(pm::AbstractUnbalancedNFASwitchModel, nw::Int, f_idx::Tuple{Int,Int,Int}; relax::Bool=false)
    i, f_bus, t_bus = f_idx

    psw = var(pm, nw, :psw, f_idx)

    z = var(pm, nw, :switch_state, i)

    connections = ref(pm, nw, :switch, i)["f_connections"]

    switch = ref(pm, nw, :switch, i)

    rating = min.(fill(100.0, length(connections)), PMD._calc_branch_power_max_frto(switch, ref(pm, nw, :bus, f_bus), ref(pm, nw, :bus, t_bus))...)

    for (idx, c) in enumerate(connections)
        if relax
            JuMP.@constraint(pm.model, psw[c] <=  rating[idx] * z)
            JuMP.@constraint(pm.model, psw[c] >= -rating[idx] * z)
        else
            JuMP.@constraint(pm.model, !z => {psw[c] == 0.0})
        end
    end
end


"do nothing, no voltage variables"
function PowerModelsDistribution.variable_mc_bus_voltage_on_off(pm::AbstractUnbalancedNFASwitchModel; nw::Int=nw_id_default)
end


"do nothing, no voltage variables"
function PowerModelsDistribution.constraint_mc_bus_voltage_on_off(pm::AbstractUnbalancedNFASwitchModel; nw::Int=nw_id_default)
end


"on/off constraint for generators"
function PowerModelsDistribution.constraint_mc_gen_power_on_off(pm::AbstractUnbalancedNFASwitchModel, nw::Int64, i::Int64, connections::Vector{Int64}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, ::Vector{<:Real}, ::Vector{<:Real})
    pg = var(pm, nw, :pg, i)

    z_block = var(pm, nw, :z_block, ref(pm, nw, :gen_block_map, i))

    for (idx, c) in enumerate(connections)
        if isfinite(pmax[idx])
            JuMP.@constraint(pm.model, pg[c] <= pmax[idx]*z_block)
        end

        if isfinite(pmin[idx])
            JuMP.@constraint(pm.model, pg[c] >= pmin[idx]*z_block)
        end
    end
end


@doc raw"""
"""
function PowerModelsDistribution.constraint_mc_power_balance_shed(pm::AbstractUnbalancedNFASwitchModel, nw::Int, i::Int, terminals::Vector{Int}, grounded::Vector{Bool}, bus_arcs::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_sw::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_trans::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_gens::Vector{Tuple{Int,Vector{Int}}}, bus_storage::Vector{Tuple{Int,Vector{Int}}}, bus_loads::Vector{Tuple{Int,Vector{Int}}}, bus_shunts::Vector{Tuple{Int,Vector{Int}}})
    p   = get(var(pm, nw),      :p,  Dict()); PMD._check_var_keys(p,   bus_arcs, "active power", "branch")
    psw = get(var(pm, nw),    :psw,  Dict()); PMD._check_var_keys(psw, bus_arcs_sw, "active power", "switch")
    pt  = get(var(pm, nw),     :pt,  Dict()); PMD._check_var_keys(pt,  bus_arcs_trans, "active power", "transformer")
    pg  = get(var(pm, nw),     :pg,  Dict()); PMD._check_var_keys(pg,  bus_gens, "active power", "generator")
    ps  = get(var(pm, nw),     :ps,  Dict()); PMD._check_var_keys(ps,  bus_storage, "active power", "storage")
    pd  = get(var(pm, nw), :pd_bus,  Dict()); PMD._check_var_keys(pd,  bus_loads, "active power", "load")
    z_block = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, i))

    Gt, _ = PMD._build_bus_shunt_matrices(pm, nw, terminals, bus_shunts)

    cstr_p = []

    ungrounded_terminals = [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]

    pd_zblock = Dict{Int,JuMP.Containers.DenseAxisArray{JuMP.VariableRef}}(l => JuMP.@variable(pm.model, [c in conns], base_name="$(nw)_pd_zblock_$(l)") for (l,conns) in bus_loads)

    for (l,conns) in bus_loads
        for c in conns
            _IM.relaxation_product(pm.model, pd[l][c], z_block, pd_zblock[l][c])
        end
    end

    for (idx, t) in ungrounded_terminals
        cp = JuMP.@constraint(pm.model,
            sum(p[a][t] for (a, conns) in bus_arcs if t in conns)
            + sum(psw[a_sw][t] for (a_sw, conns) in bus_arcs_sw if t in conns)
            + sum(pt[a_trans][t] for (a_trans, conns) in bus_arcs_trans if t in conns)
            ==
            sum(pg[g][t] for (g, conns) in bus_gens if t in conns)
            - sum(ps[s][t] for (s, conns) in bus_storage if t in conns)
            - sum(pd_zblock[l][t] for (l, conns) in bus_loads if t in conns)
            - LinearAlgebra.diag(Gt)[idx]
        )
        push!(cstr_p, cp)
    end
    # omit reactive constraint

    con(pm, nw, :lam_kcl_r)[i] = cstr_p
    con(pm, nw, :lam_kcl_i)[i] = []

    if _IM.report_duals(pm)
        sol(pm, nw, :bus, i)[:lam_kcl_r] = cstr_p
        sol(pm, nw, :bus, i)[:lam_kcl_i] = []
    end
end


"""
    constraint_mc_storage_on_off(pm::PMD.NFAUSwitchPowerModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Real, pmax::Real, qmin::Real, qmax::Real, charge_ub::Real, discharge_ub::Real)

on/off constraint for storage
"""
function PowerModelsDistribution.constraint_mc_storage_on_off(pm::AbstractUnbalancedNFASwitchModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Real, pmax::Real, qmin::Real, qmax::Real, charge_ub::Real, discharge_ub::Real)
    z_block = var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i))

    ps = [var(pm, nw, :ps, i)[c] for c in connections]

    JuMP.@constraint(pm.model, sum(ps) <= z_block*pmax)
    JuMP.@constraint(pm.model, sum(ps) >= z_block*pmin)
end


"""
    constraint_mc_storage_losses_on_off(pm::NFAUSwitchPowerModel, i::Int; nw::Int=nw_id_default)

Neglects the active and reactive loss terms associated with the squared current magnitude.
"""
function constraint_mc_storage_losses_on_off(pm::AbstractUnbalancedNFASwitchModel, i::Int; nw::Int=nw_id_default)
    storage = ref(pm, nw, :storage, i)
    z_block = var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i))

    p_loss = storage["p_loss"]
    conductors = storage["connections"]

    ps = var(pm, nw, :ps, i)
    sc = var(pm, nw, :sc, i)
    sd = var(pm, nw, :sd, i)

    JuMP.@constraint(pm.model, sum(ps[c] for c in conductors) + (sd - sc) == 0.0)
end


@doc raw"""
    constraint_mc_transformer_power(pm::NFAUSwitchPowerModel, i::Int; nw::Int=nw_id_default)

transformer active power only constraint pf=-pt

```math
p_f[fc] == -pt[tc]
```
"""
function constraint_mc_transformer_power_on_off(pm::AbstractUnbalancedNFASwitchModel, i::Int; nw::Int=nw_id_default, fix_taps::Bool=false)
    transformer = ref(pm, nw, :transformer, i)

    pf = var(pm, nw, :pt, (i, transformer["f_bus"], transformer["t_bus"]))
    pt = var(pm, nw, :pt, (i, transformer["t_bus"], transformer["f_bus"]))

    for (fc, tc) in zip(transformer["f_connections"],transformer["t_connections"])
        JuMP.@constraint(pm.model, pf[fc] == -pt[tc])
    end
end
