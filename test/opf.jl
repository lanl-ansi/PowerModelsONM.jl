@testset "test optimal dispatch" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "settings" => "../test/data/settings.json",
        "skip" => ["faults", "switching", "stability", "dispatch"],
    )
    entrypoint(args)

    args["opt-disp-formulation"] = "nfa"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -0.04; atol=1e-2)

    v_stats = get_timestep_voltage_statistics(args["optimal_dispatch_result"]["solution"], args["network"])
    @test all(all(isnan.(v)) for v in values(v_stats))

    disp_sol = get_timestep_dispatch(args["optimal_dispatch_result"]["solution"], args["network"])
    @test all(all(all(switch["voltage (V)"] .== 0) for switch in values(timestep["switch"])) for timestep in disp_sol)

    args["opt-disp-formulation"] = "lindistflow"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -0.04; atol=1e-2)

    args["opt-disp-formulation"] = "acr"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -0.04; atol=1e-2)
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["vm"], [2.4662, 2.5383, 2.5157]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["va"], [-2.4980, -121.1455, 118.9522]; atol=1e-1))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["vm"], [2.4384, 2.5761, 2.5050]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["va"], [-3.8499, -121.2418, 118.9136]; atol=1e-1))

    args["opt-disp-formulation"] = "acp"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -0.04; atol=1e-2)
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["vm"], [2.4662, 2.5383, 2.5157]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["va"], [-2.6079, -121.1914, 119.0014]; atol=1e-1))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["vm"], [2.4384, 2.5761, 2.5050]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["va"], [-3.9642, -121.2890, 118.9647]; atol=1e-1))
end
