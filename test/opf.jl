@testset "test optimal dispatch" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "events" => "../test/data/events.json",
        "opt-disp-formulation" => "nfa",
    )

    parse_network!(args)
    build_solver_instances!(args)

    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], 5.698; atol=1e-2)

    args["opt-disp-formulation"] = "lindistflow"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], 5.369; atol=1e-2)

    args["opt-disp-formulation"] = "acr"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], 5.780; atol=1e-2)
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["vm"], [2.46807, 2.54727, 2.57091]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["va"], [-0.734344, -120.934, 120.246]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["vm"], [2.4399, 2.58481, 2.56149]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["va"], [-2.0762, -121.026, 120.212]; atol=1e-2))

    args["opt-disp-formulation"] = "acp"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], 5.780; atol=1e-2)
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["vm"], [2.46807, 2.54727, 2.57091]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["va"], [-0.734344, -120.934, 120.246]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["vm"], [2.4399, 2.58481, 2.56149]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["va"], [-2.0762, -121.026, 120.212]; atol=1e-2))
end
