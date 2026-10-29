# TODO: PowerModelsProtection v0.7.1 calls PMD's private _map_eng2math_*! functions with Dicts, which RAVENS PMD
# no longer accepts, so run_fault_studies! throws a MethodError. Re-enable once PMP is ported (see onm-rrs-patch-plan O5).
const _PMP_SUPPORTS_RAVENS_PMD = false

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

        if _PMP_SUPPORTS_RAVENS_PMD
            r_faults = run_fault_studies!(args)

            @test length(r_faults) == 8
        else
            @test_broken false
        end
    end

    @testset "test fault study algorithms - no concurrency" begin
        args = deepcopy(orig_args)
        set_setting!(args, ("options", "problem", "concurrent-fault-studies"), false)

        if _PMP_SUPPORTS_RAVENS_PMD
            r_faults = run_fault_studies!(args)

            @test length(r_faults) == 8
        else
            @test_broken false
        end
    end

    @testset "test fault study algorithms - missing switching solution" begin
        args = deepcopy(orig_args)
        delete!(args, "optimal_switching_results")

        if _PMP_SUPPORTS_RAVENS_PMD
            r_faults = run_fault_studies!(args)

            @test length(r_faults) == 1
        else
            @test_broken false
        end
    end
end
