@doc raw"""
    constraint_mc_switch_state_on_off(pm::AbstractUnbalancedActivePowerSwitchModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)

No voltage variables, do nothing
"""
function PowerModelsDistribution.constraint_mc_switch_state_on_off(pm::AbstractUnbalancedActivePowerSwitchModel, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}; relax::Bool=false)
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
function PowerModelsDistribution.constraint_mc_switch_power_on_off(pm::AbstractUnbalancedActivePowerSwitchModel, nw::Int, f_idx::Tuple{Int,Int,Int}; relax::Bool=false)
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
