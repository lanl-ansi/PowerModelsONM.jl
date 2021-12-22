@doc raw"""
    constraint_mc_switch_state_on_off(pm::LPUBFSwitchModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)

Linear switch power on/off constraint for LPUBFDiagModel. If `relax`, an [indicator constraint](https://jump.dev/JuMP.jl/stable/manual/constraints/#Indicator-constraints) is used.

```math
\begin{align}
& w^{fr}_{i,c} - w^{to}_{i,c} \leq \left ( v^u_{i,c} \right )^2 \left ( 1 - z^{sw}_i \right )\ \forall i \in S,\forall c \in C \\
& w^{fr}_{i,c} - w^{to}_{i,c} \geq -\left ( v^u_{i,c}\right )^2 \left ( 1 - z^{sw}_i \right )\ \forall i \in S,\forall c \in C
\end{align}
```
"""
function PowerModelsDistribution.constraint_mc_switch_state_on_off(pm::AbstractUnbalancedACRSwitchModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)
    vr_fr = var(pm, nw, :vr, f_bus)
    vr_to = var(pm, nw, :vr, t_bus)
    vi_fr = var(pm, nw, :vi, f_bus)
    vi_to = var(pm, nw, :vi, t_bus)

    f_bus = ref(pm, nw, :bus, f_bus)
    t_bus = ref(pm, nw, :bus, t_bus)

    f_vmax = f_bus["vmax"][[findfirst(isequal(c), f_bus["terminals"]) for c in f_connections]]
    t_vmax = t_bus["vmax"][[findfirst(isequal(c), t_bus["terminals"]) for c in t_connections]]

    vmax = min.(fill(2.0, length(f_bus["vmax"])), f_vmax, t_vmax)

    z = var(pm, nw, :switch_state, i)

    for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
        if relax
            JuMP.@NLconstraint(pm.model, vr_fr[fc] - vr_fr[fc] <=  vmax[idx]^2 * (1-z))
            JuMP.@NLconstraint(pm.model, vi_fr[fc] - vi_fr[fc] <=  vmax[idx]^2 * (1-z))
            JuMP.@NLconstraint(pm.model, vr_to[tc] - vr_to[tc] >= -vmax[idx]^2 * (1-z))
            JuMP.@NLconstraint(pm.model, vi_to[tc] - vi_to[tc] >= -vmax[idx]^2 * (1-z))
        else
            JuMP.@constraint(pm.model, z => {vr_fr[fc] == vr_to[tc]})
            JuMP.@constraint(pm.model, z => {vi_fr[fc] == vi_to[tc]})
        end
    end
end


"KCL for load shed problem with transformers (AbstractWForms)"
function PowerModelsDistribution.constraint_mc_power_balance_shed(pm::AbstractUnbalancedACRSwitchModel, nw::Int, i::Int, terminals::Vector{Int}, grounded::Vector{Bool}, bus_arcs::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_sw::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_trans::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_gens::Vector{Tuple{Int,Vector{Int}}}, bus_storage::Vector{Tuple{Int,Vector{Int}}}, bus_loads::Vector{Tuple{Int,Vector{Int}}}, bus_shunts::Vector{Tuple{Int,Vector{Int}}})
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)
    p        = get(var(pm, nw),    :p, Dict()); PMD._check_var_keys(p, bus_arcs, "active power", "branch")
    q        = get(var(pm, nw),    :q, Dict()); PMD._check_var_keys(q, bus_arcs, "reactive power", "branch")
    pg       = get(var(pm, nw),   :pg, Dict()); PMD._check_var_keys(pg, bus_gens, "active power", "generator")
    qg       = get(var(pm, nw),   :qg, Dict()); PMD._check_var_keys(qg, bus_gens, "reactive power", "generator")
    ps       = get(var(pm, nw),   :ps, Dict()); PMD._check_var_keys(ps, bus_storage, "active power", "storage")
    qs       = get(var(pm, nw),   :qs, Dict()); PMD._check_var_keys(qs, bus_storage, "reactive power", "storage")
    psw      = get(var(pm, nw),  :psw, Dict()); PMD._check_var_keys(psw, bus_arcs_sw, "active power", "switch")
    qsw      = get(var(pm, nw),  :qsw, Dict()); PMD._check_var_keys(qsw, bus_arcs_sw, "reactive power", "switch")
    pt       = get(var(pm, nw),   :pt, Dict()); PMD._check_var_keys(pt, bus_arcs_trans, "active power", "transformer")
    qt       = get(var(pm, nw),   :qt, Dict()); PMD._check_var_keys(qt, bus_arcs_trans, "reactive power", "transformer")
    pd       = get(var(pm, nw), :pd_bus,  Dict()); PMD._check_var_keys(pd,  bus_loads, "active power", "load")
    qd       = get(var(pm, nw), :qd_bus,  Dict()); PMD._check_var_keys(qd,  bus_loads, "reactive power", "load")
    z_block  = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, i))

    uncontrolled_shunts = Tuple{Int,Vector{Int}}[]
    controlled_shunts = Tuple{Int,Vector{Int}}[]

    if !isempty(bus_shunts) && any(haskey(ref(pm, nw, :shunt, sh), "controls") for (sh, conns) in bus_shunts)
        for (sh, conns) in bus_shunts
            if haskey(ref(pm, nw, :shunt, sh), "controls")
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

    for (idx, t) in ungrounded_terminals
        cp = JuMP.@NLconstraint(pm.model,
            sum(p[a][t] for (a, conns) in bus_arcs if t in conns)
            + sum(psw[a_sw][t] for (a_sw, conns) in bus_arcs_sw if t in conns)
            + sum(pt[a_trans][t] for (a_trans, conns) in bus_arcs_trans if t in conns)
            ==
            sum(pg[g][t] for (g, conns) in bus_gens if t in conns)
            - sum(ps[s][t] for (s, conns) in bus_storage if t in conns)
            - sum(pd[l][t]*z_block for (l, conns) in bus_loads if t in conns)
            + ( -vr[t] * sum(Gt[idx,jdx]*vr[u]-Bt[idx,jdx]*vi[u] for (jdx,u) in ungrounded_terminals)
                -vi[t] * sum(Gt[idx,jdx]*vi[u]+Bt[idx,jdx]*vr[u] for (jdx,u) in ungrounded_terminals)
            )
        )
        push!(cstr_p, cp)

        for (sh, sh_conns) in controlled_shunts
            if t in sh_conns
                cq_cap = var(pm, nw, :capacitor_reactive_power, sh)[t]
                cap_state = var(pm, nw, :capacitor_state, sh)[t]
                bs = PMD.diag(ref(pm, nw, :shunt, sh, "bs"))[findfirst(isequal(t), sh_conns)]
                vr_lb, vr_ub = _IM.variable_domain(vr[t])
                vi_lb, vi_ub = _IM.variable_domain(vi[t])
                vm_lb = sqrt(vr_lb^2 + vi_lb^2)
                vm_ub = sqrt(vr_ub^2 + vi_ub^2)

                # tie to z_block
                JuMP.@constraint(pm.model, cap_state <= z_block)

                # McCormick envelope constraints
                JuMP.@constraint(pm.model, cq_cap ≥ bs*cap_state*vm_lb^2)
                JuMP.@constraint(pm.model, cq_cap ≥ bs*(vr[t]^2 + vi[t]^2) + bs*cap_state*vm_ub^2 - bs*vm_ub^2*z_block)
                JuMP.@constraint(pm.model, cq_cap ≤ bs*cap_state*vm_ub^2)
                JuMP.@constraint(pm.model, cq_cap ≤ bs*(vr[t]^2 + vi[t]^2) + bs*cap_state*vm_lb^2 - bs*vm_lb^2*z_block)
            end
        end

        cq = JuMP.@NLconstraint(pm.model,
            sum(q[a][t] for (a, conns) in bus_arcs if t in conns)
            + sum(qsw[a_sw][t] for (a_sw, conns) in bus_arcs_sw if t in conns)
            + sum(qt[a_trans][t] for (a_trans, conns) in bus_arcs_trans if t in conns)
            ==
            sum(qg[g][t] for (g, conns) in bus_gens if t in conns)
            - sum(qs[s][t] for (s, conns) in bus_storage if t in conns)
            - sum(qd[l][t]*z_block for (l, conns) in bus_loads if t in conns)
            + ( vr[t] * sum(Gt[idx,jdx]*vi[u]+Bt[idx,jdx]*vr[u] for (jdx,u) in ungrounded_terminals)
               -vi[t] * sum(Gt[idx,jdx]*vr[u]-Bt[idx,jdx]*vi[u] for (jdx,u) in ungrounded_terminals)
            )
            - sum(-var(pm, nw, :capacitor_reactive_power, sh)[t] for (sh, conns) in controlled_shunts if t in conns)
        )
        push!(cstr_q, cq)
    end

    PMD.con(pm, nw, :lam_kcl_r)[i] = cstr_p
    PMD.con(pm, nw, :lam_kcl_i)[i] = cstr_q

    if _IM.report_duals(pm)
        PMD.sol(pm, nw, :bus, i)[:lam_kcl_r] = cstr_p
        PMD.sol(pm, nw, :bus, i)[:lam_kcl_i] = cstr_q
    end
end


"on/off bus voltage magnitude squared constraint for relaxed formulations"
function PowerModelsDistribution.constraint_mc_bus_voltage_magnitude_on_off(pm::AbstractUnbalancedACRSwitchModel, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)

    z_block = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, i))

    terminals = ref(pm, nw, :bus, i)["terminals"]
    grounded = ref(pm, nw, :bus, i)["grounded"]

    for (idx,t) in [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]
        if isfinite(vmax[idx])
            JuMP.@constraint(pm.model, vr[t]^2 + vi[t]^2 <= vmax[idx]^2*z_block)
        end

        if isfinite(vmin[idx])
            JuMP.@constraint(pm.model, vr[t]^2 + vi[t]^2 >= vmin[idx]^2*z_block)
        end
    end
end


"""
    constraint_mc_transformer_power_yy_on_off(
        pm::LPUBFSwitchModel,
        nw::Int,
        trans_id::Int,
        f_bus::Int,
        t_bus::Int,
        f_idx::Tuple{Int,Int,Int},
        t_idx::Tuple{Int,Int,Int},
        f_connections::Vector{Int},
        t_connections::Vector{Int},
        pol::Int,
        tm_set::Vector{<:Real},
        tm_fixed::Vector{Bool},
        tm_scale::Real
    )

Links to and from power and voltages in a wye-wye transformer, assumes tm_fixed is true

```math
w_fr_i=(pol_i*tm_scale*tm_i)^2w_to_i
```
"""
function constraint_mc_transformer_power_yy_on_off(pm::AbstractUnbalancedACRSwitchModel, nw::Int, trans_id::Int, f_bus::Int, t_bus::Int, f_idx::Tuple{Int,Int,Int}, t_idx::Tuple{Int,Int,Int}, f_connections::Vector{Int}, t_connections::Vector{Int}, pol::Int, tm_set::Vector{<:Real}, tm_fixed::Vector{Bool}, tm_scale::Real)
    z_block = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, f_bus))

    transformer = ref(pm, nw, :transformer, trans_id)

    vr_fr = var(pm, nw, :vr, f_bus)
    vr_to = var(pm, nw, :vr, t_bus)
    vi_fr = var(pm, nw, :vi, f_bus)
    vi_to = var(pm, nw, :vi, t_bus)

    p_fr = [var(pm, nw, :pt, f_idx)[c] for c in f_connections]
    p_to = [var(pm, nw, :pt, t_idx)[c] for c in t_connections]
    q_fr = [var(pm, nw, :qt, f_idx)[c] for c in f_connections]
    q_to = [var(pm, nw, :qt, t_idx)[c] for c in t_connections]

    # construct tm as a parameter or scaled variable depending on whether it is fixed or not
    tm = [tm_fixed[idx] ? tm_set[idx] : var(pm, nw, :tap, trans_id)[idx] for (idx,(fc,tc)) in enumerate(zip(f_connections,t_connections))]

    for (idx,(fc,tc)) in enumerate(zip(f_connections,t_connections))
        if tm_fixed[idx]
            JuMP.@constraint(pm.model, vr_fr[fc] == pol*tm_scale*tm[idx]*vr_to[tc])
            JuMP.@constraint(pm.model, vi_fr[fc] == pol*tm_scale*tm[idx]*vi_to[tc])
        else
            # transformer taps without regcontrol, tap variable not required in regcontrol formulation
            JuMP.@constraint(pm.model, vr_fr[fc] == pol*tm_scale*tm[idx]*vr_to[tc])
            JuMP.@constraint(pm.model, vi_fr[fc] == pol*tm_scale*tm[idx]*vi_to[tc])

            # with regcontrol
            if haskey(transformer,"controls")
                # v_ref = transformer["controls"]["vreg"][idx]
                # δ = transformer["controls"]["band"][idx]
                # r = transformer["controls"]["r"][idx]
                # x = transformer["controls"]["x"][idx]

                # # (cr+jci) = (p-jq)/(vr-j⋅vi)
                # cr = JuMP.@NLexpression(pm.model, ( p_to[idx]*vr_to[tc] + q_to[idx]*vi_to[tc])/(vr_to[tc]^2+vi_to[tc]^2))
                # ci = JuMP.@NLexpression(pm.model, (-q_to[idx]*vr_to[tc] + p_to[idx]*vi_to[tc])/(vr_to[tc]^2+vi_to[tc]^2))
                # # v_drop = (cr+jci)⋅(r+jx)
                # vr_drop = JuMP.@NLexpression(pm.model, r*cr-x*ci)
                # vi_drop = JuMP.@NLexpression(pm.model, r*ci+x*cr)

                # # (v_ref-δ)^2 ≤ (vr_fr-vr_drop)^2 + (vi_fr-vi_drop)^2 ≤ (v_ref+δ)^2
                # # (vr_fr^2 + vi_fr^2)/1.1^2 ≤ (vr_to^2 + vi_to^2) ≤ (vr_fr^2 + vi_fr^2)/0.9^2
                # JuMP.@NLconstraint(pm.model, (vr_fr[fc]-vr_drop)^2 + (vi_fr[fc]-vi_drop)^2 ≥ (v_ref - δ)^2)
                # JuMP.@NLconstraint(pm.model, (vr_fr[fc]-vr_drop)^2 + (vi_fr[fc]-vi_drop)^2 ≤ (v_ref + δ)^2)
                # JuMP.@constraint(pm.model, (vr_fr[fc]^2 + vi_fr[fc]^2)/1.1^2 ≤ vr_to[tc]^2 + vi_to[tc]^2)
                # JuMP.@constraint(pm.model, (vr_fr[fc]^2 + vi_fr[fc]^2)/0.9^2 ≥ vr_to[tc]^2 + vi_to[tc]^2)
            end
        end
    end

    JuMP.@constraint(pm.model, p_fr + p_to .== 0)
    JuMP.@constraint(pm.model, q_fr + q_to .== 0)end


"""
    constraint_mc_storage_losses_on_off(pm::LPUBFSwitchModel, i::Int; nw::Int=nw_id_default)

Neglects the active and reactive loss terms associated with the squared current magnitude.
"""
function constraint_mc_storage_losses_on_off(pm::AbstractUnbalancedACRSwitchModel, i::Int; nw::Int=nw_id_default)
    storage = ref(pm, nw, :storage, i)
    z_block = var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i))

    vr  = var(pm, nw,  :vr, storage["storage_bus"])
    vi  = var(pm, nw,  :vi, storage["storage_bus"])
    ps  = var(pm, nw,  :ps, i)
    qs  = var(pm, nw,  :qs, i)
    sc  = var(pm, nw,  :sc, i)
    sd  = var(pm, nw,  :sd, i)
    qsc = var(pm, nw, :qsc, i)

    p_loss = storage["p_loss"]
    q_loss = storage["q_loss"]
    r = storage["r"]
    x = storage["x"]

    JuMP.@NLconstraint(pm.model,
        sum(ps[c] for c in storage["connections"]) + (sd - sc) * z_block
        ==
        (p_loss + r * sum((ps[c]^2 + qs[c]^2) for (idx,c) in enumerate(storage["connections"]))) * z_block
    )

    JuMP.@NLconstraint(pm.model,
        sum(qs[c] for c in storage["connections"])
        ==
        (qsc + q_loss + x * sum((ps[c]^2 + qs[c]^2) for (idx,c) in enumerate(storage["connections"]))) * z_block
    )
end
