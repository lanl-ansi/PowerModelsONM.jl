"""
"""
function generate_robust_partitions(data::Dict{String,<:Any}, contingencies::Vector{<:Dict{String,<:Any}}, model_type::Type, solver; kwargs...)::Tuple{Vector,Vector}
    results = Dict{String,Any}[]
    for state in contingencies
        eng = deepcopy(data)
        eng["switch"] = recursive_merge(get(eng, "switch", Dict{String,Any}()), state)

        eng["time_elapsed"] = 1.0  # TODO: what should the time_elapsed be for storage? how long do we want partitions to be robust for?

        push!(results, solve_robust_partitions(eng, model_type, solver))
    end

    sorted_results = sort(results; by=x->get(x, "objective", Inf))

    partitions = Dict{String,Any}[]
    for (i,result) in enumerate(sorted_results)
        push!(
            partitions,
            Dict{String,Any}(
                "uuid" => string(UUIDs.uuid4()),
                "rank" => i,
                "configuration" => Dict{String,Any}(
                    data["switch"][s]["source_id"] => string(sw["state"]) for (s,sw) in get(get(result, "solution", Dict()), "switch", Dict())
                ),
                "shed" => [data["load"][l]["source_id"] for l in keys(filter(x->x.second["status"]==DISABLED, get(get(result, "solution", Dict()), "load", Dict())))],
            )
        )
    end

    (partitions, sorted_results)
end


"""
"""
function generate_n_minus_one_contingencies(data::Dict{String,<:Any})::Vector{Dict{String,Any}}
    load_blocks = Dict{Int,Set{String}}(i => block for (i,block) in enumerate(PMD.identify_load_blocks(data)))
    block_switches = Dict{Int,Set{String}}(i=>Set([s for (s,sw) in filter(x->x.second["f_bus"]∈block || x.second["t_bus"]∈block, get(data, "switch", Dict{String,Any}()))]) for (i,block) in load_blocks)

    contingencies = Dict{String,Any}[Dict{String,Any}(s => Dict{String,Any}("dispatchable"=>NO,"state"=>OPEN,"status"=>ENABLED) for s in switches) for (i,switches) in block_switches]
    push!(contingencies, Dict{String,Any}())

    return contingencies
end


"""
"""
function solve_robust_partitions(data::Dict{String,<:Any}, model_type::Type, solver; kwargs...)::Dict{String,Any}
    solve_onm_model(data, model_type, solver, build_robust_partitions; multinetwork=false, kwargs...)
end


"""
"""
function build_robust_partitions(pm::PMD.AbstractUBFModels)
    var_opts = ref(pm, :options, "variables")
    con_opts = ref(pm, :options, "constraints")

    variable_block_indicator(pm; relax=var_opts["relax-integer-variables"])
    !con_opts["disable-grid-forming-inverter-constraint"] && variable_inverter_indicator(pm; relax=var_opts["relax-integer-variables"])

    PMD.variable_mc_bus_voltage_on_off(pm; bounded=!var_opts["unbound-voltage"])

    PMD.variable_mc_branch_current(pm; bounded=!var_opts["unbound-line-current"])
    PMD.variable_mc_branch_power(pm; bounded=!var_opts["unbound-line-power"])

    PMD.variable_mc_switch_power(pm; bounded=!var_opts["unbound-switch-power"])
    variable_switch_state(pm; relax=var_opts["relax-integer-variables"])

    PMD.variable_mc_transformer_power(pm; bounded=!var_opts["unbound-transformer-power"])
    PMD.variable_mc_oltc_transformer_tap(pm)

    PMD.variable_mc_generator_power_on_off(pm; bounded=!var_opts["unbound-generation-power"])

    variable_mc_storage_power_mi_on_off(pm; bounded=!var_opts["unbound-storage-power"], relax=var_opts["relax-integer-variables"])

    PMD.variable_mc_load_power(pm)

    PMD.variable_mc_capcontrol(pm; relax=var_opts["relax-integer-variables"])

    PMD.constraint_mc_model_current(pm)

    !con_opts["disable-grid-forming-inverter-constraint"] && constraint_grid_forming_inverter_per_cc_block(pm; relax=var_opts["relax-integer-variables"])

    if con_opts["disable-grid-forming-inverter-constraint"]
        for i in ids(pm, :ref_buses)
            PMD.constraint_mc_theta_ref(pm, i)
        end
    else
        for i in ids(pm, :bus)
            constraint_mc_inverter_theta_ref(pm, i)
        end
    end

    constraint_mc_bus_voltage_block_on_off(pm)

    for i in ids(pm, :gen)
        !var_opts["unbound-generation-power"] && constraint_mc_generator_power_block_on_off(pm, i)
    end

    for i in ids(pm, :load)
        PMD.constraint_mc_load_power(pm, i)
    end

    for i in ids(pm, :bus)
        constraint_mc_power_balance_shed_block(pm, i)
    end

    for i in ids(pm, :storage)
        PMD.constraint_storage_state(pm, i)
        constraint_storage_complementarity_mi_block_on_off(pm, i)
        constraint_mc_storage_block_on_off(pm, i)
        constraint_mc_storage_losses_block_on_off(pm, i)
        !con_opts["disable-thermal-limit-constraints"] && !var_opts["unbound-storage-power"] && PMD.constraint_mc_storage_thermal_limit(pm, i)
    end

    for i in ids(pm, :branch)
        PMD.constraint_mc_power_losses(pm, i)
        PMD.constraint_mc_model_voltage_magnitude_difference(pm, i)
        PMD.constraint_mc_voltage_angle_difference(pm, i)

        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_thermal_limit_from(pm, i)
        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_thermal_limit_to(pm, i)

        !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_ampacity_from(pm, i)
        !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_ampacity_to(pm, i)
    end

    con_opts["disable-microgrid-networking"] &&  constraint_disable_networking(pm; relax=var_opts["relax-integer-variables"])
    !con_opts["disable-radiality-constraint"] && constraint_radial_topology(pm; relax=var_opts["relax-integer-variables"])
    !con_opts["disable-block-isolation-constraint"] && constraint_isolate_block(pm)
    for i in ids(pm, :switch)
        constraint_mc_switch_state_open_close(pm, i)

        !con_opts["disable-thermal-limit-constraints"] && PMD.constraint_mc_switch_thermal_limit(pm, i)
        !con_opts["disable-current-limit-constraints"] && PMD.constraint_mc_switch_ampacity(pm, i)
    end

    for i in ids(pm, :transformer)
        constraint_mc_transformer_power_block_on_off(pm, i; fix_taps=false)
    end

    objective_robust_partitions(pm)
end
