module PowerModelsONM
    using Base: Bool

    import PowerModelsDistribution
    const PMD = PowerModelsDistribution

    import JuMP
    import JuMP: optimizer_with_attributes

    import Ipopt
    import Cbc
    import Juniper

    try
        @eval import Gurobi
    catch err
        @warn "Gurobi.jl not installed."
    end

    import ArgParse

    import DataFrames

    import JSON
    import JSONSchema

    import Logging
    import LoggingExtras

    import Dates

    import LinearAlgebra: eigvals
    import Statistics: mean

    # Additional PowerModels{x} Services
    import PowerModelsProtection
    import PowerModelsStability

    function __init__()
        global _LOGGER = Logging.ConsoleLogger(; meta_formatter=PowerModelsDistribution._pmd_metafmt)
        try
            global GRB_ENV = Gurobi.Env()
        catch err
        end
    end

    include("core/common.jl")
    include("core/constraint_template.jl")
    include("core/constraint.jl")
    include("core/data.jl")
    include("core/logging.jl")
    include("core/objective.jl")
    include("core/ref.jl")
    include("core/solution.jl")
    include("core/statistics.jl")
    include("core/variable.jl")

    include("data_model/checks.jl")
    include("data_model/transformations.jl")

    include("form/shared.jl")

    include("io/events.jl")
    include("io/faults.jl")
    include("io/inverters.jl")
    include("io/json.jl")
    include("io/network.jl")
    include("io/output.jl")
    include("io/protection.jl")
    include("io/settings.jl")

    include("prob/common.jl")
    include("prob/dispatch.jl")
    include("prob/fs.jl")
    include("prob/osw_mld.jl")
    include("prob/osw.jl")
    include("prob/stability.jl")
    include("prob/switch.jl")

    include("cli/arguments.jl")

    include("app/main.jl")

    # Export must go last
    include("core/export.jl")
end # module
