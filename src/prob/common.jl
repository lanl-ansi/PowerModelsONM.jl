function optimize_switches!(mn_data_math::Dict{String,Any}, events::Vector{<:Dict{String,<:Any}}; solution_processors::Vector=[])::Vector{Dict{String,Any}}
    cbc_solver = PMD.optimizer_with_attributes(Cbc.Optimizer, "logLevel"=>0, "threads"=>4)
    ipopt_solver = PMD.optimizer_with_attributes(Ipopt.Optimizer, "print_level"=>0, "tol"=>1e-4, "mu_strategy"=>"adaptive")
    juniper_solver = PMD.optimizer_with_attributes(Juniper.Optimizer, "nl_solver"=>ipopt_solver, "mip_solver"=>cbc_solver, "log_levels"=>[])

    # gurobi_solver = Gurobi.Optimizer(GRB_ENV)
    # PMD.JuMP.set_optimizer_attribute(gurobi_solver, "OutputFlag", 0)

    results = []
    for n in sort([parse(Int, i) for i in keys(mn_data_math["nw"])])
        n = "$n"
        nw = mn_data_math["nw"][n]
        nw["per_unit"] = mn_data_math["per_unit"]

        if !isempty(results)
            update_start_values!(nw, results[end]["solution"])
            update_switch_settings!(nw, results[end]["solution"])
            update_storage_capacity!(nw, results[end]["solution"])
        end
        push!(results, run_mc_osw_mld_mi(nw, PMD.LPUBFDiagPowerModel, juniper_solver; solution_processors=solution_processors))
    end

    solution = Dict("nw" => Dict("$n" => result["solution"] for (n, result) in enumerate(results)))

    # TODO: Multinetwork problem
    #results = run_mn_mc_osw_mi(mn_data_math, PMD.LPUBFDiagPowerModel, juniper_solver; solution_processors=solution_processors)
    #solution = results["solution"]

    update_start_values!(mn_data_math, solution)
    update_switch_settings!(mn_data_math, solution)

    apply_load_shed!(mn_data_math, Dict{String,Any}("solution" => solution))
    update_post_event_actions_load_shed!(events, solution, mn_data_math["map"])

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


""
function run_fault_study(mn_data_math::Dict{String,Any}, faults::Dict{String,Any}, solver)::Vector{Dict{String,Any}}
    results = []
    for n in sort([parse(Int, i) for i in keys(get(mn_data_math, "nw", Dict()))])
        nw = deepcopy(mn_data_math["nw"]["$n"])
        nw["method"] = "PMD"
        nw["time_elapsed"] = 1.0
        nw["fault"] = faults
        nw["bus_lookup"] = mn_data_math["bus_lookup"]
        nw["map"] = mn_data_math["map"]
        nw["settings"] = mn_data_math["settings"]

        if !isempty(get(nw, "switch", Dict()))
            PowerModelsProtection.add_switch_impedance!(nw)
        end

        if haskey(nw, "storage") && !isempty(nw["storage"])
            @warn "PowerModelsProtection cannot current support storage components due to missing constraints in IVR formulation, running without storage at timestep $n"
            nw["storage"] = Dict{String,Any}()
        end

        push!(results, PowerModelsProtection.run_mc_fault_study(nw, solver))
    end

    return results
end


""
function analyze_stability(mn_data_eng::Dict{String,<:Any}, inverters::Dict{String,<:Any})::Vector{Bool}
    is_stable = Vector{Bool}([])
    for n in sort([parse(Int, n) for n in keys(mn_data_eng["nw"])])
        @info "performing stability check for timestep $(n)"
        eng_data = deepcopy(mn_data_eng["nw"]["$(n)"])

        PowerModelsStability.add_inverters!(eng_data, inverters)

        ipopt_solver = PMD.optimizer_with_attributes(Ipopt.Optimizer, "tol"=>1e-5, "print_level"=>0)
        opfSol, mpData_math = PowerModelsStability.run_mc_opf(eng_data, PMD.ACRPowerModel, ipopt_solver; solution_processors=[PMD.sol_data_model!])

        @debug opfSol["termination_status"]

        omega0 = get(inverters, "omega0", 376.9911)
        rN = get(inverters, "rN", 1000)

        Atot = PowerModelsStability.obtainGlobal_multi(mpData_math, opfSol, omega0, rN)
        eigValList = eigvals(Atot)
        statusTemp = true
        for eig in eigValList
            if eig.re > 0
                statusTemp = false
            end
        end
        push!(is_stable, statusTemp)
    end

    return is_stable
end
