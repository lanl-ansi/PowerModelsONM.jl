module PowerModelsONM
    using Base: Bool

    # STDLIB
    import Dates
    import LinearAlgebra
    import Statistics

    # InfrastructureModels ecosystem
    import InfrastructureModels
    const _IM = InfrastructureModels

    import PowerModelsDistribution
    import PowerModelsDistribution: ref, var, con, ids, nw_ids, nw_id_default, nws, AbstractUnbalancedPowerModel
    const PMD = PowerModelsDistribution

    import PowerModelsProtection
    import PowerModelsStability

    # Optimization Modeling
    import JuMP
    import JuMP: optimizer_with_attributes

    import PolyhedralRelaxations

    import Ipopt
    import Cbc
    import Juniper
    import Alpine

    import ArgParse

    import JSON
    import JSONSchema

    # Logging Tools
    import Logging
    import LoggingExtras
    import ProgressMeter: @showprogress

    # Hardware statistics
    import Hwloc

    # Network Graphs
    import LightGraphs

    # Import Tools
    import Requires: @require

    function __init__()
        global _LOGGER = Logging.ConsoleLogger(; meta_formatter=PowerModelsDistribution._pmd_metafmt)
        global _DEFAULT_LOGGER = Logging.current_logger()

        Logging.global_logger(_LOGGER)

        @require Gurobi="2e9cd046-0924-5485-92f1-d5272153d98b" begin
            global GRB_ENV = Gurobi.Env()
        end
    end

    include("core/base.jl")
    include("core/type.jl")

    include("core/constraint_template.jl")
    include("core/constraint.jl")
    include("core/data.jl")
    include("core/logging.jl")
    include("core/objective.jl")
    include("core/ref.jl")
    include("core/solution.jl")
    include("core/variable.jl")

    include("data_model/checks.jl")
    include("data_model/transformations.jl")

    include("form/apo.jl")
    include("form/bf_mx_lin.jl")
    include("form/shared.jl")

    include("io/events.jl")
    include("io/faults.jl")
    include("io/inverters.jl")
    include("io/json.jl")
    include("io/network.jl")
    include("io/output.jl")
    include("io/settings.jl")

    include("prob/common.jl")
    include("prob/dispatch.jl")
    include("prob/faults.jl")
    include("prob/mn_opf_oltc_capc.jl")
    include("prob/osw_mld.jl")
    include("prob/stability.jl")
    include("prob/switch.jl")

    include("stats/actions.jl")
    include("stats/dispatch.jl")
    include("stats/fault.jl")
    include("stats/microgrid.jl")
    include("stats/stability.jl")
    include("stats/utils.jl")

    include("cli/arguments.jl")

    include("app/main.jl")

    # Export must go last
    include("core/export.jl")
end # module
