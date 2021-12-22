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

    @test round.(args["optimal_dispatch_result"]["objective"], RoundUp; sigdigits=2) == -0.25

    v_stats = get_timestep_voltage_statistics(args["optimal_dispatch_result"]["solution"], args["network"])
    @test all(all(v .== 0) for v in values(v_stats))

    disp_sol = get_timestep_dispatch(args["optimal_dispatch_result"]["solution"], args["network"])
    @test all(all(all(switch["voltage (V)"] .== 0) for switch in values(timestep["switch"])) for timestep in disp_sol)

    args["opt-disp-formulation"] = "lindistflow"
    optimize_dispatch!(args)
    @test round.(args["optimal_dispatch_result"]["objective"], RoundUp; sigdigits=2) == -0.25
    @test round.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], RoundUp; sigdigits=3) == [1.05, 1.05, 1.05]
    @test round.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], RoundUp; sigdigits=3) == [1.03, 1.06, 1.04]

    args["opt-disp-formulation"] = "acr"
    optimize_dispatch!(args)

    @test round.(args["optimal_dispatch_result"]["objective"], RoundUp; sigdigits=2) == -0.25
    @test round.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], RoundUp; sigdigits=3) == [1.02, 1.04, 1.04]
    @test round.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["va"], RoundUp; digits=0) == [-1.0, -121.0, 120.0]
    @test round.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], RoundUp; sigdigits=3) == [1.01, 1.06, 1.04]
    @test round.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["va"], RoundUp; digits=0) == [-3.0, -121.0, 121.0]

    args["opt-disp-formulation"] = "acp"
    optimize_dispatch!(args)

    @test round.(args["optimal_dispatch_result"]["objective"], RoundUp; sigdigits=2) == -0.25
    @test round.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], RoundUp; sigdigits=3) == [1.04, 1.03, 1.04]
    @test round.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["va"], RoundUp; digits=0) == [-1.0, -120.0, 120.0]
    @test round.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], RoundUp; sigdigits=3) == [1.02, 1.06, 1.04]
    @test round.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["va"], RoundUp; digits=0) == [-3.0, -120.0, 120.0]
end
