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
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.010, 1.016, 1.004]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [0.998, 1.023, 0.993]; atol=1e-2))
    end

    @testset "test acr opf" begin
        args = deepcopy(orig_args)
        args["opt-disp-formulation"] = "acr"
        entrypoint(args)

        vbase, _ = PMD.calc_voltage_bases(args["base_network"], args["base_network"]["settings"]["vbases_default"])

        @test isapprox(args["optimal_dispatch_result"]["objective"], 5.13; atol=2e-2)
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.013, 1.062, 1.025]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["va"], [-3.36, -122.49, 117.39]; atol=1e0))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [0.979, 1.085, 1.021]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["va"], [-4.77, -123.13, 116.81]; atol=1e0))
    end

    @testset "test acp opf" begin
        args = deepcopy(orig_args)
        args["opt-disp-formulation"] = "acp"
        entrypoint(args)

        vbase, _ = PMD.calc_voltage_bases(args["base_network"], args["base_network"]["settings"]["vbases_default"])

        @test isapprox(args["optimal_dispatch_result"]["objective"], 5.13; atol=2e-2)
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["vm"] ./ vbase["801"], [1.013, 1.062, 1.025]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["801"]["va"], [-3.36, -122.49, 117.39]; atol=1e0))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["vm"] ./ vbase["675"], [0.979, 1.085, 1.021]; atol=1e-2))
        @test all(isapprox.(args["optimal_dispatch_result"]["solution"]["nw"]["7"]["bus"]["675"]["va"], [-4.77, -123.13, 116.81]; atol=1e0))
    end

    @testset "test fix-small-numbers nfa opf" begin
        args = deepcopy(orig_args)
        prepare_data!(args)

        set_settings!(args, Dict(
            ("options","data","fix-small-numbers") => true,
            ("options","problem","dispatch-formulation") => "nfa"
        ))

        build_solver_instances!(args)

        result = optimize_dispatch!(args)

        @test isapprox(result["objective"], 4.85; atol=1e-2)
    end
end
