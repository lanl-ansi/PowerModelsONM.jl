""
function parse_inverters(inverter_file::String; validate::Bool=true)::Dict{String,Any}
    inverters = PowerModelsStability.parse_json(inverter_file)

    if validate && !validate_inverters(inverters)
        error("'inverters' file could not be validated")
    end

    return inverters
end
