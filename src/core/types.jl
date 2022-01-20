"Abstract Switch Model for NFAU formulation"
abstract type AbstractUnbalancedNFASwitchModel <: PMD.AbstractUnbalancedNFAModel end

"Abstract Switch Model for LPUBFDiag formulation"
abstract type LPUBFSwitchModel <: PMD.LPUBFDiagModel end

"Abstract Switch Model for SOCNLPUBF formulation"
abstract type SOCUBFSwitchModel <: PMD.SOCNLPUBFModel end

"Abstract Switch Model for ACPU formulation"
abstract type AbstractUnbalancedACPSwitchModel <: PMD.AbstractUnbalancedACPModel end

"Abstract Switch Model for ACRU formulation"
abstract type AbstractUnbalancedACRSwitchModel <: PMD.AbstractUnbalancedACRModel end

"SwitchPowerModel struct for NFAU formulation"
mutable struct NFAUSwitchPowerModel <: AbstractUnbalancedNFASwitchModel PMD.@pmd_fields end

"SwitchPowerModel struct for LPUBFDiag formulation"
mutable struct LPUBFSwitchPowerModel <: LPUBFSwitchModel PMD.@pmd_fields end

"SwitchPowerModel struct for SOCNLPUBF formulation"
mutable struct SOCUBFSwitchPowerModel <: SOCUBFSwitchModel PMD.@pmd_fields end

"SwitchPowerModel struct for ACPU formulation"
mutable struct ACPUSwitchPowerModel <: AbstractUnbalancedACPSwitchModel PMD.@pmd_fields end

"SwitchPowerModel struct for ACRU formulation"
mutable struct ACRUSwitchPowerModel <: AbstractUnbalancedACRSwitchModel PMD.@pmd_fields end

"Collection of all Switch Models"
const AbstractSwitchModels = Union{AbstractUnbalancedNFASwitchModel, LPUBFSwitchModel, SOCUBFSwitchModel, AbstractUnbalancedACPSwitchModel, AbstractUnbalancedACRSwitchModel}

"Collection of only UBF Switch Models"
const AbstractUBFSwitchModels = Union{LPUBFSwitchModel, SOCUBFSwitchModel}

"Collection of Non-Linear Switch Models"
const AbstractNLPSwitchModels = Union{AbstractUnbalancedACPSwitchModel, AbstractUnbalancedACRSwitchModel}

"Collection of Quadratic Switch Models"
const AbstractQPSwitchModels = Union{SOCUBFSwitchModel}

"Collection of Linear Switch Models"
const AbstractLPSwitchModels = Union{AbstractUnbalancedNFASwitchModel, LPUBFSwitchModel}

"string to PowerModelsDistribution type conversion for opt-disp-formulation"
const _dispatch_formulations = Dict{String,Any}(
    "acr" => PMD.ACRUPowerModel,
    "acrupowermodel" => PMD.ACRUPowerModel,
    "acp" => PMD.ACPUPowerModel,
    "acpupowermodel" => PMD.ACPUPowerModel,
    "lindistflow" => PMD.LPUBFDiagPowerModel,
    "lpubfdiag" => PMD.LPUBFDiagPowerModel,
    "lpubf" => PMD.LPUBFDiagPowerModel,
    "lpubfdiagpowermodel" => PMD.LPUBFDiagPowerModel,
    "nfa" => PMD.NFAUPowerModel,
    "nfau" => PMD.NFAUPowerModel,
    "nfaupowermodel" => PMD.NFAUPowerModel,
    "fot" => PMD.FOTRUPowerModel,
    "fotr" => PMD.FOTRUPowerModel,
    "fotp" => PMD.FOTPUPowerModel,
    "fbs" => PMD.FBSUBFPowerModel,
)

"helper function to convert from opt-disp-formulation string to PowerModelsDistribution Type"
_get_dispatch_formulation(form_string::String) = _dispatch_formulations[lowercase(form_string)]

"helper function to convert from PowerModelsDistribution Type to PowerModelsDistribution Type"
_get_dispatch_formulation(form::Type) = form

"string to PowerModelsONM type conversion for opt-switch-formulation"
const _switch_formulations = Dict{String,Any}(
    "acp" => ACPUSwitchPowerModel,
    "acpuswitchpowermodel" => ACPUSwitchPowerModel,
    "acr" => ACRUSwitchPowerModel,
    "acruswitchpowermodel" => ACRUSwitchPowerModel,
    "lindistflow" => LPUBFSwitchPowerModel,
    "lpubfdiag" => LPUBFSwitchPowerModel,
    "lpubf" => LPUBFSwitchPowerModel,
    "lpubfswitchpowermodel" => LPUBFSwitchPowerModel,
    "nfa" => NFAUSwitchPowerModel,
    "nfauswitchpowermodel" => NFAUSwitchPowerModel,
    "soc" => SOCUBFSwitchPowerModel,
    "socubfswitchmodel" => SOCUBFSwitchPowerModel,
)

"helper function to convert from opt-switch-formulation string to PowerModelsONM Type"
_get_switch_formulation(form_string::String) = _switch_formulations[lowercase(form_string)]

"helper function to convert from PowerModelsONM type to PowerModelsONM Type"
_get_switch_formulation(form::Type) = form
