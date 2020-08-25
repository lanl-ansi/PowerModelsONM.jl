const _formulations = Dict{String,Any}(
    "acr" => PMD.ACRPowerModel,
    "acp" => PMD.ACPPowerModel,
    "lindistflow" => PMD.LPUBFDiagPowerModel,
    "nfa" => PMD.NFAPowerModel
)

const _mn_problems = Dict{String,Any}(
    "opf" => PMD.run_mn_mc_opf,
    "mld" => PMD.build_mn_mc_mld_simple
)

const _problems = Dict{String,Any}(
    "opf" => PMD.run_mc_opf,
    "pf" => PMD.run_mc_pf,
    "mld" => PMD.build_mc_mld
)


""
function _make_dict_keys_str(dict::Dict{<:Any,<:Any})
    o = Dict{String,Any}()
    for (k, v) in dict
        if isa(v, Dict)
            v = _make_dict_keys_str(v)
        end
        o[string(k)] = v
    end

    return o
end


""
function get_formulation(form_string::String)
    return _formulations[form_string]
end


""
function get_problem(problem_string::String, ismultinetwork)::Function
    return ismultinetwork ? _mn_problems[problem_string] : _problems[problem_string]
end


""
function build_solver_instance(tolerance::Real, verbose::Bool=false)
    return PMD.optimizer_with_attributes(Ipopt.Optimizer, "tol" => tolerance, "print_level" => verbose ? 3 : 0)
end


""
function solve_problem(problem::Function, data_math::Dict{String,<:Any}, form, solver)::Dict{String,Any}
    return problem(data_math, form, solver; multinetwork=haskey(data_math, "nw"), make_si=false, solution_processors=[PMD.sol_data_model!])
end


""
function transform_solutions(sol_math::Dict{String,Any}, data_math::Dict{String,Any})::Tuple{Dict{String,Any},Dict{String,Any}}
    sol_pu = PMD.transform_solution(sol_math, data_math; make_si=false)
    sol_si = PMD.transform_solution(sol_math, data_math; make_si=true)

    return sol_pu, sol_si
end


""
function make_multinetwork!(data_eng, data_math, sol_pu, sol_si)
    if !haskey(data_eng, "time_series")
        data_eng["time_series"] = Dict{String,Any}("0" => Dict{String,Any}("time" => [0.0]))
    end

    if !haskey(data_math, "nw")
        sol_pu = Dict{String,Any}("nw" => Dict{String,Any}("0" => sol_pu))
        sol_si = Dict{String,Any}("nw" => Dict{String,Any}("0" => sol_si))
    end
end


""
function build_blank_output(data_eng::Dict{String,Any})::Dict{String,Any}
    Dict{String,Any}(
        "Simulation time steps" => Vector{String}(["$t" for t in first(data_eng["time_series"]).second["time"]]),
        "Load served" => Dict{String,Any}(
            "Feeder load (%)" => Vector{Real}([]),
            "Microgrid load (%)" => Vector{Real}([]),
            "Bonus load via microgrid (%)" => Vector{Real}([]),
        ),
        "Generator profiles" => Dict{String,Any}(
            "Grid mix (kW)" => Vector{Real}([]),
            "Solar DG (kW)" => Vector{Real}([]),
            "Energy storage (kW)" => Vector{Real}([]),
            "Diesel DG (kW)" => Vector{Real}([]),
        ),
        "Voltages" => Dict{String,Any}(
            "Min voltage (p.u.)" => Vector{Real}([]),
            "Mean voltage (p.u.)" => Vector{Real}([]),
            "Max voltage (p.u.)" => Vector{Real}([]),
        ),
        "Storage SOC (%)" => Vector{Real}([]),
        "Device action timeline" => Vector{Dict{String,Any}}([]),
        "Powerflow output" => Dict{String,Dict{String,Any}}(
            "$timestamp" => Dict{String,Any}(
                id => Dict{String,Any}(
                    "voltage (V)" => 0.0
                ) for (id,_) in data_eng["bus"]
            ) for timestamp in first(data_eng["time_series"]).second["time"]
        ),
        "Summary statistics" => Dict{String,Any}(
            "Additional stats" => "TBD"
        ),
    )
end
