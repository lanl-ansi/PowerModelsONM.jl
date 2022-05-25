"""
    parse_events!(
        args::Dict{String,<:Any};
        validate::Bool=true,
        apply::Bool=true
    )::Dict{String,Any}

Parses events file in-place using [`parse_events`](@ref parse_events), for use inside of [`entrypoint`](@ref entrypoint).

If `apply`, will apply the events to the multinetwork data structure.

## Validation

If `validate=true` (default), the parsed data structure will be validated against the latest [Events Schema](@ref Events-Schema).
"""
function parse_events!(args::Dict{String,<:Any}; validate::Bool=true, apply::Bool=true)::Dict{String,Any}
    if !isempty(get(args, "events", ""))
        if isa(args["events"], String)
            if isa(get(args, "network", ""), Dict)
                args["raw_events"] = parse_events(args["events"]; validate=validate)
                args["events"] = parse_events(deepcopy(args["raw_events"]), args["network"])
            else
                @warn "no network is loaded, cannot convert events into native multinetwork structure"
                args["events"] = parse_events(args["events"])
            end
        elseif isa(args["events"], Vector) && isa(get(args, "network", ""), Dict)
            parse_events(args["events"], args["network"])
        end
    else
        args["events"] = Dict{String,Any}()
    end

    if apply
        if isa(get(args, "network", ""), Dict)
            apply_events!(args)
        else
            error("cannot apply events, no multinetwork is loaded in 'network'")
        end
    end

    return args["events"]
end


"""
    parse_events(
        events_file::String;
        validate::Bool=true
    )::Vector{Dict{String,Any}}

Parses an events file into a raw events data structure

## Validation

If `validate=true` (default), the parsed data structure will be validated against the latest [Events Schema](@ref Events-Schema).
"""
function parse_events(events_file::String; validate::Bool=true)::Vector{Dict{String,Any}}
    events = Vector{Dict{String,Any}}(JSON.parsefile(events_file))

    if validate && !validate_events(events)
        error("'events' file could not be validated")
    end

    return events
end


"""
    _convert_event_data_types!(
        events::Vector{<:Dict{String,<:Any}}
    )::Vector{Dict{String,Any}}

Helper function to convert JSON data types to native data types (Enums) in events.
"""
function _convert_event_data_types!(events::Vector{<:Dict{String,<:Any}})::Vector{Dict{String,Any}}
    for event in events
        for (k,v) in event["event_data"]
            if k ∈ ["state", "dispatchable", "status"]
                if isa(v, String)
                    event["event_data"][k] = getproperty(PMD, Symbol(uppercase(v)))
                elseif isa(v, Int)
                    event["event_data"][k] = getproperty(PMD, k == "state" ? :SwitchState : Symbol(titlecase(k)))(v)
                elseif isa(v, Bool)
                    event["event_data"][k] = getproperty(PMD, k == "state" ? :SwitchState : Symbol(titlecase(k)))(Int(v))
                end
            end
        end
    end

    return events
end


"""
    parse_events(
        raw_events::Vector{<:Dict{String,<:Any}},
        mn_data::Dict{String,<:Any}
    )::Dict{String,Any}

Converts `raw_events`, e.g. loaded from JSON, and therefore in the format Vector{Dict}, to an internal data structure
that closely matches the multinetwork data structure for easy merging (applying) to the multinetwork data structure.

Will attempt to find the correct subnetwork from the specified timestep by using "mn_lookup" in the multinetwork
data structure.

## Switch events

Will find the correct switch id from a `source_id`, i.e., the asset_type.name from the source file, which for switches
will be `line.name`, and create a data structure containing the properties defined in `event_data` under the native
ENGINEERING switch id.

## Fault events

Will attempt to find the appropriate switches that need to be OPEN to isolate a fault, and disable them, i.e.,
set `dispatchable=false`, until the end of the `duration` of the fault, which is specified in milliseconds.

It will re-enable the switches, i.e., set `dispatchable=true` after the fault has ended, if the next timestep
exists, but will not automatically set the switches to CLOSED again; this is a decision for the algorithm
[`optimize_switches`](@ref optimize_switches) to make.
"""
function parse_events(raw_events::Vector{<:Dict{String,<:Any}}, mn_data::Dict{String,<:Any})::Dict{String,Any}
    _convert_event_data_types!(raw_events)

    events = Dict{String,Any}()
    for event in raw_events
        n = _find_nw_id_from_timestep(mn_data, event["timestep"])

        if !haskey(events, n)
            events[n] = Dict{String,Any}(
                "switch" => Dict{String,Any}()
            )
        end

        if event["event_type"] == "switch"
            switch_id = _find_switch_id_from_source_id(mn_data["nw"][n], event["affected_asset"])

            if !ismissing(switch_id)
                events[n]["switch"][switch_id] = Dict{String,Any}(
                    k => v for (k,v) in event["event_data"]
                )
            end
        elseif event["event_type"] == "fault"
            switch_ids = _find_switch_ids_by_faulted_asset(mn_data["nw"][n], event["affected_asset"])
            n_next = _find_next_nw_id_from_fault_duration(mn_data, n, event["event_data"]["duration"])

            if !ismissing(n_next)
                if !haskey(events, n_next)
                    events[n_next] = Dict{String,Any}(
                        "switch" => Dict{String,Any}()
                    )
                end
            end

            for switch_id in switch_ids
                events[n]["switch"][switch_id] = Dict{String,Any}(
                    "state" => PMD.OPEN,
                    "dispatchable" => PMD.NO,
                )
                if !ismissing(n_next) && !haskey(events[n_next], switch_id)  # don't do it if there is already an event defined for switch_id at next timestep
                    events[n_next]["switch"][switch_id] = Dict{String,Any}(
                        "dispatchable" => PMD.YES,
                    )
                end
            end
        else
            @warn "event_type '$(event["event_type"])' not recognized, skipping"
        end
    end

    return events
end


"""
    parse_events(
        events_file::String,
        mn_data::Dict{String,<:Any};
        validate::Bool=true
    )::Dict{String,Any}

Parses raw events from `events_file` and passes it to [`parse_events`](@ref parse_events) to convert to the
native data type.

## Validation

If `validate=true` (default), the parsed data structure will be validated against the latest [Events Schema](@ref Events-Schema).
"""
function parse_events(events_file::String, mn_data::Dict{String,<:Any}; validate::Bool=true)::Dict{String,Any}
    raw_events = parse_events(events_file; validate=validate)
    events = parse_events(raw_events, mn_data)
end


"""
    apply_events!(args::Dict{String,<:Any})::Dict{String,Any}

Applies events in-place using [`apply_events`](@ref apply_events), for use inside of [`entrypoint`](@ref entrypoint)
"""
function apply_events!(args::Dict{String,<:Any})::Dict{String,Any}
    args["network"] = apply_events(args["network"], get(args, "events", Dict{String,Any}()))
end


"""
    apply_events(
        network::Dict{String,<:Any},
        events::Dict{String,<:Any}
    )::Dict{String,Any}

Creates a copy of the multinetwork data structure `network` and applies the events in `events`
to that data.
"""
function apply_events(network::Dict{String,<:Any}, events::Dict{String,<:Any})::Dict{String,Any}
    mn_data = deepcopy(network)

    ns = sort([parse(Int, i) for i in keys(network["nw"])])
    for (i,n) in enumerate(ns)
        nw = get(events, "$n", Dict())
        for (t,objs) in nw
            for (id,obj) in objs
                # Apply to all subnetworks starting with the current one until the end
                for j in ns[i:end]
                    merge!(mn_data["nw"]["$j"][t][id], obj)
                end
            end
        end
    end

    return mn_data
end


"""
    _find_switch_id_from_source_id(
        network::Dict{String,<:Any},
        source_id::String
    )::Union{String,Missing}

Helper function to find a switch id in the network model based on the dss `source_id`
"""
function _find_switch_id_from_source_id(network::Dict{String,<:Any}, source_id::String)::Union{String,Missing}
    for (id, switch) in get(network, "switch", Dict())
        if switch["source_id"] == lowercase(source_id)
            return id
        end
    end
    @info "events parsing: switch '$(source_id)' not found in network model, skipping"
    return missing
end


"helper function to find which switches need to be opened to isolate a fault on asset given by `source_id`"
function _find_switch_ids_by_faulted_asset(network::Dict{String,<:Any}, source_id::String)::Vector{String}
    # TODO algorithm for isolating faults (heuristic)
end


"""
    _find_nw_id_from_timestep(
        network::Dict{String,<:Any},
        timestep::Union{Real,String}
    )::String

Helper function to find the multinetwork id of the subnetwork of `network` corresponding most closely to a `timestep`.
"""
function _find_nw_id_from_timestep(network::Dict{String,<:Any}, timestep::Union{Real,String})::String
    @assert PMD.ismultinetwork(network) "network data structure is not multinetwork"

    if isa(timestep, Int) && all(isa(v, Int) for v in values(network["mn_lookup"]))
        for (nw_id,ts) in network["mn_lookup"]
            if ts == timestep
                return nw_id
            end
        end
    elseif isa(timestep, Int) && "$timestep" in keys(network["mn_lookup"])
        return "$timestep"
    elseif isa(timestep, String)
        timestep = all(isa(v, Int) for v in values(network["mn_lookup"])) ? parse(Int, timestep) : all(isa(v, Real) for v in values(network["mn_lookup"])) ? parse(Float16, timestep) : timestep
        for (nw_id,ts) in network["mn_lookup"]
            if ts == timestep
                return nw_id
            end
        end
    elseif !all(isa(v, Int) for v in values(network["mn_lookup"]))
        for (nw_id,ts) in network["mn_lookup"]
            if ts ≈ timestep
                return nw_id
            end
        end

        timesteps = sort(collect(values(network["mn_lookup"])))
        dist = timesteps .- timestep
        ts = findfirst(x->x≈minimum(dist[dist .> 0]), timesteps)
        for (nw_id, ts) in network["mn_lookup"]
            if ts == timestep
                return nw_id
            end
        end
    end
    error("could not find timestep '$(timestep)' in the multinetwork data structure")
end


"helper function to find the next timestep following a fault given its duration in ms"
function _find_next_nw_id_from_fault_duration(network::Dict{String,<:Any}, nw_id::String, duration::Real)::Union{String,Missing}
    current_timestep = network["mn_lookup"][nw_id]
    mn_lookup_reverse = Dict{Any,String}(v => k for (k,v) in network["mn_lookup"])

    timesteps = sort(collect(values(network["mn_lookup"])))
    dist = timesteps .- current_timestep + (duration / 3.6e6)  # duration is in ms, timestep in hours
    if all(dist .< 0)
        return missing
    else
        ts = findfirst(x->x ≈ minimum(dist[dist .> 0]), timesteps)
        return mn_lookup_reverse[ts]
    end
end


"""
    build_events(case_file::String; kwargs...)::Vector{Dict{String,Any}}

A helper function to assist in making rudamentary events data structure with some default settings for switches from a network case at path `case_file`.
"""
build_events(case_file::String; kwargs...)::Vector{Dict{String,Any}} = build_events(PMD.parse_file(case_file); kwargs...)


"""
    build_events(
        eng::Dict{String,<:Any};
        custom_events::Vector{Dict{String,Any}}=Dict{String,Any}[],
        default_switch_state::Union{PMD.SwitchState,String}=PMD.CLOSED,
        default_switch_dispatchable::Union{PMD.Dispatchable,Bool}=PMD.YES,
        default_switch_status::Union{Missing,PMD.Status,Int}=missing
    )::Vector{Dict{String,Any}}

A helper function to assist in making rudamentary events data structure with some default settings for switches.

- `eng::Dict{String,<:Any}` is the input case data structure
- `custom_events` is a Vector of *events* that will be applied **after** the automatic generation of events based off of the `default` kwargs
- `default_switch_state::Union{PMD.SwitchState,String}` (default: `CLOSED`) is the toggle for the default state to apply to every switch
- `default_switch_dispatchable::Union{PMD.Dispatchable,Bool}` (default: `YES`) is the toggle for the default dispatchability (controllability) of every switch
- `default_switch_status::Union{Missing,PMD.Status,Int}` (default: `missing`) is the toggle for the default status (whether the switch appears in the model at all or not) of every switch. If `missing` will default to the status given by the model.
"""
function build_events(
    eng::Dict{String,<:Any};
    custom_events::Vector{Dict{String,Any}}=Dict{String,Any}[],
    default_switch_state::Union{PMD.SwitchState,String}=PMD.CLOSED,
    default_switch_dispatchable::Union{PMD.Dispatchable,Bool}=PMD.YES,
    default_switch_status::Union{Missing,PMD.Status,Int}=missing
    )::Vector{Dict{String,Any}}

    @assert !PMD.ismultinetwork(eng) "this function cannot utilize multinetwork data"

    events = Dict{String,Any}[]

    default_switch_state = isa(default_switch_state, String) ? getproperty(PMD, Symbol(uppercase(default_switch_state))) : default_switch_state
    default_switch_dispatchable = isa(default_switch_dispatchable, Bool) ? PMD.Dispatchable(Int(default_switch_dispatchable)) : default_switch_dispatchable
    default_switch_status = isa(default_switch_status, Int) ? PMD.Status(default_switch_status) : default_switch_status

    for (s, switch) in get(eng, "switch", Dict())
        push!(
            events,
            Dict{String,Any}(
                "timestep" => 1,
                "event_type" => "switch",
                "affected_asset" => switch["source_id"],
                "event_data" => Dict{String,Any}(
                    "state" => string(default_switch_state),
                    "dispatchable" => string(default_switch_dispatchable),
                    "status" => ismissing(default_switch_status) ? string(switch["status"]) : string(default_switch_status),
                )
            )
        )
    end

    converted_custom_events = Dict{String,Any}[]
    for event in custom_events
        converted_event = Dict{String,Any}()

        if get(event, "event_type", "switch") == "switch"
            for (k,v) in event
                converted_event[k] = v
                if k == "event_data"
                    for (_k,_v) in v
                        converted_event[k][_k] = _v
                        if _k == "state" && !isa(_v, PMD.SwitchState)
                            converted_event[k][_k] = lowercase(_v) == "closed" ? PMD.CLOSED : PMD.OPEN
                        elseif _k == "status" && !isa(_v, PMD.Status)
                            converted_event[k][_k] = PMD.Status(_v)
                        elseif _k == "dispatchable" && !isa(_v, PMD.Dispatchable)
                            converted_event[k][_k] = PMD.Dispatchable(Int(_v))
                        end
                    end
                end
            end
            push!(converted_custom_events, converted_event)
        else
            # nothing to do
            push!(converted_custom_events, event)
        end
    end

    append!(events, converted_custom_events)

    return events
end


"""
    build_events_file(case_file::String, io::IO; kwargs...)

A helper function to save a rudamentary events data structure to `io` from a network case at path `case_file`.
"""
build_events_file(case_file::String, io::IO; kwargs...) = JSON.print(io, build_events(case_file; kwargs...))


"""
    build_events_file(eng::Dict{String,<:Any}, io::IO; kwargs...)

A helper function to save a rudamentary events data structure to `io` from a network case `eng`.
"""
build_events_file(eng::Dict{String,<:Any}, io::IO; kwargs...) = JSON.print(io, build_events(eng; kwargs...))


"""
    build_events_file(case_file::String, events_file::String; kwargs...)

A helper function to build a rudamentary `events_file` from a network case at path `case_file`.
"""
build_events_file(case_file::String, events_file::String; kwargs...) = build_events_file(PMD.parse_file(case_file), events_file; kwargs...)


"""
    build_events_file(eng::Dict{String,<:Any}, events_file::String; kwargs...)

A helper function to build a rudamentary `events_file` from a network case `eng`.
"""
function build_events_file(eng::Dict{String,<:Any}, events_file::String; kwargs...)
    open(events_file, "w") do io
        build_events_file(eng, io; kwargs...)
    end
end
