"default eng2math passthrough"
const _eng2math_passthrough_default = Dict{String,Vector{String}}(
    "root"=>String[
        "options",
        "switch_close_actions_ub",
    ],
    "load"=>String["priority"],
    "bus"=>String["microgrid_id"],
    "generator"=>String["inverter"],
    "solar"=>String["inverter"],
    "storage"=>String["phase_unbalance_ub", "inverter"],
    "voltage_source"=>["inverter"],
)


"default global_keys passthrough"
const _global_keys_default = Set{String}(["options", "solvers"])


"""
    transform_data_model(eng::T; global_keys::Set{String}=Set{String}(), eng2math_passthrough::Dict{String,<:Vector{<:String}}=Dict{String,Vector{String}}(), kwargs...)::T where T <: Dict{String,Any}

ONM-specific version of `PowerModelsDistribution.transform_data_model` that includes the necessary default `eng2math_passthrough` and `global_keys`.
"""
function transform_data_model(eng::T; global_keys::Set{String}=Set{String}(), eng2math_passthrough::Dict{String,<:Vector{<:String}}=Dict{String,Vector{String}}(), kwargs...)::T where T <: Dict{String,Any}
    PMD.transform_data_model(
        eng;
        global_keys=union(_global_keys_default, global_keys),
        eng2math_passthrough=recursive_merge_including_vectors(_eng2math_passthrough_default, eng2math_passthrough),
    )
end
