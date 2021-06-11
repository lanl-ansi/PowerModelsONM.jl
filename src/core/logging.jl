"""
    silence!(mod::Module)

Sets loglevel for Module `mod` to `:Error`, silencing Info and Warn
"""
function silence!(mod)
    set_logging_level!(mod, :Error)
end


"Helper function to set loglevel of ONM to :Error"
silence!() = silence!(PowerModelsONM)


"""
    reset_logging_level!()

Resets the log level to Info
"""
function reset_logging_level!()
    Logging.global_logger(Logging.ConsoleLogger(; meta_formatter=PowerModelsDistribution._pmd_metafmt))
end


"""
    set_logging_level!(mod::Module, level::Symbol)

Sets the logging level for Module `mod`: `:Info`, `:Warn`, `:Error`
"""
function set_logging_level!(mod::Module, level::Symbol)
    Logging.global_logger(_make_filtered_logger(mod, getfield(Logging, level)))
end


"Helper function to set logging level of ONM"
set_logging_level!(level::Symbol) = set_logging_level!(PowerModelsONM, level)


"""
    _make_filtered_logger(mod::Module, level::Logging.LogLevel)

Helper function to create the filtered logger for PMD
"""
function _make_filtered_logger(mods::Vector, level::Logging.LogLevel)
    LoggingExtras.EarlyFilteredLogger(_LOGGER) do log
        if any(log._module == mod for mod in mods) && log.level < level
            return false
        else
            return true
        end
    end
end


"""
    _make_filtered_logger(mod::Module, level::Logging.LogLevel)

Helper function to create the filtered logger for PMD
"""
function _make_filtered_logger(mod::Module, level::Logging.LogLevel)
    LoggingExtras.EarlyFilteredLogger(_LOGGER) do log
        if log._module == mod && log.level < level
            return false
        else
            return true
        end
    end
end


"Helper function to create the filtered logger for ONM"
_make_filtered_logger(level) = _make_filtered_logger(PowerModelsONM, level)


"""
    setup_logging!(args::Dict{String,<:Any})

Configures logging based on runtime arguments, for use inside [`entrypoint`](@ref entrypoint)
"""
function setup_logging!(args::Dict{String,<:Any})
    mods = [PowerModelsDistribution, PowerModelsProtection, PowerModelsStability, Juniper, JSONSchema]
    if get(args, "quiet", false)
        loglevel = Logging.Error
        push!(mods, PowerModelsONM)

        # TODO remove need for Memento
        PMD._IM.silence()
    elseif get(args, "verbose", false)
        loglevel = Logging.Info
    elseif get(args, "debug", false)
        loglevel = Logging.Debug
    else
        loglevel = Logging.Error

        # TODO remove need for Memento
        PMD._IM.silence()
    end

    Logging.global_logger(_make_filtered_logger(mods, loglevel))
end
