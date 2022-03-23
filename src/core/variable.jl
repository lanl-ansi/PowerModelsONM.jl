@doc raw"""
    variable_block_indicator(
        pm::AbstractUnbalancedPowerModel;
        nw::Int=nw_id_default,
        relax::Bool=false,
        report::Bool=true
    )

Create variables for block status by load block, $$z^{bl}_i\in{0,1}~\forall i \in B$$, binary if `relax=false`.
Variables will appear in solution if `report=true`.
"""
function variable_block_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    z_block = var(pm, nw)[:z_block] = JuMP.@variable(pm.model,
        [i in ids(pm, nw, :blocks)], base_name="$(nw)_z_block",
        binary=!relax,
        lower_bound=0,
        upper_bound=1,
        start=1
    )

    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :bus,     :status, ids(pm, nw, :bus),     Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, i))     for i in ids(pm, nw, :bus)))
    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load,    :status, ids(pm, nw, :load),    Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :load_block_map, i))    for i in ids(pm, nw, :load)))
    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :shunt,   :status, ids(pm, nw, :shunt),   Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :shunt_block_map, i))   for i in ids(pm, nw, :shunt)))
    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :gen,     :status, ids(pm, nw, :gen),     Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :gen_block_map, i))     for i in ids(pm, nw, :gen)))
    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :storage, :status, ids(pm, nw, :storage), Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i)) for i in ids(pm, nw, :storage)))
end


@doc raw"""
    variable_switch_state(
        pm::AbstractUnbalancedPowerModel;
        nw::Int=nw_id_default,
        report::Bool=true,
        relax::Bool=false
    )

Create variables for switch state (open/close) variables, $$\gamma_i\in{0,1}~\forall i \in S$$, binary if `relax=false`.
Variables for non-dispatchable switches will be constants, rather than `VariableRef`. Variables will appear in
solution if `report=true`.
"""
function variable_switch_state(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, report::Bool=true, relax::Bool=false)
    state = var(pm, nw)[:switch_state] = Dict{Int,Any}(
        l => JuMP.@variable(
            pm.model,
            base_name="$(nw)_switch_state_$(l)",
            binary=!relax,
            lower_bound=0,
            upper_bound=1,
            start=PMD.comp_start_value(ref(pm, nw, :switch, l), "state_start", get(ref(pm, nw, :switch, l), "state", 1))
        ) for l in ids(pm, nw, :switch_dispatchable)
    )

    # create variables (constants) for 'fixed' (non-dispatchable) switches
    dispatchable_switches = collect(ids(pm, nw, :switch_dispatchable))
    fixed_switches = [i for i in ids(pm, nw, :switch) if i ∉ dispatchable_switches]

    for i in fixed_switches
        var(pm, nw, :switch_state)[i] = ref(pm, nw, :switch, i, "state")
    end

    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :switch, :state, ids(pm, nw, :switch_dispatchable), state)
    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :switch, :state, fixed_switches, Dict{Int,Any}(i => var(pm, nw, :switch_state, i) for i in fixed_switches))
end


@doc raw"""
    variable_mc_storage_power_mi_on_off(
        pm::AbstractUnbalancedPowerModel;
        nw::Int=nw_id_default,
        relax::Bool=false,
        bounded::Bool=true,
        report::Bool=true
    )

Variables for storage, *omitting* the storage indicator $$z^{strg}_i$$ variable:

```math
\begin{align}
p^{strg}_i,~\forall i \in S \\
q^{strg}_i,~\forall i \in S \\
q^{sc}_{i},~\forall i \in S \\
\epsilon_i,~\forall i \in S \\
c^{strg}_i,~\forall i \in S \\
c^{on}_i \in {0,1},~\forall i \in S \\
d^{on}_i \in {0,1},~\forall i \in S \\
\end{align}
```

$$c^{on}_i$$, $$d^{on}_i$$ will be binary if `relax=false`. Variables will appear in solution if `report=true`.
"""
function variable_mc_storage_power_mi_on_off(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, bounded::Bool=true, report::Bool=true)
    PMD.variable_mc_storage_power_real_on_off(pm; nw=nw, bounded=bounded, report=report)
    PMD.variable_mc_storage_power_imaginary_on_off(pm; nw=nw, bounded=bounded, report=report)
    PMD.variable_mc_storage_power_control_imaginary_on_off(pm; nw=nw, bounded=bounded, report=report)
    PMD.variable_mc_storage_current(pm; nw=nw, bounded=bounded, report=report)
    PMD.variable_storage_energy(pm; nw=nw, bounded=bounded, report=report)
    PMD.variable_storage_charge(pm; nw=nw, bounded=bounded, report=report)
    PMD.variable_storage_discharge(pm; nw=nw, bounded=bounded, report=report)
    PMD.variable_storage_complementary_indicator(pm; nw=nw, relax=relax, report=report)
end


@doc raw"""
    variable_bus_voltage_indicator(
        pm::AbstractUnbalancedPowerModel;
        nw::Int=nw_id_default,
        relax::Bool=false,
        report::Bool=true
    )

Variables for switching buses on/off $$z^{bus}_i,~\forall i \in N$$, binary if `relax=false`.
Variables will appear in solution if `report=true`.
"""
function variable_bus_voltage_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    z_voltage = var(pm, nw)[:z_voltage] = JuMP.@variable(
        pm.model,
        [i in ids(pm, nw, :bus)],
        base_name="$(nw)_z_voltage",
        binary=!relax,
        lower_bound=0,
        upper_bound=1,
        start=1
    )

    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :bus, :status, ids(pm, nw, :bus), z_voltage)
end


@doc raw"""
    variable_generator_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)

Variables for switching generators on/off $$z^{gen}_i,~\forall i \in G$$, binary if `relax=false`.
Variables will appear in solution if `report=true`.
"""
function variable_generator_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    z_gen = var(pm, nw)[:z_gen] = JuMP.@variable(
        pm.model,
        [i in ids(pm, nw, :gen)],
        base_name="$(nw)_z_gen",
        binary=!relax,
        lower_bound=0,
        upper_bound=1,
        start=1
    )

    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :gen, :status, ids(pm, nw, :gen), z_gen)
end


@doc raw"""
    variable_storage_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)

Variables for switching storage on/off $$z^{strg}_i,~\forall i \in E$$, binary if `relax=false`.
Variables will appear in solution if `report=true`.
"""
function variable_storage_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    z_storage = var(pm, nw)[:z_storage] = JuMP.@variable(
        pm.model,
        [i in ids(pm, nw, :storage)],
        base_name="$(nw)_z_storage",
        binary=!relax,
        lower_bound=0,
        upper_bound=1,
        start=1
    )

    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :storage, :status, ids(pm, nw, :storage), z_storage)
end


@doc raw"""
    variable_load_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)

Variables for switching loads on/off $$z^{d}_i,~\forall i \in L$$, binary if `relax=false`.
Variables will appear in solution if `report=true`.
"""
function variable_load_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    z_demand = var(pm, nw)[:z_demand] = JuMP.@variable(
        pm.model,
        [i in ids(pm, nw, :load)],
        base_name="$(nw)_z_demand",
        binary=!relax,
        lower_bound=0,
        upper_bound=1,
        start=1
    )

    report && _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load, :status, ids(pm, nw, :load), z_demand)
end


"""
    variable_inverter_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)

Variables for indicating whether a DER (storage or gen) is in grid-forming mode (1) or grid-following mode (0), binary is `relax=false`.
Variables will appear in solution if `report=true`
"""
function variable_inverter_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    z_inverter = var(pm, nw)[:z_inverter] = Dict{Tuple{Symbol,Int},JuMP.VariableRef}()
    for t in [:storage, :gen]
        for i in ids(pm, nw, t)
            var(pm, nw, :z_inverter)[(t,i)] = JuMP.@variable(
                pm.model,
                base_name="$(nw)_$(t)_z_inverter",
                binary=!relax,
                lower_bound=0,
                upper_bound=1,
                start=1
            )
        end
    end

    if report
        _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :storage, :inverter, [i for ((t,i),_) in var(pm, nw, :z_inverter) if t == :storage], Dict{Int,JuMP.VariableRef}(i => v for ((t,i),v) in filter(x->x.first[1]==:storage, z_inverter)))
        _IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :gen, :inverter, [i for ((t,i),_) in var(pm, nw, :z_inverter) if t == :gen], Dict{Int,JuMP.VariableRef}(i => v for ((t,i),v) in filter(x->x.first[1]==:gen, z_inverter)))
    end
end
