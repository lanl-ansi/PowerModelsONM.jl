module PowerModelsONM
    using Base: Bool

    # STDLIB
    import Dates
    import LinearAlgebra
    import Statistics

    # Parallel Computing
    import Distributed
    using Distributed: pmap

    # InfrastructureModels ecosystem
    import InfrastructureModels as IM
    import InfrastructureModels: ismultinetwork, ismultiinfrastructure

    import PowerModelsDistribution as PMD
    import PowerModelsDistribution: ref, var, con, sol, ids, nw_ids, nw_id_default, nws
    import PowerModelsDistribution: AbstractUnbalancedPowerModel, ACRUPowerModel, ACPUPowerModel, IVRUPowerModel, LPUBFDiagPowerModel, LinDist3FlowPowerModel, NFAUPowerModel, FOTRUPowerModel, FOTPUPowerModel

    import PowerModelsProtection as PMP
    import PowerModelsStability as PMS

    # Optimization Modeling
    import JuMP
    import JuMP: optimizer_with_attributes

    import PolyhedralRelaxations

    import Ipopt
    import HiGHS
    import Juniper

    import ArgParse

    import JSON
    import JSONSchema

    # Logging Tools
    import Logging
    import LoggingExtras

    # Hardware statistics
    import Hwloc

    # Generate samples for robust partitions
    import StatsBase as SB

    # Network Graphs
    import Graphs
    import EzXML

    # Import Tools
    import Requires: @require

    function __init__()
        global _LOGGER = Logging.ConsoleLogger(; meta_formatter=PMD._pmd_metafmt)
        global _DEFAULT_LOGGER = Logging.current_logger()

        Logging.global_logger(_LOGGER)
        PowerModelsONM.set_log_level!(:Info)

        @require Gurobi="2e9cd046-0924-5485-92f1-d5272153d98b" begin
            global GRB_ENV = Gurobi.Env()
        end

        @require KNITRO="67920dd8-b58e-52a8-8622-53c4cffbe346" begin
            global KN_LMC = KNITRO.LMcontext()
        end
    end

    include("core/logging.jl")

    include("core/base.jl")
    include("core/types.jl")
    include("core/constraint_template.jl")
    include("core/constraint.jl")
    include("core/objective.jl")
    include("core/variable.jl")
    include("core/ref.jl")
    include("core/solution.jl")

    include("data_model/checks.jl")
    include("data_model/eng2math.jl")

    include("form/acp.jl")
    include("form/acr.jl")
    include("form/apo.jl")
    include("form/lindistflow.jl")
    include("form/shared.jl")

    include("io/events.jl")
    include("io/faults.jl")
    include("io/graphml.jl")
    include("io/inverters.jl")
    include("io/json.jl")
    include("io/network.jl")
    include("io/output.jl")
    include("io/settings.jl")

    include("prob/common.jl")
    include("prob/dispatch.jl")
    include("prob/faults.jl")
    include("prob/opf.jl")
    include("prob/mld_traditional.jl")
    include("prob/mld_block.jl")
    include("prob/mld_block_robust.jl")
    include("prob/stability.jl")
    include("prob/switch.jl")

    include("stats/analysis.jl")
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
