@doc raw"""
    constraint_mc_switch_power_on_off(pm::LPUBFSwitchModel, nw::Int, f_idx::Tuple{Int,Int,Int}; relax::Bool=false)

Linear switch power on/off constraint for LPUBFDiagModel. If `relax`, an [indicator constraint](https://jump.dev/JuMP.jl/stable/manual/constraints/#Indicator-constraints) is used.

```math
\begin{align}
& S^{sw}_{i,c} \leq S^{swu}_{i,c} z^{sw}_i\ \forall i \in S,\forall c \in C \\
& S^{sw}_{i,c} \geq -S^{swu}_{i,c} z^{sw}_i\ \forall i \in S,\forall c \in C
\end{align}
```
"""
function PowerModelsDistribution.constraint_mc_switch_power_on_off(pm::AbstractSwitchModels, nw::Int, f_idx::Tuple{Int,Int,Int}; relax::Bool=false)
    i, f_bus, t_bus = f_idx

    psw = var(pm, nw, :psw, f_idx)
    qsw = var(pm, nw, :qsw, f_idx)

    z = var(pm, nw, :switch_state, i)

    connections = ref(pm, nw, :switch, i)["f_connections"]

    switch = ref(pm, nw, :switch, i)

    rating = min.(fill(1.0, length(connections)), PMD._calc_branch_power_max_frto(switch, ref(pm, nw, :bus, f_bus), ref(pm, nw, :bus, t_bus))...)

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


"on/off constraint for generators"
function PowerModelsDistribution.constraint_mc_gen_power_on_off(pm::AbstractSwitchModels, nw::Int, i::Int, connections::Vector{<:Int}, pmin::Vector{<:Real}, pmax::Vector{<:Real}, qmin::Vector{<:Real}, qmax::Vector{<:Real})
    pg = var(pm, nw, :pg, i)
    qg = var(pm, nw, :qg, i)

    z_block = var(pm, nw, :z_block, ref(pm, nw, :gen_block_map, i))

    for (idx, c) in enumerate(connections)
        if isfinite(pmax[idx])
            JuMP.@constraint(pm.model, pg[c] <= pmax[idx]*z_block)
        end

        if isfinite(pmin[idx])
            JuMP.@constraint(pm.model, pg[c] >= pmin[idx]*z_block)
        end

        if isfinite(qmax[idx])
            JuMP.@constraint(pm.model, qg[c] <= qmax[idx]*z_block)
        end

        if isfinite(qmin[idx])
            JuMP.@constraint(pm.model, qg[c] >= qmin[idx]*z_block)
        end
    end
end


"""
    constraint_mc_storage_on_off(pm::PMD.LPUBFDiagModel, nw::Int, i::Int, connections::Vector{Int}, pmin::Real, pmax::Real, qmin::Real, qmax::Real, charge_ub::Real, discharge_ub::Real)

on/off constraint for storage
"""
function PowerModelsDistribution.constraint_mc_storage_on_off(pm::AbstractSwitchModels, nw::Int, i::Int, connections::Vector{Int}, pmin::Real, pmax::Real, qmin::Real, qmax::Real, charge_ub::Real, discharge_ub::Real)
    z_block = var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i))

    ps = [var(pm, nw, :ps, i)[c] for c in connections]
    qs = [var(pm, nw, :qs, i)[c] for c in connections]

    JuMP.@constraint(pm.model, sum(ps) <= z_block*pmax)
    JuMP.@constraint(pm.model, sum(ps) >= z_block*pmin)

    JuMP.@constraint(pm.model, sum(qs) <= z_block*qmax)
    JuMP.@constraint(pm.model, sum(qs) >= z_block*qmin)
end


"""
    constraint_mc_storage_power_unbalance_mi(pm::AbstractSwitchModels, nw::Int, i::Int, connections::Vector{Int}, balance_factor::Float64)

Enforces that storage inputs/outputs are (approximately) balanced across each phase, by some `balance_factor`
"""
function constraint_mc_storage_power_unbalance_mi(pm::AbstractSwitchModels, nw::Int, i::Int, connections::Vector{Int}, balance_factor::Float64)
    # ps = var(pm, nw, :ps, i)
    # qs = var(pm, nw, :qs, i)

    # sc_on = var(pm, nw, :sc_on, i)  # ==1 charging (p,q > 0)
    # sd_on = var(pm, nw, :sd_on, i)  # ==1 discharging (p,q < 0)

    # sd_on_ps = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sd_on_ps_$(i)", lower_bound=0.0)
    # sc_on_ps = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sc_on_ps_$(i)", lower_bound=0.0)
    # sd_on_qs = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sd_on_qs_$(i)", lower_bound=0.0)
    # sc_on_qs = JuMP.@variable(pm.model, [c in connections], base_name="$(nw)_sc_on_qs_$(i)", lower_bound=0.0)
    # for c in connections
    #     PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sd_on, ps[c], sd_on_ps[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
    #     PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sc_on, ps[c], sc_on_ps[c], [0,1], [JuMP.lower_bound(ps[c]), JuMP.upper_bound(ps[c])])
    #     PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sd_on, qs[c], sd_on_qs[c], [0,1], [JuMP.lower_bound(qs[c]), JuMP.upper_bound(qs[c])])
    #     PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sc_on, qs[c], sc_on_qs[c], [0,1], [JuMP.lower_bound(qs[c]), JuMP.upper_bound(qs[c])])
    # end

    # abs_avg_ps = JuMP.@variable(pm.model, base_name="$(nw)_abs_avg_ps_$(i)", lower_bound=0.0)
    # JuMP.@constraint(pm.model, abs_avg_ps == (sum(sc_on_ps[c] for c in connections)-sum(sd_on_ps[c] for c in connections)) / length(connections))
    # # JuMP.@constraint(pm.model, abs_avg_ps == (-1*sd_on + 1*sc_on)*sum(sd_on_ps[d] for d in connections) / length(connections))

    # abs_avg_qs = JuMP.@variable(pm.model, base_name="$(nw)_abs_avg_qs_$(i)", lower_bound=0.0)
    # JuMP.@constraint(pm.model, abs_avg_qs == (sum(sc_on_qs[c] for c in connections)-sum(sd_on_qs[c] for c in connections)) / length(connections))
    # # JuMP.@constraint(pm.model, abs_avg_qs == (-1*sd_on + 1*sc_on)*sum(qs[d] for d in connections) / length(connections))

    # sd_on_abs_avg_ps = JuMP.@variable(pm.model, base_name="$(nw)_sd_on_abs_avg_ps_$(i)", lower_bound=0)
    # sc_on_abs_avg_ps = JuMP.@variable(pm.model, base_name="$(nw)_sc_on_abs_avg_ps_$(i)", lower_bound=0)
    # PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sd_on, abs_avg_ps, sd_on_abs_avg_ps, [0,1], [0, sum(JuMP.upper_bound(ps[c]) for c in connections)])
    # PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sc_on, abs_avg_ps, sc_on_abs_avg_ps, [0,1], [0, sum(JuMP.upper_bound(ps[c]) for c in connections)])

    # sd_on_abs_avg_qs = JuMP.@variable(pm.model, base_name="$(nw)_sd_on_abs_avg_qs_$(i)", lower_bound=0)
    # sc_on_abs_avg_qs = JuMP.@variable(pm.model, base_name="$(nw)_sc_on_abs_avg_qs_$(i)", lower_bound=0)
    # PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sd_on, abs_avg_qs, sd_on_abs_avg_qs, [0,1], [0, sum(JuMP.upper_bound(qs[c]) for c in connections)])
    # PMD.PolyhedralRelaxations.construct_bilinear_relaxation!(pm.model, sc_on, abs_avg_qs, sc_on_abs_avg_qs, [0,1], [0, sum(JuMP.upper_bound(qs[c]) for c in connections)])

    # for c in connections
    #     JuMP.@constraint(pm.model, ps[c] >= abs_avg_ps - balance_factor*(sc_on_abs_avg_ps-sd_on_abs_avg_ps))
    #     JuMP.@constraint(pm.model, ps[c] <= abs_avg_ps + balance_factor*(sc_on_abs_avg_ps-sd_on_abs_avg_ps))

    #     JuMP.@constraint(pm.model, qs[c] >= abs_avg_qs - balance_factor*(sc_on_abs_avg_qs-sd_on_abs_avg_qs))
    #     JuMP.@constraint(pm.model, qs[c] <= abs_avg_qs + balance_factor*(sc_on_abs_avg_qs-sd_on_abs_avg_qs))

    #     # JuMP.@constraint(pm.model, ps[c] >= (1-(balance_factor*(-1*sd_on + 1*sc_on)))*abs_avg_ps)
    #     # JuMP.@constraint(pm.model, ps[c] <= (1+(balance_factor*(-1*sd_on + 1*sc_on)))*abs_avg_ps)

    #     # JuMP.@constraint(pm.model, qs[c] >= (1-(balance_factor*(-1*sd_on + 1*sc_on)))*abs_avg_qs)
    #     # JuMP.@constraint(pm.model, qs[c] <= (1+(balance_factor*(-1*sd_on + 1*sc_on)))*abs_avg_qs)
    # end
end


"""
    constraint_storage_complementarity_mi_on_off(pm::LPUBFSwitchModel, n::Int, i::Int, charge_ub::Float64, discharge_ub::Float64)

sc_on + sd_on == z_block
"""
function constraint_storage_complementarity_mi_on_off(pm::AbstractSwitchModels, n::Int, i::Int, charge_ub::Float64, discharge_ub::Float64)
    sc = var(pm, n, :sc, i)
    sd = var(pm, n, :sd, i)
    sc_on = var(pm, n, :sc_on, i)
    sd_on = var(pm, n, :sd_on, i)

    z_block = var(pm, n, :z_block, ref(pm, n, :storage_block_map, i))

    JuMP.@constraint(pm.model, sc_on + sd_on == z_block)
    JuMP.@constraint(pm.model, sc_on*charge_ub >= sc)
    JuMP.@constraint(pm.model, sd_on*discharge_ub >= sd)
end
