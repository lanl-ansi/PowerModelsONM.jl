function randomize_partition_config(
    case,
    num_closed_switches)

    if num_closed_switches > length(keys(case["switch"]))
        error("Number of closed switches exceeds the total number of switches")
    end

    part_config = Dict{String,Any}()

    switch_keys = collect(keys(case["switch"]))
    shuffled_keys = Random.shuffle(switch_keys)
    closed_switches = shuffled_keys[1:num_closed_switches]

    # Set the status of the selected switches to "CLOSED" and the rest to "OPEN"
    for key in switch_keys
        if key in closed_switches
            part_config[key] = PMD.SwitchState(1)
        else
            part_config[key] = PMD.SwitchState(0)
        end
    end

    case["fixed_partition_config"] = part_config

    return case
end


@testset "robust partition evaluation" begin
    case = parse_file("../test/data/ieee13_feeder.dss")
    settings = parse_settings("../test/data/ieee13_settings.json")
    PMD.apply_voltage_bounds!(case)
    case = randomize_partition_config(case, 2)

    num_load_scenarios = 20
    uncertainty_val = 0.2
    ls = generate_load_scenarios(case, num_load_scenarios, uncertainty_val)

    solver = optimizer_with_attributes(HiGHS.Optimizer, "primal_feasibility_tolerance" => 1e-6, "dual_feasibility_tolerance" => 1e-6, "small_matrix_value" => 1e-12, "allow_unbounded_or_infeasible" => true, "output_flag" => false)

    results_eval_optimality = evaluate_partition_optimality(case, ls, PMD.LPUBFDiagPowerModel, solver)

    optimality = retrieve_load_scenario_optimality(results_eval_optimality)

    @test isapprox(optimality["1"], 5, atol=1e0)
end
