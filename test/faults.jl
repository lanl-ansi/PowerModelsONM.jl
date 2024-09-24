@testset "test fault study algorithms" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "faults" => "../test/data/ieee13_faults.json",
        "events" => "../test/data/ieee13_events.json",
    )
    prepare_data!(orig_args)

    set_settings!(
        orig_args,
        Dict(
            ("options", "problem", "operations-solver") => "mip_solver",
            ("options", "problem", "dispatch-formulation") => "acp",
            ("options", "problem", "operations-algorithm") => "rolling-horizon",
            ("options", "outputs", "log-level") => "error",
        )
    )

    build_solver_instances!(orig_args)

    r_op = optimize_switches!(orig_args)

    @testset "test fault study algorithms - base" begin
        args = deepcopy(orig_args)

        r_faults = run_fault_studies!(args)

        @test length(r_faults) == 8
    end

    @testset "test fault study algorithms - no concurrency" begin
        args = deepcopy(orig_args)
        set_setting!(args, ("options", "problem", "concurrent-fault-studies"), false)

        r_faults = run_fault_studies!(args)

        @test length(r_faults) == 8
    end

    @testset "test fault study algorithms - missing switching solution" begin
        args = deepcopy(orig_args)
        delete!(args, "optimal_switching_results")

        r_faults = run_fault_studies!(args)

        @test length(r_faults) == 1
    end
end
