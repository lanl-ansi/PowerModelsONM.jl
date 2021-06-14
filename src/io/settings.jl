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

    if validate && !validate_network_settings(args["settings"])
        error("'settings' file could not be validated")
    end

    # Handle depreciated command line arguments
    _convert_depreciated_runtime_args!(args, args["settings"], args["base_network"], length(args["network"]["nw"]))

    apply && apply_settings!(args)

    return args["settings"]
end


""
function _convert_depreciated_runtime_args!(runtime_args::Dict{String,<:Any}, settings::Dict{String,<:Any}, base_network::Dict{String,<:Any}, timesteps::Int)::Tuple{Dict{String,Any},Dict{String,Any}}
    haskey(runtime_args, "voltage-lower-bound") && _convert_to_settings!(settings, base_network, "bus", "vm_lb", pop!(runtime_args, "voltage-lower-bound"))
    haskey(runtime_args, "voltage-upper-bound") && _convert_to_settings!(settings, base_network, "bus", "vm_ub", pop!(runtime_args, "voltage-upper-bound"))
    haskey(runtime_args, "voltage-angle-difference") && _convert_to_settings!(settings, base_network, "line", "vad_lb", -runtime_args["voltage-angle-difference"])
    haskey(runtime_args, "voltage-angle-difference") && _convert_to_settings!(settings, base_network, "line", "vad_ub",  pop!(runtime_args, "voltage-angle-difference"))
    haskey(runtime_args, "clpu-factor") && _convert_to_settings!(settings, base_network, "load", "clpu_factor", pop!(runtime_args, "clpu-factor"); multiphase=false)
    if haskey(runtime_args, "timestep-hours")
        settings["time_elapsed"] = fill(pop!(runtime_args, "timestep-hours"), timesteps)
    end

    if haskey(runtime_args, "max-switch-actions")
        settings["max_switch_actions"] = fill(pop!(runtime_args, "max-switch-actions"), timesteps)
    end

    return runtime_args, settings
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
function _convert_to_settings!(settings::Dict{String,<:Any}, base_network::Dict{String,<:Any}, asset_type::String, property::String, value::Any; multiphase::Bool=true)
    if haskey(base_network, asset_type)
        if !haskey(settings, asset_type)
            settings[asset_type] = Dict{String,Any}()
        end

        for (id, asset) in base_network[asset_type]
            if !haskey(settings[asset_type], id)
                settings[asset_type][id] = Dict{String,Any}()
            end

            nphases = asset_type == "bus" ? length(asset["terminals"]) : asset_type in PMD._eng_edge_elements ? asset_type == "transformer" && haskey(asset, "bus") ? length(asset["connections"][1]) : length(asset["f_connections"]) : length(asset["connections"])

            settings[asset_type][id][property] = multiphase ? fill(value, nphases) : value
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
