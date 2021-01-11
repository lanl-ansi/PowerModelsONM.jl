module PowerModelsONM
    import InfrastructureModels
    import PowerModelsDistribution

    const PMD = PowerModelsDistribution

    import Ipopt

    import ArgParse
    import JSON
    import Memento

    import Statistics: mean

    function __init__()
        global _LOGGER = Memento.getlogger(PowerModelsDistribution._PM)
    end

    include("core/common.jl")
    include("core/io.jl")
    include("core/statistics.jl")

    include("app/main.jl")

    include("core/export.jl")
end # module
