"""
    load_schema(file::String)::JSONSchema.Schema

Loads a JSON Schema for validation, fixing the ref paths inside the schemas on load
"""
function load_schema(file::String)::JSONSchema.Schema
    return JSONSchema.Schema(JSON.parsefile(file); parent_dir=joinpath(dirname(pathof(PowerModelsONM)), ".."))
end


"""
"""
function correct_json_import!(data::Dict{String,<:Any})
    for (k, v) in data
        if isa(v, Dict)
            correct_json_import!(v)
        else
            PMD._fix_enums!(data, k, data[k])
            PowerModelsONM._fix_enums!(data, k, data[k])
            PowerModelsONM._fix_symbols!(data, k, data[k])
            PMD._fix_arrays!(data, k, data[k])
            PMD._fix_nulls!(data, k, data[k])
        end
    end
    return data
end


"helper function to convert stringified enums"
function _fix_enums!(obj, prop, val)
    if isa(val, String) && uppercase(val) == val && Symbol(val) in names(PowerModelsONM)
        obj[prop] = getfield(PowerModelsONM, Symbol(val))
    end
end


"helper function to convert stringified Symbols"
function _fix_symbols!(obj, prop, val)
    obj[prop] = convert(val)
end


JSON.lower(p::Symbol) = ":$(p)"
