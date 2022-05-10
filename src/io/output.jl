"""
"""
const _json_schema_type_conversions = Dict{Union{Missing,String},Type}(
    "string"=>String,
    "array"=>Vector,
    "integer"=>Int,
    "number"=>Real,
    "boolean"=>Bool,
    missing=>Any,
    "object"=>Dict{String,Any},
    "null"=>Union{Real,Nothing,Missing}, # Inf,NaN,missing
)


"""
"""
function _recursive_initialize_output_from_schema!(output::Dict{String,<:Any}, schema_properties::Dict{String,<:Any})
    for (prop_name,prop) in schema_properties
        if haskey(prop, "\$ref")
            _prop = prop["\$ref"]
        else
            _prop = prop
        end

        if get(_prop, "type", "") == "object"
            output[prop_name] = Dict{String,Any}()
            _recursive_initialize_output_from_schema!(output[prop_name], get(_prop, "properties", Dict{String,Any}()))
        elseif get(_prop, "type", "") == "array"
            if haskey(_prop["items"], "\$ref")
                raw_subtype = get(_prop["items"]["\$ref"], "type", missing)
            else
                raw_subtype = get(_prop["items"], "type", missing)
            end

            if isa(raw_subtype, Vector)
                subtype = Union{[_json_schema_type_conversions[t] for t in raw_subtype]...}
            else
                subtype = _json_schema_type_conversions[raw_subtype]
            end

            if subtype == Vector
                raw_subsubtype = get(_prop["items"]["items"], "type", missing)
                if isa(raw_subsubtype, Vector)
                    subsubtype = Union{[_json_schema_type_conversions[t] for t in raw_subsubtype]...}
                else
                    subsubtype = _json_schema_type_conversions[raw_subsubtype]
                end
                output[prop_name] = Vector{subtype{subsubtype}}([])
            else
                output[prop_name] = Vector{subtype}([])
            end
        elseif get(_prop, "readOnly", false)
            output[prop_name] = @eval $(Meta.parse(_prop["default"]))
        end
    end
    return output
end


"""
    initialize_output(args::Dict{String,<:Any})::Dict{String,Any}

Initializes the empty data structure for "output_data"
"""
function initialize_output(raw_args::Dict{String,<:Any})::Dict{String,Any}
    output_schema = load_schema(joinpath(dirname(pathof(PowerModelsONM)), "..", "schemas/output.schema.json"))

    output = Dict{String,Any}()
    output = _recursive_initialize_output_from_schema!(output, get(output_schema.data, "properties", Dict{String,Any}()))

    output["Runtime arguments"] = deepcopy(raw_args)

    return output
end


"""
    write_json(
        file::String,
        data::Dict{String,<:Any};
        indent::Union{Int,Missing}=missing
    )

Write JSON `data` to `file`. If `!ismissing(indent)`, JSON will be pretty-formatted with `indent`
"""
function write_json(file::String, data::Dict{String,<:Any}; indent::Union{Int,Missing}=missing)
    open(file, "w") do io
        if ismissing(indent)
            JSON.print(io, data)
        else
            JSON.print(io, data, indent)
        end
    end
end


"""
    initialize_output!(args::Dict{String,<:Any})::Dict{String,Any}

Initializes the output data strucutre inside of the args dict at "output_data"
"""
function initialize_output!(args::Dict{String,<:Any})::Dict{String,Any}
    args["output_data"] = initialize_output(get(args, "raw_args", deepcopy(args)))
end


"""
    analyze_results!(args::Dict{String,<:Any})::Dict{String,Any}

Adds information and statistics to "output_data", including

- `"Runtime arguments"`: Copied from `args["raw_args"]`
- `"Simulation time steps"`: Copied from `values(args["network"]["mn_lookup"])`, sorted by multinetwork id
- `"Events"`: Copied from `args["raw_events"]`
- `"Voltages"`: [`get_timestep_voltage_statistics!`](@ref get_timestep_voltage_statistics!)
- `"Load served"`: [`get_timestep_load_served!`](@ref get_timestep_load_served!)
- `"Generator profiles"`: [`get_timestep_generator_profiles!`](@ref get_timestep_generator_profiles!)
- `"Storage SOC (%)"`: [`get_timestep_storage_soc!`](@ref get_timestep_storage_soc!)
- `"Powerflow output"`: [`get_timestep_dispatch!`](@ref get_timestep_dispatch!)
- `"Device action timeline"`: [`get_timestep_device_actions!`](@ref get_timestep_device_actions!)
- `"Switch changes"`: [`get_timestep_switch_changes!`](@ref get_timestep_switch_changes!)
- `"Small signal stability"`: [`get_timestep_stability!`](@ref get_timestep_stability!)
- `"Fault currents"`: [`get_timestep_fault_currents!`](@ref get_timestep_fault_currents!)
- `"Optimal dispatch metadata"`: [`get_timestep_dispatch_optimization_metadata!`](@ref get_timestep_dispatch_optimization_metadata!)
- `"Optimal switching metadata"`: [`get_timestep_switch_optimization_metadata!`](@ref get_timestep_switch_optimization_metadata!)
"""
function analyze_results!(args::Dict{String,<:Any})::Dict{String,Any}
    if !haskey(args, "output_data")
        initialize_output!(args)
    end

    args["output_data"]["Simulation time steps"] = [args["network"]["mn_lookup"]["$n"] for n in sort([parse(Int,i) for i in keys(args["network"]["mn_lookup"])]) ]
    args["output_data"]["Events"] = get(args, "raw_events", Dict{String,Any}[])

    get_timestep_voltage_statistics!(args)

    get_timestep_load_served!(args)
    get_timestep_generator_profiles!(args)
    get_timestep_storage_soc!(args)

    get_timestep_dispatch!(args)
    get_timestep_inverter_states!(args) # must run after get_timestep_dispatch!
    get_timestep_dispatch_optimization_metadata!(args)

    get_timestep_device_actions!(args)
    get_timestep_switch_changes!(args)
    get_timestep_switch_optimization_metadata!(args)
    get_timestep_microgrid_networks!(args)

    get_timestep_stability!(args)

    get_timestep_fault_currents!(args)
    get_timestep_fault_study_metadata!(args)

    get_protection_network_model!(args)
    get_timestep_bus_types!(args)

    return args["output_data"]
end
