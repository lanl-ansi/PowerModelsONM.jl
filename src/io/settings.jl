"Lookup for deprecated settings conversions that are not 1-to-1"
const settings_conversions = Dict{Tuple{Vararg{String}},Function}(
    ("solvers","HiGHS","presolve") => x->x ? "off" : "choose",
    ("solvers","Gurobi","Presolve") => x->x ? 0 : -1,
    ("solvers","KNITRO","presolve") => x->Int(!x),
    ("options","problem","operations-algorithm") => x->x∈["complete horizon", "global"] ? "full-lookahead" : x∈["rolling horizon", "iterative"] ? "rolling-horizon" : x,
)


"""
    parse_settings!(
        args::Dict{String,<:Any};
        apply::Bool=true,
        validate::Bool=true
    )::Dict{String,Any}

Parses settings file specifed in runtime arguments in-place

Will attempt to convert deprecated runtime arguments to appropriate network settings
data structure.

## Validation

If `validate=true` (default), the parsed data structure will be validated against the latest [Settings Schema](@ref Settings-Schema).
"""
function parse_settings!(args::Dict{String,<:Any}; apply::Bool=true, validate::Bool=true)::Dict{String,Any}
    if !isempty(get(args, "settings", ""))
        if isa(args["settings"], String)
            settings = parse_settings(args["settings"]; validate=validate)

            # Handle deprecated command line arguments
            correct_deprecated_settings!(settings)
            correct_deprecated_runtime_args!(args, settings)

            args["settings"] = settings
        end
    else
        args["settings"] = build_default_settings()
    end

    apply && isa(get(args, "network", ""), Dict) && apply_settings!(args)

    return args["settings"]
end


"""
    correct_settings!(settings::Dict{Strinig,<:Any})

Helper function to correct deprecated settings and convert JSON types to Julia types
"""
function correct_settings!(settings::Dict{String,<:Any})::Dict{String,Any}
    correct_json_import!(settings)
    correct_deprecated_settings!(settings)

    return settings
end


"""
    build_default_settings()::Dict{String,Any}

Builds a set of default settings from the settings schema
"""
function build_default_settings()::Dict{String,Any}
    settings_schema = load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas/input-settings.schema.json"))

    settings = init_settings_default!(Dict{String,Any}(), settings_schema.data)

    return filter(x->!isempty(x.second),correct_json_import!(settings))
end


"""
    init_settings_default!(settings::T, schema::T)::T where T <: Dict{String,Any}

Helper function to walk through the settings schema to initalize the default set of settings.
"""
function init_settings_default!(settings::T, schema::T)::T where T <: Dict{String,Any}
    if haskey(schema, "properties")
        for (prop_name,props) in schema["properties"]
            if !get(props, "deprecated", false)
                if isa(props, Dict) && haskey(props, "properties")
                    settings[prop_name] = Dict{String,Any}()
                    init_settings_default!(settings[prop_name], props)
                elseif isa(props, Dict) && haskey(props, "\$ref")
                    settings[prop_name] = Dict{String,Any}()
                    init_settings_default!(settings[prop_name], props["\$ref"])
                else
                    if haskey(props, "default")
                        settings[prop_name] = props["default"]
                    end
                end
            end
        end
    end

    return settings
end


"""
    get_deprecated_properties(schema::JSONSchema.Schema)::Dict{String,Any}

Walks through the settings schema to collect the deprecated properities
"""
function get_deprecated_properties(schema::JSONSchema.Schema)::Dict{String,Any}
    get_deprecated_properties(schema.data)
end


"""
    get_deprecated_properties(schema::T; deprecated_properties::Union{T,Missing}=missing)::T where T <: Dict{String,Any}

Recursive function to walk through a schema to discover the deprecated properties
"""
function get_deprecated_properties(schema::T; deprecated_properties::Union{T,Missing}=missing)::T where T <: Dict{String,Any}
    if ismissing(deprecated_properties)
        deprecated_properties = T()
    end

    for (prop_name, prop) in get(schema, "properties", T())
        if get(prop, "deprecated", false)
            deprecated_properties[prop_name] = []
            rmatch = match(r"deprecated:\s*{*([\w\/\_\-\,]+)}*", get(prop,"description",""))
            if rmatch !== nothing
                paths = [string.(split(item, "/")) for item in split(rmatch.captures[1],",")]
                for path in paths
                    new_path = []
                    for segment in path
                        if segment == "missing"
                            segment = missing
                        end
                        push!(new_path, segment)
                    end
                    push!(deprecated_properties[prop_name], Tuple(new_path))
                end
            end
        elseif haskey(prop, "\$ref")
            _dps = get_deprecated_properties(prop["\$ref"])
            if !isempty(_dps)
                deprecated_properties[prop_name] = _dps
            end
        elseif haskey(prop, "properties")
            _dps = get_deprecated_properties(prop)
            if !isempty(_dps)
                deprecated_properties[prop_name] = _dps
            end
        end
    end

    return deprecated_properties
end


"""
    correct_deprecated_properties!(orig_properties::T, new_properties::T, deprecated_properties::T)::Tuple{T,T} where T <: Dict{String,Any}

Helper function for correcting properties that have been deprecated in `orig_properties` into `new_properties`
"""
function correct_deprecated_properties!(orig_properties::T, new_properties::T, deprecated_properties::T)::Tuple{T,T} where T <: Dict{String,Any}
    for prop in keys(filter(x->x.first∈keys(deprecated_properties),orig_properties))
        new_properties[prop] = pop!(orig_properties, prop)
    end
    correct_deprecated_properties!(new_properties, deprecated_properties)

    return orig_properties, new_properties
end


"""
    correct_deprecated_properties!(properties::T, deprecated_properties::T)::T where T <: Dict{String,Any}

Helper function for correcting properties that have been deprecated in `properties`
"""
function correct_deprecated_properties!(properties::T, deprecated_properties::T)::T where T <: Dict{String,Any}
    for prop in keys(filter(x->x.first∈keys(deprecated_properties),properties))
        paths = deprecated_properties[prop]

        if isa(paths, Dict)
            correct_deprecated_properties!(properties[prop], paths)
        else
            v = pop!(properties, prop)
            for path in paths
                if !ismissing(path)
                    set_dict_value!(properties, path, convert(v,path))
                end
            end
        end
    end

    return properties
end


"""
    correct_deprecated_settings!(settings::T)::T where T <: Dict{String,Any}

Helper function for correcting deprecated properties in `settings`
"""
function correct_deprecated_settings!(settings::T)::T where T <: Dict{String,Any}
    settings_schema = load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas/input-settings.schema.json"))

    deprecated_settings = get_deprecated_properties(settings_schema)

    settings = correct_deprecated_properties!(settings, deprecated_settings)

    return settings
end


"""
    convert_deprecated_runtime_args!(
        runtime_args::Dict{String,<:Any},
        settings::Dict{String,<:Any},
        base_network::Dict{String,<:Any},
        timesteps::Int
    )::Tuple{Dict{String,Any},Dict{String,Any}}

Helper function to convert deprecated runtime arguments to their appropriate network settings structure
"""
function correct_deprecated_runtime_args!(runtime_args::T, settings::T)::Tuple{T,T} where T <: Dict{String,Any}
    rt_args_schema = load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas/input-runtime_arguments.schema.json"))

    deprecated_args = get_deprecated_properties(rt_args_schema)

    runtime_args, settings = correct_deprecated_properties!(runtime_args, settings, deprecated_args)

    return runtime_args, settings
end


"""
    parse_settings(
        settings_file::String;
        validate::Bool=true
        correct::Bool=true
    )::Dict{String,Any}

Parses network settings JSON file.

## Validation

If `validate=true` (default), the parsed data structure will be validated against the latest [Settings Schema](@ref Settings-Schema).
"""
function parse_settings(settings_file::String; validate::Bool=true, correct::Bool=true)::Dict{String,Any}
    user_settings = JSON.parsefile(settings_file)

    if validate && !validate_settings(user_settings)
        error("'settings' file could not be validated:\n$(evaluate_settings(user_settings))")
    end

    correct && correct_settings!(user_settings)

    return recursive_merge(build_default_settings(), user_settings)
end


"""
    apply_settings!(args::Dict{String,Any})::Dict{String,Any}

Applies settings to the network.
"""
function apply_settings!(args::Dict{String,Any})::Dict{String,Any}
    args["base_network"] = apply_settings(args["base_network"], get(args, "settings", Dict()))
    args["network"] = make_multinetwork(args["base_network"])
end


"""
    apply_settings(
        network::Dict{String,<:Any},
        settings::Dict{String,<:Any}
    )::Dict{String,Any}

Applies `settings` to single-network `network`
"""
function apply_settings(network::T, settings::T; multinetwork::Bool=true)::T where T <: Dict{String,Any}
    @assert !PMD.ismultinetwork(network)

    network_objects = [(t,n) for t in PMD.pmd_eng_asset_types for n in keys(get(network, t, Dict()))]
    invalid_eng_objs = [(t,n) for t in PMD.pmd_eng_asset_types for n in keys(get(settings, t, Dict())) if !((t,n) in network_objects)]

    eng = recursive_merge(recursive_merge(deepcopy(network), filter(x->x.first!="dss",settings)), parse_dss_settings(get(settings, "dss", Dict{String,Any}()), network))

    for path in invalid_eng_objs
        @info "Settings at '$path' do not match any object in the data model, ignoring"
        delete_path!(eng, path)
    end

    if get_option(eng, ("options","data","fix-small-numbers"), false)
        @info "fix-small-numbers algorithm applied"
        PMD.adjust_small_line_impedances!(eng; min_impedance_val=1e-1)
        PMD.adjust_small_line_admittances!(eng; min_admittance_val=1e-1)
        PMD.adjust_small_line_lengths!(eng; min_length_val=10.0)
    end

    if !ismissing(get_option(eng, ("options","data","time-elapsed")))
        eng["time_elapsed"] = multinetwork ? eng["options"]["data"]["time-elapsed"] : eng["options"]["data"]["time-elapsed"][1]
    end

    eng["switch_close_actions_ub"] = multinetwork ? get_option(eng, ("options","data","switch-close-actions-ub"), Inf) : get_option(eng, ("options","data","switch-close-actions-ub"), Inf)[1]

    if !ismissing(get_option(eng, ("options","outputs","log-level")))
        set_log_level!(Symbol(titlecase(settings["options"]["outputs"]["log-level"])))
    end

    return eng
end


"""
    set_option!(network::Dict{String,<:Any}, path::Tuple{Vararg{String}}, value::Any)

Helper function to set a property in a `network` data structure at `path` to `value`
"""
function set_option!(network::Dict{String,<:Any}, path::Tuple{Vararg{String}}, value::Any)
    if ismultinetwork(network)
        mn_data = network["nw"]
        _set_property!(network, path, value)
    else
        mn_data = Dict{String,Any}("0" => network)
    end

    for (_, nw) in mn_data
        _set_property!(nw, path, value)
    end

    return network
end


"""
    _set_property!(data::Dict{String,<:Any}, path::Tuple{Vararg{String}}, value::Any)

Helper function to set a property to value at an arbitrary nested path in a dictionary
"""
function _set_property!(data::Dict{String,<:Any}, path::Tuple{Vararg{String}}, value::Any)
    if length(path) > 1
        if !haskey(data, path[1])
            data[path[1]] = Dict{String,Any}()
        end
        _set_property!(data[path[1]], path[2:end], value)
    else
        data[path[1]] = value
    end
end


"""
    set_options!(settings::Dict{String,<:Any}, options::Dict{Tuple{Vararg{String}},<:Any})

Helper function to set multiple properties in an `options` at path::Tuple{Vararg{String}} to value::Any.
This does not rebuild the network data structure.
"""
function set_options!(network::Dict{String,<:Any}, options::Dict{<:Tuple{Vararg{String}},<:Any})
    for (path,value) in options
        set_option!(network, path, value)
    end
end


"""
    set_setting!(args::Dict{String,<:Any}, path::Tuple{Vararg{String}}, value::Any)

Helper function to set an option at `path` to `value` and then regenerate the multinetwork data from `args`.
"""
function set_setting!(args::Dict{String,<:Any}, path::Tuple{Vararg{String}}, value::Any)
    _set_property!(args, ("settings", path...), value)

    apply_settings!(args)
    apply_events!(args)
end


"""
    set_settings!(args, options::Dict{Tuple{Vararg{String}},<:Any})

Helper function to set multiple options at `path` to `value` and then regenerate the multinetwork data from `args`,
where the paths are the keys of the `options` input dictionary.
"""
function set_settings!(args::Dict{String,<:Any}, options::Dict{<:Tuple{Vararg{String}},<:Any})
    for (path,value) in options
        _set_property!(args, ("settings", path...), value)
    end

    apply_settings!(args)
    apply_events!(args)
end


"""
    get_option(network::Dict{String,<:Any}, path::Tuple{Vararg{String}}, default::Any=missing)::Any

Helper function to get a property at an arbitrary nested path in a network dictionary, returning the
default value if path does not exist.
"""
function get_option(network::Dict{String,<:Any}, path::Tuple{Vararg{String}}, default::Any=missing)::Any
    if length(path) > 1
        return get_option(get(network, path[1], Dict{String,Any}()), path[2:end], default)
    else
        return get(network, path[1], default)
    end

end


"""
    get_setting(args::Dict{String,Any}, path::Tuple{Vararg{String}}, default::Any=missing)::Any

Helper function to get a property in settings at an arbitrary nested path in an `args` dictionary, returning the
default value if path does not exist.
"""
function get_setting(args::Dict{String,Any}, path::Tuple{Vararg{String}}, default::Any=missing)::Any
    return get_option(args, ("settings", path...), default)
end


"""
    get_option(settings_file::String, path::Tuple{Vararg{String}}, default::Any=missing)::Any

Helper function for variant where `settings_file` has not been parsed yet.
"""
get_option(settings_file::String, path::Tuple{Vararg{String}}, default::Any=missing)::Any = get_option(path[1] == "settings" ? Dict{String,Any}("settings"=>parse_settings(settings_file)) : parse_settings(settings_file), path, default)


"""
    delete_option!(network::Dict{String,<:Any}, path::Tuple{Vararg{String}})

Helper function to delete some option path from a network data structure
"""
function delete_option!(network::Dict{String,<:Any}, path::Tuple{Vararg{String}})
    delete_path!(network, path)
    if ismultinetwork(network)
        for (n,nw) in network["nw"]
            delete_path!(nw, path)
        end
    end
end


"""
    delete_setting!(args::Dict{String,<:Any}, path::Tuple{Vararg{String}})

Helper function to delete some option path from settings data structure
"""
function delete_setting!(args::Dict{String,<:Any}, path::Tuple{Vararg{String}})
    delete_path!(args, ("settings", path...))
end


"""
    delete_option!(settings_file::String, path::Tuple{Vararg{String}})

Helper function for variant where `settings_file` has not been parsed yet.
"""
delete_option!(settings_file::String, path::Tuple{Vararg{String}}) = @info "settings file has not yet been parsed, cannot delete option at '$path'"


"""
    build_settings(network_file::String; kwargs...)

Helper function for variant where `network_file` has not been parsed yet.
"""
build_settings(network_file::String; kwargs...) = build_settings(PMD.parse_file(network_file; transformations=[PMD.apply_kron_reduction!]); kwargs...)


"""
    build_settings(
        eng::Dict{String,<:Any};
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
    )::Dict{String,Any}

**Deprecated**: This function is deprecated in favor of [`build_settings_new`](build_settings_new)

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
function build_settings(
    eng::Dict{String,<:Any};
    max_switch_actions::Union{Missing,Int,Vector{Int}}=missing,
    vm_lb_pu::Union{Missing,Real}=missing,
    vm_ub_pu::Union{Missing,Real}=missing,
    vad_deg::Union{Missing,Real}=missing,
    line_limit_mult::Real=1.0,
    sbase_default::Union{Missing,Real}=missing,
    time_elapsed::Union{Missing,Real,Vector{Real}}=missing,
    autogen_microgrid_ids::Bool=true,
    custom_settings::Dict{String,<:Any}=Dict{String,Any}(),
    mip_solver_gap::Union{Real,Missing}=missing,
    nlp_solver_tol::Union{Real,Missing}=missing,
    mip_solver_tol::Union{Real,Missing}=missing,
    clpu_factor::Union{Missing,Real}=missing,
    disable_switch_penalty::Union{Missing,Bool}=missing,
    apply_switch_scores::Union{Missing,Bool}=missing,
    disable_radial_constraint::Union{Missing,Bool}=missing,
    disable_isolation_constraint::Union{Missing,Bool}=missing,
    disable_inverter_constraint::Union{Missing,Bool}=missing,
    storage_phase_unbalance_factor::Union{Missing,Real}=missing,
    disable_presolver::Union{Missing,Bool}=missing,
    correct::Bool=true,
    )::Dict{String,Any}
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
    )

    if !ismissing(mip_solver_gap)
        settings["mip_solver_gap"] = mip_solver_gap
    end
    if !ismissing(nlp_solver_tol)
        settings["nlp_solver_tol"] = nlp_solver_tol
    end
    if !ismissing(mip_solver_tol)
        settings["mip_solver_tol"] = mip_solver_tol
    end

    settings = recursive_merge(build_default_settings(), settings)

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

    if !ismissing(disable_switch_penalty)
        settings["disable_switch_penalty"] = disable_switch_penalty
    end
    if !ismissing(apply_switch_scores)
        settings["apply_switch_scores"] = apply_switch_scores
    end
    if !ismissing(disable_isolation_constraint)
        settings["disable_isolation_constraint"] = disable_isolation_constraint
    end
    if !ismissing(disable_radial_constraint)
        settings["disable_radial_constraint"] = disable_radial_constraint
    end
    if !ismissing(disable_inverter_constraint)
        settings["disable_inverter_constraint"] = disable_inverter_constraint
    end
    if !ismissing(disable_presolver)
        settings["disable_presolver"] = disable_presolver
    end

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

    correct && correct_settings!(settings)

    return settings
end


"""
    build_settings_file(network_file::String, settings_file::String; kwargs...)

Builds and writes a `settings_file::String` by parsing a `network_file`
"""
function build_settings_file(network_file::String, settings_file::String; kwargs...)
    open(settings_file, "w") do io
        build_settings_file(PMD.parse_file(network_file; transformations=[PMD.apply_kron_reduction!]), io; kwargs...)
    end
end


"""
    build_settings_file(eng::Dict{String,<:Any}, settings_file::String; kwargs...)

Builds and writes a `settings_file::String` from a network data set `eng::Dict{String,Any}`
"""
function build_settings_file(eng::Dict{String,<:Any}, settings_file::String; kwargs...)
    open(settings_file, "w") do io
        build_settings_file(eng, io; kwargs...)
    end
end


"""
    build_settings_file(
        network_file::String,
        settings_file::String="settings.json";
        kwargs...
    )

Helper function to write a settings structure to an `io` for use with ONM from a network data
structure `eng::Dict{String,<:Any}`.
"""
function build_settings_file(
    eng::Dict{String,<:Any},
    io::IO;
    kwargs...
    )

    settings = build_settings(
        eng;
        kwargs...
    )

    JSON.print(io, settings)
end


"""
    parse_dss_settings(dss_settings::T, eng::T)::T where T <: Dict{String,Any}

Parses the dss settings schema into a ENGINEERING-compatible settings structure
"""
function parse_dss_settings(dss_settings::T, eng::T)::T where T <: Dict{String,Any}
    settings = T()

    source_id_map = Dict{String,Tuple{String,String}}(
        obj["source_id"] => (obj_type,obj_id) for obj_type in PMD.pmd_eng_asset_types for (obj_id,obj) in get(eng,obj_type,Dict()) if haskey(obj,"source_id")
    )

    for (source_id,obj) in dss_settings
        if haskey(source_id_map, lowercase(source_id))
            (eng_obj_type,eng_obj_id) = source_id_map[lowercase(source_id)]
        else
            @warn "cannot find dss object '$(lowercase(source_id))' in the data model, skipping"
            continue
        end

        if !haskey(settings, eng_obj_type)
            settings[eng_obj_type] = Dict{String,Any}()
        end

        if !haskey(settings[eng_obj_type],eng_obj_id)
            settings[eng_obj_type][eng_obj_id] = Dict{String,Any}()
        end

        if haskey(obj, "enabled")
            settings[eng_obj_type][eng_obj_id]["status"] = parse(PMD.Status, obj["enabled"])
        end

        if haskey(obj, "inverter")
            settings[eng_obj_type][eng_obj_id]["inverter"] = parse(Inverter, obj["inverter"])
        end
    end

    return settings
end


"""
    build_settings_new(
        eng::Dict{String,<:Any};
        raw_settings::Dict{String,<:Any}=Dict{String,Any}(),
        switch_close_actions_ub::Union{Real}=missing,
        timestep_hours::Union{Missing,Real}=missing,
        vm_lb_pu::Union{Missing,Real}=missing,
        vm_ub_pu::Union{Missing,Real}=missing,
        vad_deg::Union{Missing,Real}=missing,
        line_limit_multiplier::Real=1.0,
        transformer_limit_multiplier::Real=1.0,
        generate_microgrid_ids::Bool=true,
        cold_load_pickup_factor::Union{Missing,Real}=missing,
        storage_phase_unbalance_factor::Union{Missing,Real}=missing,
    )::Dict{String,Any}

New version of the `build_settings` function. A number of the flags have been moved to `raw_settings`, which should follow
the format of the settings schema.
"""
function build_settings_new(
    eng::Dict{String,<:Any};
    raw_settings::Dict{String,<:Any}=Dict{String,Any}(),
    switch_close_actions_ub::Union{Real}=missing,
    timestep_hours::Union{Missing,Real}=missing,
    vm_lb_pu::Union{Missing,Real}=missing,
    vm_ub_pu::Union{Missing,Real}=missing,
    vad_deg::Union{Missing,Real}=missing,
    line_limit_multiplier::Real=1.0,
    transformer_limit_multiplier::Real=1.0,
    generate_microgrid_ids::Bool=true,
    cold_load_pickup_factor::Union{Missing,Real}=missing,
    storage_phase_unbalance_factor::Union{Missing,Real}=missing,
    )::Dict{String,Any}
    n_steps = !haskey(eng, "time_series") ? 1 : length(first(eng["time_series"]).second["values"])

    settings = build_default_settings()


    if !ismissing(timestep_hours)
        if !isa(timestep_hours, Vector)
            timestep_hours = fill(timestep_hours, n_steps)
        end
        _set_property!(settings, ("options", "data", "time-elapsed"), timestep_hours)
    end

    if !ismissing(switch_close_actions_ub)
        if !isa(switch_close_actions_ub, Vector)
            switch_close_actions_ub = fill(switch_close_actions_ub, n_steps)
        end
        _set_property!(settings, ("options", "data", "switch-close-actions-ub"), switch_close_actions_ub)
    end

    # Generate bus microgrid_ids
    if generate_microgrid_ids
        # merge in switch default settings
        for (id, switch) in get(raw_settings, "switch", Dict())
            eng["switch"][id] = merge(eng["switch"][id], deepcopy(switch))
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
            haskey(bus, "vm_lb") && _set_property!(settings, ("bus", b, "vm_lb"), bus["vm_lb"])
            haskey(bus, "vm_ub") && _set_property!(settings, ("bus", b, "vm_ub"), bus["vm_ub"])
            haskey(bus, "microgrid_id") && _set_property!(settings, ("bus", b, "microgrid_id"), bus["microgrid_id"])
        end
    end

    # Generate settings for loads
    if !ismissing(cold_load_pickup_factor)
        for l in keys(get(eng, "load", Dict()))
            _set_property!(settings, ("load", l, "clpu_factor"), cold_load_pickup_factor)
        end
    end

    # Generate settings for lines
    PMD.adjust_line_limits!(eng, line_limit_multiplier)
    !ismissing(vad_deg) && PMD.apply_voltage_angle_difference_bounds!(eng, vad_deg)
    for (l, line) in get(eng, "line", Dict())
        haskey(line, "vad_lb") && _set_property!(settings, ("line", l, "vad_lb"), line["vad_lb"])
        haskey(line, "vad_ub") && _set_property!(settings, ("line", l, "vad_ub"), line["vad_ub"])
        haskey(line, "cm_ub") && _set_property!(settings, ("line", l, "cm_ub"), line["cm_ub"])
    end

    # Generate settings for switches
    for (s, switch) in get(eng, "switch", Dict())
        haskey(switch, "cm_ub") && _set_property!(settings, ("switch", s, "cm_ub"), switch["cm_ub"])
    end

    # Generate settings for transformers
    PMD.adjust_transformer_limits!(eng, transformer_limit_multiplier)
    for (t, transformer) in get(eng, "transformer", Dict())
        haskey(transformer, "sm_ub") && _set_property!(transformer, ("transformer", t, "sm_ub"), transformer["sm_ub"])
    end

    if !ismissing(storage_phase_unbalance_factor)
        for i in keys(get(eng, "storage", Dict()))
            _set_property!(settings, ("storage", i, "phase_unbalance_factor"), storage_phase_unbalance_factor)
        end
    end

    settings = recursive_merge(settings, raw_settings)

    return settings
end


"""
    build_settings_new(eng::Dict{String,<:Any}, io::IO; kwargs...)

Builds and writes settings to an `io::IO` from a network data set `eng::Dict{String,Any}`
"""
build_settings_new(eng::Dict{String,<:Any}, io::IO; kwargs...) = JSON.print(io, build_settings_new(eng; kwargs...), 2)


"""
    build_settings_new(network_file::String; kwargs...)

Builds settings from a network_file
"""
build_settings_new(network_file::String; kwargs...) = build_settings_new(parse_network(network_file)[1]; kwargs...)


"""
    build_settings_new(eng::Dict{String,<:Any}, settings_file::String; kwargs...)

Builds and writes settings to a `settings_file::String` from a network data set `eng::Dict{String,Any}`
"""
function build_settings_new(eng::Dict{String,<:Any}, settings_file::String; kwargs...)
    open(settings_file, "w") do io
        build_settings_new(eng, io; kwargs)
    end
end


"""
    build_settings_new(network_file::String, settings_file::String; kwargs...)

Builds and writes settings to a `settings_file::String` from a network data set at `network_file::String`
"""
build_settings_new(network_file::String, settings_file::String; kwargs...) = build_settings_new(parse_network(network_file)[1], settings_file; kwargs)
