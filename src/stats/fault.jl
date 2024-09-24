"""
    get_timestep_fault_currents!(
        args::Dict{String,<:Any}
    )::Vector{Dict{String,Any}}

Gets fault currents for switches and corresponding fault from study in-place in args, for use in [`entrypoint`](@ref entrypoint),
using [`get_timestep_fault_currents`](@ref get_timestep_fault_currents).
"""
function get_timestep_fault_currents!(args::Dict{String,<:Any})::Vector{Dict{String,Any}}
    args["output_data"]["Fault currents"] = get_timestep_fault_currents(get(args, "fault_studies_results", Dict{String,Any}()), get(args, "faults", Dict{String,Any}()), args["network"]; ret_protection_only=!(get(args, "debug", false) || get(args, "verbose", false)))
end


"""
    get_timestep_fault_currents(
        fault_studies_results::Dict{String,<:Any},
        faults::Dict{String,<:Any},
        network::Dict{String,<:Any};
        ret_protection_only::Bool=false
    )::Vector{Dict{String,Any}}

Gets information about the results of fault studies at each timestep, including:

- information about the fault, such as
  - the admittance (`"conductance (S)"` and `"susceptance (S)"`),
  - the bus at which the fault is applied
  - the type of fault (3p, 3pg, llg, ll, lg), and
  - to which connections the fault applies
- information about the state at the network's protection, including
  - the fault current `|I| (A)`
  - the zero-sequence fault current `|I0| (A)`
  - the positive-sequence fault current `|I1| (A)`
  - the negative-sequence fault current `|I2| (A)`
  - the bus voltage from the from-side of the switch `|V| (V)`
  - the bus voltage angle from the from-side of the switch `phi (deg)`

`ret_protection_only==false` indicates that currents and voltages should be returned for all lines where switch=y, and if
`true`, should only return switches for which a protection device is defined (recloser, relay, fuse)
"""
function get_timestep_fault_currents(fault_studies_results::Dict{String,<:Any}, faults::Dict{String,<:Any}, network::Dict{String,<:Any}; ret_protection_only::Bool=true)::Vector{Dict{String,Any}}
    Dict{String,Any}[fault_studies_results["$n"] for n in sort([parse(Int, k) for k in keys(fault_studies_results)])]
end

"""
    get_timestep_fault_currents(
        fault_studies_results::Dict{String,<:Any},
        faults::String,
        network::Dict{String,<:Any}
    )::Vector{Dict{String,Any}}

Special case where the faults string was not parsed
"""
get_timestep_fault_currents(fault_studies_results::Dict{String,<:Any}, faults::String, network::Dict{String,<:Any}; ret_protection_only::Bool=false)::Vector{Dict{String,Any}} = get_timestep_fault_currents(fault_studies_results, Dict{String,Any}(), network; ret_protection_only=ret_protection_only)


"""
    get_timestep_fault_currents(::Dict{String,<:Any}, ::String, ::String; ret_protection_only::Bool=false)::Vector{Dict{String,Any}}

Helper function for the variant where `args["network"]` hasn't been parsed yet.
"""
get_timestep_fault_currents(::Dict{String,<:Any}, ::String, ::String; ret_protection_only::Bool=false)::Vector{Dict{String,Any}} = Dict{String,Any}[]


"""
    get_timestep_fault_study_metadata!(
        args::Dict{String,<:Any}
    )::Vector{Dict{String,Any}}

Retrieves the switching optimization results metadata from the optimal switching solution via
[`get_timestep_fault_study_metadata`](@ref get_timestep_fault_study_metadata)
and applies it in-place to args, for use with [`entrypoint`](@ref entrypoint)
"""
function get_timestep_fault_study_metadata!(args::Dict{String,<:Any})::Vector{Dict{String,Any}}
    args["output_data"]["Fault studies metadata"] = get_timestep_fault_study_metadata(get(args, "fault_studies_results", Dict{String,Any}()))
end


"""
    get_timestep_fault_study_metadata(
        fault_studies_results::Dict{String,Any}
    )::Vector{Dict{String,Any}}

Gets the metadata from the optimal switching results for each timestep, returning a list of Dicts
(if `opt_switch_algorithm="rolling-horizon"`), or a list with a single Dict (if `opt_switch_algorithm="full-lookahead"`).
"""
function get_timestep_fault_study_metadata(fault_studies_results::Dict{String,Any})::Vector{Dict{String,Any}}
    results_metadata = Dict{String,Any}[]
end
