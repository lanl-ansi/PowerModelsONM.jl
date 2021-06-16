"validates dict or vector structure against json schema using JSONSchema.jl"
function _validate_against_schema(data::Union{Dict{String,<:Any}, Vector}, schema::JSONSchema.Schema)::Bool
    JSONSchema.validate(data, schema) === nothing
end


"validates dict or vector structure against json schema given by `schema_name`, and `schema_version`"
function _validate_against_schema(data::Union{Dict{String,<:Any}, Vector}, schema_name::String, schema_version::String="v1")::Bool
    _validate_against_schema(data, load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "models", "$schema_name.$schema_version.json")))
end


"""
    validate_events(data::Vector{Dict})::Bool

Validates events data against models/events schema
"""
validate_events(data::Vector) = _validate_against_schema(data, "events", "v1")


"""
    validate_output(data::Dict)::Bool

Validates output data against models/outputs schema
"""
validate_output(data::Dict) = _validate_against_schema(data, "outputs", "v1")


"""
    validate_powerflow(data::Vector{Dict})::Bool

Validates powerflow data against models/powerflow schema
"""
validate_powerflow(data::Vector) = _validate_against_schema(data, "powerflow", "v1")


"""
    validate_runtime_arguments(data::Dict)::Bool

Validates runtime_arguments data against models/runtime_arguments schema
"""
validate_runtime_arguments(data::Dict) = _validate_against_schema(data, "runtime_arguments", "v1")


"""
    validate_network_settings(data::Dict)::Bool

Validates runtime_settings data against models/runtime_settings schema
"""
validate_network_settings(data::Dict) = _validate_against_schema(data, "network_settings", "v1")


"""
    validate_device_action_timeline(data::Vector{Dict})::Bool

Validates events data against models/device_action_timeline schema
"""
validate_device_action_timeline(data::Vector) = _validate_against_schema(data, "device_action_timeline", "v1")


"""
    validate_fault_currents(data::Vector{Dict})::Bool

Validates fault current output data against models/fault_currents schema
"""
validate_fault_currents(data::Vector) = _validate_against_schema(data, "fault_currents", "v1")


"""
    validate_faults(data::Dict)::Bool

Validates fault input data against models/faults schema
"""
validate_faults(data::Dict) = _validate_against_schema(data, "faults", "v1")


"""
    validate_inverters(data::Dict)::Bool

Validates inverter data against models/inverters schema
"""
validate_inverters(data::Dict) = _validate_against_schema(data, "inverters", "v1")
