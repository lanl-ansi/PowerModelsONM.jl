abstract type AbstractUnbalancedActivePowerSwitchModel <: PMD.AbstractUnbalancedActivePowerModel end

abstract type AbstractUnbalancedNFASwitchModel <: PMD.AbstractUnbalancedNFAModel end

abstract type LPUBFSwitchModel <: PMD.LPUBFDiagModel end

abstract type SOCUBFSwitchModel <: PMD.SOCNLPUBFModel end

abstract type AbstractUnbalancedACPSwitchModel <: PMD.AbstractUnbalancedACPModel end

abstract type AbstractUnbalancedACRSwitchModel <: PMD.AbstractUnbalancedACRModel end

mutable struct NFAUSwitchPowerModel <: AbstractUnbalancedNFASwitchModel PMD.@pmd_fields end

mutable struct LPUBFSwitchPowerModel <: LPUBFSwitchModel PMD.@pmd_fields end

mutable struct SOCUBFSwitchPowerModel <: SOCUBFSwitchModel PMD.@pmd_fields end

mutable struct ACPUSwitchPowerModel <: AbstractUnbalancedACPSwitchModel PMD.@pmd_fields end

mutable struct ACRUSwitchPowerModel <: AbstractUnbalancedACRSwitchModel PMD.@pmd_fields end

const AbstractSwitchModels = Union{AbstractUnbalancedActivePowerSwitchModel, LPUBFSwitchModel, SOCUBFSwitchModel, AbstractUnbalancedACPSwitchModel, AbstractUnbalancedACRSwitchModel, AbstractUnbalancedNFASwitchModel}

const AbstractUBFSwitchModels = Union{LPUBFSwitchModel, SOCUBFSwitchModel}

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
    "acr" => ACRUSwitchPowerModel,
    "lindistflow" => LPUBFSwitchPowerModel,
    "nfa" => NFAUSwitchPowerModel,
    "soc" => SOCUBFSwitchPowerModel,
)

"helper function to convert from opt-switch-formulation string to PowerModelsONM Type"
_get_switch_formulation(form_string::String) = _switch_formulations[form_string]
_get_switch_formulation(form::Type) = form
