"""
    _sanitize_results_metadata!(metadata::Dict{String,<:Any})::Dict{String,Any}

Helper function to turn any field that is not a `Real` into a `String`.
"""
function _sanitize_results_metadata!(metadata::Dict{String,<:Any})::Dict{String,Any}
    for (k,v) in metadata
        if !(typeof(v) <: Real)
            metadata[k] = string(v)
        end
    end

    return metadata
end
