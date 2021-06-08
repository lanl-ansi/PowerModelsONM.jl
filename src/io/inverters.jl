""
function parse_inverters(inverter_file::String)::Dict{String,Any}
    PowerModelsStability.parse_json(inverter_file)
end
