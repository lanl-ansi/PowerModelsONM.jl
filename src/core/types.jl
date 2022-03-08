
"string to PowerModelsDistribution type conversion for opt-disp-formulation"
const _formulation_lookup = Dict{String,Type}(
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


"""
    _get_formulation(form_string::String)

helper function to convert from opt-disp-formulation, opt-switch-formulation string to PowerModelsDistribution Type
"""
_get_formulation(form_string::String)::Type = _formulation_lookup[lowercase(form_string)]


"""
    _get_formulation(form::Type)

helper function to convert from PowerModelsDistribution Type to PowerModelsDistribution Type
"""
_get_formulation(form::Type)::Type = form