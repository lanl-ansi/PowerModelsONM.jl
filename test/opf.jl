@testset "test optimal dispatch" begin
    orig_args = Dict{String,Any}(
        "network" => "../test/data/ieee13_feeder.dss",
        "settings" => "../test/data/ieee13_settings.json",
        "skip" => ["faults", "switching", "stability"],
        "quiet" => true,
    )

    @testset "test nfa opf" begin
        args = deepcopy(orig_args)
        args["opt-disp-formulation"] = "nfa"

        entrypoint(args)

        @test isapprox(args["optimal_dispatch_result"]["objective"], 4.85; atol=1e-2)

        vbase, _ = PMD.calc_voltage_bases(args["base_network"], args["base_network"]["settings"]["vbases_default"])

        v_stats = get_timestep_voltage_statistics(args["optimal_dispatch_result"]["solution"], args["network"])
        @test all(all(v .== 0) for v in values(v_stats))

        disp_sol = get_timestep_dispatch(args["optimal_dispatch_result"]["solution"], args["network"])
        @test all(all(all(switch["voltage (V)"] .== 0) for switch in values(timestep["switch"])) for timestep in disp_sol)
    end

    @testset "test lindistflow opf" begin
        args = deepcopy(orig_args)
        args["opt-disp-formulation"] = "lindistflow"
        entrypoint(args)

        vbase, _ = PMD.calc_voltage_bases(args["base_network"], args["base_network"]["settings"]["vbases_default"])

        @test isapprox(args["optimal_dispatch_result"]["objective"], 4.85; atol=1e-2)
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.02, 1.02, 1.02]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [1.00, 1.03, 1.00]; atol=1e-2))
    end

    @testset "test acr opf" begin
        args = deepcopy(orig_args)
        args["opt-disp-formulation"] = "acr"
        entrypoint(args)

        vbase, _ = PMD.calc_voltage_bases(args["base_network"], args["base_network"]["settings"]["vbases_default"])

        @test isapprox(args["optimal_dispatch_result"]["objective"], 5.13; atol=2e-2)
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.04, 1.06, 1.04]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["va"], [-3.31, -121.51, 117.33]; atol=1e0))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [1.03, 1.08, 1.03]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["va"], [-5.03, -121.80, 116.66]; atol=1e0))
    end

    @testset "test acp opf" begin
        args = deepcopy(orig_args)
        args["opt-disp-formulation"] = "acp"
        entrypoint(args)

        vbase, _ = PMD.calc_voltage_bases(args["base_network"], args["base_network"]["settings"]["vbases_default"])

        @test isapprox(args["optimal_dispatch_result"]["objective"], 5.13; atol=2e-2)
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.04, 1.06, 1.04]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["va"], [-3.31, -121.51, 117.33]; atol=1e0))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [1.03, 1.08, 1.03]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["va"], [-5.03, -121.80, 116.66]; atol=1e0))
    end
end
