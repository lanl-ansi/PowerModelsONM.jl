function optimize_switches!(mn_data_math::Dict{String,Any}; solution_processors::Vector=[])::Vector{Dict{String,Any}}
    cbc_solver = PMD.optimizer_with_attributes(Cbc.Optimizer, "logLevel"=>0, "threads"=>4)
    ipopt_solver = PMD.optimizer_with_attributes(Ipopt.Optimizer, "print_level"=>0, "tol"=>1e-4, "mu_strategy"=>"adaptive")
    juniper_solver = PMD.optimizer_with_attributes(Juniper.Optimizer, "nl_solver"=>ipopt_solver, "mip_solver"=>cbc_solver, "log_levels"=>[])

    # gurobi_solver = Gurobi.Optimizer(GRB_ENV)
    # PMD.JuMP.set_optimizer_attribute(gurobi_solver, "OutputFlag", 0)

    results = []
    for (n,nw) in mn_data_math["nw"]
        nw["per_unit"] = mn_data_math["per_unit"]
        if !isempty(results)
            update_start_values!(nw, results[end]["solution"])
            update_switch_settings!(nw, results[end]["solution"])
        end
        push!(results, run_mc_osw_mi(nw, PMD.LPUBFDiagPowerModel, juniper_solver; solution_processors=solution_processors))
    end

    solution = Dict("nw" => Dict("$n" => result["solution"] for (n, result) in enumerate(results)))

    # TODO: Multinetwork problem
    #results = run_mn_mc_osw_mi(mn_data_math, PMD.LPUBFDiagPowerModel, juniper_solver; solution_processors=solution_processors)
    #solution = results["solution"]

    update_start_values!(mn_data_math, solution)
    update_switch_settings!(mn_data_math, solution)

    return results
end


""
function solve_problem(problem::Function, data_math::Dict{String,<:Any}, form, solver; solution_processors::Vector=[])::Dict{String,Any}
    return problem(data_math, form, solver; multinetwork=haskey(data_math, "nw"), make_si=false, solution_processors=solution_processors)
end


""
function build_solver_instance(tolerance::Real, verbose::Bool=false)
    return PMD.optimizer_with_attributes(Ipopt.Optimizer, "tol" => tolerance, "print_level" => verbose ? 3 : 0)
end
