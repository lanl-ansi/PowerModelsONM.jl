"""
    get_timestep_stability!(args::Dict{String,<:Any})::Vector{Bool}

Gets the stability at each timestep and applies it in-place to args, for use in
[`entrypoint`](@ref entrypoint), using [`get_timestep_stability`](@ref get_timestep_stability)
"""
function get_timestep_stability!(args::Dict{String,<:Any})::Union{Vector{Bool},Vector{Missing}}
    args["output_data"]["Small signal stability"] = get_timestep_stability(get(args, "stability_results", fill(missing, length(args["network"]["nw"]))))
end


# TODO replace when stability features are more complex
"""
    get_timestep_stability(is_stable::Union{Vector{Bool},Vector{Missing}})::Vector{Bool}

This is a placeholder function that simple passes through the is_stable Vector
back, until the Stability feature gets more complex.
"""
get_timestep_stability(is_stable::Union{Vector{Bool},Vector{Missing}})::Union{Vector{Bool},Vector{Missing}} = is_stable
