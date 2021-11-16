abstract type AbstractUnbalancedActivePowerSwitchModel <: PMD.AbstractUnbalancedActivePowerModel end

abstract type LPUBFSwitchModel <: PMD.LPUBFDiagModel end

abstract type SOCUBFSwitchModel <: PMD.SOCNLPUBFModel end

abstract type AbstractUnbalancedACPSwitchModel <: PMD.AbstractUnbalancedACPModel end

mutable struct NFAUSwitchPowerModel <: AbstractUnbalancedActivePowerSwitchModel PMD.@pmd_fields end

mutable struct LPUBFSwitchPowerModel <: LPUBFSwitchModel PMD.@pmd_fields end

mutable struct SOCUBFSwitchPowerModel <: SOCUBFSwitchModel PMD.@pmd_fields end

mutable struct ACPUSwitchPowerModel <: AbstractUnbalancedACPSwitchModel PMD.@pmd_fields end

AbstractSwitchModels = Union{AbstractUnbalancedActivePowerSwitchModel, LPUBFSwitchModel, SOCUBFSwitchModel, AbstractUnbalancedACPSwitchModel}

AbstractUBFSwitchModels = Union{LPUBFSwitchModel, SOCUBFSwitchModel}

"string to PowerModelsDistribution type conversion for opt-disp-formulation"
const _dispatch_formulations = Dict{String,Any}(
    "acr" => PMD.ACRUPowerModel,
    "acp" => PMD.ACPUPowerModel,
    "lindistflow" => PMD.LPUBFDiagPowerModel,
    "nfa" => PMD.NFAUPowerModel,
    "fot" => PMD.FOTRUPowerModel,
    "fbs" => PMD.FBSUBFPowerModel,
)

"helper function to convert from opt-disp-formulation string to PowerModelsDistribution Type"
_get_dispatch_formulation(form_string::String) = _dispatch_formulations[form_string]
_get_dispatch_formulation(form::Type) = form


"string to PowerModelsONM type conversion for opt-switch-formulation"
const _switch_formulations = Dict{String,Any}(
    "acp" => ACPUSwitchPowerModel,
    "lindistflow" => LPUBFSwitchPowerModel,
    "nfa" => NFAUSwitchPowerModel,
    "soc" => SOCUBFSwitchPowerModel,
)

"helper function to convert from opt-switch-formulation string to PowerModelsONM Type"
_get_switch_formulation(form_string::String) = _switch_formulations[form_string]
_get_switch_formulation(form::Type) = form
