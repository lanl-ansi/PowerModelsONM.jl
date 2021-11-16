@testset "test small signal stability analysis" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "settings" => "../test/data/settings.json",
        "inverters" => "../test/data/inverters.json",
        "skip" => ["dispatch", "switching", "faults"]
    )

    entrypoint(args)

    # TODO once more complex stability features are available, needs better tests
    @test all(!r for r in values(args["stability_results"]))
end
