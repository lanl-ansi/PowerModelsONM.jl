"""
    parse_events!(args::Dict{String,<:Any})

Parses events file in-place (within the args Dict data structure), for use inside of [`entrypoint`](@ref entrypoint)
"""
function parse_events!(args::Dict{String,<:Any})
    args["events"] = !isempty(get(args, "events", "")) ? isa(args["events"], String) ? parse_events(args["events"]) : args["events"] : Dict{String,Any}[]

    # TODO re-enable events validation
    # if !validate_events(args["events"])
    #     error("'events' file could not be validated")
    # end

    apply_events!(args)
end


"""
    parse_events(events_file::String)

Parses the events JSON file (no intepretations made)
"""
function parse_events(events_file::String)::Vector{Dict{String,Any}}
    JSON.parsefile(events_file)
end


"""
    apply_events!(args::Dict{String,<:Any})

Applies events in-place (within the args data structure), for use inside of [`entrypoint`](@ref entrypoint)
"""
function apply_events!(args::Dict{String,<:Any})
    apply_events!(args["network"], args["events"])
end


"""
    apply_events!(network::Dict, events::Vector{Dict})::Dict

Applies events to the __multinetwork__ `ENGINEERING` data structure

## Notes

Currently, only supports switch actions, fault actions to be added
"""
function apply_events!(network::Dict{String,Any}, events::Vector{<:Dict{String,Any}})::Dict{String,Any}
    parsed_events = Dict{String,Any}("nw"=>Dict{String,Any}())
    for event in events
        source_id = event["affected_asset"]
        asset_type, asset_name = split(lowercase(source_id), ".")
        timestep = event["timestep"]
        start_timestep = get_timestep(timestep, network)

        if !haskey(parsed_events["nw"], "$start_timestep")
            parsed_events["nw"]["$start_timestep"] = Dict{String,Any}()
        end

        if event["event_type"] == "switch"
            if !haskey(parsed_events["nw"]["$start_timestep"], "switch")
                parsed_events["nw"]["$start_timestep"]["switch"] = Dict{String,Any}()
            end

            if haskey(network, "nw")
                if any(haskey(nw["switch"], asset_name) for (_,nw) in network["nw"])
                    parsed_events["nw"]["$start_timestep"]["switch"][asset_name] = get(event, "event_data", Dict{String,Any}())

                    for (n, nw) in network["nw"]
                        if parse(Int, n) >= start_timestep
                            if haskey(nw["switch"], asset_name)
                                if haskey(event["event_data"], "status")
                                    nw["switch"][asset_name]["status"] = PMD.Status(event["event_data"]["status"])
                                end

                                if haskey(event["event_data"], "state")
                                    nw["switch"][asset_name]["state"] = Dict{String,PMD.SwitchState}("closed"=>PMD.CLOSED, "open"=>PMD.OPEN)[lowercase(event["event_data"]["state"])]
                                end

                                if haskey(event["event_data"], "dispatchable")
                                    nw["switch"][asset_name]["dispatchable"] = event["event_data"]["dispatchable"] ? PMD.YES : PMD.NO
                                end
                            else
                                @info "switch '$(asset_name)' mentioned in events does not exist in data set at timestep $(n)"
                            end
                        end
                    end
                else
                    @info  "switch '$(asset_name)' mentioned in events does not exist in data set"
                end
            else
                network["switch"][asset_name]["state"] = Dict{String,PMD.SwitchState}("closed"=>PMD.CLOSED, "open"=>PMD.OPEN)
            end

        else
            @warn "event of type '$(event["event_type"])' at timestep $(timestep) is not yet supported in PowerModelsONM"
        end
    end
    return parsed_events
end
