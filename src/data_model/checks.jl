"""
    _validate_against_schema(
        data::Union{Dict{String,<:Any}, Vector},
        schema::JSONSchema.Schema
    )::Bool

Validates dict or vector structure `data` against json `schema` using JSONSchema.jl.
"""
function _validate_against_schema(data::Union{Dict{String,<:Any}, Vector}, schema::JSONSchema.Schema)::Bool
    JSONSchema.validate(data, schema) === nothing
end


"""
    _validate_against_schema(
        data::Union{Dict{String,<:Any}, Vector},
        schema_name::String
    )::Bool

Validates dict or vector structure `data` against json schema given by `schema_name`.
"""
function _validate_against_schema(data::Union{Dict{String,<:Any}, Vector}, schema_name::String)::Bool
    _validate_against_schema(data, load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas", "$(schema_name).schema.json")))
end


"""
    validate_runtime_arguments(data::Dict)::Bool

Validates runtime_arguments `data` against models/runtime_arguments schema
"""
validate_runtime_arguments(data::Dict)::Bool = _validate_against_schema(data, "input-runtime_arguments")


"""
    validate_events(data::Vector{Dict})::Bool

Validates events `data` against models/events schema
"""
validate_events(data::Vector)::Bool = _validate_against_schema(data, "input-events")


"""
    validate_inverters(data::Dict)::Bool

Validates inverter `data` against models/inverters schema
"""
validate_inverters(data::Dict)::Bool = _validate_against_schema(data, "input-inverters")


"""
    validate_faults(data::Dict)::Bool

Validates fault input `data` against models/faults schema
"""
validate_faults(data::Dict)::Bool = _validate_against_schema(data, "input-faults")


"""
    validate_settings(data::Dict)::Bool

Validates runtime_settings `data` against models/runtime_settings schema
"""
validate_settings(data::Dict)::Bool = _validate_against_schema(data, "input-settings")


"""
    validate_output(data::Dict)::Bool

Validates output `data` against models/outputs schema
"""
validate_output(data::Dict)::Bool = _validate_against_schema(data, "output")


"""
    evaluate_output(data::Dict)

Helper function to give detailed output on JSON Schema validation of output `data`
"""
evaluate_output(data::Dict) = JSONSchema.validate(data, load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas", "output.schema.json")))


"""
    evaluate_events(data::Dict)

Helper function to give detailed output on JSON Schema validation of events `data`
"""
evaluate_events(data::Dict) = JSONSchema.validate(data, load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas", "input-events.schema.json")))


"""
    evaluate_settings(data::Dict)

Helper function to give detailed output on JSON Schema validation of settings `data`
"""
evaluate_settings(data::Dict) = JSONSchema.validate(data, load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas", "input-settings.schema.json")))


"""
    evaluate_runtime_arguments(data::Dict)

Helper function to give detailed output on JSON Schema validation of runtime arguments `data`
"""
evaluate_runtime_arguments(data::Dict) = JSONSchema.validate(data, load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas", "input-runtime_arguments.schema.json")))


"""
    check_switch_state_feasibility(data::Dict{String,<:Any})::Union{Dict{String,Bool},Bool}

Helper function to aid users in determining whether network model has a feasible starting switch
configuration (at each time step, if the network model is multinetwork), assuming radiality constraints
are applied.
"""
function check_switch_state_feasibility(data::Dict{String,<:Any})::Union{Dict{String,Bool},Bool}
    mn_data = !ismultinetwork(data) ? Dict{String,Any}("0" => data) : data["nw"]

    is_feasible = Dict{String,Bool}()
    for (n,nw) in mn_data
        is_feasible[n] = _check_switch_state_feasibility(nw)
    end

    return ismultinetwork(data) ? is_feasible : first(is_feasible).second
end


"""
    _check_switch_state_feasibility(eng::Dict{String,Any})

Helper function to aid users in determining whether network model has a feasible starting switch
configuration, assuming radiality constraints are applied.
"""
function _check_switch_state_feasibility(eng::Dict{String,Any})::Bool
    eng["data_model"] = PMD.ENGINEERING

    blocks = Dict(i => block for (i,block) in enumerate(PMD.identify_blocks(eng)))
    bus2block_map = Dict(bus => bid for (bid,block) in blocks for bus in block)

    g = Graphs.SimpleGraph(length(blocks))

    for (s,sw) in get(eng, "switch", Dict())
        f_block = bus2block_map[sw["f_bus"]]
        t_block = bus2block_map[sw["t_bus"]]

        if sw["state"] == PMD.CLOSED && sw["dispatchable"] == PMD.NO
            Graphs.add_edge!(g, f_block, t_block)
        end
    end

    !Graphs.is_cyclic(g)
end


"""
    validate_robust_partitions(data::Vector{Dict})::Bool

Validates events `data` against robust partitions output schema
"""
validate_robust_partitions(data::Vector)::Bool = _validate_against_schema(data, "output-robust-partitions")


"""
    evaluate_robust_partitions(data::Dict)

Helper function to give detailed output on JSON Schema validation of settings `data`
"""
evaluate_robust_partitions(data::Vector) = JSONSchema.validate(data, load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas", "output-robust-partitions.schema.json")))


"""
    update_start_values!(data::Dict{String,Any}; overwrite_start_values::Bool=false)::Dict{String,Any}

Helper function to add some start values for variables to prevent starting MIP infeasibilities
"""
function update_start_values!(data::Dict{String,Any}; overwrite_start_values::Bool=false)::Dict{String,Any}
    PMD.iseng(data) && update_start_values_eng!(data; overwrite_start_values=overwrite_start_values)
    PMD.ismath(data) && update_start_values_math!(data; overwrite_start_values=overwrite_start_values)

    return data
end


"""
    update_start_values_eng!(eng::Dict{String,Any}; overwrite_start_values::Bool=false)::Dict{String,Any}

Helper function to add some start values for variables to prevent starting MIP infeasibilities to the ENGINEERING model
"""
function update_start_values_eng!(eng::Dict{String,Any}; overwrite_start_values::Bool=false)::Dict{String,Any}
    if !PMD.ismultinetwork(eng)
        mn_eng = Dict{String,Any}("nw"=>Dict{String,Any}("0"=>eng))
    else
        mn_eng = eng
    end

    for (n,nw) in mn_eng["nw"]
        for t in ["voltage_source", "generator", "solar"]
            for (i,obj) in get(nw, t, Dict())
                if !haskey(obj, "pg_start") || overwrite_start_values
                    mn_eng["nw"][n][t][i]["pg_start"] = zeros(length(obj["connections"]))
                end

                if !haskey(obj, "qg_start") || overwrite_start_values
                    mn_eng["nw"][n][t][i]["qg_start"] = zeros(length(obj["connections"]))
                end
            end
        end

        for (i,obj) in get(nw, "storage", Dict())
            if !haskey(obj, "sc_start") || overwrite_start_values
                mn_eng["nw"][n]["storage"][i]["sc_start"] = 0
            end

            if !haskey(obj, "sd_start") || overwrite_start_values
                mn_eng["nw"][n]["storage"][i]["sd_start"] = 0
            end
        end

        for (i,obj) in get(nw, "bus", Dict())
            if !haskey(obj, "vm_start") || overwrite_start_values
                mn_eng["nw"][n]["bus"][i]["vm_start"] = zeros(length(obj["terminals"]))
            end
        end
    end

    if !PMD.ismultinetwork(eng)
        return mn_eng["nw"]["0"]
    else
        return mn_eng
    end
end


"""
    update_start_values_math!(math::Dict{String,Any}; overwrite_start_values::Bool=false)::Dict{String,Any}

Helper function to add some start values for variables to prevent starting MIP infeasibilities to the MATHEMATICAL model
"""
function update_start_values_math!(math::Dict{String,Any}; overwrite_start_values::Bool=false)::Dict{String,Any}
    if !PMD.ismultinetwork(math)
        mn_math = Dict{String,Any}("nw"=>Dict{String,Any}("0"=>math))
    else
        mn_math = math
    end

    for (n,nw) in mn_math["nw"]
        for (i,gen) in get(nw, "gen", Dict())
            if !haskey(gen, "pg_start") || overwrite_start_values
                mn_math["nw"][n]["gen"][i]["pg_start"] = zeros(length(gen["connections"]))
            end

            if !haskey(gen, "qg_start") || overwrite_start_values
                mn_math["nw"][n]["gen"][i]["qg_start"] = zeros(length(gen["connections"]))
            end
        end

        for (i,storage) in get(nw, "storage", Dict())
            if !haskey(storage, "sc_start") || overwrite_start_values
                mn_math["nw"][n]["storage"][i]["sc_start"] = 0
            end

            if !haskey(storage, "sd_start") || overwrite_start_values
                mn_math["nw"][n]["storage"][i]["sd_start"] = 0
            end
        end

        for (i,bus) in get(nw, "bus", Dict())
            if !haskey(bus, "vm_start") || overwrite_start_values
                # mn_math["nw"][n]["bus"][i]["vm_start"] = zeros(length(bus["terminals"]))
            end
        end
    end

    if !PMD.ismultinetwork(math)
        return mn_math["nw"]["0"]
    else
        return mn_math
    end
end
