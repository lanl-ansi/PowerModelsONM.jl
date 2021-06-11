"""
    parse_settings!(args::Dict{String,Any})

Parses settings file specifed in runtime arguments in-place
"""
function parse_settings!(args::Dict{String,<:Any}; apply::Bool=true, validate::Bool=true)::Dict{String,Any}
    if !isempty(get(args, "settings", ""))
        if isa(args["settings"], String)
            args["settings"] = parse_settings(args["settings"])
        end
    else
        args["settings"] = Dict{String,Any}()
    end

    # TODO enable settings validation
    # if validate && !validate_runtime_settings(args["settings"])
    #     error("'settings' file could not be validated")
    # end

    # Handle depreciated command line arguments
    haskey(args, "voltage-lower-bound") && _convert_to_settings!(args, "bus", "vm_lb", pop!(args, "voltage-lower-bound"))
    haskey(args, "voltage-upper-bound") && _convert_to_settings!(args, "bus", "vm_ub", pop!(args, "voltage-upper-bound"))
    haskey(args, "voltage-angle-difference") && _convert_to_settings!(args, "line", "vad_lb", -args["voltage-angle-difference"])
    haskey(args, "voltage-angle-difference") && _convert_to_settings!(args, "line", "vad_ub",  pop!(args, "voltage-angle-difference"))
    haskey(args, "clpu-factor") && _convert_to_settings!(args, "load", "clpu_factor", pop!(args, "clpu-factor"); multiphase=false)
    if haskey(args, "timestep-hours")
        args["settings"]["time_elapsed"] = fill(pop!(args, "timestep-hours"), length(args["network"]["nw"]))
    end

    if haskey(args, "max-switch-actions")
        args["settings"]["max_switch_actions"] = fill(pop!(args, "max-switch-actions"), length(args["network"]["nw"]))
    end

    apply && apply_settings!(args)

    return args["settings"]
end


"""
    parse_settings(settings_file::String)::Dict{String,Any}

Parses settings.json file
"""
function parse_settings(settings_file::String)::Dict{String,Any}
    JSON.parsefile(settings_file)
end


"""
    apply_settings!(args::Dict{String,Any})

Applies settings to the network
"""
function apply_settings!(args::Dict{String,Any})
    for (s, setting) in get(args, "settings", Dict())
        if s in PMD.pmd_eng_asset_types
            _apply_to_network!(args, s, setting)


        elseif s in ["time_elapsed", "max_switch_actions"]
            for n in sort([parse(Int, i) for i in keys(args["network"]["nw"])])
                args["network"]["nw"]["$n"][s] = setting[n]
            end
        end
    end
end


"converts depreciated global settings, e.g. voltage-lower-bound, to the proper way to specify settings"
function _convert_to_settings!(args::Dict{String,<:Any}, asset_type::String, property::String, value::Any; multiphase::Bool=true)
    if haskey(args["base_network"], asset_type)
        if !haskey(args["settings"], asset_type)
            args["settings"][asset_type] = Dict{String,Any}()
        end

        for (id, asset) in args["base_network"][asset_type]
            if !haskey(args["settings"][asset_type], id)
                args["settings"][asset_type][id] = Dict{String,Any}()
            end

            nphases = asset_type == "bus" ? length(asset["terminals"]) : asset_type in PMD._eng_edge_elements ? asset_type == "transformer" && haskey(asset, "bus") ? length(asset["connections"][1]) : length(asset["f_connections"]) : length(asset["connections"])

            args["settings"][asset_type][id][property] = multiphase ? fill(value, nphases) : value
        end
    end
end


"helper function that applies settings to the network objects of `type`"
function _apply_to_network!(args::Dict{String,<:Any}, type::String, data::Dict{String,<:Any})
    for (_,nw) in args["network"]["nw"]
        if haskey(nw, type)
            for (id, _data) in data
                if haskey(nw[type], id)
                    merge!(nw[type][id], _data)
                end
            end
        end
    end
end
