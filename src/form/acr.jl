@doc raw"""
    constraint_mc_switch_voltage_open_close(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int})

nonlinear switch power on/off constraint for ac-rect form

```math
\begin{align}
& \\
&
\end{align}
```
"""
function constraint_mc_switch_voltage_open_close(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int})
    vr_fr = var(pm, nw, :vr, f_bus)
    vr_to = var(pm, nw, :vr, t_bus)
    vi_fr = var(pm, nw, :vi, f_bus)
    vi_to = var(pm, nw, :vi, t_bus)

    f_bus = ref(pm, nw, :bus, f_bus)
    t_bus = ref(pm, nw, :bus, t_bus)

    f_vmin = f_bus["vmin"][[findfirst(isequal(c), f_bus["terminals"]) for c in f_connections]]
    t_vmin = t_bus["vmin"][[findfirst(isequal(c), t_bus["terminals"]) for c in t_connections]]

    f_vmax = f_bus["vmax"][[findfirst(isequal(c), f_bus["terminals"]) for c in f_connections]]
    t_vmax = t_bus["vmax"][[findfirst(isequal(c), t_bus["terminals"]) for c in t_connections]]

    vmin = max.(fill(0.0, length(f_vmax)), f_vmin, t_vmin)
    vmax = min.(fill(2.0, length(f_vmax)), f_vmax, t_vmax)

    state = var(pm, nw, :switch_state, i)

    for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
        JuMP.@NLconstraint(pm.model, (vr_fr[fc]^2 + vi_fr[fc]^2) - (vr_to[tc]^2 + vi_to[tc]^2) <=  (vmax[idx]^2-vmin[idx]^2) * (1-state))
        JuMP.@NLconstraint(pm.model, (vr_fr[fc]^2 + vi_fr[fc]^2) - (vr_to[tc]^2 + vi_to[tc]^2) >= -(vmax[idx]^2-vmin[idx]^2) * (1-state))

        # Indicator constraint version, for reference
        # JuMP.@constraint(pm.model, state => {vr_fr[fc] == vr_to[tc]})
        # JuMP.@constraint(pm.model, state => {vi_fr[fc] == vi_to[tc]})
    end
end


"""
    constraint_mc_power_balance_shed_block(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int,
        terminals::Vector{Int}, grounded::Vector{Bool}, bus_arcs::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}},
        bus_arcs_sw::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_trans::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}},
        bus_gens::Vector{Tuple{Int,Vector{Int}}}, bus_storage::Vector{Tuple{Int,Vector{Int}}},
        bus_loads::Vector{Tuple{Int,Vector{Int}}}, bus_shunts::Vector{Tuple{Int,Vector{Int}}}
    )

KCL for block load shed problem with transformers (ac-rect form)
"""
function constraint_mc_power_balance_shed_block(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, terminals::Vector{Int}, grounded::Vector{Bool}, bus_arcs::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_sw::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_trans::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_gens::Vector{Tuple{Int,Vector{Int}}}, bus_storage::Vector{Tuple{Int,Vector{Int}}}, bus_loads::Vector{Tuple{Int,Vector{Int}}}, bus_shunts::Vector{Tuple{Int,Vector{Int}}})
    z_block  = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, i))

    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)
    p    = get(var(pm, nw), :p,      Dict()); PMD._check_var_keys(p,   bus_arcs,       "active power",   "branch")
    q    = get(var(pm, nw), :q,      Dict()); PMD._check_var_keys(q,   bus_arcs,       "reactive power", "branch")
    pg   = get(var(pm, nw), :pg,     Dict()); PMD._check_var_keys(pg,  bus_gens,       "active power",   "generator")
    qg   = get(var(pm, nw), :qg,     Dict()); PMD._check_var_keys(qg,  bus_gens,       "reactive power", "generator")
    ps   = get(var(pm, nw), :ps,     Dict()); PMD._check_var_keys(ps,  bus_storage,    "active power",   "storage")
    qs   = get(var(pm, nw), :qs,     Dict()); PMD._check_var_keys(qs,  bus_storage,    "reactive power", "storage")
    psw  = get(var(pm, nw), :psw,    Dict()); PMD._check_var_keys(psw, bus_arcs_sw,    "active power",   "switch")
    qsw  = get(var(pm, nw), :qsw,    Dict()); PMD._check_var_keys(qsw, bus_arcs_sw,    "reactive power", "switch")
    pt   = get(var(pm, nw), :pt,     Dict()); PMD._check_var_keys(pt,  bus_arcs_trans, "active power",   "transformer")
    qt   = get(var(pm, nw), :qt,     Dict()); PMD._check_var_keys(qt,  bus_arcs_trans, "reactive power", "transformer")
    pd   = get(var(pm, nw), :pd_bus, Dict()); PMD._check_var_keys(pd,  bus_loads,      "active power",   "load")
    qd   = get(var(pm, nw), :qd_bus, Dict()); PMD._check_var_keys(pd,  bus_loads,      "reactive power", "load")

    Gt, Bt = PMD._build_bus_shunt_matrices(pm, nw, terminals, bus_shunts)

    cstr_p = []
    cstr_q = []

    ungrounded_terminals = [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]

    # pd/qd can be NLexpressions, so cannot be vectorized
    for (idx, t) in ungrounded_terminals
        cp = JuMP.@NLconstraint(pm.model,
              sum(  p[arc][t] for (arc, conns) in bus_arcs if t in conns)
            + sum(psw[arc][t] for (arc, conns) in bus_arcs_sw if t in conns)
            + sum( pt[arc][t] for (arc, conns) in bus_arcs_trans if t in conns)
            ==
              sum(pg[gen][t] for (gen, conns) in bus_gens if t in conns)
            - sum(ps[strg][t] for (strg, conns) in bus_storage if t in conns)
            - sum(pd[load][t]*z_block for (load, conns) in bus_loads if t in conns)
            + ( -vr[t] * sum(Gt[idx,jdx]*vr[u]-Bt[idx,jdx]*vi[u] for (jdx,u) in ungrounded_terminals)
                -vi[t] * sum(Gt[idx,jdx]*vi[u]+Bt[idx,jdx]*vr[u] for (jdx,u) in ungrounded_terminals)
            )
        )
        push!(cstr_p, cp)

        cq = JuMP.@NLconstraint(pm.model,
              sum(  q[arc][t] for (arc, conns) in bus_arcs if t in conns)
            + sum(qsw[arc][t] for (arc, conns) in bus_arcs_sw if t in conns)
            + sum( qt[arc][t] for (arc, conns) in bus_arcs_trans if t in conns)
            ==
              sum(qg[gen][t] for (gen, conns) in bus_gens if t in conns)
            - sum(qd[load][t]*z_block for (load, conns) in bus_loads if t in conns)
            - sum(qs[strg][t] for (strg, conns) in bus_storage if t in conns)
            + ( vr[t] * sum(Gt[idx,jdx]*vi[u]+Bt[idx,jdx]*vr[u] for (jdx,u) in ungrounded_terminals)
               -vi[t] * sum(Gt[idx,jdx]*vr[u]-Bt[idx,jdx]*vi[u] for (jdx,u) in ungrounded_terminals)
            )
        )
        push!(cstr_q, cq)
    end

    con(pm, nw, :lam_kcl_r)[i] = cstr_p
    con(pm, nw, :lam_kcl_i)[i] = cstr_q

    if IM.report_duals(pm)
        sol(pm, nw, :bus, i)[:lam_kcl_r] = cstr_p
        sol(pm, nw, :bus, i)[:lam_kcl_i] = cstr_q
    end
end


"""
    constraint_mc_power_balance_shed_traditional(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int,
        terminals::Vector{Int}, grounded::Vector{Bool}, bus_arcs::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}},
        bus_arcs_sw::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_trans::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}},
        bus_gens::Vector{Tuple{Int,Vector{Int}}}, bus_storage::Vector{Tuple{Int,Vector{Int}}},
        bus_loads::Vector{Tuple{Int,Vector{Int}}}, bus_shunts::Vector{Tuple{Int,Vector{Int}}}
    )

KCL for traditional load shed problem with transformers (ac-rect form)
"""
function constraint_mc_power_balance_shed_traditional(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, terminals::Vector{Int}, grounded::Vector{Bool}, bus_arcs::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_sw::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_arcs_trans::Vector{Tuple{Tuple{Int,Int,Int},Vector{Int}}}, bus_gens::Vector{Tuple{Int,Vector{Int}}}, bus_storage::Vector{Tuple{Int,Vector{Int}}}, bus_loads::Vector{Tuple{Int,Vector{Int}}}, bus_shunts::Vector{Tuple{Int,Vector{Int}}})
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)
    p    = get(var(pm, nw), :p,      Dict()); PMD._check_var_keys(p,   bus_arcs,       "active power",   "branch")
    q    = get(var(pm, nw), :q,      Dict()); PMD._check_var_keys(q,   bus_arcs,       "reactive power", "branch")
    pg   = get(var(pm, nw), :pg,     Dict()); PMD._check_var_keys(pg,  bus_gens,       "active power",   "generator")
    qg   = get(var(pm, nw), :qg,     Dict()); PMD._check_var_keys(qg,  bus_gens,       "reactive power", "generator")
    ps   = get(var(pm, nw), :ps,     Dict()); PMD._check_var_keys(ps,  bus_storage,    "active power",   "storage")
    qs   = get(var(pm, nw), :qs,     Dict()); PMD._check_var_keys(qs,  bus_storage,    "reactive power", "storage")
    psw  = get(var(pm, nw), :psw,    Dict()); PMD._check_var_keys(psw, bus_arcs_sw,    "active power",   "switch")
    qsw  = get(var(pm, nw), :qsw,    Dict()); PMD._check_var_keys(qsw, bus_arcs_sw,    "reactive power", "switch")
    pt   = get(var(pm, nw), :pt,     Dict()); PMD._check_var_keys(pt,  bus_arcs_trans, "active power",   "transformer")
    qt   = get(var(pm, nw), :qt,     Dict()); PMD._check_var_keys(qt,  bus_arcs_trans, "reactive power", "transformer")
    pd   = get(var(pm, nw), :pd_bus, Dict()); PMD._check_var_keys(pd,  bus_loads,      "active power",   "load")
    qd   = get(var(pm, nw), :qd_bus, Dict()); PMD._check_var_keys(pd,  bus_loads,      "reactive power", "load")
    z_demand  = get(var(pm, nw), :z_demand,  Dict()); PMD._check_var_keys( z_demand, bus_loads, "indicator", "load")
    z_storage = get(var(pm, nw), :z_storage, Dict()); PMD._check_var_keys( z_storage, bus_storage, "indicator", "storage")
    z_gen     = get(var(pm, nw), :z_gen,     Dict()); PMD._check_var_keys( z_gen, bus_gens, "indicator", "generator")
    z_voltage = var(pm, nw, :z_voltage, i)

    Gt, Bt = PMD._build_bus_shunt_matrices(pm, nw, terminals, bus_shunts)

    cstr_p = []
    cstr_q = []

    ungrounded_terminals = [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]

    # pd/qd can be NLexpressions, so cannot be vectorized
    for (idx, t) in ungrounded_terminals
        cp = JuMP.@NLconstraint(pm.model,
              sum(  p[arc][t] for (arc, conns) in bus_arcs if t in conns)
            + sum(psw[arc][t] for (arc, conns) in bus_arcs_sw if t in conns)
            + sum( pt[arc][t] for (arc, conns) in bus_arcs_trans if t in conns)
            ==
              sum(pg[gen][t]*z_gen[gen] for (gen, conns) in bus_gens if t in conns)
            - sum(ps[strg][t]*z_storage[strg] for (strg, conns) in bus_storage if t in conns)
            - sum(pd[load][t]*z_demand[load] for (load, conns) in bus_loads if t in conns)
            + ( -vr[t] * sum(Gt[idx,jdx]*vr[u]-Bt[idx,jdx]*vi[u] for (jdx,u) in ungrounded_terminals)
                -vi[t] * sum(Gt[idx,jdx]*vi[u]+Bt[idx,jdx]*vr[u] for (jdx,u) in ungrounded_terminals)
            ) * z_voltage
        )
        push!(cstr_p, cp)

        cq = JuMP.@NLconstraint(pm.model,
              sum(  q[arc][t] for (arc, conns) in bus_arcs if t in conns)
            + sum(qsw[arc][t] for (arc, conns) in bus_arcs_sw if t in conns)
            + sum( qt[arc][t] for (arc, conns) in bus_arcs_trans if t in conns)
            ==
              sum(qg[gen][t]*z_gen[gen] for (gen, conns) in bus_gens if t in conns)
            - sum(qd[load][t]*z_demand[load] for (load, conns) in bus_loads if t in conns)
            - sum(qs[strg][t]*z_storage[strg] for (strg, conns) in bus_storage if t in conns)
            + ( vr[t] * sum(Gt[idx,jdx]*vi[u]+Bt[idx,jdx]*vr[u] for (jdx,u) in ungrounded_terminals)
               -vi[t] * sum(Gt[idx,jdx]*vr[u]-Bt[idx,jdx]*vi[u] for (jdx,u) in ungrounded_terminals)
            ) * z_voltage
        )
        push!(cstr_q, cq)
    end

    con(pm, nw, :lam_kcl_r)[i] = cstr_p
    con(pm, nw, :lam_kcl_i)[i] = cstr_q

    if IM.report_duals(pm)
        sol(pm, nw, :bus, i)[:lam_kcl_r] = cstr_p
        sol(pm, nw, :bus, i)[:lam_kcl_i] = cstr_q
    end
end


"""
    constraint_mc_bus_voltage_magnitude_block_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})

on/off block bus voltage magnitude squared constraint for ac-rect form
"""
function constraint_mc_bus_voltage_magnitude_block_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)

    z_block = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, i))

    terminals = ref(pm, nw, :bus, i)["terminals"]
    grounded = ref(pm, nw, :bus, i)["grounded"]

    for (idx,t) in [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]
        isfinite(vmax[idx]) && JuMP.@constraint(pm.model, vr[t]^2 + vi[t]^2 <= vmax[idx]^2*z_block)
        isfinite(vmin[idx]) && JuMP.@constraint(pm.model, vr[t]^2 + vi[t]^2 >= vmin[idx]^2*z_block)
    end
end


"""
    constraint_mc_bus_voltage_magnitude_traditional_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})

on/off block bus voltage magnitude squared constraint for ac-rect form
"""
function constraint_mc_bus_voltage_magnitude_traditional_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)

    z_voltage = var(pm, nw, :z_voltage, i)

    terminals = ref(pm, nw, :bus, i)["terminals"]
    grounded = ref(pm, nw, :bus, i)["grounded"]

    for (idx,t) in [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]
        isfinite(vmax[idx]) && JuMP.@constraint(pm.model, vr[t]^2 + vi[t]^2 <= vmax[idx]^2*z_voltage)
        isfinite(vmin[idx]) && JuMP.@constraint(pm.model, vr[t]^2 + vi[t]^2 >= vmin[idx]^2*z_voltage)
    end
end


"""
"""
constraint_mc_bus_voltage_block_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real}) = constraint_mc_bus_voltage_magnitude_block_on_off(pm, nw, i, vmin, vmax)


"""
"""
constraint_mc_bus_voltage_traditional_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real}) = constraint_mc_bus_voltage_magnitude_traditional_on_off(pm, nw, i, vmin, vmax)


"""
    constraint_mc_transformer_power_yy_block_on_off(
        pm::PMD.AbstractUnbalancedACRModel,
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
"""
function constraint_mc_transformer_power_yy_block_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, trans_id::Int, f_bus::Int, t_bus::Int, f_idx::Tuple{Int,Int,Int}, t_idx::Tuple{Int,Int,Int}, f_connections::Vector{Int}, t_connections::Vector{Int}, pol::Int, tm_set::Vector{<:Real}, tm_fixed::Vector{Bool}, tm_scale::Real)
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

            # TODO: with regcontrol
            if haskey(transformer,"controls")
                # v_ref = transformer["controls"]["vreg"][idx]
                # δ = transformer["controls"]["band"][idx]
                # r = transformer["controls"]["r"][idx]
                # x = transformer["controls"]["x"][idx]

                # # (cr+jci) = (p-jq)/(vr-j⋅vi)
                # cr = JuMP.@NLexpression(pm.model, ( p_to[idx]*vr_to[tc] + q_to[idx]*vi_to[tc])/(vr_to[tc]^2+vi_to[tc]^2))
                # ci = JuMP.@NLexpression(pm.model, (-q_to[idx]*vr_to[tc] + p_to[idx]*vi_to[tc])/(vr_to[tc]^2+vi_to[tc]^2))
                # # v_drop = (cr+jci)⋅(r+jx)
                # vr_drop = JuMP.@NLexpression(pm.model, (r*cr-x*ci)*z_block)
                # vi_drop = JuMP.@NLexpression(pm.model, (r*ci+x*cr)*z_block)

                # # (v_ref-δ)^2 ≤ (vr_fr-vr_drop)^2 + (vi_fr-vi_drop)^2 ≤ (v_ref+δ)^2
                # # (vr_fr^2 + vi_fr^2)/1.1^2 ≤ (vr_to^2 + vi_to^2) ≤ (vr_fr^2 + vi_fr^2)/0.9^2
                # JuMP.@NLconstraint(pm.model, (vr_fr[fc]-vr_drop)^2 + (vi_fr[fc]-vi_drop)^2 ≥ (v_ref - δ)^2*z_block)
                # JuMP.@NLconstraint(pm.model, (vr_fr[fc]-vr_drop)^2 + (vi_fr[fc]-vi_drop)^2 ≤ (v_ref + δ)^2*z_block)
                # JuMP.@constraint(pm.model, (vr_fr[fc]^2 + vi_fr[fc]^2)/1.1^2 ≤ vr_to[tc]^2 + vi_to[tc]^2)
                # JuMP.@constraint(pm.model, (vr_fr[fc]^2 + vi_fr[fc]^2)/0.9^2 ≥ vr_to[tc]^2 + vi_to[tc]^2)
            end
        end
    end

    JuMP.@constraint(pm.model, p_fr + p_to .== 0)
    JuMP.@constraint(pm.model, q_fr + q_to .== 0)
end


"""
    constraint_mc_storage_losses_block_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, bus::Int, connections::Vector{Int}, r::Real, x::Real, p_loss::Real, q_loss::Real)

Nonlinear storage losses constraint for ac-rect form.
"""
function constraint_mc_storage_losses_block_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, bus::Int, connections::Vector{Int}, r::Real, x::Real, p_loss::Real, q_loss::Real)
    z_block = var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i))

    vr  = var(pm, nw,  :vr, bus)
    vi  = var(pm, nw,  :vi, bus)
    ps  = var(pm, nw,  :ps, i)
    qs  = var(pm, nw,  :qs, i)
    sc  = var(pm, nw,  :sc, i)
    sd  = var(pm, nw,  :sd, i)
    qsc = var(pm, nw, :qsc, i)

    JuMP.@NLconstraint(pm.model,
        (sum(ps[c] for c in connections) + (sd - sc)) * z_block
        ==
        (p_loss + r * sum((ps[c]^2 + qs[c]^2)/(vr[c]^2 + vi[c]^2) for (idx,c) in enumerate(connections))) * z_block
    )

    JuMP.@NLconstraint(pm.model,
        sum(qs[c] for c in connections)
        ==
        (qsc + q_loss + x * sum((ps[c]^2 + qs[c]^2)/(vr[c]^2 + vi[c]^2) for (idx,c) in enumerate(connections))) * z_block
    )
end


"""
    constraint_mc_storage_losses_traditional_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, bus::Int, connections::Vector{Int}, r::Real, x::Real, p_loss::Real, q_loss::Real)

Nonlinear storage losses constraint for ac-rect form.
"""
function constraint_mc_storage_losses_traditional_on_off(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, bus::Int, connections::Vector{Int}, r::Real, x::Real, p_loss::Real, q_loss::Real)
    z_storage = var(pm, nw, :z_storage, i)

    vr  = var(pm, nw,  :vr, bus)
    vi  = var(pm, nw,  :vi, bus)
    ps  = var(pm, nw,  :ps, i)
    qs  = var(pm, nw,  :qs, i)
    sc  = var(pm, nw,  :sc, i)
    sd  = var(pm, nw,  :sd, i)
    qsc = var(pm, nw, :qsc, i)

    JuMP.@NLconstraint(pm.model,
        (sum(ps[c] for c in connections) + (sd - sc)) * z_storage
        ==
        (p_loss + r * sum((ps[c]^2 + qs[c]^2)/(vr[c]^2 + vi[c]^2) for (idx,c) in enumerate(connections))) * z_storage
    )

    JuMP.@NLconstraint(pm.model,
        sum(qs[c] for c in connections)
        ==
        (qsc + q_loss + x * sum((ps[c]^2 + qs[c]^2)/(vr[c]^2 + vi[c]^2) for (idx,c) in enumerate(connections))) * z_storage
    )
end


@doc raw"""
    constraint_mc_inverter_theta_ref(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, va_ref::Vector{<:Real})

Creates phase angle constraints at reference buses for the ACR formulation

math```
\begin{align}
\Im(V) = \tan(V_a^{ref}) \Re(V)
\end{align}
```
"""
function constraint_mc_inverter_theta_ref(pm::PMD.AbstractUnbalancedACRModel, nw::Int, i::Int, va_ref::Vector{<:Real})
    terminals = ref(pm, nw, :bus, i, "terminals")
    vr = var(pm, nw, :vr, i)
    vi = var(pm, nw, :vi, i)
    inverter_objects = ref(pm, nw, :bus_inverters, i)

    # deal with cases first where tan(theta)==Inf or tan(theta)==0
    for (idx, t) in enumerate(terminals)
        if JuMP.has_upper_bound(vr[t]) && JuMP.has_upper_bound(vi[t])
            if va_ref[t] == pi/2
                JuMP.@constraint(pm.model, vr[t] <=  JuMP.upper_bound(vr[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                JuMP.@constraint(pm.model, vr[t] >= -JuMP.upper_bound(vr[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                JuMP.@constraint(pm.model, vi[t] >= -JuMP.upper_bound(vi[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
            elseif va_ref[t] == -pi/2
                JuMP.@constraint(pm.model, vr[t] <=  JuMP.upper_bound(vr[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                JuMP.@constraint(pm.model, vr[t] >= -JuMP.upper_bound(vr[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                JuMP.@constraint(pm.model, vi[t] <=  JuMP.upper_bound(vi[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
            elseif va_ref[t] == 0
                JuMP.@constraint(pm.model, vr[t] >= -JuMP.upper_bound(vr[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                JuMP.@constraint(pm.model, vi[t] <=  JuMP.upper_bound(vi[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                JuMP.@constraint(pm.model, vi[t] >= -JuMP.upper_bound(vi[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
            elseif va_ref[t] == pi
                JuMP.@constraint(pm.model, vr[t] >= -JuMP.upper_bound(vr[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                JuMP.@constraint(pm.model, vi[t] <=  JuMP.upper_bound(vi[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                JuMP.@constraint(pm.model, vi[t] >= -JuMP.upper_bound(vi[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
            else
                JuMP.@constraint(pm.model, vi[t] - tan(va_ref[idx])*vr[t] <=  deg2rad(60.0) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                JuMP.@constraint(pm.model, vi[t] - tan(va_ref[idx])*vr[t] >= -deg2rad(60.0) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                # va_ref also implies a sign for vr, vi
                if 0<=va_ref[t] && va_ref[t] <= pi
                    JuMP.@constraint(pm.model, vi[t] >= -JuMP.upper_bound(vi[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                else
                    JuMP.@constraint(pm.model, vi[t] <=  JuMP.upper_bound(vi[t]) * (1-sum(var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects)))
                end
            end
        end
    end
end
