const _formulations = Dict{String,Any}(
    "acr" => PMD.ACRUPowerModel,
    "acp" => PMD.ACPUPowerModel,
    "lindistflow" => PMD.LPUBFDiagPowerModel,
    "nfa" => PMD.NFAUPowerModel
)

get_formulation(form_string::String) = _formulations[form_string]
get_formulation(form::Type) = form
