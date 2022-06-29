"""
    _make_filtered_logger(mods::Vector, level::Logging.LogLevel)

Helper function to create the filtered logger for PMD
"""
function _make_filtered_logger(mods::Vector{<:Module}, level::Logging.LogLevel)
    LoggingExtras.EarlyFilteredLogger(_LOGGER) do log
        if any(log._module == mod for mod in mods) && log.level < level
            return false
        else
            return true
        end
    end
end


"""
    _make_filtered_logger(mods::Vector{Tuple{<:Module,Logging.LogLevel}})

Helper function to create the filtered logger for PMD
"""
function _make_filtered_logger(mods_levels::Vector{Tuple{<:Module,Logging.LogLevel}})
    LoggingExtras.EarlyFilteredLogger(_LOGGER) do log
        if any(log._module == mod && log.level < level for (mod,level) in mods_levels)
            return false
        else
            return true
        end
    end
end


"""
    setup_logging!(args::Dict{String,<:Any})

Configures logging based on runtime arguments
"""
function setup_logging!(args::Dict{String,<:Any})
    log_level = get(args, "log-level", "warn")

    set_log_level!(Symbol(titlecase(log_level)))
end


"""
    set_log_level!(level::Symbol)

Configures logging based `level`, `:Error`, `:Warn`, `:Info`, or `:Debug`
"""
function set_log_level!(level::Symbol)
    if level == :Error
        loglevel = Logging.Error
        IM.silence()
    elseif level == :Info
        loglevel = Logging.Info
        IM.logger_config!("info")
    elseif level == :Debug
        loglevel = Logging.Debug
        IM.logger_config!("debug")
    else
        loglevel = Logging.Warn
        IM.logger_config!("warn")
    end

    mods = [
        (PowerModelsONM, loglevel),
        (PMD, loglevel),
        (PMP, loglevel),
        (PMS, loglevel),
        (Juniper, loglevel),
        (JSONSchema, Logging.Warn)
    ]

    Logging.global_logger(_make_filtered_logger(mods))
end


"""
    silence!()

Sets logging level to "quiet"
"""
function silence!()
    set_log_level!(:Error)
end
