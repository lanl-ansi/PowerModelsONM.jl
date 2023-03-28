@doc raw"""
    constraint_mc_bus_voltage_magnitude_sqr_block_on_off(
        pm::PMD.AbstractUnbalancedWModels,
        nw::Int,
        i::Int,
        vmin::Vector{<:Real},
        vmax::Vector{<:Real}
    )

on/off block bus voltage magnitude squared constraint for W models

```math
```
"""
function constraint_mc_bus_voltage_magnitude_sqr_block_on_off(pm::PMD.AbstractUnbalancedWModels, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})
    w = var(pm, nw, :w, i)
    z_block = var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, i))

    terminals = ref(pm, nw, :bus, i)["terminals"]
    grounded = ref(pm, nw, :bus, i)["grounded"]

    for (idx,t) in [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]
        isfinite(vmax[idx]) && JuMP.@constraint(pm.model, w[t] <= vmax[idx]^2*z_block)
        isfinite(vmin[idx]) && JuMP.@constraint(pm.model, w[t] >= vmin[idx]^2*z_block)
    end
end


@doc raw"""
    constraint_mc_bus_voltage_magnitude_sqr_traditional_on_off(
        pm::PMD.AbstractUnbalancedWModels,
        nw::Int,
        i::Int,
        vmin::Vector{<:Real},
        vmax::Vector{<:Real}
    )

on/off traditional bus voltage magnitude squared constraint for W models

```math
```
"""
function constraint_mc_bus_voltage_magnitude_sqr_traditional_on_off(pm::PMD.AbstractUnbalancedWModels, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})
    w = var(pm, nw, :w, i)
    z_voltage = var(pm, nw, :z_voltage, i)

    terminals = ref(pm, nw, :bus, i)["terminals"]
    grounded = ref(pm, nw, :bus, i)["grounded"]

    for (idx,t) in [(idx,t) for (idx,t) in enumerate(terminals) if !grounded[idx]]
        isfinite(vmax[idx]) && JuMP.@constraint(pm.model, w[t] <= vmax[idx]^2*z_voltage)
        isfinite(vmin[idx]) && JuMP.@constraint(pm.model, w[t] >= vmin[idx]^2*z_voltage)
    end
end


"""
    constraint_mc_bus_voltage_block_on_off(pm::PMD.AbstractUnbalancedWModels, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})

Redirects to `constraint_mc_bus_voltage_magnitude_sqr_block_on_off` for `AbstractUnbalancedWModels`
"""
constraint_mc_bus_voltage_block_on_off(pm::PMD.AbstractUnbalancedWModels, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real}) = constraint_mc_bus_voltage_magnitude_sqr_block_on_off(pm, nw, i, vmin, vmax)


"""
    constraint_mc_bus_voltage_traditional_on_off(pm::PMD.AbstractUnbalancedWModels, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real})

Redirects to `constraint_mc_bus_voltage_magnitude_sqr_traditional_on_off` for `AbstractUnbalancedWModels`
"""
constraint_mc_bus_voltage_traditional_on_off(pm::PMD.AbstractUnbalancedWModels, nw::Int, i::Int, vmin::Vector{<:Real}, vmax::Vector{<:Real}) = constraint_mc_bus_voltage_magnitude_sqr_traditional_on_off(pm, nw, i, vmin, vmax)


@doc raw"""
    constraint_mc_inverter_theta_ref(pm::PMD.AbstractUnbalancedPolarModels, nw::Int, i::Int, va_ref::Vector{<:Real})

Phase angle constraints at reference buses for the Unbalanced Polar models

math```
\begin{align*}
V_a - V^{ref}_a \leq 60^{\circ} * (1-\sum{z_{inv}})
V_a - V^{ref}_a \geq -60^{\circ} * (1-\sum{z_{inv}})
\end{align*}
```
"""
function constraint_mc_inverter_theta_ref(pm::PMD.AbstractUnbalancedPolarModels, nw::Int, i::Int, va_ref::Vector{<:Real})
    terminals = ref(pm, nw, :bus, i)["terminals"]
    va = var(pm, nw, :va, i)
    inverter_objects = ref(pm, nw, :bus_inverters, i)
    z_inverters = [var(pm, nw, :z_inverter, inv_obj) for inv_obj in inverter_objects]

    if !isempty(inverter_objects)
        for (idx,t) in enumerate(terminals)
            JuMP.@constraint(pm.model, va[t] - va_ref[idx] <=  deg2rad(60) * (1-sum(z_inverters)))
            JuMP.@constraint(pm.model, va[t] - va_ref[idx] >= -deg2rad(60) * (1-sum(z_inverters)))
        end
    end
end


@doc raw"""
    constraint_mc_switch_open_voltage_distance(pm::PMD.AbstractUnbalancedWModels, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}, vm_delta_pu::Real, ::Real)

Constraints for voltages on either side of an open switch to be within some distance of one another (provided by user) for W models

math```
\begin{align}
    w_{i,\phi} - w_{j,\phi} &\leq \left(\overline{\delta}^{|V|}_{k}\right)^2 + \tau^{w}_{k,\phi}, \; \; &\forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi \\
    -\left[w_{i,\phi} - w_{j,\phi}\right] &\leq \left(\overline{\delta}^{|V|}_{k}\right)^2 + \tau^{w}_{k,\phi}, \; \; &\forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi
\end{align}
```

math```
\begin{align}
        \tau^{V}_{k,\phi} = \frac{\upsilon^{w}_{k,\phi}}{\left(\overline{\delta}^{|V|}_{k}\right)^2}, \; \; \forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi
\end{align}
```

where

math```
\begin{align}
    \upsilon^{w}_{k,\phi} \geq 2 (\underline{\tau}^{|V|}_{k})^2 \tau^{w}_{k,\phi} - (\underline{\tau}^{|V|}_{k})^4 \\
    \upsilon^{w}_{k,\phi} \geq 2 (\overline{\tau}^{|V|}_{k})^2 \tau^{w}_{k,\phi} - (\overline{\tau}^{|V|}_{k})^4 \\
    \upsilon^{w}_{k,\phi} \leq \left((\overline{\tau}^{|V|}_{k})^2 + (\underline{\tau}^{|V|}_{k})^2\right) \tau^{w}_{k,\phi} - (\overline{\tau}^{|V|}_{k})^2(\underline{\tau}^{|V|}_{k})^2 \\
\end{align}
```
"""
function constraint_mc_switch_open_voltage_distance(pm::PMD.AbstractUnbalancedWModels, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}, vm_delta_pu::Real, ::Real)
    w_fr = var(pm, nw, :w, f_bus)
    w_to = var(pm, nw, :w, t_bus)


    vmax = max(ref(pm, nw, :bus, f_bus, "vmax"),ref(pm, nw, :bus, t_bus, "vmax"))
    sw_w_slack = JuMP.@variable(pm.model, [c in 1:length(f_connections)], base_name="$(nw)_sw_w_slack_$(i)", start=0, lower_bound=-vmax[f_connections[c]]^2, upper_bound=vmax[f_connections[c]]^2)

    if vm_delta_pu < Inf
        for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
            JuMP.@constraint(pm.model,   w_fr[fc] - w_to[tc]  <= vm_delta_pu^2 + sw_w_slack[idx])
            JuMP.@constraint(pm.model, -(w_fr[fc] - w_to[tc]) <= vm_delta_pu^2 + sw_w_slack[idx])
        end
    end

    sw_w_sqr_slack = JuMP.@variable(pm.model, [c in 1:length(f_connections)], base_name="$(nw)_sw_w_sqr_slack_$(i)", start=0, lower_bound=0, upper_bound=vmax[f_connections[c]]^4)
    for idx in 1:length(f_connections)
        IM.relaxation_product(pm.model, sw_w_slack[idx], sw_w_slack[idx], sw_w_sqr_slack[idx])
    end

    var(pm, nw, :sw_v_slack)[i] = sw_w_sqr_slack ./ vm_delta_pu^2
end


@doc raw"""
    constraint_mc_switch_open_voltage_distance(pm::PMD.AbstractUnbalancedPolarModels, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}, vm_delta_pu::Real, ::Real)

Constraints for voltages on either side of an open switch to be within some distance of one another (provided by user) for Polar models
math```
\begin{align}
    |V_{i,\phi}|-|V_{j,\phi}| &\leq \overline{\delta}^{|V|}_{k} + \tau^{|V|}_{k,\phi},   \; \; & \forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi \\
    -\left[|V_{i,\phi}|-|V_{j,\phi}|\right] &\leq \overline{\delta}^{|V|}_{k} + \tau^{|V|}_{k,\phi},   \; \; &\forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi \\
    \angle V_{i,\phi}-\angle V_{j,\phi} &\leq \overline{\delta}^{\angle V}_{k} + \tau^{\angle V}_{k,\phi},   \; \; &\forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi \\
    -\left[\angle V_{i,\phi}-\angle V_{j,\phi}\right] &\leq \overline{\delta}^{\angle V}_{k} + \tau^{\angle V}_{k,\phi},   \; \; &\forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi
\end{align}
```

math```
\begin{align}
        \tau^{V}_{k,\phi} = \left(\frac{\tau^{|V|}_{k,\phi}}{\overline{\delta}^{|V|}_{k,\phi}}\right)^2 +\left(\frac{\tau^{\angle V}_{k,\phi}}{\overline{\delta}^{\angle V}_{k,\phi}}\right)^2, \; \; \forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi
\end{align}
```
"""
function constraint_mc_switch_open_voltage_distance(pm::PMD.AbstractUnbalancedPolarModels, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}, vm_delta_pu::Real, va_delta_deg::Real)
    vm_fr = var(pm, nw, :vm, f_bus)
    vm_to = var(pm, nw, :vm, t_bus)

    va_fr = var(pm, nw, :va, f_bus)
    va_to = var(pm, nw, :va, t_bus)

    vmax = max(ref(pm, nw, :bus, f_bus, "vmax"),ref(pm, nw, :bus, t_bus, "vmax"))
    sw_vm_slack = JuMP.@variable(pm.model, [c in 1:length(f_connections)], base_name="$(nw)_sw_vm_slack_$(i)", start=0, lower_bound=-vmax[f_connections[c]]^2, upper_bound=vmax[f_connections[c]]^2)
    sw_va_slack = JuMP.@variable(pm.model, [c in 1:length(f_connections)], base_name="$(nw)_sw_va_slack_$(i)", start=0, lower_bound=-pi, upper_bound=pi)

    if vm_delta_pu < Inf
        for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
            JuMP.@constraint(pm.model,   vm_fr[fc] - vm_to[tc]  <= vm_delta_pu + sw_vm_slack[idx] )
            JuMP.@constraint(pm.model, -(vm_fr[fc] - vm_to[tc]) <= vm_delta_pu + sw_vm_slack[idx])
        end
    end

    if va_delta_deg < Inf
        for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
            JuMP.@constraint(pm.model,   va_fr[fc] - va_to[tc]  <= deg2rad(va_delta_deg) + sw_va_slack[idx] )
            JuMP.@constraint(pm.model, -(va_fr[tc] - va_to[fc]) <= deg2rad(va_delta_deg) + sw_va_slack[idx])
        end
    end

    var(pm, nw, :sw_v_slack)[i] = (sw_vm_slack ./ vm_delta_pu).^2 .+ (sw_va_slack ./ deg2rad(va_delta_deg)).^2
end


@doc raw"""
    constraint_mc_switch_open_voltage_distance(pm::PMD.AbstractUnbalancedRectangularModels, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}, vm_delta_pu::Real, ::Real)

Constraints for voltages on either side of an open switch to be within some distance of one another (provided by user) for Rectangular models
math```
\begin{align}
    \sqrt{\Re{V_{i,\phi}}^2 + \Im{V_{i,\phi}}^2}-\sqrt{\Re{V_{j,\phi}}^2 + \Im{V_{j,\phi}}^2} &\leq \overline{\delta}^{|V|}_{k} + \tau^{|V|}_{k,\phi},   \; \; &\forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi \\
    -\left[\sqrt{\Re{V_{i,\phi}}^2 + \Im{V_{i,\phi}}^2}-\sqrt{\Re{V_{j,\phi}}^2 + \Im{V_{j,\phi}}^2}\right] &\leq \overline{\delta}^{|V|}_{k} + \tau^{|V|}_{k,\phi},   \; \; &\forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi \\
    \arctan{\left(\frac{\Im{V_{i,\phi}}}{\Re{V_{i,\phi}}}\right)}-\arctan{\left(\frac{\Im{V_{j,\phi}}}{\Re{V_{j,\phi}}}\right)} &\leq \overline{\delta}^{\angle V}_{k} + \tau^{\angle V}_{k,\phi},   \; \; &\forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi \\
    -\left[\arctan{\left(\frac{\Im{V_{i,\phi}}}{\Re{V_{i,\phi}}}\right)}-\arctan{\left(\frac{\Im{V_{j,\phi}}}{\Re{V_{j,\phi}}}\right)}\right] &\leq \overline{\delta}^{\angle V}_{k} + \tau^{\angle V}_{k,\phi},   \; \; &\forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi
\end{align}
```

math```
\begin{align}
        \tau^{V}_{k,\phi} = \left(\frac{\tau^{|V|}_{k,\phi}}{\overline{\delta}^{|V|}_{k,\phi}}\right)^2 +\left(\frac{\tau^{\angle V}_{k,\phi}}{\overline{\delta}^{\angle V}_{k,\phi}}\right)^2, \; \; \forall (i,j,k) \in {\cal E}_{sw}^{\mathrm{open}},\forall \phi \in \Phi
\end{align}

```
"""
function constraint_mc_switch_open_voltage_distance(pm::PMD.AbstractUnbalancedRectangularModels, nw::Int, i::Int, f_bus::Int, t_bus::Int, f_connections::Vector{Int}, t_connections::Vector{Int}, vm_delta_pu::Real, va_delta_deg::Real)
    vr_fr = var(pm, nw, :vr, f_bus)
    vi_fr = var(pm, nw, :vi, f_bus)
    vr_to = var(pm, nw, :vr, t_bus)
    vi_to = var(pm, nw, :vi, t_bus)

    vmax = max(ref(pm, nw, :bus, f_bus, "vmax"),ref(pm, nw, :bus, t_bus, "vmax"))
    sw_vm_slack = JuMP.@variable(pm.model, [c in 1:length(f_connections)], base_name="$(nw)_sw_vm_slack_$(i)", start=0, lower_bound=-vmax[f_connections[c]]^2, upper_bound=vmax[f_connections[c]]^2)
    sw_va_slack = JuMP.@variable(pm.model, [c in 1:length(f_connections)], base_name="$(nw)_sw_va_slack_$(i)", start=0, lower_bound=-2pi, upper_bound=2pi)

    if vm_delta_pu < Inf
        for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
            JuMP.@NLconstraint(pm.model,   sqrt(vr_fr[fc]^2 + vi_fr[fc]^2) - sqrt(vr_to[tc]^2 + vi_to[tc]^2)  <= vm_delta_pu + sw_vm_slack[idx])
            JuMP.@NLconstraint(pm.model, -(sqrt(vr_fr[fc]^2 + vi_fr[fc]^2) - sqrt(vr_to[tc]^2 + vi_to[tc]^2)) <= vm_delta_pu + sw_vm_slack[idx])
        end
    end

    if va_delta_deg < Inf
        for (idx, (fc, tc)) in enumerate(zip(f_connections, t_connections))
            JuMP.@NLconstraint(pm.model,   atan(vi_fr[fc], vr_fr[fc]) - atan(vi_to[tc], vr_to[tc])  <= deg2rad(va_delta_deg) + sw_va_slack[idx])
            JuMP.@NLconstraint(pm.model, -(atan(vi_fr[fc], vr_fr[fc]) - atan(vi_to[tc], vr_to[tc])) <= deg2rad(va_delta_deg) + sw_va_slack[idx])
        end
    end

    var(pm, nw, :sw_v_slack)[i] = (sw_vm_slack ./ vm_delta_pu).^2 .+ (sw_va_slack ./ deg2rad(va_delta_deg)).^2
end
