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

    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :bus,     :status, ids(pm, nw, :bus),     Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :bus_block_map, i))     for i in ids(pm, nw, :bus)))
    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load,    :status, ids(pm, nw, :load),    Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :load_block_map, i))    for i in ids(pm, nw, :load)))
    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :shunt,   :status, ids(pm, nw, :shunt),   Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :shunt_block_map, i))   for i in ids(pm, nw, :shunt)))
    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :gen,     :status, ids(pm, nw, :gen),     Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :gen_block_map, i))     for i in ids(pm, nw, :gen)))
    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :storage, :status, ids(pm, nw, :storage), Dict{Int,Any}(i => var(pm, nw, :z_block, ref(pm, nw, :storage_block_map, i)) for i in ids(pm, nw, :storage)))
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
    if ref(pm, nw, :options, "constraints")["disable-microgrid-expansion"]
        dispatchable_switches = [i for (i,sw) in ref(pm, nw, :switch) if !isempty(get(ref(pm, nw, :bus, sw["f_bus"]), "microgrid_id", "")) && !isempty(get(ref(pm, nw, :bus, sw["t_bus"]), "microgrid_id", "")) && ref(pm, nw, :bus, sw["f_bus"], "microgrid_id") == ref(pm, nw, :bus, sw["t_bus"], "microgrid_id")]
    else
        dispatchable_switches = collect(ids(pm, nw, :switch_dispatchable))
    end

    state = var(pm, nw)[:switch_state] = Dict{Int,Any}(
        l => JuMP.@variable(
            pm.model,
            base_name="$(nw)_switch_state_$(l)",
            binary=!relax,
            lower_bound=0,
            upper_bound=1,
            start=PMD.comp_start_value(ref(pm, nw, :switch, l), "state_start", get(ref(pm, nw, :switch, l), "state", 1))
        ) for l in dispatchable_switches
    )

    # create variables (constants) for 'fixed' (non-dispatchable) switches
    fixed_switches = [i for i in ids(pm, nw, :switch) if i ∉ dispatchable_switches]

    for i in fixed_switches
        var(pm, nw, :switch_state)[i] = ref(pm, nw, :switch, i, "state")
    end

    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :switch, :state, dispatchable_switches, state)
    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :switch, :state, fixed_switches, Dict{Int,Any}(i => var(pm, nw, :switch_state, i) for i in fixed_switches))
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

    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :bus, :status, ids(pm, nw, :bus), z_voltage)
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

    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :gen, :status, ids(pm, nw, :gen), z_gen)
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

    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :storage, :status, ids(pm, nw, :storage), z_storage)
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

    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :load, :status, ids(pm, nw, :load), z_demand)
end


"""
    variable_inverter_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)

Variables for indicating whether a DER (storage or gen) is in grid-forming mode (1) or grid-following mode (0), binary is `relax=false`.
Variables will appear in solution if `report=true`. If "inverter"==GRID_FOLLOWING on the device, the inverter variable will be a constant.
"""
function variable_inverter_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, relax::Bool=false, report::Bool=true)
    z_inverter = var(pm, nw)[:z_inverter] = Dict{Tuple{Symbol,Int},Union{JuMP.VariableRef,Int}}()
    for t in [:storage, :gen]
        for i in ids(pm, nw, t)
            if Int(get(ref(pm, nw, t, i), "inverter", GRID_FORMING)) == 1
                var(pm, nw, :z_inverter)[(t,i)] = JuMP.@variable(
                    pm.model,
                    base_name="$(nw)_$(t)_z_inverter",
                    binary=!relax,
                    lower_bound=0,
                    upper_bound=1,
                    start=PMD.comp_start_value(ref(pm, nw, t, i), "inverter_start", Int(get(ref(pm, nw, t, i), "inverter", GRID_FORMING))),
                )
            else
                # GRID_FOLLOWING only
                var(pm, nw, :z_inverter)[(t,i)] = Int(ref(pm, nw, t, i, "inverter"))
            end
        end
    end

    if report
        IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :storage, :inverter, [i for ((t,i),_) in var(pm, nw, :z_inverter) if t == :storage], Dict{Int,Union{JuMP.VariableRef,Int}}(i => v for ((t,i),v) in filter(x->x.first[1]==:storage, z_inverter)))
        IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :gen, :inverter, [i for ((t,i),_) in var(pm, nw, :z_inverter) if t == :gen], Dict{Int,Union{JuMP.VariableRef,Int}}(i => v for ((t,i),v) in filter(x->x.first[1]==:gen, z_inverter)))
    end
end


"""
    variable_mc_load_power(pm::PMD.AbstractUBFModels, scen::Int; nw=nw_id_default, report::Bool=false)

Load variables creation for robust mld problem. The bounds are different for each scenario.
"""
function variable_mc_load_power(pm::PMD.AbstractUBFModels, scen::Int; nw=nw_id_default, report::Bool=false)
    load_wye_ids = [id for (id, load) in ref(pm, nw, :load) if load["configuration"]==PMD.WYE]
    load_del_ids = [id for (id, load) in ref(pm, nw, :load) if load["configuration"]==PMD.DELTA]
    load_cone_ids = [id for (id, load) in ref(pm, nw, :load) if PMD._check_load_needs_cone(load)]
    load_connections = Dict{Int,Vector{Int}}(id => load["connections"] for (id,load) in ref(pm, nw, :load))

    # create dictionaries
    pd_bus = var(pm, nw)[:pd_bus] = Dict()
    qd_bus = var(pm, nw)[:qd_bus] = Dict()
    pd = var(pm, nw)[:pd] = Dict()
    qd = var(pm, nw)[:qd] = Dict()

    # variable_mc_load_power
    for i in intersect(load_wye_ids, load_cone_ids)
		pd[i] = JuMP.@variable(
			pm.model,
        	[c in load_connections[i]],
			base_name="0_pd_$(i)"
        )
    	qd[i] = JuMP.@variable(
			pm.model,
        	[c in load_connections[i]],
			base_name="0_qd_$(i)"
        )

		load = ref(pm, nw, :load, i)
		bus = ref(pm, nw, :bus, load["load_bus"])
        load_scen = deepcopy(load)
        load_scen["pd"] = load_scen["pd"]*ref(pm, :scenarios, "load")["$scen"]["$i"]
        load_scen["qd"] = load_scen["qd"]*ref(pm, :scenarios, "load")["$scen"]["$i"]
		pmin, pmax, qmin, qmax = PMD._calc_load_pq_bounds(load_scen, bus)
		for (idx,c) in enumerate(load_connections[i])
			PMD.set_lower_bound(pd[i][c], pmin[idx])
			PMD.set_upper_bound(pd[i][c], pmax[idx])
			PMD.set_lower_bound(qd[i][c], qmin[idx])
			PMD.set_upper_bound(qd[i][c], qmax[idx])
		end
	end

    # now, create auxilary power variable X for delta loads
    bound = Dict{eltype(load_del_ids), Matrix{Real}}()
    for id in load_del_ids
        load = ref(pm, nw, :load, id)
        bus = ref(pm, nw, :bus, load["load_bus"])
        load_scen = deepcopy(load)
        load_scen["pd"] = load_scen["pd"]*ref(pm, :scenarios, "load")["$scen"]["$(id)"]
        load_scen["qd"] = load_scen["qd"]*ref(pm, :scenarios, "load")["$scen"]["$(id)"]
        cmax = PMD._calc_load_current_max(load_scen, bus)
        bound[id] = bus["vmax"][[findfirst(isequal(c), bus["terminals"]) for c in conn_bus[id]]]*cmax'
    end
    (Xdr,Xdi) = PMD.variable_mx_complex(pm.model, load_del_ids, load_connections, load_connections; symm_bound=bound, name="0_Xd")
    var(pm, nw)[:Xdr] = Xdr
    var(pm, nw)[:Xdi] = Xdi

    # only delta loads need a current variable
    cmin = Dict{eltype(load_del_ids), Vector{Real}}()
    cmax = Dict{eltype(load_del_ids), Vector{Real}}()
    for id in load_del_ids
		bus = ref(pm, nw, :bus, load["load_bus"])
        load_scen = deepcopy(load)
        load_scen["pd"] = load_scen["pd"]*ref(pm, :scenarios, "load")["$scen"]["$(id)"]
        load_scen["qd"] = load_scen["qd"]*ref(pm, :scenarios, "load")["$scen"]["$(id)"]
        cmin[id], cmax[id] = PMD._calc_load_current_magnitude_bounds(load_scen, bus)
    end
    (CCdr, CCdi) = PMD.variable_mx_hermitian(pm.model, load_del_ids, load_connections; sqrt_upper_bound=cmax, sqrt_lower_bound=cmin, name="0_CCd")
    var(pm, nw)[:CCdr] = CCdr
    var(pm, nw)[:CCdi] = CCdi

end


"""
    variable_robust_inverter_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, report::Bool=true)

Robust mld (outer) problem solution for indicating whether a DER (storage or gen) is in grid-forming mode (1) or grid-following mode (0).
"""
function variable_robust_inverter_indicator(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, report::Bool=true)
    z_inverter = var(pm, nw)[:z_inverter] = Dict{Tuple{Symbol,Int},Any}()
    for t in [:storage, :gen]
        for i in ids(pm, nw, t)
            var(pm, nw, :z_inverter)[(t,i)] = Int(ref(pm, nw, t, i, "inverter"))
        end
    end

    if report
        IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :storage, :inverter, [i for ((t,i),_) in var(pm, nw, :z_inverter) if t == :storage], Dict{Int,Any}(i => v for ((t,i),v) in filter(x->x.first[1]==:storage, z_inverter)))
        IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :gen, :inverter, [i for ((t,i),_) in var(pm, nw, :z_inverter) if t == :gen], Dict{Int,Any}(i => v for ((t,i),v) in filter(x->x.first[1]==:gen, z_inverter)))
    end
end


"""
    variable_robust_switch_state(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, report::Bool=true)

Robust mld (outer) problem solution for switch state (open/close) variables
"""
function variable_robust_switch_state(pm::AbstractUnbalancedPowerModel; nw::Int=nw_id_default, report::Bool=true)
    if ref(pm, nw, :options, "constraints")["disable-microgrid-expansion"]
        dispatchable_switches = [i for (i,sw) in ref(pm, nw, :switch) if !isempty(get(ref(pm, nw, :bus, sw["f_bus"]), "microgrid_id", "")) && !isempty(get(ref(pm, nw, :bus, sw["t_bus"]), "microgrid_id", "")) && ref(pm, nw, :bus, sw["f_bus"], "microgrid_id") == ref(pm, nw, :bus, sw["t_bus"], "microgrid_id")]
    else
        dispatchable_switches = collect(ids(pm, nw, :switch_dispatchable))
    end

    state = var(pm, nw)[:switch_state] = Dict{Int,Any}(
        l => ref(pm, nw, :switch, l, "state") for l in dispatchable_switches
    )

    # create variables (constants) for 'fixed' (non-dispatchable) switches
    fixed_switches = [i for i in ids(pm, nw, :switch) if i ∉ dispatchable_switches]

    for i in fixed_switches
        var(pm, nw, :switch_state)[i] = ref(pm, nw, :switch, i, "state")
    end

    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :switch, :state, dispatchable_switches, state)
    report && IM.sol_component_value(pm, PMD.pmd_it_sym, nw, :switch, :state, fixed_switches, Dict{Int,Any}(i => var(pm, nw, :switch_state, i) for i in fixed_switches))
end
