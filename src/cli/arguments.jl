"Custom type for comma separated list to Vector{String}"
function ArgParse.parse_item(::Type{Vector{String}}, x::AbstractString)
    return Vector{String}([string(strip(item)) for item in split(x, ",")])
end


"""
    parse_commandline(; validate::Bool=true)::Dict{String,Any}

Command line argument parsing
"""
function parse_commandline(; validate::Bool=true)::Dict{String,Any}
    s = ArgParse.ArgParseSettings(
        prog = "PowerModelsONM",
        description = "Optimization library for the operation and restoration of networked microgrids",
        autofix_names = false,
    )

    runtime_args_schema = load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas/input-runtime_arguments.schema.json"))

    rt_args = []
    for (prop_name,prop) in runtime_args_schema.data["properties"]
        if prop_name ∈ ["network", "settings", "events", "faults", "output", "quiet", "verbose", "debug", "gurobi"]
            arg_name = ["--$prop_name", "-$(prop_name[1])"]
        else
            arg_name = "--$prop_name"
        end

        arg_settings = Dict{Symbol,Any}(:help=>get(prop,"description",""))
        if prop_name ∈ get(runtime_args_schema.data, "required", [])
            arg_settings[:required] = true
        end
        if prop["type"] == "boolean"
            if get(prop, "default", false)
                arg_settings[:action] = :store_false
            else
                arg_settings[:action] = :store_true
            end
        else
            if prop["type"] == "array"
                subtype = Dict("string"=>String,"integer"=>Int,"number"=>Float64)[prop["items"]["type"]]
                arg_settings[:arg_type] = Vector{subtype}
                arg_settings[:default] = Vector{subtype}([])
                if haskey(prop["items"], "enum")
                    arg_settings[:range_tester] = x->all([_x in prop["items"]["enum"] for _x in x])
                end
            else
                if haskey(prop, "enum")
                    arg_settings[:range_tester] = x->x∈prop["enum"]
                end
                if haskey(prop, "default")
                    arg_settings[:default] = prop["default"]
                end
                arg_settings[:arg_type] = Dict("string"=>String,"integer"=>Int,"number"=>Float64)[prop["type"]]
            end
        end

        push!(rt_args, arg_name)
        push!(rt_args, arg_settings)
    end

    ArgParse.add_arg_table!(s, rt_args...)

    arguments = ArgParse.parse_args(_remove_inverters_cli_arg(ARGS), s)

    for arg in collect(keys(arguments))
        if isnothing(arguments[arg]) || isempty(arguments[arg])
            delete!(arguments, arg)
        end
    end

    if validate && !validate_runtime_arguments(arguments)
        error("invalid runtime arguments detected:\n $(evaluate_runtime_arguments(arguments))")
    end

    _deepcopy_args!(arguments)

    return arguments
end


"""
    sanitize_args!(args::Dict{String,<:Any})::Dict{String,Any}

Sanitizes deprecated arguments into the correct new ones, and gives warnings
"""
function sanitize_args!(args::Dict{String,<:Any})::Dict{String,Any}
    _deepcopy_args!(args)

    runtime_args_schema = load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas/input-runtime_arguments.schema.json"))
    deprecated_args = Dict(
        prop_name=>Dict(
            "description"=>get(prop, "description", ""),
            "default"=>get(prop,"default",get(prop,"type","")=="boolean" ? false : missing)
        ) for (prop_name,prop) in runtime_args_schema.data["properties"] if get(prop, "deprecated", false)
    )

    if get(args, "quiet", false)
        args["log-level"] = "error"
    end
    if get(args, "verbose", false)
        args["log-level"] = "info"
    end
    if get(args, "debug", false)
        args["log-level"] = "debug"
    end

    for arg in ["quiet", "verbose", "debug"]
        if get(args, arg, false)
            @warn "'$arg' argument is deprecated: use 'log-level'"
            delete!(args, arg)
        end
    end

    if haskey(args, "inverters")
        _warn_stability_removed(["inverters"])
        delete!(args, "inverters")
        delete!(args["raw_args"], "inverters")
    end

    for (arg,v) in collect(args)
        if arg ∈ keys(deprecated_args)
            if !ismissing(deprecated_args[arg]["default"]) && v == deprecated_args[arg]["default"]
                delete!(args, arg)
            else
                @warn "'$arg' is deprecated: use settings.json @ '$(strip(split(deprecated_args[arg]["description"],":")[end]))'"
            end
        end
    end

    return args
end


"""
    _warn_stability_removed(inputs::Vector{String})

Warns that the given `inputs` were ignored because small-signal stability analysis was removed from PowerModelsONM,
and points the user to PowerModelsStability.jl
"""
function _warn_stability_removed(inputs::Vector{String})
    @warn """
    Ignoring $(join(["'$(input)'" for input in inputs], ", ")): small-signal stability analysis has been removed from PowerModelsONM.

    That feature was a thin wrapper around PowerModelsStability.jl (https://github.com/lanl-ansi/PowerModelsStability.jl).
    PowerModelsStability is no longer actively maintained, and its latest release only supports PowerModelsDistribution v0.16.

    If you still need small-signal stability results, run PowerModelsStability directly on the per-timestep networks from ONM:
    add your inverters with `PowerModelsStability.add_inverters!`, then call `PowerModelsStability.transform_data_model`,
    `PowerModelsStability.solve_mc_opf`, and `PowerModelsStability.get_global_stability_matrix`, and check whether every
    eigenvalue of that matrix has a negative real part.
    """
end


"""
    _remove_inverters_cli_arg(cli_args::Vector{String})::Vector{String}

Removes the `-i`/`--inverters` command line argument (and its value), which was used for the removed small-signal stability
analysis, warning the user via `_warn_stability_removed`
"""
function _remove_inverters_cli_arg(cli_args::Vector{String})::Vector{String}
    filtered_args = String[]
    found = false
    skip_next = false
    for arg in cli_args
        if skip_next
            skip_next = false
        elseif arg ∈ ["-i", "--inverters"]
            found = true
            skip_next = true
        elseif startswith(arg, "--inverters=") || (startswith(arg, "-i") && !startswith(arg, "--"))
            found = true
        else
            push!(filtered_args, arg)
        end
    end

    found && _warn_stability_removed(["--inverters"])

    return filtered_args
end


"""
    _deepcopy_args!(args::Dict{String,<:Any})::Dict{String,Any}

Copies arguments to "raw_args" in-place in `args`, for use in [`entrypoint`](@ref entrypoint)
"""
function _deepcopy_args!(args::Dict{String,<:Any})::Dict{String,Any}
    if !haskey(args, "raw_args")
        args["raw_args"] = deepcopy(args)
    end
    return args["raw_args"]
end
