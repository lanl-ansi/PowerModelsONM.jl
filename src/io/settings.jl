"""
    parse_settings!(
        args::Dict{String,<:Any};
        apply::Bool=true,
        validate::Bool=true
    )::Dict{String,Any}

Parses settings file specifed in runtime arguments in-place

Will attempt to convert depreciated runtime arguments to appropriate network settings
data structure.

## Validation

If `validate=true` (default), the parsed data structure will be validated against the latest [Settings Schema](@ref Settings-Schema).
"""
function parse_settings!(args::Dict{String,<:Any}; apply::Bool=true, validate::Bool=true)::Dict{String,Any}
    if !isempty(get(args, "settings", ""))
        if isa(args["settings"], String)
            args["settings"] = parse_settings(args["settings"]; validate=validate)
        end
    else
        args["settings"] = Dict{String,Any}()
    end

    # Handle depreciated command line arguments
    _convert_depreciated_runtime_args!(args, args["settings"], args["base_network"], length(args["network"]["nw"]))

    apply && apply_settings!(args)

    return args["settings"]
end


"""
    _convert_depreciated_runtime_args!(
        runtime_args::Dict{String,<:Any},
        settings::Dict{String,<:Any},
        base_network::Dict{String,<:Any},
        timesteps::Int
    )::Tuple{Dict{String,Any},Dict{String,Any}}

Helper function to convert depreciated runtime arguments to their appropriate network settings structure
"""
function _convert_depreciated_runtime_args!(runtime_args::Dict{String,<:Any}, settings::Dict{String,<:Any}, base_network::Dict{String,<:Any}, timesteps::Int)::Tuple{Dict{String,Any},Dict{String,Any}}
    haskey(runtime_args, "voltage-lower-bound") && _convert_voltage_bound_to_settings!(settings, base_network, "vm_lb", pop!(runtime_args, "voltage-lower-bound"))
    haskey(runtime_args, "voltage-upper-bound") && _convert_voltage_bound_to_settings!(settings, base_network, "vm_ub", pop!(runtime_args, "voltage-upper-bound"))
    haskey(runtime_args, "voltage-angle-difference") && _convert_to_settings!(settings, base_network, "line", "vad_lb", -runtime_args["voltage-angle-difference"])
    haskey(runtime_args, "voltage-angle-difference") && _convert_to_settings!(settings, base_network, "line", "vad_ub",  pop!(runtime_args, "voltage-angle-difference"))
    haskey(runtime_args, "clpu-factor") && _convert_to_settings!(settings, base_network, "load", "clpu_factor", pop!(runtime_args, "clpu-factor"); multiphase=false)

    for k in [
        "disable-networking",
        "disable-switch-penalty",
        "apply-switch-scores",
        "disable-radial-constraint",
        "disable-isolation-constraint",
        "max-switch-actions",
        "disable-inverter-constraint",
        "disable-presolver"
    ]
        if haskey(runtime_args, k)
            settings[replace(k, "-"=>"_")] = pop!(runtime_args, k)
        end
    end

    if haskey(runtime_args, "timestep-hours")
        settings["time_elapsed"] = fill(pop!(runtime_args, "timestep-hours"), timesteps)
    end

    if haskey(runtime_args, "solver-tolerance")
        settings["nlp_solver_tol"] = pop!(runtime_args, "solver-tolerance")
    end

    return runtime_args, settings
end


"""
    parse_settings(
        settings_file::String;
        validate::Bool=true
    )::Dict{String,Any}

Parses network settings JSON file.

## Validation

If `validate=true` (default), the parsed data structure will be validated against the latest [Settings Schema](@ref Settings-Schema).
"""
function parse_settings(settings_file::String; validate::Bool=true)::Dict{String,Any}
    settings = JSON.parsefile(settings_file)

    if validate && !validate_settings(settings)
        error("'settings' file could not be validated")
    end

    PMD.correct_json_import!(settings)

    return settings
end


"""
    apply_settings!(args::Dict{String,Any})::Dict{String,Any}

Applies settings to the network.
"""
function apply_settings!(args::Dict{String,Any})::Dict{String,Any}
    args["network"] = apply_settings(args["network"], get(args, "settings", Dict()))
end


"""
    apply_settings(
        network::Dict{String,<:Any},
        settings::Dict{String,<:Any}
    )::Dict{String,Any}

Applies `settings` to multinetwork `network`
"""
function apply_settings(network::Dict{String,<:Any}, settings::Dict{String,<:Any})::Dict{String,Any}
    mn_data = deepcopy(network)

    for (s, setting) in settings
        if s in PMD.pmd_eng_asset_types
            _apply_to_network!(mn_data, s, setting)
        elseif s == "time_elapsed"
            PMD.set_time_elapsed!(mn_data, setting)
        elseif s == "max_switch_actions"
            for n in sort([parse(Int, i) for i in keys(mn_data["nw"])])
                if n == 0 && isa(setting, Vector) && length(setting) == 1
                    mn_data["nw"]["$n"][s] = isa(setting, Vector) ? setting[1] : setting
                else
                    mn_data["nw"]["$n"][s] = isa(setting, Vector) ? setting[n] : setting
                end
            end
        elseif s ∈ [
            "disable_networking",
            "disable_switch_penalty",
            "apply_switch_scores",
            "disable_radial_constraint",
            "disable_isolation_constraint",
            "disable_inverter_constraint",
            "disable_presolver",
        ]
            for (_,nw) in mn_data["nw"]
                nw[s] = setting
            end
        elseif s == "settings"
            for n in sort([parse(Int, i) for i in keys(mn_data["nw"])])
                for (k,v) in setting
                    if isa(v, Dict)
                        merge!(mn_data["nw"]["$n"]["settings"][k], v)
                    else
                        mn_data["nw"]["$n"]["settings"][k] = v
                    end
                end
            end
        end
    end

    mn_data
end


"""
    _convert_to_settings!(
        settings::Dict{String,<:Any},
        base_network::Dict{String,<:Any},
        asset_type::String,
        property::String,
        value::Any; multiphase::Bool=true
    )

Helper function to convert depreciated global settings, e.g., voltage-lower-bound, to the proper way to specify settings.
"""
function _convert_to_settings!(settings::Dict{String,<:Any}, base_network::Dict{String,<:Any}, asset_type::String, property::String, value::Any; multiphase::Bool=true)
    if haskey(base_network, asset_type)
        if !haskey(settings, asset_type)
            settings[asset_type] = Dict{String,Any}()
        end

        for (id, asset) in base_network[asset_type]
            if !haskey(settings[asset_type], id)
                settings[asset_type][id] = Dict{String,Any}()
            end

            nphases = asset_type == "bus" ? length(asset["terminals"]) : asset_type in PMD._eng_edge_elements ? asset_type == "transformer" && haskey(asset, "bus") ? length(asset["connections"][1]) : length(asset["f_connections"]) : length(asset["connections"])

            settings[asset_type][id][property] = multiphase ? fill(value, nphases) : value
        end
    end
end


"""
    _convert_voltage_bound_to_settings!(
        settings::Dict{String,<:Any},
        base_network::Dict{String,<:Any},
        bound_name::String,
        bound_value::Real
    )

Helper function to convert voltage bounds to the proper settings format.
"""
function _convert_voltage_bound_to_settings!(settings::Dict{String,<:Any}, base_network::Dict{String,<:Any}, bound_name::String, bound_value::Real)
    if !haskey(settings, "bus")
        settings["bus"] = Dict{String,Any}()
    end

    bus_vbase, line_vbase = PMD.calc_voltage_bases(base_network, base_network["settings"]["vbases_default"])
    for (id,bus) in get(base_network, "bus", Dict())
        if !haskey(settings["bus"], id)
            settings["bus"][id] = Dict{String,Any}()
        end

        settings["bus"][id][bound_name] = fill(bound_value * bus_vbase[id], length(bus["terminals"]))
    end
end


"""
    _apply_to_network!(
        network::Dict{String,<:Any},
        type::String,
        data::Dict{String,<:Any}
    )

Helper function that applies settings to the network objects of `type`.
"""
function _apply_to_network!(network::Dict{String,<:Any}, type::String, data::Dict{String,<:Any})
    for (_,nw) in network["nw"]
        if haskey(nw, type)
            for (id, _data) in data
                if haskey(nw[type], id)
                    merge!(nw[type][id], _data)
                end
            end
        end
    end
end


"""
    build_settings_file(
        network_file::String,
        settings_file::String="ieee13_settings.json";
        max_switch_actions::Union{Missing,Int,Vector{Int}},
        vm_lb_pu::Union{Missing,Real}=missing,
        vm_ub_pu::Union{Missing,Real}=missing,
        vad_deg::Union{Missing,Real}=missing,
        line_limit_mult::Real=1.0,
        sbase_default::Union{Missing,Real}=missing,
        time_elapsed::Union{Missing,Real,Vector{<:Real}}=missing,
        autogen_microgrid_ids::Bool=true,
        custom_settings::Dict{String,<:Any}=Dict{String,Any}(),
        mip_solver_gap::Real=0.05,
        nlp_solver_tol::Real=1e-4,
        mip_solver_tol::Real=1e-4,
        clpu_factor::Union{Missing,Real}=missing,
        disable_switch_penalty::Bool=false,
    )

Helper function to build a settings file (json) for use with ONM. If properties are `missing` they will not be set.

- `network_file::String` is the path to the input network file (dss)
- `settings_file::String` is the path to the output settings file (json)
- `max_switch_actions::Union{Int,Vector{Int}}` can be used to specify how many actions per time step,
  maximum, may be performed. Refers in particular to switch close actions. Can be specified as a single interger,
  which will be applied to each time step, or as a list, one number per time step. (default: `missing`)
- `vm_lb_pu::Real` can be used to specify the lower bound voltages on every bus in per-unit. (default: `missing`)
- `vm_ub_pu::Real` can be used to specify the upper bound voltages on every bus in per-unit. (default: `missing`)
- `vad_deg::Real` can be used to specify the lower/upper bound (range around 0.0) for every line in degrees
  (default: `missing`)
- `line_limit_mult::Real` can be used to apply a multiplicative factor to every line, switch, and transformer
  power/current rating (default: `1.0`)
- `sbase_default::Real` can be used to tune the sbase factor used to convert to per-unit, which may help with
  optimization stability (default: `missing`)
- `time_elapsed::Union{Real,Vector{Real}}` can be used to adjust the time step duration. Can be specified as a
  single number, or as a list, one number per time step. (default: `missing`)
- `autogen_microgrid_ids::Bool` toggles the automatic generation of microgrid 'ids', which are used in the ONM
  algorithm and statistical analyses (default: `missing`)
- `custom_settings:Dict{String,Any}` can be used to pass custom settings that will be applied **after** all of the
  autogenerated settings have been created (therefore, it will overwrite any autogenerated settings that it conflicts
  with via a recursive merge)
- `mip_solver_gap::Real` can be used to tune the acceptable gap for the MIP solver (default: `0.05`, i.e., 5%)
- `nlp_solver_tol::Real` can be used to tune the accceptable tolerance for constraint violations in the NLP solvers
  (default: `0.0001`)
- `mip_solver_tol::Real` can be used to tune the acceptable tolerance for constraint violations in the MIP solvers
  (default: `0.0001`)
- `clpu_factor::Real` can be used to set a factor for the cold-load pickup estimation (default: missing)
- `disable_switch_penalty::Bool` is a toggle for disabling the penalty applied to switching actions in the
  objective function (default: `false`)
- `apply_switch_scores::Bool` is a toggle to enable switch actions weights applied in the objective function
  (default: `false`)
- `disable_radial_constraint::Bool` is a toggle to disable the radiality constraint in the switching problem
  (default: `false`)
- `disable_isolation_constraint::Bool` is a toggle to disable the block isolation constraint in the switching
  problem (default: `false`)
- `disable_presolver::Bool` is a toggle to disable presolvers on built-in solvers that support it (Gurobi,
  KNITRO) (default: `false`)
- `storage_phase_unbalance_factor::Real` is a way to set the `phase_unbalance_factor` on *all* storage devices
  (default: `missing`)
"""
function build_settings_file(
    network_file::String,
    settings_file::String="ieee13_settings.json";
    max_switch_actions::Union{Missing,Int,Vector{Int}},
    vm_lb_pu::Union{Missing,Real}=missing,
    vm_ub_pu::Union{Missing,Real}=missing,
    vad_deg::Union{Missing,Real}=missing,
    line_limit_mult::Real=1.0,
    sbase_default::Union{Missing,Real}=missing,
    time_elapsed::Union{Missing,Real,Vector{Real}}=missing,
    autogen_microgrid_ids::Bool=true,
    custom_settings::Dict{String,<:Any}=Dict{String,Any}(),
    mip_solver_gap::Real=0.05,
    nlp_solver_tol::Real=1e-4,
    mip_solver_tol::Real=1e-4,
    clpu_factor::Union{Missing,Real}=missing,
    disable_switch_penalty::Bool=false,
    apply_switch_scores::Bool=false,
    disable_radial_constraint::Bool=false,
    disable_isolation_constraint::Bool=false,
    disable_inverter_constraint::Bool=false,
    storage_phase_unbalance_factor::Union{Missing,Real}=missing,
    disable_presolver::Bool=false,
    )

    eng = PMD.parse_file(network_file; transformations=[PMD.apply_kron_reduction!])
    n_steps = !haskey(eng, "time_series") ? 1 : length(first(eng["time_series"]).second["values"])

    settings = Dict{String,Any}(
        "settings" => Dict{String,Any}("sbase_default"=>ismissing(sbase_default) ? eng["settings"]["sbase_default"] : sbase_default),
        "bus" => Dict{String,Any}(),
        "line" => Dict{String,Any}(),
        "switch" => Dict{String,Any}(),
        "transformer" => Dict{String,Any}(),
        "storage" => Dict{String,Any}(),
        "generator" => Dict{String,Any}(),
        "solar" => Dict{String,Any}(),
        "load" => Dict{String,Any}(),
        "shunt" => Dict{String,Any}(),
        "mip_solver_gap" => mip_solver_gap,
        "nlp_solver_tol" => nlp_solver_tol,
        "mip_solver_tol" => mip_solver_tol,
    )

    if !ismissing(time_elapsed)
        if !isa(time_elapsed, Vector)
            time_elapsed = fill(time_elapsed, n_steps)
        end
        settings["time_elapsed"] = time_elapsed
    end

    if !ismissing(max_switch_actions)
        if !isa(max_switch_actions, Vector)
            max_switch_actions = fill(max_switch_actions, n_steps)
        end
        settings["max_switch_actions"] = max_switch_actions
    end

    settings["disable_switch_penalty"] = disable_switch_penalty
    settings["apply_switch_scores"] = apply_switch_scores
    settings["disable_isolation_constraint"] = disable_isolation_constraint
    settings["disable_radial_constraint"] = disable_radial_constraint
    settings["disable_inverter_constraint"] = disable_inverter_constraint
    settings["disable_presolver"] = disable_presolver

    # Generate bus microgrid_ids
    if autogen_microgrid_ids
        # merge in switch default settings
        for (id, switch) in settings["switch"]
            merge!(eng["switch"][id], switch)
        end

        # identify load blocks
        blocks = PMD.identify_load_blocks(eng)

        # build list of blocks with enabled generation
        gen_blocks = [
            bl for bl in blocks if (
                any(g["bus"] in bl && g["status"] == PMD.ENABLED for (_,g) in get(eng, "storage", Dict())) ||
                any(g["bus"] in bl && g["status"] == PMD.ENABLED for (_,g) in get(eng, "solar", Dict())) ||
                any(g["bus"] in bl && g["status"] == PMD.ENABLED for (_,g) in get(eng, "generator", Dict()))
            )
        ]

        # assign microgrid ids
        for (i,b) in enumerate(gen_blocks)
            for bus in b
                eng["bus"][bus]["microgrid_id"] = "$i"
            end
        end
    end

    # Generate settings for buses
    PMD.apply_voltage_bounds!(eng; vm_lb=vm_lb_pu, vm_ub=vm_ub_pu, exclude=String[vs["bus"] for (_,vs) in get(eng, "voltage_source", Dict())])
    for (b, bus) in get(eng, "bus", Dict())
        if !(b in String[vs["bus"] for (_,vs) in get(eng, "voltage_source", Dict())])
            settings["bus"][b] = merge(
                get(settings["bus"], b, Dict{String,Any}()),
                Dict{String,Any}(
                    "vm_lb" => get(bus, "vm_lb", fill(0.0, length(bus["terminals"]))), # Voltage magnitude lower bound
                    "vm_ub" => get(bus, "vm_ub", fill(Inf, length(bus["terminals"]))), # Voltage magnitude upper bound
                )
            )
            if haskey(bus, "microgrid_id")
                settings["bus"][b] = merge(get(settings["bus"], b, Dict{String,Any}()), Dict{String,Any}("microgrid_id" => bus["microgrid_id"]))
            end
        end
    end

    # Generate settings for loads
    if !ismissing(clpu_factor)
        for (l,_) in get(eng, "load", Dict())
            settings["load"][l] = merge(
                get(settings["load"], l, Dict{String,Any}()),
                Dict{String,Any}(
                    "clpu_factor" => clpu_factor
                )
            )
        end
    end

    # Generate settings for lines
    PMD.adjust_line_limits!(eng, line_limit_mult)
    !ismissing(vad_deg) && PMD.apply_voltage_angle_difference_bounds!(eng, vad_deg)
    for (l, line) in get(eng, "line", Dict())
        settings["line"][l] = merge(
            get(settings["line"], l, Dict{String,Any}()),
            Dict{String,Any}(
                "vad_lb" => line["vad_lb"], # voltage angle difference lower bound
                "vad_ub" => line["vad_ub"], # voltage angle different upper bound
                "cm_ub" => get(line, "cm_ub", fill(Inf, length(line["f_connections"]))),
            )
        )
    end

    # Generate settings for switches
    for (s, switch) in get(eng, "switch", Dict())
        settings["switch"][s] = merge(
            get(settings["switch"], s, Dict{String,Any}()),
            Dict{String,Any}(
                "cm_ub" => get(switch, "cm_ub", fill(Inf, length(switch["f_connections"])))
            )
        )
    end

    # Generate settings for transformers
    PMD.adjust_transformer_limits!(eng, line_limit_mult)
    for (t, transformer) in get(eng, "transformer", Dict())
        settings["transformer"][t] = merge(
            get(settings["transformer"], t, Dict{String,Any}()),
            Dict{String,Any}(
                "sm_ub" => get(transformer, "sm_ub", Inf)
            )
        )
    end

    if !ismissing(storage_phase_unbalance_factor)
        for (i,strg) in get(eng, "storage", Dict())
            settings["storage"][i] = Dict{String,Any}(
                "phase_unbalance_factor" => storage_phase_unbalance_factor
            )
        end
    end

    settings = recursive_merge(settings, custom_settings)

    # Save the ieee13_settings.json file
    open(settings_file, "w") do io
        JSON.print(io, settings)
    end
end
