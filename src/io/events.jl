"""
    parse_events!(args::Dict{String,<:Any})::Dict

Parses events file in-place using [`parse_faults`](@ref parse_faults), for use inside of [`entrypoint`](@ref entrypoint)
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
    parse_events(events_file::String)::Dict

Parses the events JSON file (no intepretations made), and validates against JSON Schema in `models` folder if `validate=true` (default).
"""
function parse_events(events_file::String; validate::Bool=true)::Vector{Dict{String,Any}}
    events = Vector{Dict{String,Any}}(JSON.parsefile(events_file))

    if validate && !validate_events(events)
        error("'events' file could not be validated")
    end

    return events
end


""
function _fix_event_data_types!(events::Vector{<:Dict{String,<:Any}})::Vector{Dict{String,Any}}
    for event in events
        for (k,v) in event["event_data"]
            if k == "dispatchable"
                event["event_data"][k] = PMD.Dispatchable(Int(v))
            end

            if k == "state"
                event["event_data"][k] = Dict("open" => PMD.OPEN, "closed" => PMD.CLOSED)[lowercase(v)]
            end

            if k == "status"
                event["event_data"][k] = PMD.Status(v)
            end
        end
    end

    return events
end


"""
    parse_events(raw_events::Vector{Dict}, mn_data::Dict)::Dict

TODO documentation for parse_events
"""
function parse_events(raw_events::Vector{<:Dict{String,<:Any}}, mn_data::Dict{String,<:Any})::Dict{String,Any}
    _fix_event_data_types!(raw_events)

    events = Dict{String,Any}()
    for event in raw_events
        n = _find_nw_id_from_timestep(mn_data, event["timestep"])

        if !haskey(events, n)
            events[n] = Dict{String,Any}()
        end

        if event["event_type"] == "switch"
            switch_id = _find_switch_id_from_source_id(mn_data["nw"][n], event["affected_asset"])

            events[n][switch_id] = Dict{String,Any}(
                k => v for (k,v) in event["event_data"]
            )
        elseif event["event_type"] == "fault"
            switch_ids = _find_switch_ids_by_faulted_asset(mn_data["nw"][n], event["affected_asset"])
            n_next = _find_next_nw_id_from_fault_duration(mn_data, n, event["event_data"]["duration"])

            if !ismissing(n_next)
                if !haskey(events, n_next)
                    events[n_next] = Dict{String,Any}()
                end
            end

            for switch_id in switch_ids
                events[n][switch_id] = Dict{String,Any}(
                    "state" => PMD.OPEN,
                    "dispatchable" => PMD.NO,
                )
                if !ismissing(n_next) && !haskey(events[n_next], switch_id)  # don't do it if there is already an event defined for switch_id at next timestep
                    events[n_next][switch_id] = Dict{String,Any}(
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
    parse_events(events_file::String, mn_data::Dict; validate::Bool=true)::Dict{String,Any}

"""
function parse_events(events_file::String, mn_data::Dict{String,<:Any}; validate::Bool=true)::Dict{String,Any}
    raw_events = parse_events(events_file; validate=validate)
    events = parse_events(raw_events, mn_data)
end


"""
    apply_events!(args::Dict{String,<:Any})

Applies events in-place using [`apply_events`](@ref apply_events), for use inside of [`entrypoint`](@ref entrypoint)
"""
function apply_events!(args::Dict{String,<:Any})
    args["network"] = apply_events(args["network"], args["events"])
end


"""
"""
function apply_events(mn_data::Dict{String,<:Any}, events::Dict{String,<:Any})::Dict{String,Any}
    network = deepcopy(mn_data)

    PMD._IM.update_data!(network, events)

    return mn_data
end


"helper function to find a switch id in the network model based on the dss `source_id`"
function _find_switch_id_from_source_id(network::Dict{String,<:Any}, source_id::String)::String
    for (id, switch) in get(network, "switch", Dict())
        if switch["source_id"] == source_id
            return id
        end
    end
    error("switch '$(source_id)' not found in network model, aborting")
end


"helper function to find which switches need to be opened to isolate a fault on asset given by `source_id`"
function _find_switch_ids_by_faulted_asset(network::Dict{String,<:Any}, source_id::String)::Vector{String}
    # TODO algorithm for isolating faults (heuristic)
end


"helper function to find the multinetwork id of the subnetwork corresponding most closely to a `timestep`"
function _find_nw_id_from_timestep(network::Dict{String,<:Any}, timestep::Union{Real,String})::String
    @assert PMD.ismultinetwork(network) "network data structure is not multinetwork"

    if isa(timestep, Int) && all(isa(v, Int) for v in values(network["mn_lookup"])) || isa(timestep, String)
        if isa(timestep, String)
            timestep = all(isa(v, Int) for v in values(network["mn_lookup"])) ? parse(Int, timestep) : all(isa(v, Real) for v in values(network["mn_lookup"])) ? parse(Float16, timestep) : timestep
        end

        for (nw_id,ts) in network["mn_lookup"]
            if ts == timestep
                return nw_id
            end
        end
    else
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
