const _EXCLUDE_SYMBOLS = [Symbol(@__MODULE__), :eval, :include]
for sym in names(@__MODULE__, all=true)
    sym_string = string(sym)
    if sym in _EXCLUDE_SYMBOLS || startswith(sym_string, "_")
        continue
    end
    if !(Base.isidentifier(sym) || (startswith(sym_string, "@") &&
         Base.isidentifier(sym_string[2:end])))
       continue
    end
    @eval export $sym
end

# explicitly export some PMD exports
export nw_id_default, ref, var, ids, nws, nw_ids, con, sol, optimizer_with_attributes

# explicitly export the PMD PowerModels used in this package
export AbstractUnbalancedPowerModel, ACRUPowerModel, ACPUPowerModel, IVRUPowerModel, LPUBFDiagPowerModel, LinDist3FlowPowerModel, NFAUPowerModel, FOTRUPowerModel, FOTPUPowerModel

import PowerModelsDistribution: Status
export Status

import PowerModelsDistribution: SwitchState
export SwitchState

import PowerModelsDistribution: Dispatchable
export Dispatchable

# explicity export the PMD Enums used in this package
for status_code_enum in [Status, SwitchState, Dispatchable]
    for status_code in instances(status_code_enum)
        @eval import PowerModelsDistribution: $(Symbol(status_code))
        @eval export $(Symbol(status_code))
    end
end

# so that users do not need to import JuMP to use a solver with PowerModels
import JuMP: optimizer_with_attributes
export optimizer_with_attributes

import JuMP: TerminationStatusCode
export TerminationStatusCode

import JuMP: ResultStatusCode
export ResultStatusCode

for status_code_enum in [TerminationStatusCode, ResultStatusCode]
    for status_code in instances(status_code_enum)
        @eval import JuMP: $(Symbol(status_code))
        @eval export $(Symbol(status_code))
    end
end
