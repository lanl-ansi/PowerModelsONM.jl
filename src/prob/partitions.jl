"""
"""
function generate_robust_partitions(data::Dict{String,<:Any}, contingencies::Set{<:Dict{String,<:Any}}, model_type::Type, solver; kwargs...)
    results = Dict{String,Any}()
    for state in contingencies
        eng = deepcopy(data)
        eng["switch"] = recursive_merge(get(eng, "switch", Dict{String,Any}()), state)

        eng["time_elapsed"] = 1.0  # TODO: what should the time_elapsed be? how long do we want partitions to be robust for?

        results[SHA.bytes2hex(SHA.sha1(join(sort(collect(keys(state))))))] = solve_robust_partitions(eng, model_type, solver; kwargs...)
    end

    return results
end


"""
"""
function generate_ranked_robust_partitions(data::Dict{String,<:Any}, results::Dict{String,<:Any})::Vector
    sorted_results = sort(collect(keys(results)); by=x->get(results[x], "objective", Inf) + get(results[x], "mip_gap", 0.0))

    configs = Set()

    partitions = Set{Dict{String,Any}}()
    rank = 1
    for id in sorted_results
        result = results[id]
        config = Dict{String,Any}(
            "configuration" => Dict{String,String}(
                data["switch"][s]["source_id"] => string(sw["state"]) for (s,sw) in get(get(result, "solution", Dict()), "switch", Dict())
            ),
            "shed" => [data["load"][l]["source_id"] for l in keys(filter(x->x.second["status"]==DISABLED, get(get(result, "solution", Dict()), "load", Dict())))],
        )

        if config ∉ configs
            push!(
                partitions,
                Dict{String,Any}(
                    "uuid" => string(UUIDs.uuid4()),
                    "rank" => rank,
                    "score" => round(get(result, "objective", Inf) + get(result, "mip_gap", 0.0); sigdigits=6),
                    config...
                )
            )
            rank += 1

            push!(configs, config)
        end
    end

    partitions = sort(collect(partitions); by=x->x["rank"])

    @assert validate_robust_partitions(partitions) evaluate_robust_partitions(partitions)

    return partitions
end


"""
"""
generate_n_minus_one_contingencies(data::Dict{String,<:Any})::Set{Dict{String,Any}} = generate_n_minus_contingencies(data, 1)


"""
"""
function generate_n_minus_contingencies(data::Dict{String,<:Any}, n_minus::Int)::Set{Dict{String,Any}}
    load_blocks = Dict{Int,Set{String}}(i => block for (i,block) in enumerate(PMD.identify_load_blocks(data)))
    @assert n_minus <= length(load_blocks)

    block_switches = Dict{Int,Set{String}}(i=>Set([s for (s,sw) in filter(x->x.second["f_bus"]∈block || x.second["t_bus"]∈block, get(data, "switch", Dict{String,Any}()))]) for (i,block) in load_blocks)

    contingencies = Set{Dict{String,Any}}()
    for n in 0:n_minus
        for block_ids in combinations(collect(keys(load_blocks)), n)
            push!(
                contingencies,
                Dict{String,Any}(s => Dict{String,Any}("dispatchable"=>NO,"state"=>OPEN,"status"=>ENABLED) for i in block_ids for s in block_switches[i])
            )
        end
    end

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
