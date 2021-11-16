"""
    get_timestep_fault_currents!(args::Dict{String,<:Any})::Vector{Dict{String,Any}}

Gets fault currents for switches and corresponding fault from study in-place in args, for use in [`entrypoint`](@ref entrypoint),
using [`get_timestep_fault_currents`](@ref get_timestep_fault_currents).
"""
function get_timestep_fault_currents!(args::Dict{String,<:Any})::Vector{Dict{String,Any}}
    args["output_data"]["Fault currents"] = get_timestep_fault_currents(get(args, "fault_studies_results", Dict{String,Any}()), get(args, "faults", Dict{String,Any}()), args["network"])
end


"""
    get_timestep_fault_currents(fault_studies_results::Dict{String,<:Any}, faults::Dict{String,<:Any}, network::Dict{String,<:Any})::Vector{Dict{String,Any}}

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
"""
function get_timestep_fault_currents(fault_studies_results::Dict{String,<:Any}, faults::Dict{String,<:Any}, network::Dict{String,<:Any})::Vector{Dict{String,Any}}
    fault_currents = Dict{String,Any}[]

    for n in sort([parse(Int, i) for i in keys(fault_studies_results)])
        _fault_currents = Dict{String,Any}()
        for (bus_id, fault_types) in faults
            _fault_currents[bus_id] = Dict{String,Any}()
            for (fault_type, sub_faults) in fault_types
                _fault_currents[bus_id][fault_type] = Dict{String,Any}()
                for (fault_id, fault_result) in sub_faults
                    fault = faults[bus_id][fault_type][fault_id]
                    fault_sol = get(get(get(get(get(fault_studies_results, "$n", Dict()), bus_id, Dict()), fault_type, Dict()), fault_id, Dict()), "solution", Dict())

                    _fault_currents[bus_id][fault_type][fault_id] =  Dict{String,Any}(
                        "fault" => Dict{String,Any}(
                            "bus" => fault["bus"],
                            "type" => fault["fault_type"],
                            "conductance (S)" => fault["g"],
                            "susceptance (S)" => fault["b"],
                            "connections" => fault["connections"],
                        ),
                        "switch" => Dict{String,Any}(
                            id => Dict{String,Any}(
                                "|I| (A)" => get(get(get(fault_sol, "switch", Dict()), id, Dict()), "cf_fr", fill(0.0, length(switch["f_connections"]))),
                                "|I0| (A)" => sqrt(get(get(get(fault_sol, "switch", Dict()), id, Dict()), "cf0r_fr", 0.0)^2 + get(get(get(fault_sol, "switch", Dict()), id, Dict()), "cf0i_fr", 0.0)^2),
                                "|I1| (A)" => sqrt(get(get(get(fault_sol, "switch", Dict()), id, Dict()), "cf1r_fr", 0.0)^2 + get(get(get(fault_sol, "switch", Dict()), id, Dict()), "cf1i_fr", 0.0)^2),
                                "|I2| (A)" => sqrt(get(get(get(fault_sol, "switch", Dict()), id, Dict()), "cf2r_fr", 0.0)^2 + get(get(get(fault_sol, "switch", Dict()), id, Dict()), "cf2i_fr", 0.0)^2),
                                # TODO add real and imaginary sequence currents
                                "|V| (V)" => sqrt.(
                                       get(get(get(fault_sol, "bus", Dict()), switch["f_bus"], Dict()), "vr", fill(0.0, length(network["nw"]["$n"]["bus"][switch["f_bus"]]["terminals"])))[findall(network["nw"]["$n"]["bus"][switch["f_bus"]]["terminals"].==switch["f_connections"])].^2
                                    .+ get(get(get(fault_sol, "bus", Dict()), switch["f_bus"], Dict()), "vi", fill(0.0, length(network["nw"]["$n"]["bus"][switch["f_bus"]]["terminals"])))[findall(network["nw"]["$n"]["bus"][switch["f_bus"]]["terminals"].==switch["f_connections"])].^2
                                )
                            ) for (id, switch) in get(network["nw"]["$n"], "switch", Dict())
                        ),
                    )
                end
            end
        end
        push!(fault_currents, _fault_currents)
    end

    return fault_currents
end

"Special case where the faults string was not parsed"
get_timestep_fault_currents(fault_studies_results::Dict{String,<:Any}, faults::String, network::Dict{String,<:Any})::Vector{Dict{String,Any}} = get_timestep_fault_currents(fault_studies_results, Dict{String,Any}(), network)
