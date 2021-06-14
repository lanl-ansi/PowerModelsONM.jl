"""
    initialize_output(args::Dict{String,<:Any})::Dict{String,Any}

Initializes the empty data structure for "output_data"
"""
function initialize_output(args::Dict{String,<:Any})::Dict{String,Any}
    Dict{String,Any}(
        "Runtime arguments" => args,
        "Simulation time steps" => Any[],
        "Load served" => Dict{String,Any}(
            "Feeder load (%)" => Real[],
            "Microgrid load (%)" => Real[],
            "Bonus load via microgrid (%)" => Real[],
        ),
        "Generator profiles" => Dict{String,Any}(
            "Grid mix (kW)" => Real[],
            "Solar DG (kW)" => Real[],
            "Energy storage (kW)" => Real[],
            "Diesel DG (kW)" => Real[],
        ),
        "Voltages" => Dict{String,Any}(
            "Min voltage (p.u.)" => Real[],
            "Mean voltage (p.u.)" => Real[],
            "Max voltage (p.u.)" => Real[],
        ),
        "Storage SOC (%)" => Real[],
        "Device action timeline" => Dict{String,Any}[],
        "Powerflow output" => Dict{String,Any}[],
        "Summary statistics" => Dict{String,Any}(),
        "Events" => Dict{String,Any}[],
        "Protection Settings" => Dict{String,Any}[],
        "Fault currents" => Dict{String,Any}[],
        "Small signal stable" => Bool[],
        "Runtime timestamp" => "$(Dates.now())",
    )
end


"""
    write_json(file::String, data::Dict{String,<:Any}; indent::Union{Int,Missing}=missing)

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
    initialize_output!(args::Dict{String,Any})

Initializes the output data strucutre inside of the args dict at "output_data"
"""
function initialize_output!(args::Dict{String,<:Any})::Dict{String,Any}
    args["output_data"] = initialize_output(args)
end


"""
    analyze_results!(args::Dict{String,<:Any})

Adds statistics to "output_data"
"""
function analyze_results!(args::Dict{String,<:Any})::Dict{String,Any}
    if !haskey(args, "output_data")
        initialize_output!(args)
    end

    args["output_data"]["Simulation time steps"] = [args["network"]["mn_lookup"]["$n"] for n in sort([parse(Int,i) for i in keys(args["network"]["mn_lookup"])]) ]
    args["output_data"]["Events"] = args["raw_events"]

    get_timestep_voltage_stats!(args)
    get_timestep_load_served!(args)
    get_timestep_generator_profiles!(args)
    get_timestep_powerflow_output!(args)
    get_timestep_storage_soc!(args)
    get_timestep_device_actions!(args)
    get_timestep_switch_changes!(args)

    get_timestep_stability!(args)
    return args["output_data"]
end
