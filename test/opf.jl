@testset "test optimal dispatch" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "events" => "../test/data/events.json",
        "opt-disp-formulation" => "nfa",
    )

    parse_network!(args)
    build_solver_instances!(args)

    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], 10.73; atol=1e-2)
end
