"""
    get_timestep_voltage_statistics!(args::Dict{String,<:Any})::Dict{String,Vector{Real}}

Gets voltage statistics min, mean, max for each timestep in-place in args, for use in [`entrypoint`][@ref entrypoint],
using [`get_timestep_voltage_statistics`](@ref get_timestep_voltage_statistics)
"""
function get_timestep_voltage_statistics!(args::Dict{String,<:Any})::Dict{String,Vector{Real}}
    args["output_data"]["Voltages"] = get_timestep_voltage_statistics(get(args["optimal_dispatch_result"], "solution", Dict()), args["network"])
end


"""
    get_voltage_min_mean_max(solution::Dict{String,<:Any}, data::Dict{String,<:Any}; make_per_unit::Bool=true)::Tuple{Real,Real,Real}

Calculates the minimum, mean, and maximum of the voltages across a network (not a multinetwork)

`data` is used to convert the units to per_unit if `make_per_unit` and the data is not already per_unit.

If `make_per_unit` (default: true), will return voltage statistics in per-unit representation. If `make_per_unit` is false, and there are different
voltage bases across the network, the statistics will not make sense.
"""
function get_voltage_min_mean_max(solution::Dict{String,<:Any}, data::Dict{String,<:Any}; make_per_unit::Bool=true)::Tuple{Real,Real,Real}
    if make_per_unit
        bus_vbase, line_vbase = PMD.calc_voltage_bases(data, data["settings"]["vbases_default"])
        voltages = [get(bus, "vm", zeros(length(data["bus"][id]["terminals"]))) ./ bus_vbase[id] for (id,bus) in solution["bus"]]
    else
        voltages = [get(bus, "vm", zeros(length(data["bus"][id]["terminals"]))) for (id,bus) in solution["bus"]]
    end

    return minimum(minimum.(voltages)), mean(mean.(voltages)), maximum(maximum.(voltages))
end


"""
    get_timestep_voltage_statistics(solution::Dict{String,<:Any}, network::Dict{String,<:Any}; make_per_unit::Bool=true)::Dict{String,Vector{Real}}

Returns statistics on the Minimum, Mean, and Maximum voltages for each timestep using [`get_voltage_min_mean_max`](@ref get_voltage_min_mean_max)

If `make_per_unit` (default: true), will return voltage statistics in per-unit representation. If `make_per_unit` is false, and there are different
voltage bases across the network, the statistics will not make sense.
"""
function get_timestep_voltage_statistics(solution::Dict{String,<:Any}, network::Dict{String,<:Any}; make_per_unit::Bool=true)::Dict{String,Vector{Real}}
    voltages = Dict{String,Vector{Real}}(
        "Min voltage (p.u.)" => Real[],
        "Mean voltage (p.u.)" => Real[],
        "Max voltage (p.u.)" => Real[],
    )
    per_unit = get(solution, "per_unit", true)
    for n in sort([parse(Int,i) for i in keys(get(solution, "nw", Dict()))])
        nw = network["nw"]["$n"]
        nw["data_model"] = network["data_model"]
        min_v, mean_v, max_v = get_voltage_min_mean_max(solution["nw"]["$n"], nw; make_per_unit=make_per_unit && !per_unit)
        push!(voltages["Min voltage (p.u.)"], min_v)
        push!(voltages["Mean voltage (p.u.)"], mean_v)
        push!(voltages["Max voltage (p.u.)"], max_v)
    end

    return voltages
end


"""
    get_timestep_dispatch!(args::Dict{String,<:Any})::Vector{Dict{String,Any}}

Gets the optimal dispatch results in-place in args, for use in [`entrypoint`](@ref entrypoint), using
[`get_timestep_dispatch`](@ref get_timestep_dispatch).
"""
function get_timestep_dispatch!(args::Dict{String,<:Any})::Vector{Dict{String,Any}}
    args["output_data"]["Powerflow output"] = get_timestep_dispatch(get(args["optimal_dispatch_result"], "solution", Dict()))
end


"""
    get_timestep_dispatch(solution::Dict{String,<:Any})::Vector{Dict{String,Any}}

Returns the dispatch information for generation assets (generator, storage, solar, voltage_source) and bus voltage magnitudes in SI units for each timestep
from the optimal dispatch `solution`
"""
function get_timestep_dispatch(solution::Dict{String,<:Any})::Vector{Dict{String,Any}}
    dispatch = Dict{String,Any}[]

    for n in sort([parse(Int, i) for i in keys(get(solution, "nw", Dict()))])
        _dispatch = Dict{String,Any}(
            "bus" => Dict{String,Any}(),
        )

        for (gen_type, (p, q)) in [("storage", ("ps", "qs")), ("generator", ("pg", "qg")), ("solar", ("pg", "qg")), ("voltage_source", ("pg", "qg"))]
            if !isempty(get(solution["nw"]["$n"], gen_type, Dict()))
                _dispatch[gen_type] = Dict{String,Any}()
                for (id, gen) in solution["nw"]["$n"][gen_type]
                    _dispatch[gen_type][id] = Dict{String,Any}(
                        "real power setpoint (kW)" => gen[p],
                        "reactive power setpoint (kVar)" => gen[q],
                    )
                end
            end
        end

        for (id, bus) in get(solution["nw"]["$n"], "bus", Dict())
            _dispatch["bus"][id] = Dict{String,Any}(
                "voltage (V)" => haskey(bus, "vr") && haskey(bus, "vi") ? sqrt.(bus["vr"].^2 + bus["vi"].^2) : bus["vm"],
            )
        end

        push!(dispatch, _dispatch)
    end

    return dispatch
end
