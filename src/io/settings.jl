settings_conversions = Dict{Tuple{Vararg{String}},Function}(
    ("solvers","HiGHS","presolve") => x->x ? "off" : "choose",
    ("solvers","Gurobi","Presolve") => x->x ? 0 : -1,
    ("solvers","KNITRO","presolve") => x->Int(!x),
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
"""
function correct_settings!(settings)
    correct_json_import!(settings)
    correct_deprecated_settings!(settings)

    return settings
end


"""
"""
function build_default_settings()::Dict{String,Any}
    settings_schema = load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas/input-settings.schema.json"))

    settings = init_settings_default!(Dict{String,Any}(), settings_schema.data)

    return filter(x->!isempty(x.second),correct_json_import!(settings))
end


"""
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
"""
function get_deprecated_properties(schema::JSONSchema.Schema)::Dict{String,Any}
    get_deprecated_properties(schema.data)
end


"""
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
"""
function correct_deprecated_properties!(orig_properties::T, new_properties::T, deprecated_properties::T)::Tuple{T,T} where T <: Dict{String,Any}
    for prop in keys(filter(x->x.first∈keys(deprecated_properties),orig_properties))
        new_properties[prop] = pop!(orig_properties, prop)
    end
    correct_deprecated_properties!(new_properties, deprecated_properties)

    return orig_properties, new_properties
end


"""
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
function apply_settings(network::T, settings::T)::T where T <: Dict{String,Any}
    @assert !PMD.ismultinetwork(network)

    eng = recursive_merge(recursive_merge(deepcopy(network), filter(x->x.first!="dss",settings)), parse_dss_settings(get(settings, "dss", Dict{String,Any}()), network))

    if get(get(get(eng, "options", T()), "data", T()), "fix-small-numbers", false)
        @info "fix-small-numbers algorithm applied"
        PMD.adjust_small_line_impedances!(eng; min_impedance_val=1e-1)
        PMD.adjust_small_line_admittances!(eng; min_admittance_val=1e-1)
        PMD.adjust_small_line_lengths!(eng; min_length_val=10.0)
    end

    if !ismissing(get(get(get(eng, "options", T()), "data", T()), "time-elapsed", missing))
        eng["time_elapsed"] = eng["options"]["data"]["time-elapsed"]
    end

    eng["switch_close_actions_ub"] = get(get(get(eng, "options", T()), "data", T()), "switch-close-actions-ub", Inf)

    if !ismissing(get(get(get(eng, "options", T()), "outputs", T()), "log-level", missing))
        set_log_level!(Symbol(titlecase(settings["options"]["outputs"]["log-level"])))
    end

    return eng
end


"""
"""
set_option!(args, option, value) = set_option!(args, missing, option, value)


"""
"""
function set_option!(args::Dict{String,<:Any}, category::Union{Missing,String}, option::String, value::Any)
    if haskey(args, "base_network") && haskey(args, "network")
        for k in ["base_network", "network"]
            set_option!(args[k], category, option, value)
        end
    elseif haskey(args, "data_model")
        if !haskey(args, "options")
            args["options"] = Dict{String,Any}()
        end
        if ismissing(category)
            args["options"][option] = value
        else
            if !haskey(args["options"], category)
                args["options"][category] = Dict{String,Any}()
            end
            args["options"][category][option] = value
        end
    end
end


"""
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
