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
    r_disp = optimize_dispatch!(orig_args)

    @testset "test fault study algorithms - base" begin
        args = deepcopy(orig_args)

        r_faults = run_fault_studies!(args)

        @test args["fault_studies_results"]["5"]["692"]["3p"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
        @test args["fault_studies_results"]["5"]["692"]["ll"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
        @test args["fault_studies_results"]["5"]["692"]["lg"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
    end

    @testset "test fault study algorithms - no concurrency" begin
        args = deepcopy(orig_args)
        set_setting!(args, ("options", "problem", "concurrent-fault-studies"), false)

        r_faults = run_fault_studies!(args)

        @test args["fault_studies_results"]["5"]["692"]["3p"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
        @test args["fault_studies_results"]["5"]["692"]["ll"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
        @test args["fault_studies_results"]["5"]["692"]["lg"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
    end

    @testset "test fault study algorithms - missing dispatch solution" begin
        args = deepcopy(orig_args)
        delete!(args, "optimal_dispatch_result")

        r_faults = run_fault_studies!(args)

        @test args["fault_studies_results"]["5"]["692"]["3p"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
        @test args["fault_studies_results"]["5"]["692"]["ll"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
        @test args["fault_studies_results"]["5"]["692"]["lg"]["1"]["termination_status"] == PowerModelsONM.JuMP.LOCALLY_SOLVED
    end

    @testset "test fault study algorithms - no fault inputs" begin
        args = deepcopy(orig_args)
        delete!(args, "faults")

        r_faults = run_fault_studies!(args)

        @test count_faults(args["faults"]) == 193
    end
end
