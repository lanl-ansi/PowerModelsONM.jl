@doc raw"""
    constraint_mc_switch_voltage_open_close(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int})

No voltage variables, do nothing
"""
function constraint_mc_switch_voltage_open_close(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int})
end


@doc raw"""
    constraint_mc_switch_power_open_close(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int})

Linear switch power on/off constraint for Active Power Only Models. If `relax`, an [indicator constraint](https://jump.dev/JuMP.jl/stable/manual/constraints/#Indicator-constraints) is used.

```math
\begin{align}
& P^{sw}_{i,c} \leq P^{swu}_{i,c} z^{sw}_i\ \forall i \in P,\forall c \in C \\
& P^{sw}_{i,c} \geq -P^{swu}_{i,c} z^{sw}_i\ \forall i \in P,\forall c \in C
\end{align}
```
"""
function constraint_mc_switch_power_open_close(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int})
    psw = var(pm, nw, :psw, (i, f_bus, t_bus))

    state = var(pm, nw, :switch_state, i)

    rating = min.(fill(1.0, length(f_connections)), PMD._calc_branch_power_max_frto(ref(pm, nw, :switch, i), ref(pm, nw, :bus, f_bus), ref(pm, nw, :bus, t_bus))...)

    for (idx, c) in enumerate(f_connections)
        JuMP.@constraint(pm.model, psw[c] <=  rating[idx] * state)
        JuMP.@constraint(pm.model, psw[c] >= -rating[idx] * state)

        # Indicator constraint version, for reference
        # JuMP.@constraint(pm.model, !state => {psw[c] == 0.0})
    end
end


"do nothing, no voltage variables"
function constraint_mc_bus_voltage_block_on_off(::PMD.AbstractUnbalancedNFAModel, ::Int, ::Int, ::Vector{<:Real}, ::Vector{<:Real})
end


"do nothing, no voltage variables"
function constraint_mc_bus_voltage_traditional_on_off(::PMD.AbstractUnbalancedNFAModel, ::Int, ::Int, ::Vector{<:Real}, ::Vector{<:Real})
end


"""
    constraint_mc_generator_power_block_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, ::Vector{<:Real}, ::Vector{<:Real})

on/off block constraint for generators for NFA model
"""
function constraint_mc_generator_power_block_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, connections::Vector{<:Int}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, qmin::Vector{<:Real}, qmax::Vector{<:Real})
    pg = var(pm, nw, :pg, i)

    z_block = var(pm, nw, :z_block, ref(pm, nw, :gen_block_map, i))

    for (idx, c) in enumerate(connections)
        isfinite(pmax[idx]) && JuMP.@constraint(pm.model, pg[c] <= pmax[idx]*z_block)
        isfinite(pmin[idx]) && JuMP.@constraint(pm.model, pg[c] >= pmin[idx]*z_block)
    end
end


"""
    constraint_mc_generator_power_traditional_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, ::Vector{<:Real}, ::Vector{<:Real})

on/off traditional constraint for generators for NFAU form
"""
function constraint_mc_generator_power_traditional_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, connections::Vector{<:Int}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, qmin::Vector{<:Real}, qmax::Vector{<:Real})
    pg = var(pm, nw, :pg, i)

    z_gen = var(pm, nw, :z_gen, i)

    for (idx, c) in enumerate(connections)
        isfinite(pmax[idx]) && JuMP.@constraint(pm.model, pg[c] <= pmax[idx]*z_gen)
        isfinite(pmin[idx]) && JuMP.@constraint(pm.model, pg[c] >= pmin[idx]*z_gen)
    end
end


@doc raw"""
    constraint_mc_power_balance_shed_block(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int,
        terminals::Vector{Int}, grounded::Vector{Bool}, bus_arcs::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}},
        bus_arcs_sw::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_trans::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}},
        bus_gens::Vector{Tuple{Int,Vector{Int}}}, bus_storage::Vector{Tuple{Int,Vector{Int}}},
        bus_loads::Vector{Tuple{Int,Vector{Int}}}, bus_shunts::Vector{Tuple{Int,Vector{Int}}}
    )

KCL for load shed problem with transformers (NFAU Form)
"""
function constraint_mc_power_balance_shed_block(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, terminals::Vector{Int}, grounded::Vector{Bool}, bus_arcs::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_sw::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_trans::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_gens::Vector{Tuple{Int,Vector{Int}}}, bus_storage::Vector{Tuple{Int,Vector{Int}}}, bus_loads::Vector{Tuple{Int,Vector{Int}}}, bus_shunts::Vector{Tuple{Int,Vector{Int}}})
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
    constraint_mc_storage_block_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Real, pmax::Real, ::Real, ::Real, ::Real, ::Real)

block on/off constraint for storage in NFAU Form.
"""
function constraint_mc_storage_block_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Real, pmax::Real, ::Real, ::Real, ::Real, ::Real)
    z_block = var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i))

    ps = [var(pm, nw, :ps, i)[c] for c in connections]

    isfinite(pmin) && JuMP.@constraint(pm.model, sum(ps) >= z_block*pmin)
    isfinite(pmax) && JuMP.@constraint(pm.model, sum(ps) <= z_block*pmax)
end


"""
    constraint_mc_storage_traditional_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Real, pmax::Real, ::Real, ::Real, ::Real, ::Real)

traditional on/off constraint for storage in NFAU Form.
"""
function constraint_mc_storage_traditional_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Real, pmax::Real, ::Real, ::Real, ::Real, ::Real)
    z_storage = var(pm, nw, :z_storage, i)

    ps = [var(pm, nw, :ps, i)[c] for c in connections]

    isfinite(pmin) && JuMP.@constraint(pm.model, sum(ps) >= z_storage*pmin)
    isfinite(pmax) && JuMP.@constraint(pm.model, sum(ps) <= z_storage*pmax)
end


"""
    constraint_mc_storage_losses_block_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, bus::Int, connections::Vector{Int}, ::Real, ::Real, ::Real, ::Real)

Neglects all losses (lossless model), NFAU Form.
"""
function constraint_mc_storage_losses_block_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, bus::Int, connections::Vector{Int}, ::Real, ::Real, ::Real, ::Real)
    z_block = var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i))

    ps = var(pm, nw, :ps, i)
    sc = var(pm, nw, :sc, i)
    sd = var(pm, nw, :sd, i)

    JuMP.@constraint(pm.model, sum(ps[c] for c in connections) + (sd - sc) == 0.0 * z_block)
end


"""
    constraint_mc_storage_losses_traditional_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, bus::Int, connections::Vector{Int}, ::Real, ::Real, ::Real, ::Real)

Neglects all losses (lossless model), NFAU Form.
"""
function constraint_mc_storage_losses_traditional_on_off(pm::PMD.AbstractUnbalancedNFAModel, nw::Int, i::Int, bus::Int, connections::Vector{Int}, ::Real, ::Real, ::Real, ::Real)
    storage = ref(pm, nw, :storage, i)
    z_storage = var(pm, nw, :z_storage, i)

    ps = var(pm, nw, :ps, i)
    sc = var(pm, nw, :sc, i)
    sd = var(pm, nw, :sd, i)

    JuMP.@constraint(pm.model, sum(ps[c] for c in connections) + (sd - sc) == 0.0 * z_storage)
end


@doc raw"""
    constraint_mc_transformer_power_block_on_off(pm::PMD.AbstractUnbalancedNFAModel, i::Int; nw::Int=nw_id_default, fix_taps::Bool=false)

transformer active power only constraint pf=-pt

```math
p_f[fc] == -pt[tc]
```
"""
function constraint_mc_transformer_power_block_on_off(pm::PMD.AbstractUnbalancedNFAModel, i::Int; nw::Int=nw_id_default, fix_taps::Bool=false)
    transformer = ref(pm, nw, :transformer, i)

    pf = var(pm, nw, :pt, (i, transformer["f_bus"], transformer["t_bus"]))
    pt = var(pm, nw, :pt, (i, transformer["t_bus"], transformer["f_bus"]))

    for (fc, tc) in zip(transformer["f_connections"],transformer["t_connections"])
        JuMP.@constraint(pm.model, pf[fc] == -pt[tc])
    end
end

"""
"""
constraint_mc_transformer_power_traditional_on_off(pm::PMD.AbstractUnbalancedNFAModel, i::Int; nw::Int=nw_id_default, fix_taps::Bool=false) = constraint_mc_transformer_power_block_on_off(pm, i; nw=nw, fix_taps=fix_taps)


@doc raw"""
    constraint_storage_complementarity_mi_block_on_off(pm::Union{PMD.LPUBFDiagModel,PMD.AbstractUnbalancedNFAModel}, n::Int, i::Int, charge_ub::Real, discharge_ub::Real)

linear storage complementarity mi constraint for block mld problem

math```
sc_{on} + sd_{on} == z_{block}
```
"""
function constraint_storage_complementarity_mi_block_on_off(pm::PMD.AbstractUnbalancedNFAModel, n::Int, i::Int, charge_ub::Real, discharge_ub::Real)
    sc = var(pm, n, :sc, i)
    sd = var(pm, n, :sd, i)
    sc_on = var(pm, n, :sc_on, i)
    sd_on = var(pm, n, :sd_on, i)

    z_block = var(pm, n, :z_block, ref(pm, n, :storage_block_map, i))

    JuMP.@constraint(pm.model, sc_on + sd_on == z_block)
    JuMP.@constraint(pm.model, sc_on*charge_ub >= sc)
    JuMP.@constraint(pm.model, sd_on*discharge_ub >= sd)
end


@doc raw"""
    constraint_storage_complementarity_mi_traditional_on_off(
        pm::Union{PMD.LPUBFDiagModel,PMD.AbstractUnbalancedNFAModel},
        n::Int,
        i::Int,
        charge_ub::Real,
        discharge_ub::Real
    )

linear storage complementarity mi constraint for traditional mld problem

math```
sc_{on} + sd_{on} == z_{block}
```
"""
function constraint_storage_complementarity_mi_traditional_on_off(pm::PMD.AbstractUnbalancedNFAModel, n::Int, i::Int, charge_ub::Real, discharge_ub::Real)
    sc = var(pm, n, :sc, i)
    sd = var(pm, n, :sd, i)
    sc_on = var(pm, n, :sc_on, i)
    sd_on = var(pm, n, :sd_on, i)

    z_storage = var(pm, n, :z_storage, i)

    JuMP.@constraint(pm.model, sc_on + sd_on == z_storage)
    JuMP.@constraint(pm.model, sc_on*charge_ub >= sc)
    JuMP.@constraint(pm.model, sd_on*discharge_ub >= sd)
end


"nothing to do, no voltage angle variables"
function constraint_mc_inverter_theta_ref(::PMD.AbstractUnbalancedNFAModel, ::Int; nw::Int=nw_id_default)
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
inverters only. Requires z_inverter variable. Variant for Active Power Only models.

```math
S^{strg}_{i,c} \geq S^{strg}_{i,d} - f^{unbal} \left( -d^{on}_i S^{strg}_{i,d} + c^{on}_i S^{strg}_{i,d} \right) \forall c,d \in C
```
"""
function constraint_mc_storage_phase_unbalance_grid_following(pm::PMD.AbstractUnbalancedActivePowerModel, nw::Int, i::Int, connections::Vector{Int}, unbalance_factor::Real)
    z_inverter = var(pm, nw, :z_inverter, (:storage, i))

    ps = var(pm, nw, :ps, i)

    sc_on = var(pm, nw, :sc_on, i)  # ==1 charging (p,q > 0)
    sd_on = var(pm, nw, :sd_on, i)  # ==1 discharging (p,q < 0)

    sd_on_ps = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sd_on_ps_$(i)")
    sc_on_ps = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sc_on_ps_$(i)")
    for c in connections
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sd_on, ps[c], sd_on_ps[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sc_on, ps[c], sc_on_ps[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
    end

    ps_zinverter = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_ps_zinverter_$(i)")
    for c in connections
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, z_inverter, ps[c], ps_zinverter[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
    end

    sd_on_ps_zinverter = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sd_on_ps_zinverter_$(i)")
    sc_on_ps_zinverter = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sc_on_ps_zinverter_$(i)")
    for c in connections
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, z_inverter, sd_on_ps[c], sd_on_ps_zinverter[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
        PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, z_inverter, sc_on_ps[c], sc_on_ps_zinverter[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
    end

    for (idx,c) in enumerate(connections)
        if idx < length(connections)
            for d in connections[idx+1:end]
                JuMP.@constraint(pm.model, ps[c]-ps_zinverter[c] >= ps[d] - unbalance_factor*(-1*sd_on_ps[d] + 1*sc_on_ps[d]) - ps_zinverter[d] + unbalance_factor*(-1*sd_on_ps_zinverter[d] + 1*sc_on_ps_zinverter[d]))
                JuMP.@constraint(pm.model, ps[c]-ps_zinverter[c] <= ps[d] + unbalance_factor*(-1*sd_on_ps[d] + 1*sc_on_ps[d]) - ps_zinverter[d] - unbalance_factor*(-1*sd_on_ps_zinverter[d] + 1*sc_on_ps_zinverter[d]))
            end
        end
    end
end
