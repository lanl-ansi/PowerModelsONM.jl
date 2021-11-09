@doc raw"""
    constraint_mc_switch_state_on_off(pm::PMD.LPUBFDiagModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)

Linear switch power on/off constraint for LPUBFDiagModel. If `relax`, an [indicator constraint](https://jump.dev/JuMP.jl/stable/manual/constraints/#Indicator-constraints) is used.

```math
\begin{align}
& w^{fr}_{i,c} - w^{to}_{i,c} \leq \left ( v^u_{i,c} \right )^2 \left ( 1 - z^{sw}_i \right )\ \forall i \in S,\forall c \in C \\
& w^{fr}_{i,c} - w^{to}_{i,c} \geq -\left ( v^u_{i,c}\right )^2 \left ( 1 - z^{sw}_i \right )\ \forall i \in S,\forall c \in C
\end{align}
```
"""
function PowerModelsDistribution.constraint_mc_switch_state_on_off(pm::PMD.LPUBFDiagModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)
    w_fr = PMD.var(pm, nw, :w, f_bus)
    w_to = PMD.var(pm, nw, :w, t_bus)

    f_bus = PMD.ref(pm, nw, :bus, f_bus)
    t_bus = PMD.ref(pm, nw, :bus, t_bus)

    f_vmax = f_bus["vmax"][[findfirst(isequal(c), f_bus["terminals"]) for c in f_connections]]
    t_vmax = t_bus["vmax"][[findfirst(isequal(c), t_bus["terminals"]) for c in t_connections]]

    vmax = min.(fill(2.0, length(f_bus["vmax"])), f_vmax, t_vmax)

    z = PMD.var(pm, nw, :switch_state, i)

    for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
        if relax
            JuMP.@constraint(pm.model, w_fr[fc] - w_to[tc] <=  vmax[idx].^2 * (1-z))
            JuMP.@constraint(pm.model, w_fr[fc] - w_to[tc] >= -vmax[idx].^2 * (1-z))
        else
            JuMP.@constraint(pm.model, z => {w_fr[fc] == w_to[tc]})
        end
    end
end


@doc raw"""
    constraint_mc_switch_power_on_off(pm::PMD.LPUBFDiagModel, nw::Int, f_idx::Tuple{Int,Int,Int}; relax::Bool=false)

Linear switch power on/off constraint for LPUBFDiagModel. If `relax`, an [indicator constraint](https://jump.dev/JuMP.jl/stable/manual/constraints/#Indicator-constraints) is used.

```math
\begin{align}
& S^{sw}_{i,c} \leq S^{swu}_{i,c} z^{sw}_i\ \forall i \in S,\forall c \in C \\
& S^{sw}_{i,c} \geq -S^{swu}_{i,c} z^{sw}_i\ \forall i \in S,\forall c \in C
\end{align}
```
"""
function PowerModelsDistribution.constraint_mc_switch_power_on_off(pm::PMD.LPUBFDiagModel, nw::Int, f_idx::Tuple{Int,Int,Int}; relax::Bool=false)
    i, f_bus, t_bus = f_idx

    psw = PMD.var(pm, nw, :psw, f_idx)
    qsw = PMD.var(pm, nw, :qsw, f_idx)

    z = PMD.var(pm, nw, :switch_state, i)

    connections = PMD.ref(pm, nw, :switch, i)["f_connections"]

    switch = PMD.ref(pm, nw, :switch, i)

    rating = min.(fill(1.0, length(connections)), PMD._calc_branch_power_max_frto(switch, PMD.ref(pm, nw, :bus, f_bus), PMD.ref(pm, nw, :bus, t_bus))...)

    for (idx, c) in enumerate(connections)
        if relax
            JuMP.@constraint(pm.model, psw[c] <=  rating[idx] * z)
            JuMP.@constraint(pm.model, psw[c] >= -rating[idx] * z)
            JuMP.@constraint(pm.model, qsw[c] <=  rating[idx] * z)
            JuMP.@constraint(pm.model, qsw[c] >= -rating[idx] * z)
        else
            JuMP.@constraint(pm.model, !z => {psw[c] == 0.0})
            JuMP.@constraint(pm.model, !z => {qsw[c] == 0.0})
        end
    end
end


@doc raw"""
    constraint_mc_switch_state_on_off(pm::PMD.AbstractUnbalancedActivePowerModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)

No voltage variables, do nothing
"""
function PowerModelsDistribution.constraint_mc_switch_state_on_off(pm::PMD.AbstractUnbalancedActivePowerModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)
end


@doc raw"""
    constraint_mc_switch_power_on_off(pm::PMD.AbstractUnbalancedActivePowerModel, nw::Int, f_idx::Tuple{Int,Int,Int}; relax::Bool=false)

Linear switch power on/off constraint for Active Power Only Models. If `relax`, an [indicator constraint](https://jump.dev/JuMP.jl/stable/manual/constraints/#Indicator-constraints) is used.

```math
\begin{align}
& P^{sw}_{i,c} \leq P^{swu}_{i,c} z^{sw}_i\ \forall i \in P,\forall c \in C \\
& P^{sw}_{i,c} \geq -P^{swu}_{i,c} z^{sw}_i\ \forall i \in P,\forall c \in C
\end{align}
```
"""
function PowerModelsDistribution.constraint_mc_switch_power_on_off(pm::PMD.AbstractUnbalancedActivePowerModel, nw::Int, f_idx::Tuple{Int,Int,Int}; relax::Bool=false)
    i, f_bus, t_bus = f_idx

    psw = PMD.var(pm, nw, :psw, f_idx)

    z = PMD.var(pm, nw, :switch_state, i)

    connections = PMD.ref(pm, nw, :switch, i)["f_connections"]

    switch = PMD.ref(pm, nw, :switch, i)

    rating = min.(fill(100.0, length(connections)), PMD._calc_branch_power_max_frto(switch, PMD.ref(pm, nw, :bus, f_bus), PMD.ref(pm, nw, :bus, t_bus))...)

    for (idx, c) in enumerate(connections)
        if relax
            JuMP.@constraint(pm.model, psw[c] <=  rating[idx] * z)
            JuMP.@constraint(pm.model, psw[c] >= -rating[idx] * z)
        else
            JuMP.@constraint(pm.model, !z => {psw[c] == 0.0})
        end
    end
end


"helper function for pd/qd variables"
function JuMP.lower_bound(x::Float64)
    return x
end


"helper function for pd/qd variables"
function JuMP.upper_bound(x::Float64)
    return x
end


"KCL for load shed problem with transformers (AbstractWForms)"
function PowerModelsDistribution.constraint_mc_power_balance_shed(pm::PMD.LPUBFDiagModel, nw::Int, i::Int, terminals::Vector{Int}, grounded::Vector{Bool}, bus_arcs::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_sw::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_trans::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_gens::Vector{Tuple{Int,Vector{Int}}}, bus_storage::Vector{Tuple{Int,Vector{Int}}}, bus_loads::Vector{Tuple{Int,Vector{Int}}}, bus_shunts::Vector{Tuple{Int,Vector{Int}}})
    w        = PMD.var(pm, nw, :w, i)
    p        = get(PMD.var(pm, nw),    :p, Dict()); PMD._check_var_keys(p, bus_arcs, "active power", "branch")
    q        = get(PMD.var(pm, nw),    :q, Dict()); PMD._check_var_keys(q, bus_arcs, "reactive power", "branch")
    pg       = get(PMD.var(pm, nw),   :pg, Dict()); PMD._check_var_keys(pg, bus_gens, "active power", "generator")
    qg       = get(PMD.var(pm, nw),   :qg, Dict()); PMD._check_var_keys(qg, bus_gens, "reactive power", "generator")
    ps       = get(PMD.var(pm, nw),   :ps, Dict()); PMD._check_var_keys(ps, bus_storage, "active power", "storage")
    qs       = get(PMD.var(pm, nw),   :qs, Dict()); PMD._check_var_keys(qs, bus_storage, "reactive power", "storage")
    psw      = get(PMD.var(pm, nw),  :psw, Dict()); PMD._check_var_keys(psw, bus_arcs_sw, "active power", "switch")
    qsw      = get(PMD.var(pm, nw),  :qsw, Dict()); PMD._check_var_keys(qsw, bus_arcs_sw, "reactive power", "switch")
    pt       = get(PMD.var(pm, nw),   :pt, Dict()); PMD._check_var_keys(pt, bus_arcs_trans, "active power", "transformer")
    qt       = get(PMD.var(pm, nw),   :qt, Dict()); PMD._check_var_keys(qt, bus_arcs_trans, "reactive power", "transformer")
    pd       = get(PMD.var(pm, nw), :pd_bus,  Dict()); PMD._check_var_keys(pd,  bus_loads, "active power", "load")
    qd       = get(PMD.var(pm, nw), :qd_bus,  Dict()); PMD._check_var_keys(qd,  bus_loads, "reactive power", "load")
    z_block  = PMD.var(pm, nw, :z_block, PMD.ref(pm, nw, :bus_block_map, i))

    uncontrolled_shunts = Tuple{Int,Vector{Int}}[]
    controlled_shunts = Tuple{Int,Vector{Int}}[]

    if !isempty(bus_shunts) && any(haskey(PMD.ref(pm, nw, :shunt, sh), "controls") for (sh, conns) in bus_shunts)
        for (sh, conns) in bus_shunts
            if haskey(PMD.ref(pm, nw, :shunt, sh), "controls")
                push!(controlled_shunts, (sh,conns))
            else
                push!(uncontrolled_shunts, (sh, conns))
            end
        end
    else
        uncontrolled_shunts = bus_shunts
    end

    Gt, _ = PMD._build_bus_shunt_matrices(pm, nw, terminals, bus_shunts)
    _, Bt = PMD._build_bus_shunt_matrices(pm, nw, terminals, uncontrolled_shunts)

    cstr_p = []
    cstr_q = []

    ungrounded_terminals = [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]

    pd_zblock = Dict{Int,PMD.JuMP.Containers.DenseAxisArray{PMD.JuMP.VariableRef}}(l => PMD.JuMP.@variable(pm.model, [c in conns], base_name="$(nw)_pd_zblock_$(l)") for (l,conns) in bus_loads)
    qd_zblock = Dict{Int,PMD.JuMP.Containers.DenseAxisArray{PMD.JuMP.VariableRef}}(l => PMD.JuMP.@variable(pm.model, [c in conns], base_name="$(nw)_qd_zblock_$(l)") for (l,conns) in bus_loads)

    for (l,conns) in bus_loads
        for c in conns
            PMD.JuMP.@constraint(pm.model, pd_zblock[l][c] >= PMD.JuMP.lower_bound(pd[l][c]) * z_block)
            PMD.JuMP.@constraint(pm.model, pd_zblock[l][c] >= PMD.JuMP.upper_bound(pd[l][c]) * z_block + pd[l][c] - PMD.JuMP.upper_bound(pd[l][c]))
            PMD.JuMP.@constraint(pm.model, pd_zblock[l][c] <= PMD.JuMP.upper_bound(pd[l][c]) * z_block)
            PMD.JuMP.@constraint(pm.model, pd_zblock[l][c] <= pd[l][c] + PMD.JuMP.lower_bound(pd[l][c]) * z_block - PMD.JuMP.lower_bound(pd[l][c]))

            PMD.JuMP.@constraint(pm.model, qd_zblock[l][c] >= PMD.JuMP.lower_bound(qd[l][c]) * z_block)
            PMD.JuMP.@constraint(pm.model, qd_zblock[l][c] >= PMD.JuMP.upper_bound(qd[l][c]) * z_block + qd[l][c] - PMD.JuMP.upper_bound(qd[l][c]))
            PMD.JuMP.@constraint(pm.model, qd_zblock[l][c] <= PMD.JuMP.upper_bound(qd[l][c]) * z_block)
            PMD.JuMP.@constraint(pm.model, qd_zblock[l][c] <= qd[l][c] + PMD.JuMP.lower_bound(qd[l][c]) * z_block - PMD.JuMP.lower_bound(qd[l][c]))
        end
    end

    for (idx, t) in ungrounded_terminals
        cp = PMD.JuMP.@constraint(pm.model,
            sum(p[a][t] for (a, conns) in bus_arcs if t in conns)
            + sum(psw[a_sw][t] for (a_sw, conns) in bus_arcs_sw if t in conns)
            + sum(pt[a_trans][t] for (a_trans, conns) in bus_arcs_trans if t in conns)
            ==
            sum(pg[g][t] for (g, conns) in bus_gens if t in conns)
            - sum(ps[s][t] for (s, conns) in bus_storage if t in conns)
            - sum(pd_zblock[l][t] for (l, conns) in bus_loads if t in conns)
            - sum((w[t] * LinearAlgebra.diag(Gt')[idx]) for (sh, conns) in bus_shunts if t in conns)
        )
        push!(cstr_p, cp)

        for (sh, sh_conns) in controlled_shunts
            if t in sh_conns
                cq_cap = PMD.var(pm, nw, :capacitor_reactive_power, sh)[t]
                cap_state = PMD.var(pm, nw, :capacitor_state, sh)[t]
                bs = PMD.diag(PMD.ref(pm, nw, :shunt, sh, "bs"))[findfirst(isequal(t), sh_conns)]
                w_min = PMD.JuMP.lower_bound(w[t])
                w_max = PMD.JuMP.upper_bound(w[t])

                # tie to z_block
                PMD.JuMP.@constraint(pm.model, cap_state <= z_block)

                # McCormick envelope constraints
                PMD.JuMP.@constraint(pm.model, cq_cap ≥ bs*cap_state*w_min)
                PMD.JuMP.@constraint(pm.model, cq_cap ≥ bs*w[t] + bs*cap_state*w_max - bs*w_max*z_block)
                PMD.JuMP.@constraint(pm.model, cq_cap ≤ bs*cap_state*w_max)
                PMD.JuMP.@constraint(pm.model, cq_cap ≤ bs*w[t] + bs*cap_state*w_min - bs*w_min*z_block)
            end
        end

        cq = PMD.JuMP.@constraint(pm.model,
            sum(q[a][t] for (a, conns) in bus_arcs if t in conns)
            + sum(qsw[a_sw][t] for (a_sw, conns) in bus_arcs_sw if t in conns)
            + sum(qt[a_trans][t] for (a_trans, conns) in bus_arcs_trans if t in conns)
            ==
            sum(qg[g][t] for (g, conns) in bus_gens if t in conns)
            - sum(qs[s][t] for (s, conns) in bus_storage if t in conns)
            - sum(qd_zblock[l][t] for (l, conns) in bus_loads if t in conns)
            - sum((-w[t] * LinearAlgebra.diag(Bt')[idx]) for (sh, conns) in uncontrolled_shunts if t in conns)
            - sum(-PMD.var(pm, nw, :capacitor_reactive_power, sh)[t] for (sh, conns) in controlled_shunts if t in conns)
        )
        push!(cstr_q, cq)
    end

    PMD.con(pm, nw, :lam_kcl_r)[i] = cstr_p
    PMD.con(pm, nw, :lam_kcl_i)[i] = cstr_q

    if PMD._IM.report_duals(pm)
        PMD.sol(pm, nw, :bus, i)[:lam_kcl_r] = cstr_p
        PMD.sol(pm, nw, :bus, i)[:lam_kcl_i] = cstr_q
    end
end


"on/off bus voltage magnitude squared constraint for relaxed formulations"
function PowerModelsDistribution.constraint_mc_bus_voltage_magnitude_sqr_on_off(pm::PMD.LPUBFDiagModel, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})
    w = PMD.var(pm, nw, :w, i)
    z_block = PMD.var(pm, nw, :z_block, PMD.ref(pm, nw, :bus_block_map, i))

    terminals = PMD.ref(pm, nw, :bus, i)["terminals"]
    grounded = PMD.ref(pm, nw, :bus, i)["grounded"]

    for (idx,t) in [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]
        if isfinite(vmax[idx])
            PMD.JuMP.@constraint(pm.model, w[t] <= vmax[idx]^2*z_block)
        end

        if isfinite(vmin[idx])
            PMD.JuMP.@constraint(pm.model, w[t] >= vmin[idx]^2*z_block)
        end
    end
end


"on/off constraint for generators"
function PowerModelsDistribution.constraint_mc_gen_power_on_off(pm::PMD.LPUBFDiagModel, nw::Int, i::Int, connections::Vector{<:Int}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, qmin::Vector{<:Real}, qmax::Vector{<:Real})
    pg = PMD.var(pm, nw, :pg, i)
    qg = PMD.var(pm, nw, :qg, i)
    z_block = PMD.var(pm, nw, :z_block, PMD.ref(pm, nw, :gen_block_map, i))

    for (idx, c) in enumerate(connections)
        if isfinite(pmax[idx])
            PMD.JuMP.@constraint(pm.model, pg[c] <= pmax[idx]*z_block)
        end

        if isfinite(pmin[idx])
            PMD.JuMP.@constraint(pm.model, pg[c] >= pmin[idx]*z_block)
        end

        if isfinite(qmax[idx])
            PMD.JuMP.@constraint(pm.model, qg[c] <= qmax[idx]*z_block)
        end

        if isfinite(qmin[idx])
            PMD.JuMP.@constraint(pm.model, qg[c] >= qmin[idx]*z_block)
        end
    end
end


"on/off constraint for storage"
function PowerModelsDistribution.constraint_mc_storage_on_off(pm::PMD.LPUBFDiagModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, qmin::Vector{<:Real}, qmax::Vector{<:Real}, charge_ub, discharge_ub)
    z_block = PMD.var(pm, nw, :z_block, PMD.ref(pm, nw, :storage_block_map, i))

    ps = [PMD.var(pm, nw, :ps, i)[c] for c in connections]
    qs = [PMD.var(pm, nw, :qs, i)[c] for c in connections]

    PMD.JuMP.@constraint(pm.model, ps .<= z_block.*pmax)
    PMD.JuMP.@constraint(pm.model, ps .>= z_block.*pmin)

    PMD.JuMP.@constraint(pm.model, qs .<= z_block.*qmax)
    PMD.JuMP.@constraint(pm.model, qs .>= z_block.*qmin)
end

"""
Links to and from power and voltages in a wye-wye transformer, assumes tm_fixed is true

```math
w_fr_i=(pol_i*tm_scale*tm_i)^2w_to_i
```
"""
function constraint_mc_transformer_power_yy_on_off(pm::PMD.LPUBFDiagModel, nw::Int, trans_id::Int, f_bus::Int, t_bus::Int, f_idx::Tuple{Int,Int,Int}, t_idx::Tuple{Int,Int,Int}, f_connections::Vector{Int}, t_connections::Vector{Int}, pol::Int, tm_set::Vector{<:Real}, tm_fixed::Vector{Bool}, tm_scale::Real)
    z_block = PMD.var(pm, nw, :z_block, PMD.ref(pm, nw, :bus_block_map, f_bus))

    tm = [tm_fixed[idx] ? tm_set[idx] : PMD.var(pm, nw, :tap, trans_id)[idx] for (idx,(fc,tc)) in enumerate(zip(f_connections,t_connections))]
    transformer = PMD.ref(pm, nw, :transformer, trans_id)

    p_fr = [PMD.var(pm, nw, :pt, f_idx)[p] for p in f_connections]
    p_to = [PMD.var(pm, nw, :pt, t_idx)[p] for p in t_connections]
    q_fr = [PMD.var(pm, nw, :qt, f_idx)[p] for p in f_connections]
    q_to = [PMD.var(pm, nw, :qt, t_idx)[p] for p in t_connections]

    w_fr = PMD.var(pm, nw, :w)[f_bus]
    w_to = PMD.var(pm, nw, :w)[t_bus]

    tmsqr = [tm_fixed[i] ? tm[i]^2 : PMD.JuMP.@variable(pm.model, base_name="$(nw)_tmsqr_$(trans_id)_$(f_connections[i])", start=PMD.JuMP.start_value(tm[i])^2, lower_bound=PMD.JuMP.has_lower_bound(tm[i]) ? PMD.JuMP.lower_bound(tm[i])^2 : 0.0, upper_bound=PMD.JuMP.has_upper_bound(tm[i]) ? PMD.JuMP.upper_bound(tm[i])^2 : 2.0^2) for i in 1:length(tm)]

    for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
        if tm_fixed[idx]
            PMD.JuMP.@constraint(pm.model, w_fr[fc] == (pol*tm_scale*tm[idx])^2*w_to[tc])
        else
            PMD.PolyhedralRelaxations.construct_univariate_relaxation!(pm.model, x->x^2, tm[idx], tmsqr[idx], [PMD.JuMP.has_lower_bound(tm[idx]) ? PMD.JuMP.lower_bound(tm[idx]) : 0.0, PMD.JuMP.has_upper_bound(tm[idx]) ? PMD.JuMP.upper_bound(tm[idx]) : 2.0], false)

            tmsqr_w_to = PMD.JuMP.@variable(pm.model, base_name="$(nw)_tmsqr_w_to_$(trans_id)_$(t_bus)_$(tc)")
            PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, tmsqr[idx], w_to[tc], tmsqr_w_to, [PMD.JuMP.lower_bound(tmsqr[idx]), PMD.JuMP.upper_bound(tmsqr[idx])], [PMD.JuMP.has_lower_bound(w_to[tc]) ? PMD.JuMP.lower_bound(w_to[tc]) : 0.0, PMD.JuMP.has_upper_bound(w_to[tc]) ? PMD.JuMP.upper_bound(w_to[tc]) : 2.0^2])

            PMD.JuMP.@constraint(pm.model, w_fr[fc] == (pol*tm_scale)^2*tmsqr_w_to)

            # with regcontrol
            if haskey(transformer,"controls")
                v_ref = transformer["controls"]["vreg"][idx]
                δ = transformer["controls"]["band"][idx]
                r = transformer["controls"]["r"][idx]
                x = transformer["controls"]["x"][idx]

                # linearized voltage squared: w_drop = (2⋅r⋅p+2⋅x⋅q)
                w_drop = PMD.JuMP.@expression(pm.model, 2*r*p_to[idx] + 2*x*q_to[idx])

                # (v_ref-δ)^2 ≤ w_fr-w_drop ≤ (v_ref+δ)^2
                # w_fr/1.1^2 ≤ w_to ≤ w_fr/0.9^2
                w_drop_z_block = PMD.JuMP.@variable(pm.model, base_name="$(nw)_w_drop_z_block_$(trans_id)_$(idx)")
                w_drop_lb = 0.0
                w_drop_ub = PMD.JuMP.has_upper_bound(p_to[idx]) && PMD.JuMP.has_upper_bound(q_to[idx]) ? 2*r*PMD.JuMP.upper_bound(p_to[idx]) + 2*x*PMD.JuMP.upper_bound(q_to[idx]) : 1.0
                PMD.JuMP.@constraint(pm.model, w_drop_z_block >= w_drop_lb * z_block)
                PMD.JuMP.@constraint(pm.model, w_drop_z_block >= w_drop_ub * z_block + w_drop - w_drop_ub)
                PMD.JuMP.@constraint(pm.model, w_drop_z_block <= w_drop_ub * z_block)
                PMD.JuMP.@constraint(pm.model, w_drop_z_block <= w_drop + w_drop_lb * z_block - w_drop_lb)

                PMD.JuMP.@constraint(pm.model, w_fr[fc] ≥ z_block * (v_ref - δ)^2 + w_drop_z_block)
                PMD.JuMP.@constraint(pm.model, w_fr[fc] ≤ z_block * (v_ref + δ)^2 + w_drop_z_block)
                PMD.JuMP.@constraint(pm.model, w_fr[fc]/1.1^2 ≤ w_to[tc])
                PMD.JuMP.@constraint(pm.model, w_fr[fc]/0.9^2 ≥ w_to[tc])
            end
        end
    end

    PMD.JuMP.@constraint(pm.model, p_fr + p_to .== 0)
    PMD.JuMP.@constraint(pm.model, q_fr + q_to .== 0)
end
