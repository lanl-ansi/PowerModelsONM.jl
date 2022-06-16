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
        if prop_name ∈ ["network", "settings", "events", "faults", "inverters", "output", "quiet", "verbose", "debug", "gurobi"]
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

    arguments = ArgParse.parse_args(s)

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
    _deepcopy_args!(args::Dict{String,<:Any})::Dict{String,Any}

Copies arguments to "raw_args" in-place in `args`, for use in [`entrypoint`](@ref entrypoint)
"""
function _deepcopy_args!(args::Dict{String,<:Any})::Dict{String,Any}
    if !haskey(args, "raw_args")
        args["raw_args"] = deepcopy(args)
    end
    return args["raw_args"]
end
