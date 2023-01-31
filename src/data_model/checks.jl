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
