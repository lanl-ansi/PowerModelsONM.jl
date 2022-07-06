"""
    load_schema(file::String)::JSONSchema.Schema

Loads a JSON Schema for validation, fixing the ref paths inside the schemas on load
"""
function load_schema(file::String)::JSONSchema.Schema
    return JSONSchema.Schema(JSON.parsefile(file); parent_dir=joinpath(dirname(pathof(PowerModelsONM)), ".."))
end


"""
    correct_json_import!(data::Dict{String,<:Any})

Helper function to assist in converting to correct Julia data types when importing
JSON files, like settings or events.
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
            PowerModelsONM._fix_nulls!(data, k, data[k])
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


"helper function to fix null values from json (usually Inf or NaN)"
function _fix_nulls!(obj, prop, val)
    if endswith(prop, "-ub")
        fill_val = Inf
    elseif endswith(prop, "-lb")
        fill_val = -Inf
    else
        return
    end

    if isa(val, Matrix) && any(val .=== nothing)
        @debug "a 'null' was encountered in the json import, making an assumption that null values in $prop = $fill_val"
        valdtype = valtype(val)
        if isa(valdtype, Union)
            dtype = [getproperty(valdtype, n) for n in propertynames(valdtype) if getproperty(valdtype, n) != Nothing][end]
        else
            dtype = valdtype
        end
        val[val .=== nothing] .= fill_val
        obj[prop] = Matrix{valtype(val) == Nothing ? typeof(fill_val) : valtype(val)}(val)
    elseif isa(val, Vector) && any(v === nothing for v in val)
        @debug "a 'null' was encountered in the json import, making an assumption that null values in $prop = $fill_val"
        obj[prop] = Vector{valtype(val) == Nothing ? typeof(fill_val) : valtype(val)}([v === nothing ? fill_val : v for v in val])
    elseif val === nothing
        @debug "a 'null' was encountered in the json import, making an assumption that null values in $prop = $fill_val"
        obj[prop] = fill_val
    end
end



"Helper to ensure that Symbols get exported as strings prefaced with a ':'"
JSON.lower(p::Symbol) = ":$(p)"
