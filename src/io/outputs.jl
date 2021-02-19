""
function build_blank_output(data_eng::Dict{String,Any})::Dict{String,Any}
    Dict{String,Any}(
        "Simulation time steps" => Vector{String}(["$t" for t in first(data_eng["time_series"]).second["time"]]),
        "Load served" => Dict{String,Any}(
            "Feeder load (%)" => Vector{Real}([]),
            "Microgrid load (%)" => Vector{Real}([]),
            "Bonus load via microgrid (%)" => Vector{Real}([]),
        ),
        "Generator profiles" => Dict{String,Any}(
            "Grid mix (kW)" => Vector{Real}([]),
            "Solar DG (kW)" => Vector{Real}([]),
            "Energy storage (kW)" => Vector{Real}([]),
            "Diesel DG (kW)" => Vector{Real}([]),
        ),
        "Voltages" => Dict{String,Any}(
            "Min voltage (p.u.)" => Vector{Real}([]),
            "Mean voltage (p.u.)" => Vector{Real}([]),
            "Max voltage (p.u.)" => Vector{Real}([]),
        ),
        "Storage SOC (%)" => Vector{Real}([]),
        "Device action timeline" => Vector{Dict{String,Any}}([]),
        "Powerflow output" => Dict{String,Dict{String,Any}}(
            "$timestamp" => Dict{String,Any}(
                id => Dict{String,Any}(
                    "voltage (V)" => 0.0
                ) for (id,_) in data_eng["bus"]
            ) for timestamp in first(data_eng["time_series"]).second["time"]
        ),
        "Summary statistics" => Dict{String,Any}(
            "Additional stats" => "TBD"
        ),
        "Events" => Vector{Dict{String,Any}}([]),
        "Protection Settings" => Vector{Dict{String,Any}}([]),
        "Fault currents" => Vector{Dict{String,Any}}([]),
        "Small signal stable" => Vector{Bool}([]),
    )
end


""
function write_outputs(output_file::String, output_data::Dict{String,<:Any})
    open(output_file, "w") do f
        JSON.print(f, output_data, 2)
    end
end
