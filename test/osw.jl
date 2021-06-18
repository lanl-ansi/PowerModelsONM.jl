@testset "test optimal switching" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "events" => "../test/data/events.json",
    )
    initialize_output!(args)

    parse_network!(args)
    parse_events!(args)
    build_solver_instances!(args)

    optimize_switches!(args)

    @test isapprox(args["optimal_switching_results"]["1"]["objective"], 0.001621; atol=1e-4)
    @test isapprox(args["optimal_switching_results"]["2"]["objective"], 0.001434; atol=1e-4)

    actions = get_timestep_device_actions!(args)
    @test actions[1]["Switch configurations"]["671700"] == "open"
    @test actions[2]["Switch configurations"]["671700"] == "closed"
end
