







"Linear switch power on/off constraint for LPUBFDiagModel"
function PowerModelsDistribution.constraint_mc_switch_power_on_off(pm::PMD.LPUBFDiagModel, nw::Int, f_idx::Tuple{Int,Int,Int}; relax::Bool=false)
    i, f_bus, t_bus = f_idx

    psw = PMD.var(pm, nw, :psw, f_idx)
    qsw = PMD.var(pm, nw, :qsw, f_idx)

    z = PMD.var(pm, nw, :switch_state, i)

    connections = PMD.ref(pm, nw, :switch, i)["f_connections"]

    rating = get(PMD.ref(pm, nw, :switch, i), "rate_a", fill(1e-2, length(connections)))

    for (idx, c) in enumerate(connections)
        if relax
            PMD.JuMP.@constraint(pm.model, psw[c] <=  rating[idx] * z)
            PMD.JuMP.@constraint(pm.model, psw[c] >= -rating[idx] * z)
            PMD.JuMP.@constraint(pm.model, qsw[c] <=  rating[idx] * z)
            PMD.JuMP.@constraint(pm.model, qsw[c] >= -rating[idx] * z)
        else
            PMD.JuMP.@constraint(pm.model, !z => {psw[c] == 0.0})
            PMD.JuMP.@constraint(pm.model, !z => {qsw[c] == 0.0})
        end
    end
end


"Linear switch state on/off constraint for LPUBFDiagModel"
function PowerModelsDistribution.constraint_mc_switch_state_on_off(pm::PMD.LPUBFDiagModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)
    w_fr = PMD.var(pm, nw, :w, f_bus)
    w_to = PMD.var(pm, nw, :w, t_bus)

    z = PMD.var(pm, nw, :switch_state, i)

    for (fc, tc) in zip(f_connections, t_connections)
        if relax
            M = 0.2
            PMD.JuMP.@constraint(pm.model, w_fr[fc] - w_to[tc] <=  M * (1-z))
            PMD.JuMP.@constraint(pm.model, w_fr[fc] - w_to[tc] >= -M * (1-z))
        else
            PMD.JuMP.@constraint(pm.model, z => {w_fr[fc] == w_to[tc]})
        end
    end
end
