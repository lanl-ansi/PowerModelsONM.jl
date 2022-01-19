@testset "test small signal stability analysis" begin
    args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "inverters" => "../test/data/ieee13_inverters.json",
        "skip" => ["dispatch", "switching", "faults"]
    )

    entrypoint(args)

    # TODO once more complex stability features are available, needs better tests
    @test all(!r for r in values(args["stability_results"]))
end
