function transform_data_model_ravens(ravens::T; global_keys::Set{String}=Set{String}(), ravens2math_extensions::Vector{<:Function}=Function[] ,ravens2math_passthrough::Dict{String,<:Vector{<:String}}=Dict{String,Vector{String}}(), kwargs...)::T where T <: Dict{String,Any}
    PMD.transform_data_model_ravens(
        ravens;
        global_keys=union(_default_global_keys, global_keys),
        ravens2math_extensions=ravens2math_extensions,
        ravens2math_passthrough=ravens2math_passthrough,
    )
end


"helper function to passthrough keywords from RAVENS to MATHEMATICAL data models"
function ravens2math_add_root_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})

    data_math["options"] = Dict()

    # Add default switch_close_actions_ub
    data_math["switch_close_actions_ub"] = Inf

end

function ravens2math_add_load_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    for (name, data) in get(data_math, "load", Dict{Any,Dict{String,Any}}())
        data["priority"] = 1
    end
end

function ravens2math_add_bus_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    for (name, data) in get(data_math, "bus", Dict{Any,Dict{String,Any}}())
        data["microgrid_id"] = "1"
    end
end

function ravens2math_add_generator_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    for (name, data) in get(data_math, "gen", Dict{Any,Dict{String,Any}}())
        data["inverter"] = 1
        data["gen_model"] = 1
    end
end


function ravens2math_add_storage_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    for (name, data) in get(data_math, "storage", Dict{Any,Dict{String,Any}}())
        data["inverter"] = 1
        data["gen_model"] = 1
        data["phase_unbalance_ub"] = 1
    end
end


function ravens2math_add_switch_passthrough_default!(data_math::Dict{String,<:Any}, data_ravens::Dict{String,<:Any})
    for (name, data) in get(data_math, "switch", Dict{Any,Dict{String,Any}}())
        data["vm_delta_pu_ub"] = 1
        data["va_delta_deg_ub"] = 1
    end
end






