@testset "test small signal stability analysis" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "inverters" => "../test/data/ieee13_inverters.json",
        "skip" => ["dispatch", "switching", "faults"],
        "quiet" => true,
    )

    entrypoint(args)

    # TODO once more complex stability features are available, needs better tests
    @test all(!r for r in values(args["stability_results"]))
end

@testset "test small signal stability - single processor" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "inverters" => "../test/data/ieee13_inverters.json",
    )
    prepare_data!(args)
    set_setting!(args, ("options","problem","concurrent-stability-studies"), false)
    build_solver_instances!(args)

    run_stability_analysis!(args)

    @test all(!r for r in values(args["stability_results"]))
end

@testset "test small signal stability - no inverters" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
    )
    prepare_data!(args)
    build_solver_instances!(args)

    run_stability_analysis!(args)

    @test all(!r for r in values(args["stability_results"]))
end
