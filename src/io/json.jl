"helper function to correct schema refs from relative to absolute"
function _fix_schema_refs!(model::Union{Vector,Dict})
    if isa(model, Dict)
        for (k,v) in model
            if k == raw"$ref"
                model[k] = joinpath(dirname(pathof(PowerModelsONM)), "..", "models", basename(v))
            elseif isa(v, Dict) || isa(v, Vector)
                _fix_schema_refs!(v)
            end
        end
    else
        for item in model
            if isa(item, Dict) || isa(item, Vector)
                _fix_schema_refs!(item)
            end
        end
    end
end


"""
    load_schema(file::String)::Schema

Loads a JSON Schema for validation, fixing the ref paths inside the schemas on load
"""
function load_schema(file::String)::JSONSchema.Schema
    model = JSON.parsefile(file)
    _fix_schema_refs!(model)
    return JSONSchema.Schema(model)
end
