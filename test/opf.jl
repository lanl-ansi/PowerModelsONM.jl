@testset "test optimal dispatch" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "settings" => "../test/data/settings.json",
        "skip" => ["faults", "switching", "stability", "dispatch"],
    )
    entrypoint(args)

    args["opt-disp-formulation"] = "nfa"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -1.0; atol=1e-2)

    v_stats = get_timestep_voltage_statistics(args["optimal_dispatch_result"]["solution"], args["network"])
    @test all(all(v .== 0) for v in values(v_stats))

    disp_sol = get_timestep_dispatch(args["optimal_dispatch_result"]["solution"], args["network"])
    @test all(all(all(switch["voltage (V)"] .== 0) for switch in values(timestep["switch"])) for timestep in disp_sol)

    args["opt-disp-formulation"] = "lindistflow"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -1.0; atol=1e-2)

    args["opt-disp-formulation"] = "acr"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -1.0; atol=1e-2)
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["vm"], [2.4345, 2.4935, 2.4856]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["va"], [-2.0369, -122.5283, 120.5413]; atol=1e-1))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["vm"], [2.4144, 2.5003, 2.4741]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["va"], [-2.5140, -122.8706, 120.7900]; atol=1e-1))

    args["opt-disp-formulation"] = "acp"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -1.0; atol=1e-2)
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["vm"], [2.4897, 2.4566, 2.4636]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["700"]["va"], [-0.8117, -121.2266, 117.8934]; atol=1e-1))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["vm"], [2.4799, 2.4538, 2.4507]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["1"]["bus"]["671"]["va"], [-0.9965, -121.3314, 117.5778]; atol=1e-1))
end
