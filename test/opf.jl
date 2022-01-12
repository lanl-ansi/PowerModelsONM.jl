@testset "test optimal dispatch" begin
    args = Dict{String,Any}(
        "network" => "../test/data/IEEE13Nodeckt_mod.dss",
        "settings" => "../test/data/settings.json",
        "skip" => ["faults", "switching", "stability", "dispatch"],
    )
    entrypoint(args)

    vbase, _ = PowerModelsDistribution.calc_voltage_bases(args["base_network"], args["base_network"]["settings"]["vbases_default"])

    args["opt-disp-formulation"] = "nfa"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -0.71; atol=1e-2)

    v_stats = get_timestep_voltage_statistics(args["optimal_dispatch_result"]["solution"], args["network"])
    @test all(all(v .== 0) for v in values(v_stats))

    disp_sol = get_timestep_dispatch(args["optimal_dispatch_result"]["solution"], args["network"])
    @test all(all(all(switch["voltage (V)"] .== 0) for switch in values(timestep["switch"])) for timestep in disp_sol)

    args["opt-disp-formulation"] = "lindistflow"
    optimize_dispatch!(args)
    @test isapprox(args["optimal_dispatch_result"]["objective"], -0.72; atol=1e-2)
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.03, 1.03, 1.03]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [1.02, 1.04, 1.01]; atol=1e-2))

    args["opt-disp-formulation"] = "acr"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -0.19; atol=1e-2)
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.04, 1.06, 1.04]; atol=1e0))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["va"], [-3.0, -121.0, 118.0]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [1.03, 1.08, 1.03]; atol=1e0))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["va"], [-5.0, -121.0, 117.0]; atol=1e-2))

    args["opt-disp-formulation"] = "acp"
    optimize_dispatch!(args)

    @test isapprox(args["optimal_dispatch_result"]["objective"], -0.18; atol=1e-2)
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.04, 1.06, 1.03]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["va"], [-3.0, -121.0, 118.0]; atol=1e-1))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [1.03, 1.07, 1.03]; atol=1e-2))
    @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["va"], [-4.0, -121.0, 117.0]; atol=1e-1))
end
